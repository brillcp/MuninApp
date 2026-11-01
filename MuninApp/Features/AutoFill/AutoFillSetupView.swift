import SwiftUI

/// How to turn on Munin's AutoFill: why, the steps for this platform, a
/// button for the system's own prompt, and one that opens Settings.
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
    /// The steps in Settings for this platform.
    var steps: [LocalizedStringKey] {
        #if os(macOS)
        ["autofill.setup.step1.mac", "autofill.setup.step2", "autofill.setup.step3.mac", "autofill.setup.step4"]
        #else
        ["autofill.setup.step1.ios", "autofill.setup.step2", "autofill.setup.step3.ios", "autofill.setup.step4"]
        #endif
    }

    /// Shows the system's prompt to turn Munin on.
    func turnOn() {
        Task { await autoFill.turnOn() }
    }

    /// Opens AutoFill & Passwords in Settings.
    func openSettings() {
        Task { await autoFill.openSettings() }
    }
}

/// One numbered step of the guide.
private struct AutoFillStepRow: View {
    /// The step's number, from 1.
    let number: Int
    /// What to do.
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignKit.Spacing.Primitive.s12) {
            Text(verbatim: "\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: DesignKit.Spacing.Primitive.s24)
            Text(text)
        }
    }
}
