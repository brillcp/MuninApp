import LocalAuthentication
import SwiftUI

/// AutoFill's interface: unlock with Face ID / Touch ID, then pick a password
/// or a 2FA code. Suggestions for the site asking come first; the rest can be
/// searched.
struct AutoFillView: View {
    /// Munin's accent colour. The extension has no asset catalog of its own.
    private static let accent = Color(red: 0x38 / 255, green: 0x86 / 255, blue: 0x59 / 255)

    /// The request's state, data and actions.
    @Bindable var model: AutoFillModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("autofill.title")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("global.cancel", action: model.cancel)
                    }
                }
        }
        .tint(Self.accent)
        .task(model.unlock)
    }
}

private extension AutoFillView {
    /// The unlock prompt, a spinner, the list, or why AutoFill can't be used.
    @ViewBuilder
    var content: some View {
        switch model.state {
        case .locked:
            unlockPrompt
        case .working:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            switch model.mode {
            case .passwords: passwordList
            case .oneTimeCodes: codeList
            }
        case .unavailable(let message):
            ContentUnavailableView {
                Label("autofill.unavailable", systemImage: DesignKit.Icon.locked)
            } description: {
                Text(message)
            }
        }
    }

    /// Shown after Face ID / Touch ID was cancelled, to try again.
    var unlockPrompt: some View {
        ContentUnavailableView {
            Label("autofill.locked", systemImage: DesignKit.Icon.locked)
        } actions: {
            Button(Self.usesFaceID ? "settings.biometrics.face" : "settings.biometrics.touch",
                   systemImage: Self.usesFaceID ? DesignKit.Icon.faceID : DesignKit.Icon.touchID,
                   action: unlock)
                .buttonStyle(.glassProminent)
        }
    }

    /// Passwords: suggestions for the site, then all of them.
    var passwordList: some View {
        List {
            if model.searchText.isEmpty, !model.suggestedPasswords.isEmpty {
                Section("autofill.suggested") {
                    ForEach(model.suggestedPasswords) { item in
                        AutoFillPasswordRow(item: item) { model.choose(item) }
                    }
                }
            }
            Section("autofill.allPasswords") {
                ForEach(model.allPasswords) { item in
                    AutoFillPasswordRow(item: item) { model.choose(item) }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "autofill.search")
        .overlay {
            if model.allPasswords.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    /// 2FA codes: suggestions for the site, then all of them.
    var codeList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                if model.searchText.isEmpty, !model.suggestedCodes.isEmpty {
                    Section("autofill.suggested") {
                        ForEach(model.suggestedCodes) { item in
                            AutoFillCodeRow(account: item.account, date: context.date) { model.choose(item) }
                        }
                    }
                }
                Section("autofill.allCodes") {
                    ForEach(model.allCodes) { item in
                        AutoFillCodeRow(account: item.account, date: context.date) { model.choose(item) }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "autofill.search")
        .overlay {
            if model.allCodes.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }

    /// Whether this device has Face ID rather than Touch ID.
    static var usesFaceID: Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID
    }

    /// Tries Face ID / Touch ID again.
    func unlock() {
        Task { await model.unlock() }
    }
}

/// A password to fill: website icon, name and username.
private struct AutoFillPasswordRow: View {
    /// The password item.
    let item: PasswordItem
    /// Fills it.
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: DesignKit.Spacing.Primitive.s12) {
                WebsiteIcon(url: item.url, size: DesignKit.Spacing.Primitive.s32)
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                    Text(item.name)
                    if !item.username.isEmpty {
                        Text(item.username)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A 2FA account to fill: issuer, account name and the current code.
private struct AutoFillCodeRow: View {
    /// The account.
    let account: OTPAccount
    /// The time the code is for, updated every second.
    let date: Date
    /// Fills its code.
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: DesignKit.Spacing.Primitive.s12) {
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
                    Text(account.title)
                    if let subtitle = account.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: account.code(at: date))
                    .font(.title3.monospacedDigit())
                    .contentTransition(.numericText())
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
