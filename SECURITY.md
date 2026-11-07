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
master password. This section describes both the apps and the server.

All encryption uses Apple [CryptoKit](https://developer.apple.com/documentation/cryptokit), except PBKDF2, which uses CommonCrypto.

### Algorithms

| Purpose | Algorithm |
| --- | --- |
| Encrypting vault data and wrapping the vault key | [AES-256][aes] in [GCM][gcm] mode |
| Stretching the master password | [PBKDF2][pbkdf2] with [HMAC][hmac]-[SHA-256][sha], 600,000 iterations, 16-byte random salt |
| Splitting a secret into a wrapping key and a proof | [HKDF][hkdf] with [SHA-256][sha] |
| Storing proofs on the server | [bcrypt][bcrypt] |
| Transport | HTTPS over [TLS][tls], enforced by [App Transport Security][ats] |

[aes]: https://csrc.nist.gov/pubs/fips/197/final
[gcm]: https://csrc.nist.gov/pubs/sp/800/38/d/final
[pbkdf2]: https://www.rfc-editor.org/rfc/rfc8018
[hmac]: https://www.rfc-editor.org/rfc/rfc2104
[sha]: https://csrc.nist.gov/pubs/fips/180-4/upd1/final
[hkdf]: https://www.rfc-editor.org/rfc/rfc5869
[bcrypt]: https://www.usenix.org/legacy/events/usenix99/provos/provos.pdf
[tls]: https://www.rfc-editor.org/rfc/rfc8446
[ats]: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity

Every AES-GCM operation uses a fresh random 96-bit nonce and a 128-bit
authentication tag. Each ciphertext is stored as the nonce, the encrypted
bytes, and the tag, base64-encoded. A wrong key, a wrong owner or field, or
any change to the ciphertext makes decryption fail instead of returning wrong
data.

### End to end

The vault key is created on your device and never leaves it unencrypted. The
server only ever receives ciphertext, wrapped keys, KDF parameters, and
proofs.

- **Setting up a vault.** The app creates a random vault key, derives a
  wrapping key and proof from the master password and from the recovery key,
  wraps the vault key with each wrapping key, and uploads both wrapped copies,
  the KDF parameters, and both proofs.
- **Saving an item.** The app encrypts the item with the vault key on the
  device (each password field separately, or a 2FA account as one item), then
  uploads the ciphertext.
- **Unlocking on a new device.** After Sign in with Apple, the app downloads
  the wrapped vault key and the KDF parameters, derives the wrapping key from
  the master password you enter, and unwraps the vault key locally. A wrong
  password fails to unwrap; nothing about it is sent to the server. Because
  this check happens on the device, the server's rate limit doesn't apply to
  it: the cost of PBKDF2 is what slows down guessing a master password.
- **Reading an item.** The app downloads the ciphertext and decrypts it on
  the device.
- **Changing the master password.** The app derives new keys with a new salt,
  wraps the same vault key again, and replaces the wrapped copies on the
  server. Vault data isn't re-encrypted, and the recovery key stays the same.
- **Resetting with the recovery key.** The app unwraps the vault key with the
  recovery key, then sets a new master password the same way.

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
