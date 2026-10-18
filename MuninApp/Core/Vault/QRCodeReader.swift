import CoreImage
import Foundation

/// Reads QR codes from an image (a screenshot or photo of a QR code).
enum QRCodeReader {
    static func messages(in imageData: Data) -> [String] {
        guard let image = CIImage(data: imageData),
              let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              ) else { return [] }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
