import SwiftUI

/// A step that unlocks with Face ID or Touch ID, with the master password as
/// an alternative.
struct LockBiometricsStep: View {
    @Environment(VaultSession.self) private var session
    /// The view model that receives the password list during unlock.
    @Environment(VaultViewModel.self) private var vaultModel

    let onUseMasterPassword: () -> Void

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
            LockButton(
                session.usesFaceID ? "settings.biometrics.face" : "settings.biometrics.touch",
                systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                isLoading: isUnlocking,
                action: unlockWithBiometrics
            )
            LockButton(systemImage: DesignKit.Icon.useMasterPassword, style: .secondary, action: onUseMasterPassword)
                .buttonSizing(.fitted)
        }
    }
}

private extension LockBiometricsStep {
    /// A Boolean value that indicates whether an unlock or vault check is in progress.
    var isUnlocking: Bool {
        session.isWorking || session.state == .checking
    }

    /// Unlocks with Face ID or Touch ID and downloads the password list.
    func unlockWithBiometrics() {
        Task { await session.unlockWithBiometrics(prefetchingInto: vaultModel) }
    }
}
