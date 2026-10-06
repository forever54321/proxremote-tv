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

    /// Demo data is tied to the demo profile itself — never a global switch,
    /// so opening the demo can't make a real server show fake data.
    private var isDemo: Bool { server.isDemo }

    // MARK: - Auth

    func login() async throws {
        if isDemo {
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
        if isDemo { return DemoData.clusterResources() }
        let data = try await get("/api2/json/cluster/resources")
        let list = (data["data"] as? [[String: Any]]) ?? []
        return list.compactMap { dict in
            // Real PVE: nodes carry no "name" (it's "node"), storage uses
            // "storage". Requiring "name" dropped every node and storage.
            guard let type = dict["type"] as? String,
                  let node = dict["node"] as? String,
                  let name = (dict["name"] ?? dict["storage"] ?? dict["node"]) as? String
            else { return nil }
            let status = (dict["status"] as? String) ?? "unknown"
            return ClusterResource(
                pveId: dict["id"] as? String,
                type: type,
                status: status,
                name: name,
                node: node,
                vmid: dict["vmid"] as? Int,
                cpu: (dict["cpu"] as? NSNumber)?.doubleValue,
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
        if isDemo {
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
                // /cluster/tasks puts a finished task's result in "status"
                // ("OK", "WARNINGS: n" or the error); "exitstatus" is only on
                // the per-task status endpoint.
                exitstatus: (dict["exitstatus"] as? String) ?? (dict["endtime"] != nil ? dict["status"] as? String : nil)
            )
        }
    }

    func fetchNodeStatus(node: String) async throws -> NodeStatus {
        if isDemo { return DemoData.nodeStatus(node: node) }
        let data = try await get("/api2/json/nodes/\(node)/status")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return NodeStatus(from: dict)
    }

    func fetchVMConfig(node: String, vmid: Int, type: String) async throws -> VMConfig {
        if isDemo {
            return DemoData.vmConfig(vmid: vmid, type: type)
        }
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/config")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return VMConfig(from: dict)
    }

    func fetchVMStatus(node: String, vmid: Int, type: String) async throws -> [String: Any] {
        if isDemo {
            return DemoData.vmStatus(vmid: vmid, type: type, isRunning: vmid != 111)
        }
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/status/current")
        return (data["data"] as? [String: Any]) ?? [:]
    }

    func fetchSnapshots(node: String, vmid: Int, type: String) async throws -> [Snapshot] {
        if isDemo { return DemoData.snapshots() }
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
        if server.usesApiToken,
           let tokenId = server.tokenId, let tokenSecret = server.tokenSecret {
            request.setValue(
                "PVEAPIToken=\(tokenId)=\(tokenSecret)",
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
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            try check(retryResponse)
            return try parse(retryData)
        }

        try check(response)
        return try parse(data)
    }

    /// PVE errors (401 revoked token, 403, 500, 595 offline node) used to be
    /// parsed as empty data — an empty dashboard with no explanation.
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        if http.statusCode == 401 && server.usesApiToken {
            throw APIError.requestFailed("The Apple TV's access token was rejected. Pair again from ProxRemote on your iPhone.")
        }
        if http.statusCode == 401 { throw APIError.authFailed }
        if http.statusCode == 595 {
            throw APIError.requestFailed("That node is unreachable (offline or no route).")
        }
        throw APIError.requestFailed("Server error \(http.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))")
    }

    private func parse(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.requestFailed("Unexpected reply from the server.")
        }
        return obj
    }

    /// Turns transport errors into something a person can act on.
    static func describe(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .cancelled:
                return "The server's certificate changed. Remove this server and pair it again from your iPhone."
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "Can't reach the server. Check that the Apple TV and Proxmox are on the same network."
            default: break
            }
        }
        return error.localizedDescription
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
