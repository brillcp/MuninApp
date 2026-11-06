import Foundation
import Observation
import StoreKit

/// An observable object that manages the user's subscription and links App Store purchases to their account.
///
/// The server is the source of truth for subscription status. Every purchase,
/// renewal, and restore is sent to the server as a transaction identifier,
/// which the server verifies with Apple. Purchases use the user's identifier
/// as their app account token, so the server can match them to the account.
@Observable
final class SubscriptionManager {
    /// The product identifier of the monthly subscription in App Store Connect.
    static let productID = "munin.monthly.sub"

    /// The task that listens to `Transaction.updates` while the vault is unlocked.
    private var updatesTask: Task<Void, Never>?

    /// The subscription status reported by the server, or `nil` until loaded or while locked.
    private(set) var status: SubscriptionStatus?
    /// A description of the last error from linking or restoring a purchase.
    private(set) var errorMessage: String?
    /// A Boolean value that indicates whether the paywall is presented.
    var isPaywallPresented = false

    /// Creates a subscription manager with no status loaded.
    init() {}
}

// MARK: - Public functions
extension SubscriptionManager {
    /// A Boolean value that indicates whether changes are blocked because a required subscription is inactive.
    ///
    /// Reading, copying, and unlocking remain available.
    var isReadOnly: Bool {
        guard let status else { return false }
        return status.required && !status.active
    }

    /// A Boolean value that indicates whether the subscription is in a billing grace period.
    ///
    /// During the grace period the subscription remains active while the App
    /// Store retries a failed renewal payment.
    var isInGracePeriod: Bool {
        guard let status else { return false }
        return status.active && status.billingIssue == true
    }

    /// Returns the app account token for purchases, derived from the user's identifier.
    func appAccountToken(auth: AuthManager) -> UUID? {
        auth.userID.flatMap(UUID.init(uuidString:))
    }

    /// Starts listening for transactions and loads the subscription status.
    ///
    /// Call this after the vault unlocks. If the server reports no active
    /// subscription, current App Store entitlements are linked first, which
    /// covers renewals the server missed and purchases made on other devices.
    /// The paywall is presented if the vault remains read-only.
    func start(auth: AuthManager) async {
        listenForTransactions(auth: auth)
        await refreshStatus(auth: auth)
        if isReadOnly { await linkCurrentEntitlements(auth: auth) }
        if isReadOnly { isPaywallPresented = true }
    }

    /// Stops listening for transactions and clears the status, for example on lock or sign-out.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        status = nil
        errorMessage = nil
        isPaywallPresented = false
    }

    /// Fetches the current subscription status from the server.
    func refreshStatus(auth: AuthManager) async {
        do {
            status = try await MuninService(tokenProvider: auth.tokenProvider).subscription()
        } catch {
            errorMessage = error.muninDescription
        }
    }

    /// Links a purchase made in the paywall to the account, then finishes the transaction.
    func handlePurchase(_ result: Result<Product.PurchaseResult, any Error>, auth: AuthManager) async {
        switch result {
        case .success(.success(.verified(let transaction))):
            await link(transaction, auth: auth)
        case .success(.success(.unverified)):
            errorMessage = Localized("subscription.error.unverified")
        case .success:
            break
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Syncs with the App Store and links any current entitlements to the account.
    func restore(auth: AuthManager) async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await linkCurrentEntitlements(auth: auth)
        await refreshStatus(auth: auth)
    }
}

// MARK: - Private functions
private extension SubscriptionManager {
    /// Listens for transaction updates, such as renewals, purchases on other devices, and Ask to Buy approvals.
    func listenForTransactions(auth: AuthManager) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await self?.link(transaction, auth: auth)
            }
        }
    }

    func linkCurrentEntitlements(auth: AuthManager) async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productID == Self.productID else { continue }
            await link(transaction, auth: auth)
        }
    }

    /// Sends a transaction to the server for verification, then finishes it so StoreKit stops delivering it.
    func link(_ transaction: Transaction, auth: AuthManager) async {
        do {
            status = try await MuninService(tokenProvider: auth.tokenProvider)
                .linkSubscription(transactionID: String(transaction.originalID))
            errorMessage = nil
            await transaction.finish()
            if !isReadOnly { isPaywallPresented = false }
        } catch {
            errorMessage = error.muninDescription
        }
    }
}
