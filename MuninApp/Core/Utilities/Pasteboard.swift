import Foundation
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#else
import AppKit
#endif

/// A namespace for copying text to the system pasteboard, with special handling for sensitive values.
enum Pasteboard {
    /// The duration a copied sensitive value remains on the pasteboard.
    static let sensitiveLifetime: Duration = .seconds(60)

    /// Copies non-sensitive text, such as a username, URL, or note.
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// The pasteboard's change count after the last sensitive copy.
    ///
    /// Clearing compares against this value, so it removes only the app's own
    /// value and never something the user copied later.
    private static var sensitiveChangeCount: Int?

    /// Immediately removes a copied sensitive value if it's still on the pasteboard.
    ///
    /// Call this when the vault locks.
    static func clearSensitive() {
        guard let sensitiveChangeCount else { return }
        #if os(iOS)
        if UIPasteboard.general.changeCount == sensitiveChangeCount {
            UIPasteboard.general.items = []
        }
        #else
        if NSPasteboard.general.changeCount == sensitiveChangeCount {
            NSPasteboard.general.clearContents()
        }
        #endif
        self.sensitiveChangeCount = nil
    }

    /// Copies a sensitive value, such as a password, and clears it after ``sensitiveLifetime``.
    ///
    /// On iOS, the item expires automatically and is excluded from Universal
    /// Clipboard, so it doesn't appear on the user's other devices.
    ///
    /// On macOS, the value is cleared after the delay unless something else was
    /// copied in the meantime. If the app quits first, the value remains on the pasteboard.
    static func copySensitive(_ string: String) {
        #if os(iOS)
        let expiry = Date.now.addingTimeInterval(TimeInterval(sensitiveLifetime.components.seconds))
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: string]],
            options: [.expirationDate: expiry, .localOnly: true]
        )
        sensitiveChangeCount = UIPasteboard.general.changeCount
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        let changeCount = pasteboard.changeCount
        sensitiveChangeCount = changeCount
        Task {
            try? await Task.sleep(for: sensitiveLifetime)
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
        #endif
    }
}
