import Foundation

class ProxmoxAPI: ObservableObject {
    let server: ServerProfile
    private var ticket: String?
    private var csrf: String?
    private let session: URLSession

    @Published var resources: [ClusterResource] = []
    @Published var isLoading = false
    @Published var error: String?

    init(server: ServerProfile) {
        self.server = server

        // Auto-activate demo mode when the demo server profile is used.
        // DemoMode is in-memory only, so after an app relaunch the persisted
        // demo server would otherwise try to hit the network.
        if server.id == "demo-cluster" {
            DemoMode.shared.enter()
        }

        if server.trustSelfSigned {
            // Retain the delegate — URLSession holds it weakly, so a local
            // would be released and pinning would silently stop working.
            let delegate = PinnedTLSDelegate()
            self.tlsDelegate = delegate
            self.session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            self.session = URLSession.shared
        }
    }

    private var tlsDelegate: PinnedTLSDelegate?

    // MARK: - Auth

    func login() async throws {
        if DemoMode.shared.isActive {
            ticket = "DEMO:fake"
            csrf = "DEMO:fake"
            return
        }
        // API-token auth needs no ticket exchange — every request carries the
        // Authorization header instead (see `authorize`).
        if server.usesApiToken {
            ticket = "TOKEN"
            return
        }
        let url = URL(string: "\(server.baseURL)/api2/json/access/ticket")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        // Percent-encode each field — a password containing & + % = would
        // otherwise corrupt the form body or be mis-parsed by Proxmox.
        func enc(_ s: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")   // RFC 3986 unreserved
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        let user = "\(server.username)@\(server.realm)"
        let body = "username=\(enc(user))&password=\(enc(server.password))"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]

        guard let t = dataObj?["ticket"] as? String,
              let c = dataObj?["CSRFPreventionToken"] as? String
        else {
            throw APIError.authFailed
        }

        ticket = t
        csrf = c
    }

    // MARK: - API Calls

    func fetchClusterResources() async throws -> [ClusterResource] {
        if DemoMode.shared.isActive { return DemoData.clusterResources() }
        let data = try await get("/api2/json/cluster/resources")
        let list = (data["data"] as? [[String: Any]]) ?? []
        return list.compactMap { dict in
            guard let type = dict["type"] as? String,
                  let status = dict["status"] as? String,
                  let name = dict["name"] as? String,
                  let node = dict["node"] as? String
            else { return nil }
            return ClusterResource(
                type: type,
                status: status,
                name: name,
                node: node,
                vmid: dict["vmid"] as? Int,
                cpu: dict["cpu"] as? Double,
                maxcpu: dict["maxcpu"] as? Int,
                mem: dict["mem"] as? Int,
                maxmem: dict["maxmem"] as? Int,
                disk: dict["disk"] as? Int,
                maxdisk: dict["maxdisk"] as? Int,
                uptime: dict["uptime"] as? Int
            )
        }
    }

    func fetchClusterTasks(limit: Int = 50) async throws -> [ClusterTask] {
        if DemoMode.shared.isActive {
            return Array(DemoData.clusterTasks().prefix(limit))
        }
        let data = try await get("/api2/json/cluster/tasks")
        let list = (data["data"] as? [[String: Any]]) ?? []
        return list.prefix(limit).compactMap { dict in
            guard let upid = dict["upid"] as? String,
                  let type = dict["type"] as? String,
                  let node = dict["node"] as? String,
                  let starttime = dict["starttime"] as? Int
            else { return nil }
            return ClusterTask(
                upid: upid,
                type: type,
                node: node,
                user: dict["user"] as? String ?? "",
                starttime: starttime,
                endtime: dict["endtime"] as? Int,
                status: dict["status"] as? String,
                exitstatus: dict["exitstatus"] as? String
            )
        }
    }

    func fetchNodeStatus(node: String) async throws -> NodeStatus {
        if DemoMode.shared.isActive { return DemoData.nodeStatus(node: node) }
        let data = try await get("/api2/json/nodes/\(node)/status")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return NodeStatus(from: dict)
    }

