import SwiftUI

struct DashboardView: View {
    let server: ServerProfile
    @StateObject private var api: ProxmoxAPI
    @State private var resources: [ClusterResource] = []
    @State private var tasks: [ClusterTask] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var lastUpdated: Date?
    @State private var refreshTask: Task<Void, Never>?
    @State private var idleTimer: Timer?
    @State private var showScreenSaver = false
    private let autoRefreshInterval: TimeInterval = 30
    private let idleTimeout: TimeInterval = 90

    init(server: ServerProfile) {
        self.server = server
        _api = StateObject(wrappedValue: ProxmoxAPI(server: server))
    }

    var nodes: [ClusterResource] { resources.filter { $0.isNode } }
    var vms: [ClusterResource] { resources.filter { $0.isVM } }
    var containers: [ClusterResource] { resources.filter { $0.isContainer } }
    var storage: [ClusterResource] { resources.filter { $0.isStorage } }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Connecting to \(server.displayName)...")
            } else if let error = error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await loadResources() } }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 50) {
                        // Recent activity / notifications
                        NotificationsView(tasks: tasks)

                        // Summary
                        summarySection

                        // Nodes
                        if !nodes.isEmpty {
                            resourceSection(
                                title: "Nodes",
                                icon: "server.rack",
                                items: nodes
                            )
                        }

                        // VMs
                        if !vms.isEmpty {
                            resourceSection(
                                title: "Virtual Machines",
                                icon: "desktopcomputer",
                                items: vms
                            )
                        }

                        // Containers
                        if !containers.isEmpty {
                            resourceSection(
                                title: "Containers",
                                icon: "shippingbox",
                                items: containers
                            )
                        }

                        // Storage
                        if !storage.isEmpty {
                            storageSection
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle(server.displayName)
        .task { await loadResources() }
        .refreshable { await loadResources() }
        .onAppear {
            startAutoRefresh()
            resetIdleTimer()
        }
        .onDisappear {
            refreshTask?.cancel()
            idleTimer?.invalidate()
        }
        .fullScreenCover(isPresented: $showScreenSaver) {
            ScreenSaverView(nodes: nodes) {
                showScreenSaver = false
                resetIdleTimer()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let lastUpdated = lastUpdated, !isLoading {
                Text("Updated \(timeAgo(lastUpdated))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(20)
            }
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: idleTimeout,
            repeats: false
        ) { _ in
            if !nodes.isEmpty { showScreenSaver = true }
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(autoRefreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await loadResources()
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }

    // MARK: - Summary

    private var summarySection: some View {
        HStack(spacing: 30) {
            summaryCard(
                "Nodes",
                count: nodes.count,
                online: nodes.filter(\.isRunning).count,
                icon: "server.rack",
                color: .cyan
            )
            summaryCard(
                "VMs",
                count: vms.count,
                online: vms.filter(\.isRunning).count,
                icon: "desktopcomputer",
                color: .blue
            )
            summaryCard(
                "Containers",
                count: containers.count,
                online: containers.filter(\.isRunning).count,
                icon: "shippingbox",
                color: .purple
            )
            summaryCard(
                "Storage",
                count: storage.count,
                online: storage.filter(\.isRunning).count,
                icon: "externaldrive",
                color: .orange
            )
        }
    }

    private func summaryCard(
        _ title: String,
        count: Int,
        online: Int,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            Text("\(online)/\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Resource Sections

    private func resourceSection(
        title: String,
        icon: String,
        items: [ClusterResource]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.title2)
                .fontWeight(.bold)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 40),
                    GridItem(.flexible(), spacing: 40),
                    GridItem(.flexible(), spacing: 40),
                ],
                spacing: 40
            ) {
                ForEach(items) { resource in
                    NavigationLink(
                        destination: resourceDetailView(for: resource)
                    ) {
                        ResourceCard(resource: resource)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Storage", systemImage: "externaldrive")
                .font(.title2)
                .fontWeight(.bold)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ],
                spacing: 20
            ) {
                ForEach(storage) { s in
                    StorageCard(resource: s)
                }
            }
        }
    }

    @ViewBuilder
    private func resourceDetailView(for resource: ClusterResource) -> some View {
        if resource.isNode {
            NodeDetailView(api: api, resource: resource)
        } else {
            VMDetailView(api: api, resource: resource)
        }
    }

    // MARK: - Data

    private func loadResources() async {
        if resources.isEmpty { isLoading = true }
        error = nil
        do {
            try await api.login()
            async let res = api.fetchClusterResources()
            async let tks = api.fetchClusterTasks()
            resources = try await res
            tasks = (try? await tks) ?? []
            lastUpdated = Date()
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Resource Card

struct ResourceCard: View {
    let resource: ClusterResource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header — status dot + name
            HStack(spacing: 10) {
                Circle()
                    .fill(resource.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(resource.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            // Subtitle — type and VMID, or "Stopped"
            HStack {
                if let vmid = resource.vmid {
                    Text("\(resource.displayType) \(vmid)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !resource.isRunning {
                    Text("Stopped")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }

            // Bars — always rendered (use 0% for stopped) to keep height
            // consistent across cards.
            VStack(spacing: 10) {
                MiniBar(
                    label: "CPU",
                    value: resource.isRunning ? resource.cpuPercent : 0,
                    color: .cyan,
                    dimmed: !resource.isRunning
                )
                MiniBar(
                    label: "RAM",
                    value: resource.isRunning ? resource.memPercent : 0,
                    color: .purple,
                    dimmed: !resource.isRunning
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }
}

struct StorageCard: View {
    let resource: ClusterResource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "externaldrive")
                    .foregroundColor(.orange)
                Text(resource.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            MiniBar(
                label: "Disk",
                value: resource.diskPercent,
                color: .orange
            )
            Text(resource.node)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct MiniBar: View {
    let label: String
    let value: Double
    let color: Color
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.25))
                    Capsule()
                        .fill(color)
                        .frame(
                            width: max(0, geo.size.width * value / 100)
                        )
                }
            }
            .frame(height: 8)

            Text("\(Int(value))%")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .opacity(dimmed ? 0.35 : 1.0)
    }
}
