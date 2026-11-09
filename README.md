![icon](https://github.com/user-attachments/assets/4947bff9-c02e-41a0-ab7a-0272424aaa4f)

# Munin – Passwords and 2FA Authenticator

![platforms](https://img.shields.io/badge/Platforms-iOS%2026.6%2B%20%7C%20macOS%2026.6%2B-blue)
![swift](https://img.shields.io/badge/Swift-6-orange)
![tests](https://img.shields.io/github/actions/workflow/status/brillcp/MuninApp/tests.yml?branch=main&event=push&label=tests)
![release](https://img.shields.io/github/v/release/brillcp/MuninApp)
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

## Requirements

Xcode 27.1 or later.

## License

Munin is licensed under the GNU General Public License v3.0. See
[LICENSE](LICENSE).
