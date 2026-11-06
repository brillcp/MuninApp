import SwiftUI

/// A form section for entering an account's issuer, name, and setup key
/// manually.
struct ManualEntrySection: View {
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
