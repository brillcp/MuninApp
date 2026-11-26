import SwiftUI

/// A view that shows the signed-in user's initials in an accent-colored circle, above their email address.
struct AccountHeader: View {
    /// The signed-in user's email address.
    let email: String?

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            AccountAvatar(email: email, size: DesignKit.Spacing.Primitive.s64)
            if let email {
                Text(verbatim: email)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
