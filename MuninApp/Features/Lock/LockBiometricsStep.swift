import SwiftUI

/// A step that unlocks with Face ID or Touch ID, with the master password as
/// an alternative.
///
/// Return starts the biometric unlock. While unlocking, a spinner replaces
/// the button's title on iOS, and sits to the right of the buttons on macOS.
struct LockBiometricsStep: View {
    /// The vault session to unlock.
    @Environment(VaultSession.self) private var session
    /// The view model that receives the password list during unlock.
    @Environment(VaultViewModel.self) private var vaultModel

    /// The action that switches to the master password step.
    let onUseMasterPassword: () -> Void

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s16) {
            LockButton(
                session.usesFaceID ? "settings.biometrics.face" : "settings.biometrics.touch",
                systemImage: session.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                isLoading: showsButtonSpinner,
                action: unlockWithBiometrics
            )
            LockButton(systemImage: DesignKit.Icon.useMasterPassword, style: .secondary, action: onUseMasterPassword)
                .buttonSizing(.fitted)
        }
        .lockSpinner(isShown: isUnlocking && !showsButtonSpinner)
        .animation(DesignKit.Motion.linear, value: isUnlocking)
    }
}

private extension LockBiometricsStep {
    /// A Boolean value that indicates whether an unlock or vault check is in progress.
    var isUnlocking: Bool {
        session.isWorking || session.state == .checking
    }

    /// A Boolean value that indicates whether the unlock button shows its own
    /// spinner: on iOS while unlocking. On macOS, the spinner sits to the
    /// right of the buttons instead.
    var showsButtonSpinner: Bool {
        #if os(iOS)
        isUnlocking
        #else
        false
        #endif
    }

    /// Unlocks with Face ID or Touch ID and downloads the password list.
    func unlockWithBiometrics() {
        Task { await session.unlockWithBiometrics(prefetchingInto: vaultModel) }
    }
}
