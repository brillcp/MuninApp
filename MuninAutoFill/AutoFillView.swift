import LocalAuthentication
import SwiftUI

/// The AutoFill extension's interface for choosing a password or 2FA code.
///
/// The user unlocks with Face ID or Touch ID, then picks an item. Suggestions
/// for the requesting site come first; the rest are searchable.
struct AutoFillView: View {
    /// The app's accent color, defined in code because the extension has no asset catalog.
    private static let accent = Color(red: 0x38 / 255, green: 0x86 / 255, blue: 0x59 / 255)

    /// The model that holds the request's state, data, and actions.
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
    /// The content for the current state: the unlock prompt, a progress indicator, the list, or an error.
    @ViewBuilder
    var content: some View {
        switch model.state {
        case .locked:
            unlockPrompt
        case .working:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tint(.primary)
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

    /// A prompt to retry unlocking after biometric authentication is canceled.
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

    /// The password list, with suggestions for the site first.
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

    /// The 2FA code list, with suggestions for the site first.
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

    /// A Boolean value that indicates whether this device uses Face ID rather than Touch ID.
    static var usesFaceID: Bool {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .faceID
    }

    /// Retries biometric unlock.
    func unlock() {
        Task { await model.unlock() }
    }
}
