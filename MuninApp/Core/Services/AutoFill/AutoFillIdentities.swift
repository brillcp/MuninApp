import AuthenticationServices

/// Manages the app's AutoFill keyboard suggestions.
///
/// Each password's username and website are stored in the system's credential
/// identity store so they appear above the keyboard. Passwords are never
/// stored there; choosing a suggestion opens the AutoFill extension, which
/// unlocks with Face ID or Touch ID first.
///
/// A load replaces all suggestions; a create, edit, or delete changes only
/// that item's. Suggestions are removed on sign-out. Changes have no effect
/// while the app isn't enabled as an AutoFill provider.
enum AutoFillIdentities {
    /// Replaces all suggestions with the given items.
    static func replaceAll(with items: [PasswordItem]) {
        let identities = Self.identities(for: items)
        Task {
            guard await isEnabled() else { return }
            try? await ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities)
        }
    }

    /// Adds suggestions for new items.
    static func save(_ items: [PasswordItem]) {
        let identities = Self.identities(for: items)
        guard !identities.isEmpty else { return }
        Task {
            guard await isEnabled() else { return }
            try? await ASCredentialIdentityStore.shared.saveCredentialIdentities(identities)
        }
    }

    /// Replaces an edited item's suggestion.
    static func replace(_ original: PasswordItem, with updated: PasswordItem) {
        let removed = Self.identities(for: [original])
        let added = Self.identities(for: [updated])
        Task {
            guard await isEnabled() else { return }
            let store = ASCredentialIdentityStore.shared
            if !removed.isEmpty { try? await store.removeCredentialIdentities(removed) }
            if !added.isEmpty { try? await store.saveCredentialIdentities(added) }
        }
    }

    /// Removes deleted items' suggestions.
    static func remove(_ items: [PasswordItem]) {
        let identities = Self.identities(for: items)
        guard !identities.isEmpty else { return }
        Task {
            guard await isEnabled() else { return }
            try? await ASCredentialIdentityStore.shared.removeCredentialIdentities(identities)
        }
    }

    /// Removes all suggestions.
    static func removeAll() {
        Task {
            try? await ASCredentialIdentityStore.shared.removeAllCredentialIdentities()
        }
    }
}

private extension AutoFillIdentities {
    /// Returns the suggestions for items, skipping those without a website or username.
    static func identities(for items: [PasswordItem]) -> [any ASCredentialIdentity] {
        items.compactMap { item in
            guard let domain = item.domain, !item.username.isEmpty else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                user: item.username,
                recordIdentifier: item.id.uuidString
            )
        }
    }

    /// Returns a Boolean value that indicates whether the app is an enabled AutoFill provider.
    static func isEnabled() async -> Bool {
        await ASCredentialIdentityStore.shared.state().isEnabled
    }
}
