import SwiftUI

/// A view that shows the signed-in user's initials in an accent-colored circle.
struct AccountAvatar: View {
    /// The signed-in user's email address, which the initials come from.
    let email: String?
    /// The circle's diameter.
    let size: CGFloat

    var body: some View {
        Text(verbatim: initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.accent, in: .circle)
    }
}

private extension AccountAvatar {
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
