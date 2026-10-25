import Foundation
import Observation
import StoreKit

/// The user's Munin subscription: what Munin says about it, the App Store
/// product, and linking purchases to the account.
///
/// Munin is the source of truth. Every purchase, renewal and restore is sent
/// to Munin as a transaction ID, which Munin looks up with Apple before
/// unlocking changes. Purchases carry the user's ID as their app account
/// token, so Munin can tell they were made for this account.
@Observable
final class SubscriptionManager {
    /// The monthly subscription's product ID in App Store Connect.
    static let productID = "dev.gidlof.Munin.monthly"

    /// Listens to `Transaction.updates` while the vault is unlocked.
    private var updatesTask: Task<Void, Never>?

    /// Munin's view of the subscription; nil until loaded, or while locked.
    private(set) var status: SubscriptionStatus?
    /// The last error from linking or restoring a purchase.
    private(set) var errorMessage: String?
    /// Shows the paywall.
    var isPaywallPresented = false

    /// Creates a manager with nothing loaded.
    init() {}
}

// MARK: - Public functions
extension SubscriptionManager {
    /// True when changes need a subscription and the user doesn't have one.
    /// Reading, copying and unlocking still work.
    var isReadOnly: Bool {
        guard let status else { return false }
        return status.required && !status.active
    }

    /// The App Store account token for purchases: the Munin user ID.
    func appAccountToken(auth: AuthManager) -> UUID? {
        auth.userID.flatMap(UUID.init(uuidString:))
    }

    /// Starts after unlocking: listens for transactions and loads the status.
    /// If Munin has no active subscription, any current App Store entitlement
    /// is sent to Munin first (a renewal it hasn't heard about, or a purchase
    /// on another device). Shows the paywall if the vault is still read-only.
    func start(auth: AuthManager) async {
        listenForTransactions(auth: auth)
        await refreshStatus(auth: auth)
        if isReadOnly { await linkCurrentEntitlements(auth: auth) }
        if isReadOnly { isPaywallPresented = true }
    }

    /// Stops listening and forgets the status. Called on lock and sign-out.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        status = nil
        errorMessage = nil
        isPaywallPresented = false
    }

    /// Asks Munin for the current status.
    func refreshStatus(auth: AuthManager) async {
        do {
            status = try await MuninService(tokenProvider: auth.tokenProvider).subscription()
        } catch {
            errorMessage = error.muninDescription
        }
    }

    /// Links a purchase made in the paywall, then finishes it.
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

    /// Restore Purchases: syncs with the App Store and links what it finds.
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
    /// Handles renewals, purchases from other devices and Ask to Buy approvals.
    func listenForTransactions(auth: AuthManager) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await self?.link(transaction, auth: auth)
            }
        }
    }

    /// Sends every current entitlement for the subscription to Munin.
    func linkCurrentEntitlements(auth: AuthManager) async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productID == Self.productID else { continue }
            await link(transaction, auth: auth)
        }
    }

    /// Sends a transaction to Munin, which checks it with Apple, then
    /// finishes it so StoreKit stops delivering it.
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
