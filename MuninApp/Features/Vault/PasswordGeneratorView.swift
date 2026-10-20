import SwiftUI

/// Generates a password; "Fill Password" hands it to the editor.
///
/// A new password is generated on appear and whenever a setting changes.
struct PasswordGeneratorView: View {
    /// Called by Fill Password with the generated password.
    let onFill: (String) -> Void

    /// The generator's settings.
    @State private var generator = PasswordGenerator()
    /// The current password.
    @State private var password = ""
    /// Bumped by buttons for a light haptic.
    @State private var hapticTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s0) {
            VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s16) {
                Text(password)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)

                HStack {
                    Label(strength.title, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(strength.color)
                    Spacer()
                    Button("passwordGenerator.regenerate", systemImage: "arrow.counterclockwise") {
                        hapticTaps += 1
                        regenerate()
                    }
                    .labelStyle(.iconOnly)
                    Button("global.copy", systemImage: "square.on.square") {
                        hapticTaps += 1
                        Pasteboard.copySensitive(password)
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)

                Button {
                    hapticTaps += 1
                    onFill(password)
                } label: {
                    Text("passwordGenerator.fillPassword").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .padding(.top)

            Form {
                LabeledContent("passwordGenerator.length") {
                    HStack {
                        Slider(value: $generator.sliderLength, in: 8...64, step: 1)
                        Text(generator.length, format: .number)
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                Toggle("passwordGenerator.useCapitals", isOn: $generator.useCapitals)
                Toggle("passwordGenerator.useDigits", isOn: $generator.useDigits)
                Toggle("passwordGenerator.useSymbols", isOn: $generator.useSymbols)
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 340, idealWidth: 380)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTaps)
        .onAppear(perform: regenerate)
        .onChange(of: generator.length) { regenerate() }
        .onChange(of: generator.useCapitals) { regenerate() }
        .onChange(of: generator.useDigits) { regenerate() }
        .onChange(of: generator.useSymbols) { regenerate() }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    /// Generates a new password with the current settings.
    private func regenerate() {
        password = generator.generate()
    }

    /// The strength label and colour, from the password's entropy:
    /// weak under 60 bits, good under 80, strong above.
    private var strength: (title: LocalizedStringKey, color: Color) {
        switch generator.entropy {
        case ..<60:  return ("passwordGenerator.strength.weak", .red)
        case ..<80:  return ("passwordGenerator.strength.good", .orange)
        default:     return ("passwordGenerator.strength.strong", .green)
        }
    }
}

#Preview {
    PasswordGeneratorView { _ in }
}
