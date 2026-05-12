import SwiftUI

struct VMDetailView: View {
    let api: ProxmoxAPI
    let resource: ClusterResource
    @State private var config: VMConfig?
    @State private var snapshots: [Snapshot] = []
    @State private var statusData: [String: Any] = [:]
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(resource.displayType) details...")
            } else if let error = error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text(error).foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        // Status header
                        statusHeader

                        // Tab picker
                        Picker("Section", selection: $selectedTab) {
                            Text("Overview").tag(0)
                            Text("Configuration").tag(1)
                            Text("Snapshots").tag(2)
                        }
                        .pickerStyle(.segmented)

                        switch selectedTab {
                        case 0: overviewTab
                        case 1: configTab
                        case 2: snapshotTab
                        default: EmptyView()
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle(resource.name)
        .task { await load() }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 20) {
            Image(systemName: resource.isVM ? "desktopcomputer" : "shippingbox")
                .font(.system(size: 40))
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.title)
                    .fontWeight(.bold)
                HStack(spacing: 12) {
                    Circle()
                        .fill(resource.isRunning ? Color.green : Color.red)
                        .frame(width: 14, height: 14)
                    Text(resource.isRunning ? "Running" : "Stopped")
                        .foregroundColor(
                            resource.isRunning ? .green : .red
                        )
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("\(resource.displayType) \(resource.vmid ?? 0)")
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("Node: \(resource.node)")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if resource.isRunning, let uptime = resource.uptime {
                VStack {
                    Text("Uptime")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatUptime(uptime))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            if resource.isRunning {
                HStack(spacing: 40) {
                    gaugeView(
                        "CPU",
                        value: resource.cpuPercent,
                        color: .cyan
                    )
                    gaugeView(
                        "Memory",
                        value: resource.memPercent,
                        subtitle: "\(formatBytes(resource.mem)) / \(formatBytes(resource.maxmem))",
                        color: .purple
                    )
                    if resource.disk != nil {
                        gaugeView(
                            "Disk",
                            value: resource.diskPercent,
                            subtitle: "\(formatBytes(resource.disk)) / \(formatBytes(resource.maxdisk))",
                            color: .orange
                        )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("This \(resource.displayType.lowercased()) is currently stopped.")
                        .foregroundColor(.secondary)
                }
            }

            // Basic info from status
            if let name = statusData["name"] as? String {
                infoRow("Name", name)
            }
            if let pid = statusData["pid"] as? Int {
                infoRow("PID", "\(pid)")
            }
            if let cpus = resource.maxcpu {
                infoRow("vCPUs", "\(cpus)")
            }
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config = config {
                if let cores = config.cores {
                    infoRow("CPU Cores", "\(cores)")
                }
                if let sockets = config.sockets {
                    infoRow("Sockets", "\(sockets)")
                }
                if let memory = config.memory {
                    infoRow("Memory", "\(memory) MB")
                }
                if let balloon = config.balloon {
                    infoRow("Balloon", "\(balloon) MB")
                }
                if let ostype = config.ostype {
                    infoRow("OS Type", ostype)
                }
                if let boot = config.boot {
                    infoRow("Boot Order", boot)
                }
                if let agent = config.agent {
                    infoRow("QEMU Agent", agent)
                }
                if let net0 = config.net0 {
                    infoRow("Network (net0)", net0)
                }
                if let scsi0 = config.scsi0 {
                    infoRow("Disk (scsi0)", scsi0)
                }
                if let ide2 = config.ide2 {
                    infoRow("CD/DVD (ide2)", ide2)
                }
            } else {
                Text("No configuration data available")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Snapshot Tab

    private var snapshotTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshots.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "camera")
                        .foregroundColor(.secondary)
                    Text("No snapshots")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(snapshots) { snap in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snap.name)
                                .font(.headline)
                            if let desc = snap.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(snap.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if snap.vmstate == 1 {
                            Image(systemName: "memorychip")
                                .foregroundColor(.yellow)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    // MARK: - Helpers

    private func load() async {
        isLoading = true
        error = nil
        do {
            async let configTask = api.fetchVMConfig(
                node: resource.node,
                vmid: resource.vmid ?? 0,
                type: resource.type
            )
            async let snapshotsTask = api.fetchSnapshots(
                node: resource.node,
                vmid: resource.vmid ?? 0,
                type: resource.type
            )
            async let statusTask = api.fetchVMStatus(
                node: resource.node,
                vmid: resource.vmid ?? 0,
                type: resource.type
            )

            config = try await configTask
            snapshots = try await snapshotsTask
            statusData = try await statusTask
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.body)
    }

    private func gaugeView(
        _ title: String,
        value: Double,
        subtitle: String? = nil,
        color: Color
    ) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(value / 100, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))%")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .frame(width: 140, height: 140)
            Text(title).font(.headline)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: Int?) -> String {
        guard let bytes = bytes else { return "0" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        let mins = (seconds % 3600) / 60
        return "\(hours)h \(mins)m"
    }
}
