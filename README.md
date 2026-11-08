![icon](https://github.com/user-attachments/assets/4947bff9-c02e-41a0-ab7a-0272424aaa4f)

# Munin -- Passwords and Authenticator

![swift](https://img.shields.io/badge/Swift-6-orange)
![tests](https://img.shields.io/github/actions/workflow/status/brillcp/MuninApp/tests.yml?branch=main&event=push&label=tests)
![release](https://img.shields.io/github/v/release/brillcp/MuninApp)
![platforms](https://img.shields.io/badge/Platforms-iOS%2026.6%2B%20%7C%20macOS%2026.6%2B-blue)
[![license](https://img.shields.io/github/license/brillcp/MuninApp)](/LICENSE)
![stars](https://img.shields.io/github/stars/brillcp/MuninApp?style=social)

Munin is an end-to-end encrypted password manager and two-factor authenticator
for iPhone, iPad, and Mac.

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
- **Sign in with Apple.** No separate account or password to create.
- **Localization.** 20 languages: Arabic, Chinese (Simplified), Czech, Danish,
  Dutch, English, Finnish, French, German, Greek, Hebrew, Italian, Japanese,
  Korean, Norwegian Bokmål, Polish, Portuguese (Brazil), Russian, Spanish, and
  Swedish.

## Security

Everything you store is encrypted on your device before it's sent to the
server. The server stores ciphertext it can't read, and can't reset your
master password for you. See [SECURITY.md](SECURITY.md) for the cryptographic
design and how to report a vulnerability.

## Requirements

Xcode 27.1 or later.

## Configuration

Build settings live in `Config/Base.xcconfig`:

| Setting | Purpose |
| --- | --- |
| `DEVELOPMENT_TEAM` | The team that signs the app and extension. |
| `APP_BUNDLE_ID` | The app's bundle identifier. The AutoFill extension uses `$(APP_BUNDLE_ID).AutoFill`, and the shared keychain group is `$(AppIdentifierPrefix)$(APP_BUNDLE_ID).shared`. |
| `MUNIN_API_HOST` | The host of the Munin API. |
| `SUPABASE_HOST` | The host of the authentication service. |
| `SUPABASE_PUBLISHABLE_KEY` | The authentication service's publishable key. It's public by design and ships in the app. |

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
└── Features/
    ├── AddAccount/    Adding 2FA accounts by QR code, link, or setup key
    ├── AutoFill/      AutoFill setup guide and banner
    ├── Lock/          Sign-in and lock screen
    ├── Main/          The main window: sidebar and tabs
    ├── MenuBar/       The Mac menu bar extra
    ├── Search/        The iOS Search tab, across passwords and 2FA accounts
    ├── Settings/      Settings and changing the master password
    ├── Subscription/  Paywall and subscription banners
    ├── TwoFactor/     The list of 2FA codes
    ├── Vault/         The password list, detail, editor, and generator
    └── VaultKey/      Master password setup and the recovery key
MuninAutoFill/         The AutoFill credential provider extension
MuninTests/            Unit tests
Config/                Build settings
```

## License

Munin is licensed under the GNU General Public License v3.0. See
[LICENSE](LICENSE).
