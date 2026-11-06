import CoreImage
import Foundation

/// A namespace for reading QR codes from an image, such as a screenshot or photo.
enum QRCodeReader {
    /// Returns the text of every QR code found in the image.
    ///
    /// - Parameter imageData: The encoded image data.
    /// - Returns: The decoded messages, or an empty array if the image contains no QR codes.
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
