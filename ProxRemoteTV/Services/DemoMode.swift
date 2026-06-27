import Foundation

final class DemoMode {
    static let shared = DemoMode()
    private init() {}

    private(set) var isActive: Bool = false

    func enter() { isActive = true }
    func exit() { isActive = false }
}

extension ServerProfile {
    static let demo = ServerProfile(
        id: "demo-cluster",
        displayName: "Demo Cluster",
        host: "demo.proxremote.local",
        port: 8006,
        username: "demo",
        password: "demo",
        realm: "pve",
        trustSelfSigned: true,
        tokenId: nil,
        tokenSecret: nil
    )
}
