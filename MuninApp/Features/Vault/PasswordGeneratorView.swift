import SwiftUI

/// Generates a password; "Fill Password" hands it to the editor.
struct PasswordGeneratorView: View {
    let onFill: (String) -> Void

    @State private var generator = PasswordGenerator()
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(password)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)

                HStack {
                    Label(strength.title, systemImage: "checkmark.shield.fill")
                        .foregroundStyle(strength.color)
                    Spacer()
                    Button("passwordGenerator.regenerate", systemImage: "arrow.counterclockwise", action: regenerate)
                        .labelStyle(.iconOnly)
                    Button("global.copy", systemImage: "doc.on.doc") { Pasteboard.copySensitive(password) }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)

                Button {
                    onFill(password)
                } label: {
                    Text("passwordGenerator.fillPassword").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()

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
        .onAppear(perform: regenerate)
        .onChange(of: generator.length) { regenerate() }
        .onChange(of: generator.useCapitals) { regenerate() }
        .onChange(of: generator.useDigits) { regenerate() }
        .onChange(of: generator.useSymbols) { regenerate() }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func regenerate() {
        password = generator.generate()
    }

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
