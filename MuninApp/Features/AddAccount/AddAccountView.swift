import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

/// A view for adding two-factor accounts from a QR code, an `otpauth://` URL,
/// or manual entry.
///
/// A Google Authenticator export QR code adds all of its accounts at once.
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    /// The most recent error, shown at the bottom of the form.
    @State private var errorMessage: String?
    /// A Boolean value that indicates whether accounts are being encrypted and
    /// uploaded.
    @State private var isSaving = false
    /// A Boolean value that indicates whether the camera scanner is presented (iOS).
    @State private var isScanning = false
    /// A Boolean value that indicates whether the image file picker is presented
    /// (macOS).
    @State private var isImportingFile = false
    /// The image selected from Photos (iOS).
    @State private var photoItem: PhotosPickerItem?

    /// Encrypts and uploads accounts, returning the number of new accounts added.
    let onAdd: ([OTPAccount]) async throws -> Int

    var body: some View {
        NavigationStack {
            Form {
                QRCodeSection(
                    isScanning: $isScanning,
                    isImportingFile: $isImportingFile,
                    photoItem: $photoItem
                )
                LinkSection(onSubmit: submit(text:))
                ManualEntrySection(onSubmit: submitManual)
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: DesignKit.Icon.warning)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isSaving)
            .overlay {
                if isSaving { ProgressView("addAccount.encrypting") }
            }
            .navigationTitle("addAccount.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("global.cancel", action: dismiss.callAsFunction)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $isScanning) {
                ScannerSheet { value in
                    isScanning = false
                    submit(text: value)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            #else
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
                importFile(result)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 540)
        #endif
    }
}

private extension AddAccountView {
    /// Parses an `otpauth://` or `otpauth-migration://` URL and saves its
    /// accounts.
    func submit(text: String) {
        do {
            save(try OTPAuthParser.parse(text))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a manually entered account.
    func submitManual(issuer: String, name: String, secret: String, digits: Int) {
        guard let secretData = Base32.decode(secret) else {
            errorMessage = OTPAuthParser.ParseError.invalidSecret.localizedDescription
            return
        }
        save([OTPAccount(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            secret: secretData,
            digits: digits
        )])
    }

    /// Reads the QR codes in an image and saves the accounts from the first
    /// valid one.
    func submit(imageData: Data) {
        let messages = QRCodeReader.messages(in: imageData)
        guard !messages.isEmpty else {
            errorMessage = Localized("addAccount.error.noQRCode")
            return
        }
        for message in messages {
            if let accounts = try? OTPAuthParser.parse(message) {
                save(accounts)
                return
            }
        }
        errorMessage = OTPAuthParser.ParseError.unsupported.localizedDescription
    }

    #if os(iOS)
    /// Loads the selected image and reads its QR code.
    func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = Localized("addAccount.error.loadImage")
            return
        }
        submit(imageData: data)
    }
    #else
    /// Reads the selected image file and its QR code.
    func importFile(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = Localized("addAccount.error.readImage")
            return
        }
        submit(imageData: data)
    }
    #endif

    // MARK: - Save

    /// Encrypts and uploads the accounts, then dismisses the sheet.
    ///
    /// If every account already exists, the sheet stays open and shows an
    /// error.
    func save(_ accounts: [OTPAccount]) {
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let added = try await onAdd(accounts)
                if added == 0 {
                    errorMessage = accounts.count == 1
                        ? Localized("addAccount.error.alreadyAddedOne")
                        : Localized("addAccount.error.alreadyAddedMany")
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.muninDescription
            }
        }
    }
}

// MARK: - Sections

/// A form section for adding accounts from a QR code, by camera scan or image.
private struct QRCodeSection: View {
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

/// A form section for adding accounts from an `otpauth://` or
/// `otpauth-migration://` URL.
private struct LinkSection: View {
    @State private var link = ""
    let onSubmit: (String) -> Void

    var body: some View {
        Section {
            TextField("addAccount.link.placeholder", text: $link, axis: .vertical)
                .lineLimit(1...4)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("addAccount.link.add") { onSubmit(link) }
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("addAccount.link.header")
        }
    }
}

/// A form section for entering an account's issuer, name, and setup key
/// manually.
private struct ManualEntrySection: View {
    /// The service's name.
    @State private var issuer = ""
    /// The account's name at the service.
    @State private var name = ""
    /// The Base32 setup key.
    @State private var secret = ""
    /// The number of digits per code, either 6 or 8.
    @State private var digits = 6
    /// The action to perform with the issuer, account name, Base32 setup key,
    /// and digit count.
    let onSubmit: (_ issuer: String, _ name: String, _ secret: String, _ digits: Int) -> Void

    var body: some View {
        Section {
            TextField("addAccount.manual.issuer", text: $issuer)
            TextField("addAccount.manual.account", text: $name)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("addAccount.manual.setupKey", text: $secret)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            Picker("addAccount.manual.digits", selection: $digits) {
                Text(6, format: .number).tag(6)
                Text(8, format: .number).tag(8)
            }
            Button("addAccount.manual.add") { onSubmit(issuer, name, secret, digits) }
                .disabled(secret.isEmpty || (issuer.isEmpty && name.isEmpty))
        } header: {
            Text("addAccount.manual.header")
        } footer: {
            Text("addAccount.manual.footer")
        }
    }
}
