import SwiftUI

/// A view that shows the signed-in user's initials in an accent-colored circle, above their email address.
struct AccountHeader: View {
    /// The signed-in user's email address.
    let email: String?

    var body: some View {
        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
            Text(verbatim: initials)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(.accent, in: .circle)
            if let email {
                Text(verbatim: email)
                    .font(.headline)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension AccountHeader {
    /// The user's initials, derived from the local part of their email address.
    ///
    /// For example, `jane.doe@…` becomes "JD" and `jane@…` becomes "J".
    var initials: String {
        guard let local = email?.split(separator: "@").first else { return "?" }
        let parts = local.split(whereSeparator: { ".-_+".contains($0) })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
