import Foundation
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#else
import AppKit
#endif

/// Copies text to the system clipboard, with special handling for passwords.
enum Pasteboard {
    /// How long a copied password stays on the clipboard.
    static let sensitiveLifetime: Duration = .seconds(60)

    /// Copies non-sensitive text (a username, a URL, a note).
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// The clipboard's change count right after the last sensitive copy, so
    /// clearing only removes our own password, not something copied later.
    private static var sensitiveChangeCount: Int?

    /// Removes a copied password right away, if it's still on the clipboard.
    /// Called when the vault locks.
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

    /// Copies a password and clears it after `sensitiveLifetime`.
    ///
    /// iOS: the item expires on its own and is kept off Universal Clipboard, so
    /// it isn't left behind on the user's other devices.
    /// macOS: cleared after the delay unless something else was copied in the
    /// meantime. If the app quits first, it stays on the clipboard.
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
