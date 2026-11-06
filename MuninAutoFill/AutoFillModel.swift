import AuthenticationServices
import Foundation
import Observation

/// An object that completes or cancels an AutoFill request.
///
/// The extension's view controller implements this protocol.
protocol AutoFillHandler: AnyObject {
    /// Fills a login with a username and password.
    ///
    /// - Parameters:
    ///   - user: The username to fill.
    ///   - password: The password to fill.
    func fill(user: String, password: String)
    /// Fills a one-time code field.
    ///
    /// - Parameter code: The code to fill.
    func fill(code: String)
    /// Closes AutoFill without filling anything.
    func cancel()
}

/// The model behind the AutoFill extension: biometric unlock, vault loading,
/// and the passwords or 2FA codes to choose from.
///
/// Decrypted data lives only in memory and is discarded when AutoFill closes.
/// Passwords stay encrypted until the user chooses one.
@Observable
final class AutoFillModel {
    /// The unlocked vault key, held while AutoFill is open.
    private var vault: UnlockedVault?
    private weak var handler: AutoFillHandler?

    /// The current stage.
    private(set) var state: State = .locked
    /// The user's passwords, with name, URL, and username decrypted.
    private(set) var passwords: [PasswordItem] = []
    /// The user's 2FA accounts, decrypted.
    private(set) var codes: [VaultItem] = []
    /// The search field's text.
    var searchText = ""

    /// The kind of field that opened AutoFill.
    let mode: Mode
    /// The domains of the requesting sites, such as `github.com`.
    let domains: [String]
    /// The item to fill after unlocking, when the user taps a keyboard suggestion.
    let requestedItemID: UUID?

    /// Creates a model for an AutoFill request.
    ///
    /// - Parameters:
    ///   - mode: The kind of field that opened AutoFill.
    ///   - serviceIdentifiers: The services requesting credentials.
    ///   - requestedItemID: The item to fill after unlocking, if any.
    ///   - handler: The object that completes or cancels the request.
    init(mode: Mode, serviceIdentifiers: [ASCredentialServiceIdentifier], requestedItemID: UUID? = nil, handler: AutoFillHandler) {
        self.mode = mode
        self.requestedItemID = requestedItemID
        self.handler = handler
        domains = serviceIdentifiers.compactMap(Self.domain(of:))
    }
}

// MARK: - Public API
extension AutoFillModel {
    /// The kind of field that opened AutoFill.
    enum Mode {
        /// A login field, which offers passwords.
        case passwords
        /// A one-time code field, which offers 2FA codes.
        case oneTimeCodes
    }

    /// The stages of an AutoFill session.
    enum State: Equatable {
        /// Waiting for Face ID or Touch ID.
        case locked
        /// Unlocking or loading the vault.
        case working
        /// The list is ready.
        case ready
        /// AutoFill is unavailable, with the reason.
        case unavailable(String)
    }

    /// The passwords whose domain matches a requesting site.
    var suggestedPasswords: [PasswordItem] {
        passwords.filter { item in item.domain.map(matchesRequest) ?? false }
    }

    /// The passwords whose name matches the search text.
    var allPasswords: [PasswordItem] {
        let sorted = passwords.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
                || $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The 2FA accounts whose issuer matches a requesting site, such as
    /// "GitHub" for `github.com`.
    var suggestedCodes: [VaultItem] {
        let names = Set(domains.map(Self.siteName(of:)))
        return codes.filter { names.contains(Self.compact($0.account.issuer)) }
    }

    /// The 2FA accounts whose issuer matches the search text.
    var allCodes: [VaultItem] {
        let sorted = codes.sorted { $0.account.title.localizedStandardCompare($1.account.title) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.account.title.localizedCaseInsensitiveContains(searchText)
                || ($0.account.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Unlocks the biometric copy of the vault key, then loads the vault.
    ///
    /// The app saves the biometric copy when the vault is unlocked with Face ID
    /// or Touch ID turned on.
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

    /// Decrypts and fills the chosen password.
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

// MARK: - Private
private extension AutoFillModel {
    /// Loads and decrypts the passwords or 2FA accounts.
    ///
    /// If the user tapped a keyboard suggestion, fills that item immediately.
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

    /// Returns a Boolean value that indicates whether a domain matches a
    /// requesting site.
    ///
    /// Domains match when they're equal or one is a subdomain of the other,
    /// such as `accounts.github.com` and `github.com`.
    func matchesRequest(_ domain: String) -> Bool {
        domains.contains { requested in
            requested == domain || requested.hasSuffix("." + domain) || domain.hasSuffix("." + requested)
        }
    }

    /// Decrypts an item's name, URL, and username, leaving the password and
    /// note encrypted.
    static func item(from entry: EncryptedPassword, vault: UnlockedVault) -> PasswordItem? {
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

    /// Returns a service identifier's domain, lowercased and without `www.`.
    static func domain(of identifier: ASCredentialServiceIdentifier) -> String? {
        let host: String?
        switch identifier.type {
        case .domain: host = identifier.identifier
        case .URL: host = URL(string: identifier.identifier)?.host
        default: host = nil
        }
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Returns a domain's site name for matching 2FA issuers, such as `github`
    /// for `github.com`.
    static func siteName(of domain: String) -> String {
        let labels = domain.split(separator: ".")
        return labels.count >= 2 ? String(labels[labels.count - 2]) : domain
    }

    /// Returns the text lowercased without spaces or punctuation, such as
    /// `githubinc` for "Git Hub, Inc."
    static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
