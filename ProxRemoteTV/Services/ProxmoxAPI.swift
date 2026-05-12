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
            let delegate = SelfSignedDelegate()
            self.session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
        } else {
            self.session = URLSession.shared
        }
    }

    // MARK: - Auth

    func login() async throws {
        let url = URL(string: "\(server.baseURL)/api2/json/access/ticket")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let body = "username=\(server.username)@\(server.realm)&password=\(server.password)"
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
        let data = try await get("/api2/json/nodes/\(node)/status")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return NodeStatus(from: dict)
    }

    func fetchVMConfig(node: String, vmid: Int, type: String) async throws -> VMConfig {
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/config")
        let dict = (data["data"] as? [String: Any]) ?? [:]
        return VMConfig(from: dict)
    }

    func fetchVMStatus(node: String, vmid: Int, type: String) async throws -> [String: Any] {
        let data = try await get("/api2/json/nodes/\(node)/\(type)/\(vmid)/status/current")
        return (data["data"] as? [String: Any]) ?? [:]
    }

    func fetchSnapshots(node: String, vmid: Int, type: String) async throws -> [Snapshot] {
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

    private func get(_ path: String) async throws -> [String: Any] {
        if ticket == nil { try await login() }

        let url = URL(string: "\(server.baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.setValue("PVEAuthCookie=\(ticket!)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 401 {
            // Re-auth and retry
            try await login()
            var retryRequest = URLRequest(url: url)
            retryRequest.setValue(
                "PVEAuthCookie=\(ticket!)",
                forHTTPHeaderField: "Cookie"
            )
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

// MARK: - Self-signed cert support

class SelfSignedDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
