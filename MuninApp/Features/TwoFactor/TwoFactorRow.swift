import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A row that shows a two-factor account's name, current code, and countdown.
///
/// Tapping the row copies the code.
struct TwoFactorRow: View {
    /// A Boolean value that indicates whether the code was just copied.
    ///
    /// While true, the row shows Copied instead of the code.
    @State private var didCopy = false

    /// The account whose code is shown.
    let account: OTPAccount
    /// The clock that drives the code and countdown.
    ///
    /// Reading `clock.now` in the row lets each row update independently.
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
        .contentShape(.rect)
        .onTapGesture(perform: copy)
        .sensoryFeedback(.success, trigger: didCopy) { _, new in new }
        .animation(DesignKit.Motion.linear, value: didCopy)
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

    /// Splits a code into two halves for readability.
    ///
    /// For example, `"123456"` becomes `"123 456"`, and `"12345678"` becomes
    /// `"1234 5678"`.
    ///
    /// - Parameter code: The code to format.
    /// - Returns: The code with a space between its halves, or the code
    ///   unchanged if it has four or fewer digits.
    static func formatted(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}

private extension TwoFactorRow {
    /// The current time, read from the clock so the row updates every second.
    var now: Date { clock.now }

    /// Copies the current code and briefly shows Copied.
    func copy() {
        Self.copyCode(of: account)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}

/// A view that shows a two-factor account's issuer and name.
///
/// Equatable, so it doesn't redraw when the clock ticks.
struct AccountLabel: View, Equatable {
    /// The issuer, or the account name when there's no issuer.
    let title: String
    /// The account name, when the title is the issuer; otherwise, `nil`.
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
