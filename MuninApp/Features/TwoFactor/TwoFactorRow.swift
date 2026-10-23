import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// One 2FA account in the iOS list: name, current code and countdown. Tap to copy the code.
struct TwoFactorRow: View {
    /// Briefly true after copying, to show "Copied" instead of the code.
    @State private var didCopy = false

    /// The account whose code is shown.
    let account: OTPAccount
    /// Passed in (not from the environment): the Mac table's cells don't get
    /// the environment. Reading `clock.now` here still makes each row update itself.
    let clock: TwoFactorClock

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            AccountLabel(title: account.title, subtitle: account.subtitle)
                .equatable()
            Spacer(minLength: 8)
            CodeText(code: account.code(at: now), didCopy: didCopy)
                .equatable()
            CountdownGauge(remaining: account.secondsRemaining(at: now), period: account.period)
                .equatable()
        }
        .padding(.vertical, DesignKit.Spacing.Primitive.s4)
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .sensoryFeedback(.success, trigger: didCopy) { _, new in new }
        .animation(DesignKit.Motion.standard, value: didCopy)
        .accessibilityElement(children: .combine)
        .accessibilityHint("codes.row.copyHint")
    }
}

extension TwoFactorRow {
    /// Copies the account's current code to the clipboard.
    static func copyCode(of account: OTPAccount) {
        #if os(iOS)
        UIPasteboard.general.string = account.code(at: .now)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.code(at: .now), forType: .string)
        #endif
    }

    /// Splits a code in two halves for reading: "123456" → "123 456", "12345678" → "1234 5678".
    static func formatted(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}

private extension TwoFactorRow {
    /// The current time, read from the clock so the row redraws every second.
    var now: Date { clock.now }

    /// Copies the current code and shows "Copied" for a moment.
    func copy() {
        Self.copyCode(of: account)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}

/// Issuer and account name. Never changes while the row is on screen.
struct AccountLabel: View, Equatable {
    /// The issuer, or the account name when there's no issuer.
    let title: String
    /// The account name, when the title is the issuer.
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignKit.Spacing.Primitive.s2) {
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

/// The code and countdown for the Mac table's Code column. Click to copy.
struct TwoFactorCell: View {
    /// Briefly true after copying, to show "Copied" instead of the code.
    @State private var didCopy = false

    /// The account whose code is shown.
    let account: OTPAccount
    /// The screen's clock, passed in because table cells don't get the environment.
    let clock: TwoFactorClock

    var body: some View {
        HStack(spacing: DesignKit.Spacing.Primitive.s12) {
            CodeText(code: account.code(at: now), didCopy: didCopy)
                .equatable()
            CountdownGauge(remaining: account.secondsRemaining(at: now), period: account.period)
                .equatable()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            TwoFactorRow.copyCode(of: account)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        }
        .animation(DesignKit.Motion.standard, value: didCopy)
        .accessibilityElement(children: .combine)
        .accessibilityHint("codes.row.copyHint")
    }
}

private extension TwoFactorCell {
    /// The current time, read from the clock so the cell redraws every second.
    var now: Date { clock.now }
}

/// The code. Only redraws when the code rotates or is copied.
private struct CodeText: View, Equatable {
    /// The current code.
    let code: String
    /// Shows "Copied" instead of the code.
    let didCopy: Bool

    var body: some View {
        (didCopy ? Text("global.copied") : Text(verbatim: TwoFactorRow.formatted(code)))
            .font(.system(.title2, design: .monospaced, weight: .semibold))
            .foregroundStyle(didCopy ? .accent : .primary)
            .monospacedDigit()
            .animation(DesignKit.Motion.standard, value: code)
    }
}

/// The countdown. The only part of a row that redraws every second.
///
/// Turns red for the last five seconds.
private struct CountdownGauge: View, Equatable {
    /// Seconds until the code changes.
    let remaining: Int
    /// The code's full period in seconds.
    let period: Int

    var body: some View {
        Gauge(value: Double(remaining), in: 0...Double(max(period, 1))) {
            Text(remaining, format: .number)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(remaining <= 5 ? Color.red : Color.green)
        .scaleEffect(0.6)
        .accessibilityLabel(LocalizedKey("codes.row.secondsLeft", remaining))
        .animation(DesignKit.Motion.quickBouncy, value: remaining)
    }
}
