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
                    Button("Regenerate", systemImage: "arrow.counterclockwise", action: regenerate)
                        .labelStyle(.iconOnly)
                    Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(password) }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)

                Button {
                    onFill(password)
                } label: {
                    Text("Fill Password").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()

            Form {
                LabeledContent("Length") {
                    HStack {
                        Slider(value: $generator.sliderLength, in: 8...64, step: 1)
                        Text("\(generator.length)")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                Toggle("Use capital letters (A-Z)", isOn: $generator.useCapitals)
                Toggle("Use digits (0-9)", isOn: $generator.useDigits)
                Toggle("Use symbols (@!$%&*)", isOn: $generator.useSymbols)
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

    private var strength: (title: String, color: Color) {
        switch generator.entropy {
        case ..<60:  return ("Weak Password", .red)
        case ..<80:  return ("Good Password", .orange)
        default:     return ("Strong Password", .green)
        }
    }
}

#Preview {
    PasswordGeneratorView { _ in }
}
