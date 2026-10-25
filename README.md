![icon](https://github.com/user-attachments/assets/4947bff9-c02e-41a0-ab7a-0272424aaa4f)

# Munin – Secure and open source password manager and 2 factor authenticator

Munin is an end-to-end encrypted password manager and authenticator (2FA
codes) for iPhone, iPad and Mac.

This repository is the source code of the Munin apps for iOS and macOS. The
Munin sync service the apps talk to is not part of this repository.

## Support

No support is provided for this code directly. For help with the Munin app or
your subscription, contact <!-- support email -->.

## Contributions

<!-- Pick one: -->
External contributions are not accepted at the moment. Pull requests will be
closed without review.

## Security model

Everything you store is encrypted on your device before it's sent to Munin.
Munin stores ciphertext it can't read, and can't reset your master password
for you.

### Keys

- **Vault key.** A random 256-bit key, created on your device the first time
  you set up Munin. It encrypts every password and 2FA account.
- **Master password.** Turned into a key with PBKDF2-HMAC-SHA256 (600,000
  rounds, random 16-byte salt), then split with HKDF into a *wrapping key* and
  a *proof*. The wrapping key encrypts the vault key (AES-256-GCM) and never
  leaves the device.
- **Recovery key.** Shown once when you set up Munin. It also wraps the vault
  key, so it can reset a forgotten master password.
- **What Munin stores.** The vault key wrapped twice (by the master password
  and by the recovery key), the KDF settings, and bcrypt hashes of the two
  proofs. Each wrapped key is bound to your account and to which key wrapped
  it, so the copies can't be swapped.

### Data

- **Passwords.** Each field (name, website, username, password, note) is
  encrypted separately with AES-256-GCM and bound to your account and to its
  field, so ciphertext can't be moved between users or fields.
- **2FA accounts.** Each account (issuer, name, secret) is encrypted as one
  item. Codes are calculated on your device.
- **In memory.** While unlocked, names, websites and usernames are decrypted
  for the list and search. Passwords and notes stay encrypted until you show
  or copy them. Locking drops everything decrypted and the vault key.

### Protections

- **Proof for destructive changes.** Edits and deletes are only accepted with
  your master password's proof. Munin rate-limits wrong proofs.
- **Face ID / Touch ID.** An optional copy of the vault key, kept in this
  device's Keychain behind biometrics. It's never synced, and stops working if
  enrolled faces or fingers change.
- **Clipboard.** A copied password is cleared after a minute, and when Munin
  locks. On iOS it's kept off Universal Clipboard.
- **Auto-lock.** After a chosen time without use, when the Mac sleeps or its
  screen locks, or on leaving the app.

### What Munin can see

Munin can't read your data, but it does see:

- your account (from Sign in with Apple; you can hide your email),
- how many items and 2FA accounts you have, their sizes and when they changed.

Website icons are downloaded by the app straight from each website, not
through Munin. Those websites can see that a request came from your IP
address. Icons are kept in memory only.

## Reporting a vulnerability

Please report security issues privately to <!-- security email -->, not in
public issues.

## Building

Requirements:

- Xcode with the iOS 27 and macOS 27 SDKs
- An Apple Developer account (for signing and Sign in with Apple)

Steps:

1. Clone the repository and open `MuninApp.xcodeproj`.
2. Under *Signing & Capabilities*, choose your team.
3. Run the **MuninApp** scheme on an iPhone, iPad or Mac.

Swift packages:

- [brillcp/Networking](https://github.com/brillcp/networking)

Builds from source are meant for reviewing and verifying the code. Signing in
to the hosted Munin service only works with the official app's bundle
identifier.

## Project structure

```
MuninApp/
├── App/          Commands and the Mac menu bar window
├── Core/
│   ├── DesignSystem/   Spacing, motion and AppKit colour overrides
│   ├── Security/       Vault session, unlocking and auto-lock
│   ├── Services/       Munin and sign-in requests, website icons
│   ├── Utilities/      Keychain, clipboard, localisation helpers
│   └── Vault/          Encryption, keys, TOTP, import parsers
└── Features/     Lock screen, Vault, 2FA, Search, Settings
```

## License

See [LICENSE](LICENSE).
