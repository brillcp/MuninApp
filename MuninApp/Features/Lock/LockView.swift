import SwiftUI

/// Covers the app until the user unlocks: logo, unlock actions and version on
/// the left, artwork on the right (Mac and iPad; hidden on iPhone).
struct LockView: View {
    @Environment(VaultSession.self) private var session
    @Environment(AuthManager.self) private var auth
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        if showsArtworkPanel {
            HStack(spacing: 48) {
                content
                    .padding(48)
                LockArtwork()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        } else {
            content
                .background(alignment: .trailing) {
                    Image("munin")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            LockLogo()
            Spacer()
            LockUnlockSection()
                .padding(showsArtworkPanel ? 0 : 24)
                .background(showsArtworkPanel ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial), in: .rect(cornerRadius: 24))
            Spacer()
            LockVersionLabel()
        }
    }

    private var showsArtworkPanel: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }
}

/// App logo and name, top left. Add the logo image to the "Logo" image set.
private struct LockLogo: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            Text("main.window.title")
                .font(.title2.bold())
        }
    }
}

private struct LockUnlockSection: View {
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
            Text("lock.title")
                .font(.largeTitle.bold())

            LockAccountRow(email: auth.email)

            Button("lock.switchAccount", action: auth.signOut)
                .buttonStyle(.borderless)

            switch currentMode {
            case .biometrics:
                #if os(iOS)
                HStack(spacing: 16.0) {
                #else
                VStack(spacing: 16.0) {
                #endif
                    Button { Task { await session.unlockWithBiometrics() } } label: {
                        Label("lock.unlockWithBiometrics", systemImage: "touchid")
                            .foregroundStyle(.white)
                    }
                    .tint(.accent)

                    Button("lock.useMasterPassword") { mode = .masterPassword }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.bark)
            case .masterPassword:
                SecureField("lock.masterPassword.placeholder", text: $password)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
                    .frame(maxWidth: 320)
                    .onSubmit(unlockWithPassword)

                HStack(spacing: 16) {
                    Button("lock.unlock", action: unlockWithPassword)
                        .buttonStyle(.glassProminent)
                        .tint(Color(.bark))
                        .controlSize(.large)
                        .disabled(password.isEmpty)
                    if session.canUseBiometrics {
                        Button("lock.useBiometrics") { mode = .biometrics }
                            .buttonStyle(.borderless)
                    }
                }
                Button("lock.forgotMasterPassword") { mode = .recoveryKey }
                    .buttonStyle(.borderless)

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
                    .frame(maxWidth: 360)
                HStack(spacing: 16) {
                    Button("global.cancel") { mode = .masterPassword }
                    Button("lock.recovery.continue") { session.unlock(recoveryKey: recoveryKey) }
                        .buttonStyle(.borderedProminent)
                        .disabled(recoveryKey.isEmpty)
                }
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
    }

    /// Biometrics first when this device has them; otherwise the master password.
    private var currentMode: Mode {
        mode ?? (session.canUseBiometrics ? .biometrics : .masterPassword)
    }

    private func unlockWithPassword() {
        guard !password.isEmpty else { return }
        let entered = password
        password = ""
        Task { await session.unlock(masterPassword: entered) }
    }
}

/// Initials avatar, email and "Switch account" (signs out).
private struct LockAccountRow: View {
    let email: String?

    var body: some View {
        HStack {
            Text(verbatim: initials)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.accent, in: .circle)

            if let email {
                Text(email)
            }
        }
    }

    private var initials: String {
        String((email ?? "").prefix(2)).capitalized
    }
}

private struct LockVersionLabel: View {
    var body: some View {
        Text(LocalizedKey("lock.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Right-hand panel. Add the image to the "LockArtwork" image set.
private struct LockArtwork: View {
    var body: some View {
        Image("munin")
            .resizable()
            .scaledToFit()
    }
}

#Preview {
    LockView()
        .environment(VaultSession())
        .environment(AuthManager())
}
