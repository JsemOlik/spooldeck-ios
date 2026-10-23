import SwiftUI
import Vision
import VisionKit

struct ScanTab: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScanView(path: $path)
                .withRoutes()
        }
    }
}

struct ScanView: View {
    @Environment(AppModel.self) private var app
    @Binding var path: [Route]
    @AppStorage("scanOpensLogUsage") private var opensLogUsage = false
    @State private var manualText = ""
    @State private var isResolving = false
    @State private var message: String?
    @State private var lastScanned: (text: String, at: Date)?
    @State private var isVisible = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        Screen {
            ZStack {
                if scannerAvailable {
                    QRScannerView(isActive: isVisible && path.isEmpty && !isResolving) { text in
                        handleScan(text)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Theme.mutedForeground)
                        Text("Camera unavailable").font(.headline)
                        Text(DataScannerViewController.isSupported
                             ? "Allow camera access in Settings to scan spool QR codes."
                             : "This device can't scan. Paste a link or type a code below.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.muted.opacity(0.5))
                }
                ScanFrame()
                    .allowsHitTesting(false)
                if isResolving {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))

            Text("Point the camera at a Prusament spool QR code or a Spooldeck label.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.destructive.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }

            Card {
                Toggle("Open “Log usage” after scan", isOn: $opensLogUsage)
                    .font(.subheadline)
                    .tint(Theme.primary)
            }

            Card("Or enter it") {
                HStack(spacing: 8) {
                    TextField("Link or 6-character code", text: $manualText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await resolve(manualText) } }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.input))
                    Button("Go") { Task { await resolve(manualText) } }
                        .buttonStyle(.spoolPrimary)
                        .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty || isResolving)
                }
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        manualText = text
                        await resolve(text)
                    }
                }
                .tint(Theme.primary)
            }
        }
        .navigationTitle("Scan")
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private func handleScan(_ text: String) {
        // The scanner reports the same code repeatedly while it's in view.
        if let last = lastScanned, last.text == text, Date().timeIntervalSince(last.at) < 3 { return }
        lastScanned = (text, Date())
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await resolve(text) }
    }

    private func resolve(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResolving else { return }
        if case .unknown = ScanClassifier.classify(trimmed) {
            message = "That code isn't a Prusament spool or a Spooldeck label."
            return
        }
        isResolving = true
        message = nil
        defer { isResolving = false }
        do {
            let result: ScanResolution = try await app.api.post("scan/resolve", body: ["text": trimmed])
            switch result.kind {
            case "spool":
                if let id = result.id {
                    manualText = ""
                    path.append(.spool(id: id, logUsage: opensLogUsage))
                }
            case "prusament":
                if let url = result.url {
                    manualText = ""
                    path.append(.prusament(url: url))
                }
            default:
                message = result.error ?? "Nothing found for that code."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Corner brackets over the camera, like the web scanner's viewfinder.
private struct ScanFrame: View {
    var body: some View {
        let size: CGFloat = 200
        let arm: CGFloat = 28
        Path { p in
            for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (size, 0, -1, 1), (0, size, 1, -1), (size, size, -1, -1)] {
                p.move(to: CGPoint(x: x, y: y + dy * arm))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + dx * arm, y: y))
            }
        }
        .stroke(Theme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}

/// Live QR scanning with VisionKit.
struct QRScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if isActive, !controller.isScanning {
            try? controller.startScanning()
        } else if !isActive, controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
