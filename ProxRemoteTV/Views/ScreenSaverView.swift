import SwiftUI

struct ScreenSaverView: View {
    let nodes: [ClusterResource]
    let onDismiss: () -> Void

    @State private var index: Int = 0
    @State private var timer: Timer?

    private let interval: TimeInterval = 8

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            if !nodes.isEmpty {
                let node = nodes[index % nodes.count]
                VStack(spacing: 30) {
                    Spacer()

                    Image(systemName: "server.rack")
                        .font(.system(size: 100))
                        .foregroundColor(.cyan.opacity(0.7))

                    Text(node.name)
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)

                    Text(node.status.uppercased())
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(node.isRunning ? .green : .gray)

                    Spacer()

                    HStack(spacing: 60) {
                        statBlock(
                            label: "CPU",
                            value: "\(Int((node.cpu ?? 0) * 100))%",
                            icon: "cpu"
                        )
                        statBlock(
                            label: "Memory",
                            value: memPercent(node),
                            icon: "memorychip"
                        )
                        statBlock(
                            label: "Uptime",
                            value: uptimeString(node.uptime ?? 0),
                            icon: "clock"
                        )
                    }
                    .padding(.bottom, 80)

                    Spacer()
                }
                .transition(.opacity)
                .id(index)
            }

            VStack {
                Spacer()
                Text("Press any button to exit")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 30)
            }
        }
        .onAppear { startCycle() }
        .onDisappear { timer?.invalidate() }
        .onTapGesture { onDismiss() }
        .onMoveCommand { _ in onDismiss() }
        .onPlayPauseCommand { onDismiss() }
        .onExitCommand { onDismiss() }
    }

    private func statBlock(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.cyan.opacity(0.6))
            Text(value)
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 22))
                .foregroundColor(.gray)
        }
    }

    private func memPercent(_ node: ClusterResource) -> String {
        guard let mem = node.mem, let maxMem = node.maxmem, maxMem > 0 else {
            return "—"
        }
        let pct = Int((Double(mem) / Double(maxMem)) * 100)
        return "\(pct)%"
    }

    private func uptimeString(_ secs: Int) -> String {
        if secs <= 0 { return "—" }
        let days = secs / 86400
        let hours = (secs % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h"
    }

    private func startCycle() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                index = (index + 1) % max(nodes.count, 1)
            }
        }
    }
}
