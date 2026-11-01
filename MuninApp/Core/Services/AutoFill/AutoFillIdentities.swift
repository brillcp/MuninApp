import AuthenticationServices

/// Munin's keyboard suggestions: each password's username and website, kept
/// in the system's AutoFill store so they show above the keyboard. Passwords
/// are never stored there; picking a suggestion opens Munin's AutoFill, which
/// unlocks with Face ID / Touch ID first.
///
/// Updated whenever the password list changes, and removed on sign-out.
/// Nothing happens while Munin isn't turned on in AutoFill settings.
enum AutoFillIdentities {
    /// Replaces the suggestions with `items`. Items without a website or a
    /// username are left out.
    static func update(_ items: [PasswordItem]) {
        let identities: [any ASCredentialIdentity] = items.compactMap { item in
            guard let domain = item.domain, !item.username.isEmpty else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                user: item.username,
                recordIdentifier: item.id.uuidString
            )
        }
        Task {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled else { return }
            try? await store.replaceCredentialIdentities(identities)
        }
    }

    /// Removes every suggestion, on sign-out.
    static func removeAll() {
        Task {
            try? await ASCredentialIdentityStore.shared.removeAllCredentialIdentities()
        }
    }
}
