# Mido Notes / Mido筆記

Encrypted notes and password manager for Android and Windows, built with Flutter.
加密筆記與帳號密碼本（Android／Windows），Flutter 開發，由 GitHub Actions 編譯。

**Download / 下載**: see the [Releases](../../releases) page — `Mido-notes.apk` (Android) or `Mido-notes-windows.zip` (Windows).

## Features / 功能

- Text notes and logins (site / username / password / notes), several accounts per login note
- Folders, tags, pin, color, drag-to-reorder, search, Markdown preview, image attachments (encrypted)
- Per-note lock with its own lock password; optional "no master password" mode
- Trash (30 days), password generator, reused/weak password check, Chrome/Google CSV import
- Encrypted backup export / restore (manual — no cloud service is used)
- Fingerprint unlock, screenshot blocking, auto-lock
- Traditional Chinese / English, light / dark / pure black, 8 theme colors
- Manual "check for updates" in Settings (only when you tap it)

## Security design / 安全設計

- Random 256-bit data key (DEK) encrypts everything with AES-256-GCM.
- The master password goes through PBKDF2-HMAC-SHA256 (400,000 rounds) and only wraps the DEK.
- Everything stays on the device. The app never uploads your data; the only network call is the optional manual update check to the GitHub API.
- **If you forget the master password there is no recovery and no backdoor.**
- Not independently audited. Use at your own risk. 自製 App，未經第三方資安審計。

## Privacy / 隱私

No accounts, no analytics, no ads, no cloud sync. Backups are files you export yourself.

## Build it yourself / 自行編譯

1. Fork or copy this repository.
2. (Recommended) create your own Android signing key and add four Actions secrets in
   **Settings → Secrets and variables → Actions**: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
   Without them the APK is signed with a temporary debug key, and a later build cannot be installed over it.
   Keep the key file safe and never commit it.
3. Run the **Build APK** / **Build Windows** workflows (Actions tab) or push to `main`.
   Each run publishes a GitHub Release tagged `v<version in pubspec.yaml>`.

To publish a new version: raise `version:` in `pubspec.yaml` (the number after `+` must increase every time),
add a section to `CHANGELOG.md`, and push.

## Project layout

```
lib/                   Flutter source (UI in lib/ui, data & crypto in lib/data, lib/crypto)
lib/i18n*.dart         tr() translation helper + Chinese→English table
android_overlay/       Native Android files (biometrics, screenshot blocking)
tool/                  Scripts that patch the generated Android / Windows projects
.github/workflows/     Cloud build definitions
```

## License

MIT — see [LICENSE](LICENSE).
