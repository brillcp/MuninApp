import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

/// Add accounts from a QR code (camera, screenshot), an otpauth link, or by
/// hand. A Google Authenticator export QR code adds all its accounts at once.
struct AddAccountView: View {
    /// Encrypts and uploads; returns how many were new.
    let onAdd: ([OTPAccount]) async throws -> Int

    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isScanning = false
    @State private var isImportingFile = false
    @State private var photoItem: PhotosPickerItem?

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
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
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
                    Button("global.cancel") { dismiss() }
                }
            }
            .barkNavigationBar(title: "addAccount.title")
            #if os(iOS)
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

    // MARK: - Input

    private func submit(text: String) {
        do {
            save(try OTPAuthParser.parse(text))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitManual(issuer: String, name: String, secret: String, digits: Int) {
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

    private func submit(imageData: Data) {
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
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = Localized("addAccount.error.loadImage")
            return
        }
        submit(imageData: data)
    }
    #else
    private func importFile(_ result: Result<URL, any Error>) {
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

    private func save(_ accounts: [OTPAccount]) {
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

/// Camera scan (iPhone) or an image of a QR code.
private struct QRCodeSection: View {
    @Binding var isScanning: Bool
    @Binding var isImportingFile: Bool
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        Section {
            #if os(iOS)
            if DataScannerViewController.isSupported {
                Button {
                    isScanning = true
                } label: {
                    Label("addAccount.scanQRCode", systemImage: "qrcode.viewfinder")
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("addAccount.chooseScreenshot", systemImage: "photo")
            }
            #else
            Button {
                isImportingFile = true
            } label: {
                Label("addAccount.chooseImage", systemImage: "photo")
            }
            #endif
        } header: {
            Text("addAccount.qr.header")
        } footer: {
            Text("addAccount.qr.footer")
        }
    }
}

/// A pasted otpauth:// or otpauth-migration:// link.
private struct LinkSection: View {
    let onSubmit: (String) -> Void
    @State private var link = ""

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

/// Issuer, account and setup key typed in by hand.
private struct ManualEntrySection: View {
    let onSubmit: (_ issuer: String, _ name: String, _ secret: String, _ digits: Int) -> Void
    @State private var issuer = ""
    @State private var name = ""
    @State private var secret = ""
    @State private var digits = 6

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

#Preview {
    AddAccountView { accounts in accounts.count }
}
