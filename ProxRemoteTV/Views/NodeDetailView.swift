import SwiftUI

struct NodeDetailView: View {
    let api: ProxmoxAPI
    let resource: ClusterResource
    @State private var status: NodeStatus?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading node details...")
            } else if let error = error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text(error).foregroundColor(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else if let s = status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        // Status header
                        HStack(spacing: 20) {
                            Circle()
                                .fill(resource.isRunning ? Color.green : Color.red)
                                .frame(width: 20, height: 20)
                            Text(resource.isRunning ? "Online" : "Offline")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(
                                    resource.isRunning ? .green : .red
                                )
                            Spacer()
                            if let uptime = s.uptime {
                                Text("Uptime: \(formatUptime(uptime))")
                                    .foregroundColor(.secondary)
                            }
                        }

                        // System info
                        if let model = s.cpuModel {
                            infoRow("CPU Model", model)
                        }
                        if let cores = s.cpuCores {
                            infoRow("CPU Cores", "\(cores)")
                        }
                        if let kv = s.kernelVersion {
                            infoRow("Kernel", kv)
                        }
                        if let pv = s.pveVersion {
                            infoRow("Proxmox VE", pv)
                        }

                        Divider()

                        // Gauges
                        HStack(spacing: 40) {
                            gaugeView(
                                "CPU",
                                value: (s.cpu ?? 0) * 100,
                                color: .cyan
                            )
                            gaugeView(
                                "Memory",
                                value: pct(s.memoryUsed, s.memoryTotal),
                                subtitle: "\(formatBytes(s.memoryUsed)) / \(formatBytes(s.memoryTotal))",
                                color: .purple
                            )
                            gaugeView(
                                "Disk",
                                value: pct(s.rootfsUsed, s.rootfsTotal),
                                subtitle: "\(formatBytes(s.rootfsUsed)) / \(formatBytes(s.rootfsTotal))",
                                color: .orange
                            )
                            if let swapTotal = s.swapTotal, swapTotal > 0 {
                                gaugeView(
                                    "Swap",
                                    value: pct(s.swapUsed, s.swapTotal),
                                    subtitle: "\(formatBytes(s.swapUsed)) / \(formatBytes(s.swapTotal))",
                                    color: .yellow
                                )
                            }
                        }
                    }
                    .padding(40)
                }
            }
        }
        .navigationTitle(resource.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            status = try await api.fetchNodeStatus(node: resource.name)
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

            Text(title)
                .font(.headline)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func pct(_ used: Int?, _ total: Int?) -> Double {
        guard let u = used, let t = total, t > 0 else { return 0 }
        return Double(u) / Double(t) * 100
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
