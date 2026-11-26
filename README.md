# Aloud

Listen to anything: books, PDFs, web novels, articles and comics, read by natural
voices, with the sentence being spoken highlighted on screen.

A ground-up Flutter redesign of the original *AStory* Android app. It keeps what
that app was *for* (see [`docs/FEATURE_MAP.md`](docs/FEATURE_MAP.md)) and replaces
its 3 MB of accreted Kotlin with a small, layered, tested codebase.

## Quick start

```powershell
flutter pub get
flutter run
```

The Android project and Aloud-specific manifest/activity are checked in. If you
regenerate the Android folder, use `flutter create --org dev.aloud
--project-name aloud --platforms=android .` and then run
`dart tool/setup_android.dart`. The setup script keeps the application ID,
raises `minSdk` to 24, and adds the voice-archive dependency without changing
Gradle, AGP, or Kotlin versions.

### Verify

```powershell
Push-Location packages/aloud_core
dart pub get
dart test
Pop-Location
flutter test
flutter analyze
```

On Windows, Flutter tests that load `pdfrx` also need the Windows SDK headers
(`windows.h`) installed through Visual Studio. This is only needed for the
Windows test target; Android builds use the Android SDK.

## Android release identity

The Android `applicationId` is permanently `dev.aloud.aloud`. Keep it unchanged
for every release so Android recognizes new APKs as updates to the same app.
The release signing key is a second part of that identity: losing or replacing
it prevents existing installations from accepting future APK updates. Keep a
secure backup of the keystore and its passwords; neither belongs in Git.

Create a release key once (do not regenerate it for later releases):

```powershell
keytool -genkeypair -v -keystore "$HOME\.android\aloud-release.jks" `
  -alias aloud-release -keyalg RSA -keysize 2048 -validity 10000
```

Create the ignored file `android/key.properties` with the following fields,
using the passwords chosen above and the full path to the keystore:

```properties
storePassword=<keystore-password>
keyPassword=<key-password>
keyAlias=aloud-release
storeFile=C:/Users/<you>/.android/aloud-release.jks
```

Build a signed release APK with `flutter build apk --release`; the output is
`build/app/outputs/flutter-apk/app-release.apk`. Before each update, increment
the build number after `+` in `pubspec.yaml`. To print the public SHA-256
certificate fingerprint, run:

```powershell
keytool -list -v -keystore "$HOME\.android\aloud-release.jks" -alias aloud-release
```

The release certificate created for this checkout has SHA-256 fingerprint
`C3:EE:40:9C:73:79:3C:57:BD:3F:D1:48:F0:C8:5B:99:D9:01:39:E9:AF:DE:F9:97:81:21:43:87:DE:7D:20:17`.
Keep the keystore that matches this fingerprint for all future updates.

## What you get

| Area | Highlights |
|---|---|
| **Library** | Nested shelves, search, sort, grid/list, "continue listening", per-item progress, share/open-with from other apps |
| **Formats** | EPUB 2/3, PDF (text layer **or OCR** for scans), TXT/MD, HTML, CBZ comics, web pages & novels |
| **Reader** | Sentence highlight + auto-follow, tap any sentence to start there, chapters, themes/typography, PDF page view synced to speech |
| **Voices** | Device TTS · Edge neural (online) · offline neural (Kokoro/Piper via Sherpa-ONNX) · your own PC server — with automatic fallback to the device voice |
| **Natural speech** | Number/date/money/unit/abbreviation normaliser, sentence-aware pauses, gapless playback, audio cache, prefetch, "prepare chapter for offline" |
| **Rules** | One rule engine: skip notes/links, fix pronunciations, pauses, speed changes, stop / next chapter. Templates + live tester |
| **Web novels** | Reader-mode extraction, follows "next chapter" links, saves as **one** book, auto-fetches more as you listen, browser view for JS sites |
| **Translation** | On-device (ML Kit), DeepL, Google, Microsoft, LibreTranslate, OpenAI, Gemini, MyMemory — translated text is read in a matching voice |
| **Background** | Media notification, lock-screen & headset controls, sleep timer (minutes / end of chapter) |
| **Privacy** | Optional passphrase lock with a decoy library; API keys in the Android Keystore |

## Layout

```
packages/aloud_core/   Pure Dart: text pipeline, rules, PDF clean-up, reading model, WAV, catalogs  (no Flutter)
lib/core/              Theme, typed prefs, shared widgets, the one native bridge
lib/data/              Sembast database, repositories, importers (EPUB/PDF/web/comic/text)
lib/features/          library · reader · listen (engines, narrator) · rules · translate · web_import · comics · lock · settings
lib/app/               Composition root: services, providers, router, vault-gated startup
android_overrides/     Manifest, MainActivity.kt (share intents + tar.bz2 extraction), icon
tool/setup_android.dart
docs/                  ARCHITECTURE.md · FEATURE_MAP.md · ROADMAP.md
```

## Honest status

* **Verified:** all 82 pure-Dart core tests pass and `flutter analyze` reports no
  issues.
* **Not yet device-verified:** actual audio, the Edge handshake, Sherpa model
  loading, PDF rendering/OCR, WebView, and media notifications need a device or
  network.
* On this Windows machine, `flutter test` currently stops before executing tests
  because Visual Studio's Windows SDK headers are not installed; install the
  Windows SDK component to run tests on the Windows host.
* Each plugin is isolated behind a small adapter (see ARCHITECTURE.md) so fixes
  stay local.
* `sherpa_onnx` is pinned to the 1.x line (`<2.0.0`): 2.x changed how espeak data is
  handled, and the catalogued models depend on it.
