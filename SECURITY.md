# Security

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's private vulnerability
reporting: open the repository's **Security** tab and choose **Report a
vulnerability**. Don't open public issues or pull requests for security
problems.

Include the affected platform and version, steps to reproduce, and the impact
you expect. You'll get a response once the report has been reviewed. Please
allow time for a fix to ship before disclosing the issue publicly.

## Supported versions

Only the latest release on the App Store receives security fixes.

## Design

Everything you store is encrypted on your device before it's sent to the
server. The server stores ciphertext it can't read, and can't reset your
master password. The server's source code is private; this section
describes both the apps and the server.

All encryption uses Apple CryptoKit, except PBKDF2, which uses CommonCrypto.

### Keys

- **Vault key.** A random 256-bit key, created on the device when a new vault
  is set up. It encrypts every password field and 2FA account.
- **Master password.** Normalized to Unicode NFC, then stretched with
  PBKDF2-HMAC-SHA256 (600,000 iterations, random 16-byte salt) into 32 bytes.
  HKDF-SHA256 splits the result into two independent keys:
  - a *wrapping key*, which encrypts the vault key and never leaves the
    device, and
  - a *proof*, which is sent to the server to authorize changes.

  The KDF algorithm, iteration count, and salt are stored on the server with
  the wrapped key, so every device derives the same keys. Changing the master
  password uses a new salt.
- **Recovery key.** The vault key itself, shown once when the vault is created
  as base64 in groups of four characters. Because it's already uniformly
  random, it skips PBKDF2 and goes straight through HKDF-SHA256 to produce its
  own wrapping key and proof. It resets a forgotten master password.
- **Key separation.** The HKDF `info` strings name both the purpose
  (`password` or `recovery`) and the output (`wrap` or `auth`), so the proof
  can't be used to unwrap anything, and keys from different secrets are never
  interchangeable.

### Wrapped vault key

The vault key is encrypted twice with AES-256-GCM: once with the master
password's wrapping key and once with the recovery key's wrapping key. The
associated data binds each copy to the user ID and to the secret that wrapped
it, so the two copies can't be swapped or moved to another account.

The server stores both wrapped copies and the KDF parameters, which it never
reads. It doesn't store the proofs: it keeps a bcrypt hash of each and
returns only the wrapped keys and KDF parameters to the app, with
`Cache-Control: no-store`.

### Vault data

- **Passwords.** Each field (name, website, username, password, note) is
  encrypted separately with AES-256-GCM. The associated data binds each
  ciphertext to the user ID and to its field, so ciphertext can't be moved
  between users or fields.
- **2FA accounts.** Each account (issuer, name, secret, algorithm, digits,
  period) is encoded as JSON and encrypted as one item with AES-256-GCM,
  bound to the user ID. Codes are calculated on the device.
- **In memory.** While the vault is unlocked, names, websites, and usernames
  are decrypted for the list and search. Passwords and notes stay encrypted
  until they're shown, copied, or edited.

### Authorization

Every request carries a Supabase access token from Sign in with Apple. The
server verifies its signature, expiration, and audience, and scopes every
query to the token's user.

Editing or deleting a password, deleting a 2FA account, replacing the vault
key, and deleting the account also require a proof in the `X-Munin-Proof`
header. The app sends the master password's proof, or the recovery key's
proof when resetting a forgotten master password. The server accepts either
proof for any of these requests, and checks it against the bcrypt hashes.

After five wrong proofs within an hour, the server rejects further proofs for
that user with `429 Too Many Requests` until the hour has passed. A correct
proof resets the count.

Deleting the account removes the user's passwords, 2FA accounts,
subscription link, and wrapped vault key, then the user and their sign-in
identities, in one database transaction. When the app provides a fresh Sign
in with Apple authorization code, the server first revokes the user's Sign in
with Apple tokens.

### Storage on the device

Items are stored in the data protection keychain. The app and the AutoFill
extension share one access group.

- **Session.** Access token, refresh token, user ID, and email, readable after
  the first unlock and never synced (`AfterFirstUnlockThisDeviceOnly`).
- **Face ID and Touch ID.** When biometric unlock is on, a copy of the vault
  key and proof is stored with `WhenPasscodeSetThisDeviceOnly` and
  `biometryCurrentSet`. It never syncs, and it becomes unreadable if the
  enrolled faces or fingerprints change. Turning biometric unlock off, or
  signing out, deletes it.
- **Legacy key.** Vaults created before master passwords kept the vault key in
  iCloud Keychain. It's read once to set up a master password, then deleted
  from all devices.

Decrypted vault data isn't written to disk. Exports are built in memory and
written only to the location the user picks in the save panel.

### Locking

Locking removes the vault key and decrypted data from memory, clears the
website icon cache, and clears a copied password from the clipboard.

Auto-lock can lock immediately, after one, five, or fifteen minutes away, or
never. Time away starts when the app moves to the background on iOS, or stops
being the active app on macOS. On macOS, the vault also locks when the Mac
sleeps, the display sleeps, or the screen locks, unless auto-lock is set to
never.

### Clipboard

A copied password is cleared after 60 seconds, and when the vault locks. The
app clears only its own value, never something copied afterward.

- On iOS, the item has an expiration date and is local only, so it doesn't
  reach other devices through Universal Clipboard.
- On macOS, the value is cleared after 60 seconds if nothing else was copied
  in the meantime. If the app quits first, the value stays on the clipboard.

Usernames, websites, and notes are copied without clearing.

### What the server can see

The server can't read vault data, but it does see:

- the account from Sign in with Apple, including the email address you chose
  to share,
- how many passwords and 2FA accounts you have, their sizes, and when they
  were created and changed,
- when a password was last copied: copying a password in the app updates its
  timestamp on the server,
- your subscription status.

Website icons are downloaded by the app directly from each website, not
through the server, using an ephemeral session without cookies or a URL
cache. Those websites can see a request from your IP address. Icons are kept
in memory only.
