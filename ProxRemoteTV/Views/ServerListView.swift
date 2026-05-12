import SwiftUI

struct ServerListView: View {
    @ObservedObject var appState: AppState

    @State private var serverToRemove: ServerProfile?

    var body: some View {
        NavigationStack {
            List {
                if appState.pairedServers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 64))
                            .foregroundColor(.cyan)
                        Text("No paired iPhone yet")
                            .font(.title3)
                        Text("Tap \"Pair iPhone\" below to start.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }

                ForEach(appState.pairedServers) { server in
                    NavigationLink(destination: DashboardView(server: server)) {
                        ServerRow(server: server)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            serverToRemove = server
                        } label: {
                            Label("Remove server", systemImage: "trash")
                        }
                    }
                }

                Section {
                    NavigationLink(destination: PairingView(appState: appState)) {
                        Label("Pair iPhone", systemImage: "qrcode")
                            .foregroundColor(.cyan)
                    }
                }

                if !appState.pairedServers.isEmpty {
                    Section {
                        Label(
                            "Hold the remote on a server to remove it.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("ProxRemote")
            .confirmationDialog(
                "Remove this paired server?",
                isPresented: Binding(
                    get: { serverToRemove != nil },
                    set: { if !$0 { serverToRemove = nil } }
                ),
                presenting: serverToRemove
            ) { server in
                Button("Remove \(server.displayName)", role: .destructive) {
                    appState.removeServer(server)
                    serverToRemove = nil
                }
                Button("Cancel", role: .cancel) { serverToRemove = nil }
            } message: { server in
                Text(
                    "Credentials for \(server.username)@\(server.host) " +
                    "will be deleted from this Apple TV. You can re-pair " +
                    "from the iPhone at any time."
                )
            }
        }
    }
}

private struct ServerRow: View {
    let server: ServerProfile

    var body: some View {
        HStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.title)
                .foregroundColor(.cyan)
                .frame(width: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.displayName)
                    .font(.headline)
                Text("\(server.host):\(server.port)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(server.username)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}
