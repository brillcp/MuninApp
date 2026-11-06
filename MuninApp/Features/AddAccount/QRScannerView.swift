#if os(iOS)
import SwiftUI
internal import Vision
import VisionKit

/// A full-screen camera view that reports the first QR code it detects.
struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The action to perform with the QR code's text.
    let onFound: (String) -> Void

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

/// A wrapper around VisionKit's live data scanner, configured for QR codes.
struct QRScannerView: UIViewControllerRepresentable {
    /// The action to perform once, with the first QR code's text.
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

    /// A delegate that receives the scanner's results and reports only the first QR code.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// The action to perform with the first QR code's text.
        private let onFound: (String) -> Void
        /// A Boolean value that indicates whether a QR code was already reported.
        private var didFind = false

        /// Creates a coordinator that reports QR codes to the given action.
        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }
    }
}

extension QRScannerView.Coordinator {
    /// Stops scanning and reports the first newly recognized QR code.
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
#endif
