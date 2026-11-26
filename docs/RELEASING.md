# Releasing Aloud

This document explains how **Aloud** keeps its Android app identity consistent so every future APK update installs cleanly on your phone without losing data or hitting signature-conflict errors.

## App Identity

- **Application ID / Package Name:** `dev.aloud.aloud` (configured in `android/app/build.gradle.kts`)
- **Signing Keystore (local, gitignored):** `android/app/aloud-release.jks` / `$HOME/.android/aloud-release.jks`
- **Signing Properties (local, gitignored):** `android/key.properties`
- **Key Alias:** `aloud-release`
- **Certificate SHA-1:** `48:F6:6A:F1:D7:D7:6E:57:55:8B:9D:08:E1:CA:46:1A:6A:13:0C:8C`
- **Certificate SHA-256:** `C3:EE:40:9C:73:79:3C:57:BD:3F:D1:48:F0:C8:5B:99:D9:01:39:E9:AF:DE:F9:97:81:21:43:87:DE:7D:20:17`

> **Important:** Never delete or replace the keystore or change `applicationId`. Android rejects updates if either the package ID or the signing certificate changes. The keystore is gitignored so private keys are never exposed in the public repository; an identical copy can be stored in GitHub Actions repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).

## Creating a New GitHub Release

1. Update the version in `pubspec.yaml` (for example `version: 0.1.1+2`) and commit your changes to `main`.
2. Tag the release and push the tag:
   ```bash
   git tag v0.1.1
   git push origin main --tags
   ```
3. GitHub Actions (`.github/workflows/release.yml`) will automatically:
   - Run `flutter analyze` and `packages/aloud_core` unit tests
   - Build a signed release APK using the repository signing secrets
   - Verify the APK signing certificate fingerprint
   - Publish a GitHub Release with `aloud-v0.1.1-arm64.apk` and its `.sha256` checksum attached

You can also trigger a release manually from the **Actions → Release Android APK → Run workflow** tab on GitHub.

## Building a Signed APK Locally

Because the release keystore and `android/key.properties` are configured locally, running a release build signs with the exact same release identity:

```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
