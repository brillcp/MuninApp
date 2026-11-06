import SwiftUI

/// A list of two-factor codes.
///
/// A separate view, so the screen's toolbar and overlays don't re-evaluate
/// when the codes change. Each row has a context menu to copy the code or
/// delete the account.
struct TwoFactorList: View {
    /// The subscription state. Delete is disabled while the vault is read-only.
    @Environment(SubscriptionManager.self) private var subscriptions

    let viewModel: TwoFactorViewModel
    /// The clock shared by every row.
    let clock: TwoFactorClock
    /// The account awaiting delete confirmation, set by a row's Delete action.
    @Binding var pendingDeletion: VaultItem?

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                TwoFactorRow(account: item.account, clock: clock)
                    .contextMenu {
                        Button("codes.copyCode", systemImage: DesignKit.Icon.copy) { TwoFactorRow.copyCode(of: item.account) }
                            .tint(.primary)
                        Button("global.delete", systemImage: DesignKit.Icon.delete, role: .destructive) { pendingDeletion = item }
                            .disabled(subscriptions.isReadOnly)
                            .tint(.red)
                    }
            }
            if viewModel.undecryptableCount > 0 {
                Section {
                    undecryptableLabel
                }
            }
        }
        #if os(macOS)
        .alternatingRowBackgrounds()
        #endif
        .listStyle(.plain)
    }
}

private extension TwoFactorList {
    /// A label with the number of entries that couldn't be decrypted with the
    /// current vault key.
    var undecryptableLabel: some View {
        Label(LocalizedKey("codes.undecryptable", viewModel.undecryptableCount), systemImage: DesignKit.Icon.undecryptable)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
