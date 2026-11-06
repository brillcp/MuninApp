import SwiftUI

/// A guide to enabling the app as an AutoFill provider.
///
/// Explains the benefit, lists the steps for the current platform, and offers
/// buttons for the system prompt and for opening Settings.
struct AutoFillSetupView: View {
    @Environment(AutoFillSetup.self) private var autoFill
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s24) {
                    Image(systemName: DesignKit.Icon.autoFill)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("autofill.setup.turnOn")
                        .font(.title.bold())
                    Text("autofill.setup.message")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s16) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            AutoFillStepRow(number: index + 1, text: step)
                        }
                    }
                    if autoFill.isEnabled == true {
                        Label("autofill.setup.done", systemImage: DesignKit.Icon.copied)
                            .foregroundStyle(.tint)
                    } else {
                        VStack(spacing: DesignKit.Spacing.Primitive.s12) {
                            Button("autofill.setup.turnOn", action: turnOn)
                                .buttonStyle(.glassProminent)
                            Button("autofill.setup.openSettings", action: openSettings)
                                .buttonStyle(.glass)
                        }
                        .buttonSizing(.flexible)
                        .controlSize(.large)
                    }
                }
                .padding(DesignKit.Spacing.Primitive.s24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("global.done", action: dismiss.callAsFunction)
                }
            }
        }
        .task(autoFill.refresh)
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }
}

private extension AutoFillSetupView {
    /// The Settings steps for the current platform.
    var steps: [LocalizedStringKey] {
        #if os(macOS)
        ["autofill.setup.step1.mac", "autofill.setup.step2", "autofill.setup.step3.mac", "autofill.setup.step4"]
        #else
        ["autofill.setup.step1.ios", "autofill.setup.step2", "autofill.setup.step3.ios", "autofill.setup.step4"]
        #endif
    }

    /// Shows the system prompt to enable the app as an AutoFill provider.
    func turnOn() {
        Task { await autoFill.turnOn() }
    }

    /// Opens the AutoFill & Passwords page in Settings.
    func openSettings() {
        Task { await autoFill.openSettings() }
    }
}
