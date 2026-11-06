import SwiftUI

/// A form section for adding accounts from an `otpauth://` or
/// `otpauth-migration://` URL.
struct LinkSection: View {
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
