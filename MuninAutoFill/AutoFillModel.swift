import AuthenticationServices
import Foundation
import Observation

/// Completes or cancels the AutoFill request. Implemented by the extension's
/// view controller.
protocol AutoFillHandler: AnyObject {
    /// Fills a login with a username and password.
    func fill(user: String, password: String)
    /// Fills a 2FA code field.
    func fill(code: String)
    /// Closes AutoFill without filling anything.
    func cancel()
}

/// AutoFill's state: unlocking with Face ID / Touch ID, loading the vault
/// from Munin, and the passwords or 2FA codes to choose from.
///
/// Everything is decrypted in memory only and dropped when AutoFill closes.
/// Passwords stay encrypted until one is chosen.
@Observable
final class AutoFillModel {
    /// What AutoFill was opened for.
    enum Mode {
        /// A login field: passwords.
        case passwords
        /// A one-time code field: 2FA codes.
        case oneTimeCodes
    }

    /// Where AutoFill is.
    enum State: Equatable {
        /// Waiting for Face ID / Touch ID.
        case locked
        /// Unlocking, or loading the vault from Munin.
        case working
        /// The list is ready.
        case ready
        /// AutoFill can't be used right now, and why.
        case unavailable(String)
    }

    /// The unlocked vault key, while AutoFill is open.
    private var vault: UnlockedVault?
    /// Completes or cancels the request.
    private weak var handler: AutoFillHandler?

    /// Where AutoFill is.
    private(set) var state: State = .locked
    /// The user's passwords, with name, URL and username decrypted.
    private(set) var passwords: [PasswordItem] = []
    /// The user's 2FA accounts, decrypted.
    private(set) var codes: [VaultItem] = []
    /// The search field's text.
    var searchText = ""

    /// What AutoFill was opened for.
    let mode: Mode
    /// The sites asking, as domains: "github.com".
    let domains: [String]
    /// Set when a keyboard suggestion was tapped: the item to fill once unlocked.
    let requestedItemID: UUID?

    /// Creates a model for one AutoFill request.
    init(mode: Mode, serviceIdentifiers: [ASCredentialServiceIdentifier], requestedItemID: UUID? = nil, handler: AutoFillHandler) {
        self.mode = mode
        self.requestedItemID = requestedItemID
        self.handler = handler
        domains = serviceIdentifiers.compactMap(Self.domain(of:))
    }
}

// MARK: - Public functions
extension AutoFillModel {
    /// Passwords for the sites asking, matched by domain.
    var suggestedPasswords: [PasswordItem] {
        passwords.filter { item in item.domain.map(matchesRequest) ?? false }
    }

    /// Every password matching the search, by name.
    var allPasswords: [PasswordItem] {
        let sorted = passwords.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
                || $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 2FA accounts whose issuer matches the sites asking: "GitHub" for github.com.
    var suggestedCodes: [VaultItem] {
        let names = Set(domains.map(Self.siteName(of:)))
        return codes.filter { names.contains(Self.compact($0.account.issuer)) }
    }

    /// Every 2FA account matching the search, by issuer.
    var allCodes: [VaultItem] {
        let sorted = codes.sorted { $0.account.title.localizedStandardCompare($1.account.title) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.account.title.localizedCaseInsensitiveContains(searchText)
                || ($0.account.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Unlocks with this device's Face ID / Touch ID copy of the vault key,
    /// then loads the vault. The app saves that copy when the vault is first
    /// unlocked with Face ID / Touch ID turned on.
    func unlock() async {
        guard state == .locked else { return }
        guard let userID = KeychainService.loadUserID() else {
            state = .unavailable(Localized("autofill.signIn"))
            return
        }
        guard VaultKeyStore.hasBiometric(userID: userID) else {
            state = .unavailable(Localized("autofill.turnOnBiometrics"))
            return
        }
        state = .working
        let reason = Localized("lock.reason")
        let result = await Task.detached(priority: .userInitiated) {
            VaultKeyStore.loadWithBiometrics(userID: userID, reason: reason)
        }.value
        switch result {
        case .unlocked(let unlocked):
            vault = unlocked
            await load()
        case .canceled:
            state = .locked
        case .notAvailable:
            state = .unavailable(Localized("autofill.turnOnBiometrics"))
        case .failed:
            state = .unavailable(Localized("lock.biometrics.failed"))
        }
    }

    /// Fills the chosen password, decrypting it only now.
    func choose(_ item: PasswordItem) {
        guard let vault,
              let password = try? VaultCrypto.open(item.encryptedPassword, field: "password", key: vault.key, userID: vault.userID) else {
            state = .unavailable(Localized("autofill.decryptFailed"))
            return
        }
        handler?.fill(user: item.username, password: password)
    }

    /// Fills the chosen account's current 2FA code.
    func choose(_ item: VaultItem) {
        handler?.fill(code: item.account.code(at: .now))
    }

    /// Closes AutoFill without filling anything.
    func cancel() {
        handler?.cancel()
    }
}

// MARK: - Private functions
private extension AutoFillModel {
    /// Loads and decrypts the passwords or 2FA accounts. For a tapped keyboard
    /// suggestion, fills that item straight away.
    func load() async {
        guard let vault else { return }
        let service = MuninService(tokenProvider: AuthTokenProvider.shared)
        do {
            switch mode {
            case .passwords:
                passwords = try await service.passwords().compactMap { Self.item(from: $0, vault: vault) }
                if let requestedItemID, let item = passwords.first(where: { $0.id == requestedItemID }) {
                    choose(item)
                    return
                }
            case .oneTimeCodes:
                codes = try await service.entries().compactMap { entry in
                    (try? VaultCrypto.open(entry.ciphertext, key: vault.key, userID: vault.userID))
                        .map { VaultItem(id: entry.id, account: $0) }
                }
            }
            state = .ready
        } catch {
            state = .unavailable(error.muninDescription)
        }
    }

    /// Whether `domain` belongs to one of the sites asking: the same domain,
    /// or one a subdomain of the other ("accounts.github.com" and "github.com").
    func matchesRequest(_ domain: String) -> Bool {
        domains.contains { requested in
            requested == domain || requested.hasSuffix("." + domain) || domain.hasSuffix("." + requested)
        }
    }

    /// Decrypts an item's name, URL and username; password and note stay encrypted.
    static func item(from entry: EncryptedPassword, vault: UnlockedVault) -> PasswordItem? {
        /// Decrypts one field.
        func open(_ ciphertext: String, _ field: String) -> String? {
            try? VaultCrypto.open(ciphertext, field: field, key: vault.key, userID: vault.userID)
        }
        guard let name = open(entry.name, "name"),
              let url = open(entry.url, "url"),
              let username = open(entry.username, "username") else { return nil }
        return PasswordItem(
            id: entry.id, name: name, url: url, username: username,
            encryptedPassword: entry.password, encryptedNote: entry.note, lastUpdated: entry.updatedAt
        )
    }

    /// A service identifier's domain, lower case and without "www.".
    static func domain(of identifier: ASCredentialServiceIdentifier) -> String? {
        let host: String?
        switch identifier.type {
        case .domain: host = identifier.identifier
        case .URL: host = URL(string: identifier.identifier)?.host
        @unknown default: host = nil
        }
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The name part of a domain, for matching 2FA issuers: "github.com" → "github".
    static func siteName(of domain: String) -> String {
        let labels = domain.split(separator: ".")
        return labels.count >= 2 ? String(labels[labels.count - 2]) : domain
    }

    /// Lower case without spaces or punctuation: "Git Hub, Inc." → "githubinc".
    static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
