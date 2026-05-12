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

    private let storageKey = "paired_servers"

    init() {
        loadServers()
    }

    func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let servers = try? JSONDecoder().decode([ServerProfile].self, from: data)
        else { return }
        pairedServers = servers
    }

    func saveServers() {
        guard let data = try? JSONEncoder().encode(pairedServers) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func addServer(_ server: ServerProfile) {
        if !pairedServers.contains(where: { $0.host == server.host }) {
            pairedServers.append(server)
            saveServers()
        }
    }

    func removeServer(_ server: ServerProfile) {
        pairedServers.removeAll { $0.id == server.id }
        saveServers()
    }

    func clearAll() {
        pairedServers.removeAll()
        saveServers()
    }
}
