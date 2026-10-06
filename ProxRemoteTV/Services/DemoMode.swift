import Foundation

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
