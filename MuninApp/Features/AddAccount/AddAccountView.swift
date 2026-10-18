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

    @State private var link = ""
    @State private var issuer = ""
    @State private var name = ""
    @State private var secret = ""
    @State private var digits = 6
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isScanning = false
    @State private var isImportingFile = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                qrSection
                linkSection
                manualSection
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

    // MARK: - Sections

    private var qrSection: some View {
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

    private var linkSection: some View {
        Section {
            TextField("otpauth://…", text: $link, axis: .vertical)
                .lineLimit(1...4)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Add from Link") { submit(text: link) }
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Link")
        }
    }

    private var manualSection: some View {
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
            Button("Add Account", action: submitManual)
                .disabled(secret.isEmpty || (issuer.isEmpty && name.isEmpty))
        } header: {
            Text("Enter manually")
        } footer: {
            Text("Sites show the setup key under \"Can't scan the QR code?\".")
        }
    }

    // MARK: - Input

    private func submit(text: String) {
        do {
            save(try OTPAuthParser.parse(text))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitManual() {
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

#Preview {
    AddAccountView { accounts in accounts.count }
}
