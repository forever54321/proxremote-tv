import CryptoKit
import Foundation
import Network

/// Handles pairing between the Apple TV and iOS app.
///
/// Protocol v2 (encrypted):
///   - TV generates an X25519 ephemeral keypair on every startPairing()
///   - QR carries: proxremote://pair?ip=…&port=…&code=…&pk=<base64 TV pk>&v=2
///   - iPhone scans, generates its own X25519 keypair, derives shared secret
///     via X25519, expands to 32-byte AES-GCM key with HKDF-SHA256
///     (info = "proxremote-pair-v1")
///   - iPhone encrypts the credentials JSON with AES-GCM-256 (random 12-byte
///     nonce, AAD = code as utf8). Sends:
///       { v:2, pk: <base64 iPhone pk>, nonce: <base64>, ct: <base64> }
///     where `ct` is the AES-GCM combined output (ciphertext+tag).
///   - TV derives the same shared secret. Decryption fails (tag mismatch) if
///     the code is wrong → cleanly rejected without leaking which part failed.
///
/// Hardening:
///   - 6-digit code (1M space)
///   - 60-second TTL on the listener (auto-stops)
///   - Max 3 attempts total before listener tears down
///   - Listener also stops on first successful pairing
class PairingService: ObservableObject {
    @Published var pairingCode: String = ""
    @Published var localIP: String = ""
    @Published var isPairing = false
    @Published var receivedServer: ServerProfile?

    private var listener: NWListener?
    private let port: UInt16 = 9876
    private let ttlSeconds: TimeInterval = 60
    private let maxAttempts = 3

    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private var attemptCount = 0
    private var ttlTimer: Timer?

    var publicKeyB64: String {
        guard let pk = privateKey?.publicKey.rawRepresentation else { return "" }
        return pk.base64EncodedString()
    }

    var qrPayload: String {
        let encodedPk = publicKeyB64
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "proxremote://pair?ip=\(localIP)&port=\(port)" +
               "&code=\(pairingCode)&pk=\(encodedPk)&v=2"
    }

    func startPairing() {
        pairingCode = String(format: "%06d", Int.random(in: 100000...999999))
        localIP = getLocalIP() ?? "0.0.0.0"
        privateKey = Curve25519.KeyAgreement.PrivateKey()
        attemptCount = 0
        isPairing = true

        do {
            let params = NWParameters.tcp
            listener = try NWListener(
                using: params,
                on: NWEndpoint.Port(rawValue: port)!
            )
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .main)
        } catch {
            print("Failed to start listener: \(error)")
            isPairing = false
            return
        }

        // Auto-stop after TTL
        ttlTimer?.invalidate()
        ttlTimer = Timer.scheduledTimer(
            withTimeInterval: ttlSeconds,
            repeats: false
        ) { [weak self] _ in
            self?.stopPairing()
        }
    }

    func stopPairing() {
        ttlTimer?.invalidate()
        ttlTimer = nil
        listener?.cancel()
        listener = nil
        privateKey = nil
        attemptCount = 0
        isPairing = false
    }

    private func handleConnection(_ connection: NWConnection) {
        attemptCount += 1
        if attemptCount > maxAttempts {
            connection.cancel()
            DispatchQueue.main.async { [weak self] in self?.stopPairing() }
            return
        }

        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, _, _ in
            guard let self = self, let data = data else { return }
            self.processPayload(data, on: connection)
        }
    }

    private func processPayload(_ data: Data, on connection: NWConnection) {
        guard let privateKey = privateKey,
              let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let version = json["v"] as? Int, version == 2,
              let pkB64 = json["pk"] as? String,
              let nonceB64 = json["nonce"] as? String,
              let ctB64 = json["ct"] as? String,
              let pkData = Data(base64Encoded: pkB64),
              let nonceData = Data(base64Encoded: nonceB64),
              let ctData = Data(base64Encoded: ctB64),
              let peerKey = try? Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: pkData
              )
        else {
            sendError(on: connection, message: "Bad payload")
            return
        }

        guard let key = derivedKey(privateKey: privateKey, peer: peerKey),
              let nonce = try? AES.GCM.Nonce(data: nonceData),
              let plaintext = try? decrypt(
                ct: ctData,
                nonce: nonce,
                key: key,
                aad: Data(pairingCode.utf8)
              ),
              let serverData = try? JSONSerialization.jsonObject(with: plaintext)
                as? [String: Any]
        else {
            // Either wrong code (AAD mismatch) or any other malformed input.
            // Don't distinguish — keeps the protocol safe against oracle-style
            // probing.
            sendError(on: connection, message: "Decryption failed")
            return
        }

        let server = ServerProfile(
            id: serverData["id"] as? String ?? UUID().uuidString,
            displayName: serverData["displayName"] as? String ?? "Server",
            host: serverData["host"] as? String ?? "",
            port: serverData["port"] as? Int ?? 8006,
            username: serverData["username"] as? String ?? "root",
            password: serverData["password"] as? String ?? "",
            realm: serverData["realm"] as? String ?? "pam",
            trustSelfSigned: serverData["trustSelfSigned"] as? Bool ?? true,
            tokenId: serverData["tokenId"] as? String,
            tokenSecret: serverData["tokenSecret"] as? String
        )

        DispatchQueue.main.async { [weak self] in
            self?.receivedServer = server
            self?.stopPairing()
        }

        let resp = #"{"status":"ok"}"#
        connection.send(
            content: resp.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func sendError(on connection: NWConnection, message: String) {
        let body = #"{"status":"error","message":"\#(message)"}"#
        connection.send(
            content: body.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func derivedKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peer: Curve25519.KeyAgreement.PublicKey
    ) -> SymmetricKey? {
        guard let shared = try? privateKey.sharedSecretFromKeyAgreement(
            with: peer
        ) else { return nil }
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("proxremote-pair-v1-salt".utf8),
            sharedInfo: Data("proxremote-pair-v1".utf8),
            outputByteCount: 32
        )
    }

    private func decrypt(
        ct: Data,
        nonce: AES.GCM.Nonce,
        key: SymmetricKey,
        aad: Data
    ) throws -> Data {
        // ct here is ciphertext || tag (16 bytes tag at the end).
        let tagLength = 16
        guard ct.count > tagLength else {
            throw NSError(domain: "Pairing", code: 1)
        }
        let cipher = ct.prefix(ct.count - tagLength)
        let tag = ct.suffix(tagLength)
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: cipher,
            tag: tag
        )
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}
