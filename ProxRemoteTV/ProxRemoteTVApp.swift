import SwiftUI

@main
struct ProxRemoteTVApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.pairedServers.isEmpty {
                PairingView(appState: appState)
            } else {
                ServerListView(appState: appState)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var pairedServers: [ServerProfile] = []
    @Published var isConnected = false

    // Server profiles include the Proxmox password, so they live in the
    // Keychain (device-only), not UserDefaults. `storageKey` is retained
    // only to migrate-and-purge any plaintext copy left by older builds.
    private let storageKey = "paired_servers"
    private let keychainAccount = "paired_servers"

    init() {
        loadServers()
    }

    func loadServers() {
        // One-time migration: if an older build left profiles (with the
        // password) in UserDefaults, move them into the Keychain and wipe
        // the plaintext copy.
        if let legacy = UserDefaults.standard.data(forKey: storageKey),
           let servers = try? JSONDecoder().decode([ServerProfile].self, from: legacy) {
            pairedServers = servers
            saveServers()  // writes to Keychain
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        guard let data = KeychainStore.load(account: keychainAccount),
              let servers = try? JSONDecoder().decode([ServerProfile].self, from: data)
        else { return }
        pairedServers = servers
    }

    func saveServers() {
        guard let data = try? JSONEncoder().encode(pairedServers) else { return }
        if pairedServers.isEmpty {
            KeychainStore.delete(account: keychainAccount)
        } else {
            KeychainStore.save(data, account: keychainAccount)
        }
    }

    func addServer(_ server: ServerProfile) {
        if !pairedServers.contains(where: { $0.host == server.host }) {
            pairedServers.append(server)
            saveServers()
        }
    }

    func removeServer(_ server: ServerProfile) {
        pairedServers.removeAll { $0.id == server.id }
        if server.id == "demo-cluster" {
            DemoMode.shared.exit()
        }
        saveServers()
    }

    func clearAll() {
        pairedServers.removeAll()
        saveServers()
    }
}
