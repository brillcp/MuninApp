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
                if isSaving { ProgressView("Encrypting…") }
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            errorMessage = "No QR code found in that image."
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
            errorMessage = "Couldn't load that image."
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
            errorMessage = "Couldn't read that image."
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
                        ? "That account is already in your vault."
                        : "Those accounts are already in your vault."
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
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Screenshot…", systemImage: "photo")
            }
            #else
            Button {
                isImportingFile = true
            } label: {
                Label("Choose Image…", systemImage: "photo")
            }
            #endif
        } header: {
            Text("QR code")
        } footer: {
            Text("A site's 2FA setup QR code, or Google Authenticator's Transfer accounts → Export accounts QR code to import everything at once.")
        }
    }
}

/// A pasted otpauth:// or otpauth-migration:// link.
private struct LinkSection: View {
    let onSubmit: (String) -> Void
    @State private var link = ""

    var body: some View {
        Section {
            TextField("otpauth://…", text: $link, axis: .vertical)
                .lineLimit(1...4)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Add from Link") { onSubmit(link) }
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Link")
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
            TextField("Issuer, e.g. GitHub", text: $issuer)
            TextField("Account, e.g. you@example.com", text: $name)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            TextField("Setup key", text: $secret)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            Picker("Digits", selection: $digits) {
                Text("6").tag(6)
                Text("8").tag(8)
            }
            Button("Add Account") { onSubmit(issuer, name, secret, digits) }
                .disabled(secret.isEmpty || (issuer.isEmpty && name.isEmpty))
        } header: {
            Text("Enter manually")
        } footer: {
            Text("Sites show the setup key under \"Can't scan the QR code?\".")
        }
    }
}

#Preview {
    AddAccountView { accounts in accounts.count }
}
