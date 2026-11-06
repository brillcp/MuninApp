![icon](https://github.com/user-attachments/assets/4947bff9-c02e-41a0-ab7a-0272424aaa4f)

# Munin

Munin is an end-to-end encrypted password manager and two-factor authenticator
for iPhone, iPad, and Mac.

This repository contains the source code of the Munin apps for iOS, iPadOS,
and macOS. The Munin sync service the apps talk to isn't part of this
repository.

## Features

- **Passwords.** Store names, websites, usernames, passwords, and notes.
  Generate passwords, search, and sort the vault.
- **Two-factor codes.** TOTP codes (SHA-1, SHA-256, SHA-512), added by scanning
  a QR code, opening an `otpauth://` link, or entering the setup key. Google
  Authenticator exports (`otpauth-migration://`) import several accounts at
  once.
- **AutoFill.** A credential provider extension fills passwords and one-time
  codes in Safari and other apps.
- **Import and export.** Import CSV exports from other password managers,
  including Chrome, Apple Passwords, 1Password, Bitwarden, LastPass, Proton
  Pass, NordPass, and Firefox. Export passwords as CSV and 2FA accounts as
  `otpauth://` links.
- **Mac.** A main window, a Settings window, and a menu bar extra for copying
  usernames and passwords.
- **Sign in with Apple.** Accounts are created and signed in with Apple.
- **Subscription.** A monthly App Store subscription. Without an active
  subscription, the vault becomes read-only: reading, copying, and unlocking
  still work, but changes are blocked.
- **Localization.** 20 languages.

## Security

Everything you store is encrypted on your device before it's sent to the
server. The server stores ciphertext it can't read, and can't reset your
master password for you. See [SECURITY.md](SECURITY.md) for the cryptographic
design and how to report a vulnerability.

## Requirements

- Xcode 27.1 or later
- iOS 26.6, iPadOS 26.6, or macOS 26.6 or later
- An Apple Developer account, to sign the app and use Sign in with Apple

## Getting started

1. Clone the repository.
2. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your own team and bundle identifier:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   APP_BUNDLE_ID = com.example.Munin
   ```

3. Open `MuninApp.xcodeproj`.
4. Run the **MuninApp** scheme on an iPhone, iPad, or Mac.

Swift packages are resolved automatically:

- [brillcp/Networking](https://github.com/brillcp/networking)

## Configuration

Build settings live in `Config/Base.xcconfig`, which is committed:

| Setting | Purpose |
| --- | --- |
| `DEVELOPMENT_TEAM` | The team that signs the app and extension. |
| `APP_BUNDLE_ID` | The app's bundle identifier. The AutoFill extension uses `$(APP_BUNDLE_ID).AutoFill`, and the shared keychain group is `$(AppIdentifierPrefix)$(APP_BUNDLE_ID).shared`. |
| `MUNIN_API_HOST` | The host of the Munin API. |
| `SUPABASE_HOST` | The host of the authentication service. |
| `SUPABASE_PUBLISHABLE_KEY` | The authentication service's publishable key. It's public by design and ships in the app. |

`Base.xcconfig` ends with `#include? "Local.xcconfig"`. Put your overrides in
`Config/Local.xcconfig`, which git ignores. At minimum, set
`DEVELOPMENT_TEAM` and `APP_BUNDLE_ID` to sign with your own account.

By default, the app talks to the production backend. The values reach Swift
through Info.plist keys, which `APIConfig` reads. The server's source code
isn't public. Sign in with Apple against the hosted service only works with
the official bundle identifier, so a build with your own identifier can't
sign in.

## Project structure

```
MuninApp/              The app target
├── App/               Menu bar commands (Find, Lock, sections)
├── Core/
│   ├── DesignSystem/  Spacing, motion, icons, and AppKit color overrides
│   ├── Security/      Vault session, unlocking, and auto-lock
│   ├── Services/      API requests, sign-in, subscription, AutoFill, icons
│   ├── Utilities/     Keychain, clipboard, localization helpers
│   └── Vault/         Encryption, keys, TOTP, and import/export
├── Features/
│   ├── AddAccount/    Adding 2FA accounts by QR code, link, or setup key
│   ├── AutoFill/      AutoFill setup guide and banner
│   ├── Lock/          Sign-in and lock screen
│   ├── Main/          The main window: sidebar and tabs
│   ├── MenuBar/       The Mac menu bar extra
│   ├── Search/        The iOS Search tab, across passwords and 2FA accounts
│   ├── Settings/      Settings and changing the master password
│   ├── Subscription/  Paywall and subscription banners
│   ├── TwoFactor/     The list of 2FA codes
│   ├── Vault/         The password list, detail, editor, and generator
│   └── VaultKey/      Master password setup and the recovery key
└── *.lproj/           Localized strings
MuninAutoFill/         The AutoFill credential provider extension
MuninTests/            Unit tests
Config/                Build configuration
```

## Tests

Unit tests use Swift Testing. Run them with Command-U in Xcode, or:

```
xcodebuild test -scheme MuninApp -destination 'platform=macOS'
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
code conventions, and how to open a pull request.

## License

Munin is licensed under the GNU General Public License v3.0. See
[LICENSE](LICENSE).
