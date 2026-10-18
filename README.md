# MuninApp

iOS + macOS end-to-end encrypted authenticator backed by [Munin](../Munin).
Tap a row to copy its code.

- **End-to-end encrypted.** A per-user AES-256 vault key lives in iCloud Keychain
  (synchronizable, so it reaches the user's other Apple devices). Entries
  (issuer, name, secret) are sealed with AES-GCM, bound to the user ID, before
  upload. Munin stores ciphertext only; codes are calculated on device.
  Account menu → Show Recovery Key to back the key up; a device without the key
  can restore from it.
- **Add accounts:** scan a QR code (iPhone camera), choose a screenshot/image,
  paste an `otpauth://` link, or enter the setup key. Google Authenticator export
  QR codes (`otpauth-migration://`) import all their accounts at once.

- **Sign in with Apple → Supabase.** The Apple identity token is exchanged at
  `/auth/v1/token?grant_type=id_token` for a Supabase session (Keychain,
  auto-refreshed, modelled on Oden's `SupabaseTokenProvider`). Its JWT is the
  bearer token for Munin, which scopes every account to the signed-in user.
- **Networking:** [brillcp/Networking](https://github.com/brillcp/networking),
  used like Oden (Request / Endpoint / ServiceFactory / Service).
- **Config:** `Core/Services/APIConfig.swift`: Munin URL, Supabase URL and the
  publishable key.
- `Info.plist` allows plain HTTP to local hosts (`NSAllowsLocalNetworking`) for
  development. Remove it once Munin runs behind HTTPS.

## One-time setup

1. Apple Developer → Identifiers → `dev.gidlof.Munin`: enable **Sign in with Apple**
   (Xcode's automatic signing usually does this from the entitlement).
2. Supabase (Munin's project) → Authentication → Sign In / Providers → **Apple**:
   enable it and add `dev.gidlof.Munin` under Client IDs. Native sign-in needs no
   secret key.
3. Paste the project's publishable key into `APIConfig.anonKey`.
