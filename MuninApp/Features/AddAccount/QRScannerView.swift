#if os(iOS)
import SwiftUI
import VisionKit
internal import Vision

/// Full-screen camera that reports the first QR code it sees.
struct ScannerSheet: View {
    /// Called with the QR code's text.
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScannerView(onFound: onFound)
                .ignoresSafeArea()
                .navigationTitle("scanner.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("global.cancel", action: dismiss.callAsFunction)
                    }
                }
        }
    }
}

/// VisionKit's live data scanner, set up to find QR codes.
struct QRScannerView: UIViewControllerRepresentable {
    /// Called once, with the first QR code's text.
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }

    /// Receives the scanner's results and reports the first QR code only.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// Called with the first QR code's text.
        private let onFound: (String) -> Void
        /// Set after the first QR code, so later ones are ignored.
        private var didFind = false

        /// Creates a coordinator that reports to `onFound`.
        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        /// Stops scanning and reports the first newly recognised QR code.
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFind else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    didFind = true
                    dataScanner.stopScanning()
                    onFound(value)
                    return
                }
            }
        }
    }
}
#endif