    func fetchVMConfig(node: String, vmid: Int, type: String) async throws -> VMConfig {
        if DemoMode.shared.isActive {
            return DemoData.vmConfig(vmid: vmid, type: type)
        }
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/config")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return VMConfig(from: dict)
    }

    func fetchVMStatus(node: String, vmid: Int, type: String) async throws -> [String: Any] {
        if DemoMode.shared.isActive {
            return DemoData.vmStatus(vmid: vmid, type: type, isRunning: vmid != 111)
        }
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/status/current")
        return (data["data"] as? [String: Any]) ?? [:]
    }

    func fetchSnapshots(node: String, vmid: Int, type: String) async throws -> [Snapshot] {
        if DemoMode.shared.isActive { return DemoData.snapshots() }
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/snapshot")
        let list = (data["data"] as? [[String: Any]]) ?? []
        return list.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            return Snapshot(
                name: name,
                description: dict["description"] as? String,
                snaptime: dict["snaptime"] as? Int,
                parent: dict["parent"] as? String,
                vmstate: dict["vmstate"] as? Int
            )
        }.filter { !$0.isCurrent }
         .sorted { ($0.snaptime ?? 0) > ($1.snaptime ?? 0) }
    }

    // MARK: - Helpers

    /// Applies the right auth to a request: a `PVEAPIToken` Authorization
    /// header in token mode, or the ticket cookie in password mode.
    private func authorize(_ request: inout URLRequest) {
        if server.usesApiToken {
            request.setValue(
                "PVEAPIToken=\(server.tokenId!)=\(server.tokenSecret!)",
                forHTTPHeaderField: "Authorization"
            )
        } else if let ticket {
            request.setValue("PVEAuthCookie=\(ticket)", forHTTPHeaderField: "Cookie")
        }
    }

    private func get(_ path: String) async throws -> [String: Any] {
        // Token mode needs no login; password mode needs a ticket first.
        if ticket == nil { try await login() }

        let url = URL(string: "\(server.baseURL)\(path)")!
        var request = URLRequest(url: url)
        authorize(&request)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 401,
           !server.usesApiToken {
            // Ticket expired — re-auth and retry once. (A 401 in token mode
            // means a bad/revoked token; retrying wouldn't help, so we fall
            // through and surface the response.)
            ticket = nil
            try await login()
            var retryRequest = URLRequest(url: url)
            authorize(&retryRequest)
            let (retryData, _) = try await session.data(for: retryRequest)
            return (try JSONSerialization.jsonObject(with: retryData) as? [String: Any]) ?? [:]
        }

        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    enum APIError: LocalizedError {
        case authFailed
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .authFailed: return "Authentication failed"
            case .requestFailed(let msg): return msg
            }
        }
    }
}

// MARK: - Self-signed cert support (TOFU pinned)

/// Validates TLS server trust with trust-on-first-use pinning for self-signed
/// Proxmox certs. A normally-valid (CA-signed) cert is accepted outright; a
/// self-signed cert is accepted only if its leaf fingerprint matches the one
/// first seen for that host:port — a changed cert is rejected as MITM.
/// Replaces the prior delegate that accepted ANY certificate.
final class PinnedTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let port = challenge.protectionSpace.port

        // 1) Accept if the chain is valid against the system trust store
        //    (proper CA-signed cert — e.g. a reverse proxy with Let's Encrypt).
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // 2) Otherwise TOFU-pin the leaf cert.
        guard let leaf = leafCertificate(of: trust),
              TofuPinStore.shared.acceptOrPin(certificate: leaf, host: host, port: port)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func leafCertificate(of trust: SecTrust) -> SecCertificate? {
        if #available(tvOS 15.0, *) {
            return (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        } else {
            return SecTrustGetCertificateAtIndex(trust, 0)
        }
    }
}
