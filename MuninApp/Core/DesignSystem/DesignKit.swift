import SwiftUI

/// Munin's design tokens.
enum DesignKit {
    /// Spacing tokens, for paddings and stack spacing.
    enum Spacing {
        enum Primitive {
            static let s0: CGFloat = 0
            static let s2: CGFloat = 2
            static let s4: CGFloat = 4
            static let s6: CGFloat = 6
            static let s8: CGFloat = 8
            static let s12: CGFloat = 12
            static let s16: CGFloat = 16
            static let s24: CGFloat = 24
            static let s32: CGFloat = 32
            static let s40: CGFloat = 40
            static let s48: CGFloat = 48
            static let s56: CGFloat = 56
            static let s64: CGFloat = 64
            static let s72: CGFloat = 72
        }
    }

    /// Animation tokens, for implicit and explicit animations.
    enum Motion {
        /// The system default, for small state changes like copy feedback.
        static let linear: Animation = .linear(duration: 0.25)
        /// A springy bounce, for content that changes step or size.
        static let bouncy: Animation = .bouncy
        /// A short bounce, for showing and hiding panels.
        static let quickBouncy: Animation = .bouncy(duration: 0.25)
        /// A gentle ease, for color and tint changes.
        static let easeInOut: Animation = .easeInOut
        /// A smooth curve, for rows being added to or removed from a list.
        static let listChange: Animation = .smooth(duration: 0.3)
        /// A slow, smooth curve, for full-screen transitions like the lock screen.
        static let slowSmooth: Animation = .smooth(duration: 0.45)
    }

    /// SF Symbol names, by what they stand for. Use with `systemImage:` and
    /// `Image(systemName:)`.
    enum Icon {
        // MARK: Sections
        /// The Vault: passwords.
        static let vault = "lock.rectangle.stack"
        /// 2FA accounts.
        static let twoFactor = "key.viewfinder"
        /// Settings.
        static let settings = "gearshape"
        /// Settings, when its sidebar tab is selected.
        static let settingsSelected = "gearshape.fill"
        /// Search.
        static let search = "magnifyingglass"

        // MARK: Actions
        /// Add a 2FA account.
        static let add = "plus"
        /// Create a password.
        static let createPassword = "plus.square.on.square"
        /// Copy a value.
        static let copy = "square.on.square"
        /// A value was just copied.
        static let copied = "checkmark"
        /// Edit an item.
        static let edit = "square.and.pencil"
        /// Delete an item.
        static let delete = "trash"
        /// Close a panel.
        static let close = "xmark"
        /// Reload from Munin.
        static let refresh = "arrow.clockwise"
        /// Generate a new password in the generator.
        static let regenerate = "arrow.counterclockwise"
        /// Open the password generator.
        static let generatePassword = "wand.and.stars"
        /// Import from a file.
        static let importFile = "folder.badge.plus"
        /// Export to a file.
        static let export = "square.and.arrow.up"
        /// Open an item's website.
        static let openWebsite = "arrow.up.right.square.fill"
        /// Reveal a password.
        static let showPassword = "eye"
        /// Hide a revealed password.
        static let hidePassword = "eye.slash"
        /// Quit the app (Mac menu bar).
        static let quit = "power"

        // MARK: Sorting
        /// The sort menu.
        static let sort = "arrow.up.arrow.down"
        /// Sort by title.
        static let sortByTitle = "textformat"
        /// Sort by date edited.
        static let sortByDateEdited = "square.and.pencil"
        /// Ascending order.
        static let ascending = "arrow.down"
        /// Descending order.
        static let descending = "arrow.up"

        // MARK: Items
        /// A website, and the placeholder for a missing website icon.
        static let website = "globe"
        /// A username.
        static let username = "person"
        /// A password (Mac menu bar copy).
        static let password = "key"
        /// Scan a 2FA QR code.
        static let scanQRCode = "qrcode.viewfinder"
        /// Choose an image or screenshot with a QR code.
        static let chooseImage = "photo"
        /// No 2FA accounts yet.
        static let noAccounts = "lock.shield"

        // MARK: Lock and security
        /// Lock Munin.
        static let lock = "lock"
        /// Locked: read-only mode and auto-lock.
        static let locked = "lock.fill"
        /// The master password.
        static let masterPassword = "lock.shield"
        /// Unlock with the master password instead of biometrics.
        static let useMasterPassword = "lock.shield.fill"
        /// The recovery key.
        static let recoveryKey = "key"
        /// The vault key is missing on this device.
        static let missingKey = "key.slash"
        /// Set up AutoFill.
        static let autoFill = "rectangle.and.pencil.and.ellipsis"
        /// Face ID.
        static let faceID = "faceid"
        /// Touch ID.
        static let touchID = "touchid"
        /// A generated password's strength.
        static let passwordStrength = "checkmark.shield.fill"

        // MARK: Account and subscription
        /// Subscribe.
        static let subscribe = "star"
        /// Restore App Store purchases.
        static let restorePurchases = "arrow.clockwise"
        /// Manage the App Store subscription.
        static let manageSubscription = "creditcard"
        /// Sign out.
        static let signOut = "rectangle.portrait.and.arrow.right"
        /// Delete the account.
        static let deleteAccount = "xmark.octagon.fill"
        /// The privacy policy.
        static let privacyPolicy = "hand.raised"
        /// The terms of use.
        static let termsOfUse = "doc.text"

        // MARK: Status
        /// Something went wrong.
        static let warning = "exclamationmark.triangle"
        /// The App Store couldn't renew the subscription.
        static let billingIssue = "exclamationmark.triangle.fill"
        /// Munin couldn't be reached.
        static let offline = "wifi.exclamationmark"
        /// Items that couldn't be decrypted.
        static let undecryptable = "exclamationmark.lock"
    }

    /// Image names in the asset catalog.
    enum Asset {
        /// The app icon, shown on the lock screen and the paywall.
        static let appIcon = "icon-512"
        static let appIconDark = "icon-dark-512"
        /// The raven artwork behind the lock screen.
        static let lockArtwork = "corpus"
        /// The raven silhouette in the Mac menu bar: a template image, sized
        /// for the menu bar (18 pt high) in the asset itself.
        static let menuBarIcon = "munin-silouette"
    }
}
