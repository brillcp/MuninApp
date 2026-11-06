import PhotosUI
import SwiftUI
#if os(iOS)
import VisionKit
#endif

/// A form section for adding accounts from a QR code, by camera scan or image.
struct QRCodeSection: View {
    /// A Boolean value that indicates whether the camera scanner is presented (iOS).
    @Binding var isScanning: Bool
    /// A Boolean value that indicates whether the image file picker is presented
    /// (macOS).
    @Binding var isImportingFile: Bool
    /// The image selected from Photos (iOS).
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        Section {
            #if os(iOS)
            if DataScannerViewController.isSupported {
                Button {
                    isScanning = true
                } label: {
                    Label("addAccount.scanQRCode", systemImage: DesignKit.Icon.scanQRCode)
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("addAccount.chooseScreenshot", systemImage: DesignKit.Icon.chooseImage)
            }
            #else
            Button {
                isImportingFile = true
            } label: {
                Label("addAccount.chooseImage", systemImage: DesignKit.Icon.chooseImage)
            }
            #endif
        } header: {
            Text("addAccount.qr.header")
        } footer: {
            Text("addAccount.qr.footer")
        }
    }
}
