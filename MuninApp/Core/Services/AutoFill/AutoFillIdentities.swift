import AuthenticationServices

/// Manages the app's AutoFill keyboard suggestions.
///
/// Each password's username and website are stored in the system's credential
/// identity store so they appear above the keyboard. Passwords are never
/// stored there; choosing a suggestion opens the AutoFill extension, which
/// unlocks with Face ID or Touch ID first.
///
/// Suggestions update whenever the password list changes and are removed on
/// sign-out. Updates have no effect while the app isn't enabled as an AutoFill
/// provider.
enum AutoFillIdentities {
    /// Replaces the suggestions with the given items.
    ///
    /// Items without a website or username are skipped.
    ///
    /// - Parameter items: The password items to suggest.
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

    /// Removes all suggestions.
    static func removeAll() {
        Task {
            try? await ASCredentialIdentityStore.shared.removeAllCredentialIdentities()
        }
    }
}
