import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct CodeRow: View {
    let account: OTPAccount
    let now: Date

    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 12) {
            AccountLabel(title: account.title, subtitle: account.subtitle)
                .equatable()

            Spacer(minLength: 8)

            CodeText(code: account.code(at: now), didCopy: didCopy)
                .equatable()

            CountdownGauge(remaining: account.secondsRemaining(at: now), period: account.period)
                .equatable()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .sensoryFeedback(.success, trigger: didCopy) { _, new in new }
        .animation(.default, value: didCopy)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Copies the code")
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = account.code(at: .now)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.code(at: .now), forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }

    /// "123456" → "123 456", "12345678" → "1234 5678".
    static func formatted(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}

/// Issuer and account name. Never changes while the row is on screen.
private struct AccountLabel: View, Equatable {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// The code. Only redraws when the code rotates or is copied.
private struct CodeText: View, Equatable {
    let code: String
    let didCopy: Bool

    var body: some View {
        Text(didCopy ? "Copied" : CodeRow.formatted(code))
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .foregroundStyle(didCopy ? Color.accentColor : .primary)
            .monospacedDigit()
            .animation(.default, value: code)
    }
}

/// The countdown. The only part of a row that redraws every second.
private struct CountdownGauge: View, Equatable {
    let remaining: Int
    let period: Int

    var body: some View {
        Gauge(value: Double(remaining), in: 0...Double(max(period, 1))) {
            Text("\(remaining)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(remaining <= 5 ? Color.red : Color.mint)
        .scaleEffect(0.6)
        .accessibilityLabel("\(remaining) seconds left")
        .animation(.bouncy, value: remaining)
    }
}
