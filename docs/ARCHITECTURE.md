# Architecture

## Principles

1. **Domain logic is plain Dart.** Everything that decides *what to say and how*
   lives in `packages/aloud_core` with zero Flutter/IO imports, so it is fast to
   test and cannot accidentally depend on the UI.
2. **Plugins sit behind ports.** Every third-party API is used in exactly one
   adapter file. When a plugin changes (they do), one file changes.
3. **One concept, one implementation.** The old app had two rule systems, four
   audio caches and per-engine players. Here: one rule model, one audio cache,
   one narrator.
4. **No code generation.** No `build_runner`, no `freezed`, no Drift schema. A fresh
   clone builds with `flutter pub get`. State is plain Riverpod `Notifier`s;
   persistence is Sembast (pure-Dart document store).
5. **Feature-first folders**, layered inside each feature only where it earns its keep.

## Dependency direction

```
features/*  ──►  data/*  ──►  aloud_core
    │              ▲
    └──► core/* ───┘            app/ wires everything (composition root)
```

`aloud_core` never imports anything above it. `features/listen/narrator.dart`
and the engine contracts import only `aloud_core`, which is why they are
unit-tested with fake backends.

## The listening pipeline

```
 ReaderSection ─► SectionIndex (flat sentence ids) ─► Narrator ─► SpeechBackend ─► audio
                                                       │  ▲            │
                              RuleEngine.plan() ◄──────┘  │            ├─ SystemSpeechBackend   (flutter_tts)
                      (rules → TextNormalizer → pauses)   │            └─ ClipSpeechBackend     (just_audio ×2)
                                                  events  │                   ├─ EdgeSynthesizer   (WebSocket)
                                       ReadingController ◄┘                   ├─ SherpaSynthesizer (isolate)
                           (position, auto-advance, sleep,                    └─ PcSynthesizer     (HTTP)
                            translation, media session)                 wrapped by FallbackSpeechBackend
```

* **Display text never changes; only speech does.** Rules and normalisation
  produce a `SpeechPlan` per sentence (spoken text, pauses, speed delta, flow).
* **Cache key = voice + rules fingerprint + spoken text.** Speed is applied at
  playback, so changing speed never invalidates audio; changing a rule only
  invalidates sentences it touches. One cache serves every engine and every book.
* **Gapless playback:** two `AudioPlayer`s alternate; the next clip is already loaded
  while the current one speaks.
* **Prefetch** synthesises upcoming sentences (default 3) while the current one
  plays; `renderAhead` fills the same cache for a whole chapter ("offline").
* **Failure policy:** a failing engine falls back to the device voice, is skipped
  for 60 s after repeated failures, and recovers automatically.

## State

| Provider | Owns |
|---|---|
| `servicesProvider` | the opened vault (DB, repositories, importer, cache) — overridden at the root |
| `settingsProvider` | one map, read via typed `Pref<T>` keys (`ref.pref(Prefs.speed)`) |
| `docsProvider` / `shelvesProvider` / `rulesListProvider` | live Sembast queries |
| `readingProvider` | the open document + narrator; **app-scoped** so playback survives leaving the reader and the library shows a mini-player |

## Storage

* Metadata: Sembast (`docs`, `shelves`, `rules`, `settings`, `kv`).
* Content: one JSON file per chapter (`library/<id>/sections/N.json`) — only the
  chapter being read is ever in memory.
* Secrets: Android Keystore via `flutter_secure_storage`.
* Vaults: each vault (`main`, `guest`) is a separate folder + database; locking
  disposes the provider scope entirely.

## Native code

One Kotlin file (`MainActivity.kt`), one channel (`dev.aloud/native`), documented in
`lib/core/platform/native_bridge.dart`: receive share/open-with intents (copying
`content://` streams into the cache) and extract `.tar.bz2` voice models on a
background thread.

## Testing

| Layer | How |
|---|---|
| `aloud_core` | `dart test` — sentence splitter, normaliser, rules, PDF clean-up, WAV, batching… |
| Importers | real EPUB built in memory; real HTML fixtures |
| Narrator | fake `SpeechBackend` (pause/resume, jumps, rules, errors, fallback) |
| Widgets | smoke tests for shared widgets and the lock screen |
