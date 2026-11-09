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

/// The model behind the AutoFill extension: unlocking with Face ID, Touch ID,
/// or the master password, vault loading, and the passwords or 2FA codes to
/// choose from.
///
/// Decrypted data lives only in memory and is discarded when AutoFill closes.
/// Passwords stay encrypted until the user chooses one.
@Observable
final class AutoFillModel {
    private let api: any MuninAPI
    /// The unlocked vault key, held while AutoFill is open.
    private var vault: UnlockedVault?
    private weak var handler: AutoFillHandler?

    /// The signed-in user's ID, read from the shared Keychain.
    private let userID = KeychainService.loadUserID()

    /// The current stage.
    private(set) var state: State = .locked
    /// A Boolean value that indicates whether this device has a Face ID or
    /// Touch ID copy of the vault key, so the lock screen offers biometric unlock.
    private(set) var offersBiometrics = false
    /// Why the last unlock attempt failed, such as a wrong master password.
    private(set) var errorMessage: String?
    /// The user's passwords, with name, URL, and username decrypted.
    private(set) var passwords: [PasswordItem] = []
    /// The user's 2FA accounts, decrypted.
    private(set) var codes: [VaultItem] = []
    /// The search field's text.
    var searchText = ""
    /// The master password the user is typing.
    var masterPassword = ""

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
    ///   - api: The API that loads the encrypted vault.
    ///   - handler: The object that completes or cancels the request.
    init(mode: Mode, serviceIdentifiers: [ASCredentialServiceIdentifier], requestedItemID: UUID? = nil, api: any MuninAPI, handler: AutoFillHandler) {
        self.api = api
        self.mode = mode
        self.requestedItemID = requestedItemID
        self.handler = handler
        domains = serviceIdentifiers.compactMap(Self.domain(of:))
        offersBiometrics = userID.map(VaultKeyStore.hasBiometric(userID:)) ?? false
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
        /// Waiting for Face ID, Touch ID, or the master password.
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
    /// or Touch ID turned on. Without one, or if Face ID or Touch ID fails,
    /// the lock screen asks for the master password instead.
    func unlockWithBiometrics() async {
        guard state == .locked else { return }
        guard let userID else {
            state = .unavailable(Localized("autofill.signIn"))
            return
        }
        guard offersBiometrics else { return }
        state = .working
        errorMessage = nil
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
            offersBiometrics = false
            state = .locked
        case .failed:
            errorMessage = Localized("lock.biometrics.failed")
            state = .locked
        }
    }

    /// Unlocks by unwrapping the server's vault key with ``masterPassword``,
    /// then loads the vault.
    ///
    /// The master password stays in this extension; nothing is saved for
    /// later unlocks.
    func unlockWithMasterPassword() async {
        guard state == .locked, !masterPassword.isEmpty else { return }
        guard let userID else {
            state = .unavailable(Localized("autofill.signIn"))
            return
        }
        state = .working
        errorMessage = nil
        defer { masterPassword = "" }
        do {
            guard let record = try await api.vaultKey() else {
                state = .unavailable(Localized("errors.keyMissing"))
                return
            }
            guard let unlocked = try await VaultKeyCrypto.unlock(record, password: masterPassword, userID: userID) else {
                errorMessage = Localized("lock.wrongMasterPassword")
                state = .locked
                return
            }
            vault = unlocked
            await load()
        } catch {
            errorMessage = error.muninDescription
            state = .locked
        }
    }

    /// Decrypts and fills the chosen password.
    func choose(_ item: PasswordItem) {
        guard let vault,
              let password = try? VaultDecoder.open(item.encryptedPassword, .password, vault: vault) else {
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
        do {
            switch mode {
            case .passwords:
                let records = try await api.passwords()
                passwords = await VaultDecoder.passwordItems(from: records, vault: vault).items
                if let requestedItemID, let item = passwords.first(where: { $0.id == requestedItemID }) {
                    choose(item)
                    return
                }
            case .oneTimeCodes:
                let records = try await api.entries()
                codes = await VaultDecoder.twoFactorItems(from: records, vault: vault).items
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
