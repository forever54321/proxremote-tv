import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingView: View {
    @ObservedObject var appState: AppState
    @StateObject private var pairing = PairingService()
    @Environment(\.dismiss) private var dismiss

    @State private var pairedServerName: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Image(systemName: "appletvremote.gen4")
                    .font(.system(size: 80))
                    .foregroundColor(.cyan)

                if let name = pairedServerName {
                    // ── Success state ──────────────────────────────────────
                    successView(name: name)
                } else if pairing.isPairing {
                    // ── QR + code ──────────────────────────────────────────
                    activePairingView
                } else {
                    // ── Idle: tap to start ────────────────────────────────
                    idleView
                }
            }
            .padding(60)
            .onChange(of: pairing.receivedServer) { server in
                guard let server = server else { return }
                appState.addServer(server)
                pairedServerName = server.displayName
                // Auto-dismiss after a short success display
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    dismiss()
                }
            }
            .onDisappear {
                pairing.stopPairing()
            }
        }
    }

    // MARK: - Subviews

    private var activePairingView: some View {
        VStack(spacing: 24) {
            Text("Pair with iPhone")
                .font(.largeTitle.bold())

            if let qrImage = generateQRCode(from: pairing.qrPayload) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 320, height: 320)
                    .cornerRadius(16)
            }

            Text("Scan with ProxRemote on your iPhone")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text("Code:")
                    .foregroundColor(.secondary)
                Text(pairing.pairingCode)
                    .font(.system(
                        size: 48,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .foregroundColor(.cyan)
            }

            Text("IP: \(pairing.localIP)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(role: .destructive) {
                pairing.stopPairing()
            } label: {
                Label("Cancel pairing", systemImage: "xmark.circle")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .padding(.top, 16)
        }
    }

    private var idleView: some View {
        VStack(spacing: 20) {
            Text("Pair with iPhone")
                .font(.largeTitle.bold())

            Text(
                "Open ProxRemote on your iPhone, tap the TV icon in the " +
                "server list, then scan the QR code that appears here."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            Button { pairing.startPairing() } label: {
                Label("Start Pairing", systemImage: "qrcode")
                    .font(.title3)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.top, 16)
        }
    }

    private func successView(name: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Paired!")
                .font(.largeTitle.bold())

            Text(name)
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Returning to server list…")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 24)
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 320.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        guard let cgImage = context.createCGImage(
            scaledImage,
            from: scaledImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
