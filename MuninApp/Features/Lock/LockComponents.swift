import SwiftUI

// Pieces shared by the Mac and iOS lock screens (LockView+macOS / LockView+iOS).

/// App logo and name, top left. Add the logo image to the "Logo" image set.
struct LockLogo: View {
    var body: some View {
        HStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("main.window.title")
                .font(.title2.bold())
                .foregroundStyle(.white)
        }
    }
}

struct LockUnlockSection: View {
    /// iOS stacks the unlock buttons; the Mac puts them side by side.
    var stacksButtons = false

    private enum Mode {
        case biometrics
        case masterPassword
        case recoveryKey
    }

    @Environment(AuthManager.self) private var auth
    @Environment(VaultSession.self) private var session
    @State private var mode: Mode?
    @State private var password = ""
    @State private var recoveryKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                switch currentMode {
                case .biometrics:
                    Text("Unlock your vault")
                case .masterPassword:
                    Text("Use Master password")
                case .recoveryKey:
                    Text("Enter revovery key")
                }
            }
            .font(.title.bold())

            LockAccountRow(email: auth.email)

            switch currentMode {
            case .biometrics:
                biometricsLayout {
                    Button { Task { await session.unlockWithBiometrics() } } label: {
                        Label("lock.unlockWithBiometrics", systemImage: "touchid")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.accent)
                    .buttonStyle(.glassProminent)

                    Button {
                        withAnimation {
                            mode = .masterPassword
                            session.errorMessage = nil
                        }
                    } label: {
                        Text("lock.useMasterPassword")
                    }
                    .buttonStyle(.borderless)
                    .tint(.white)
                }
                .controlSize(.large)
                .tint(.bark)
            case .masterPassword:
                SecureField("lock.masterPassword.placeholder", text: $password)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
//                    .frame(maxWidth: 320)
                    .onSubmit(unlockWithPassword)
                    .colorScheme(.light)

                Button(action: unlockWithPassword) {
                    Text("lock.unlock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.accent)
                .controlSize(.large)
                .disabled(password.isEmpty)

                if session.offersBiometricUnlock {
                    Button("lock.useBiometrics") { withAnimation { mode = .biometrics } }
                        .buttonStyle(.borderless)
                        .tint(.white)
                }
                Button("lock.forgotMasterPassword") { withAnimation { mode = .recoveryKey } }
                    .buttonStyle(.borderless)
                    .tint(.white)
            case .recoveryKey:
                Text("lock.recovery.message")
                    .foregroundStyle(.secondary)
                TextField("vaultKey.missing.placeholder", text: $recoveryKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
//                    .frame(maxWidth: 360)
                    .colorScheme(.light)

                Button(action: { session.unlock(recoveryKey: recoveryKey) }) {
                    Text("lock.recovery.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(recoveryKey.isEmpty)
                .tint(.accent)

                Button("global.cancel") { withAnimation { mode = .masterPassword } }
                    .tint(.white)
            }

            if session.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .disabled(session.isWorking)
        .animation(.bouncy, value: mode)
    }

    /// Stacked (iOS) or side by side (Mac); each layout decides.
    private var biometricsLayout: AnyLayout {
        stacksButtons
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    /// Biometrics first when this device has them; otherwise the master password.
    private var currentMode: Mode {
        mode ?? (session.offersBiometricUnlock ? .biometrics : .masterPassword)
    }

    private func unlockWithPassword() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered) }
    }
}

/// Initials avatar, email and "Switch account" (signs out).
struct LockAccountRow: View {
    let email: String?

    var body: some View {
        if let email {
            HStack {
                Text(verbatim: initials)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.accent, in: .circle)

                Text(email)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var initials: String {
        String((email ?? "").prefix(2)).capitalized
    }
}

struct LockVersionLabel: View {
    var body: some View {
        Text(LocalizedKey("lock.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.footnote)
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 2)
            .padding(.leading)
    }
}
