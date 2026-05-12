import SwiftUI

struct NotificationsView: View {
    let tasks: [ClusterTask]

    var recentInteresting: [ClusterTask] {
        // Show running + recently failed (last 24h) + last 5 OK
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86400)

        let running = tasks.filter { $0.isRunning }
        let failed = tasks
            .filter { $0.isFailed && $0.startDate > dayAgo }
            .prefix(5)
        let ok = tasks
            .filter { $0.isOK && $0.startDate > dayAgo }
            .prefix(3)

        return Array(running) + Array(failed) + Array(ok)
    }

    var body: some View {
        let entries = recentInteresting
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label("Recent Activity", systemImage: "bell")
                    .font(.title3.bold())
                    .foregroundColor(.cyan)

                ForEach(entries.prefix(6)) { task in
                    HStack(spacing: 14) {
                        statusIcon(for: task)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.displayType)
                                .font(.body.weight(.medium))
                            Text("\(task.node) • \(task.user)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(relativeTime(task.startDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func statusIcon(for task: ClusterTask) -> some View {
        if task.isRunning {
            ProgressView().scaleEffect(0.8)
        } else if task.isFailed {
            Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "\(secs)s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }
}
