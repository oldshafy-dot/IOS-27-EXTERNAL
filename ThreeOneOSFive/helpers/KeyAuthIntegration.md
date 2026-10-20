# Key Auth Integration

The app starts on a white/blue key-verification screen. **Temporary demo mode is enabled** so any non-empty key is accepted locally.

## Switch to the real API

In `ThreeOneOSFive/views/DesignSystem.swift`, change:

```swift
static let demoMode = false
static let enabled = true
static let verificationURL = URL(string: "https://YOUR-AUTH-ENDPOINT.example/verify")
```

The app sends:

```json
{
  "key": "USER_KEY",
  "device": "SHA256_DEVICE_FINGERPRINT"
}
```

Expected success response:

```json
{ "authorized": true }
```

For a key already bound to another device:

```json
{ "authorized": false, "reason": "already_bound" }
```

The **one-key/one-device rule must be enforced by the server**. The app generates a per-installation identifier in Keychain and sends its SHA-256 fingerprint to the API.

## Recommended production response

For stronger security, the API should return a short-lived signed session token after successful verification instead of treating the raw key as a permanent local credential.
