import StoreKit
import SwiftUI

extension View {
    /// Opens subscription management when `isPresented` becomes `true`.
    ///
    /// On iOS, it presents the Manage Subscriptions sheet. On macOS, it opens
    /// the App Store's subscription page and sets `isPresented` back to `false`.
    ///
    /// - Parameter isPresented: A binding to whether subscription management is open.
    func manageSubscriptions(isPresented: Binding<Bool>) -> some View {
        modifier(ManageSubscriptions(isPresented: isPresented))
    }
}

/// The modifier behind ``SwiftUI/View/manageSubscriptions(isPresented:)``.
private struct ManageSubscriptions: ViewModifier {
    /// The action that opens the App Store's subscription page on macOS.
    @Environment(\.openURL) private var openURL

    /// A binding to whether subscription management is open.
    @Binding var isPresented: Bool

    /// Creates the modifier.
    ///
    /// - Parameter isPresented: A binding to whether subscription management is open.
    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .manageSubscriptionsSheet(isPresented: $isPresented)
        #else
        content
            .onChange(of: isPresented, openSubscriptionPage)
        #endif
    }

    #if os(macOS)
    /// Opens the App Store's subscription page once `isPresented` becomes `true`.
    private func openSubscriptionPage() {
        guard isPresented else { return }
        openURL(AppLinks.manageSubscriptions)
        isPresented = false
    }
    #endif
}
