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
        List {
            Section {
                ZStack {
                    if scannerAvailable {
                        QRScannerView(isActive: isVisible && path.isEmpty && !isResolving) { text in
                            handleScan(text)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Camera unavailable", systemImage: "camera")
                        } description: {
                            Text(DataScannerViewController.isSupported
                                 ? "Allow camera access in Settings to scan spool QR codes."
                                 : "This device can't scan. Paste a link or type a code below.")
                        }
                    }
                    if isResolving {
                        ProgressView()
                            .controlSize(.large)
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Point the camera at a Prusament spool QR code or a Spooldeck label.")
            }

            if let message {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Open “Log usage” after scan", isOn: $opensLogUsage)
            }

            Section("Or enter it") {
                HStack {
                    TextField("Link or 6-character code", text: $manualText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { Task { await resolve(manualText) } }
                    Button("Go") { Task { await resolve(manualText) } }
                        .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty || isResolving)
                }
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        manualText = text
                        await resolve(text)
                    }
                }
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
