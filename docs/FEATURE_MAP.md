# From AStory to Aloud: goals, not ports

Each row starts from what the old feature was *for*, then says how Aloud achieves
that outcome. Where the new approach is deliberately different, the reason is given.

| AStory (old) | End goal | Aloud (new) |
|---|---|---|
| `FileBrowserFragment`, `FolderManager`, `ShelfTree` (path-string folders) | Organise a growing pile of books | Shelves are records with a `parentId` (rename/move can't corrupt paths), cycle-safe moves, search, sort, grid/list, *Continue listening* card |
| `MainActivity` (3.2k lines, dialogs built in code) | — | Small widgets per feature, one composition root |
| `TextExtractor`, `EpubV2*`, `HtmlExtractor` | Get clean text out of any format | One reader model (`ReaderSection → ReaderBlock`) fed by `EpubImporter`, `TextImporter`, `PdfImporter`, `ArticleExtractor`. Same reader, same TTS for every format |
| `PdfExtractor`, `PdfCleanupDetector`, docs/pdf-subsystem | PDFs that read like books, not like scans | `PdfCleanup` (headers/footers, page numbers, hyphenation, paragraph rebuild — pure, tested) + automatic OCR for scans; page view follows the speaker |
| CBZ/CBR reader | Read comics | `ComicReaderView`: swipe/tap/zoom/RTL, progress saved. CBR needs a native RAR reader (roadmap) |
| `WebExtractor`, `WebBatchChapterSaver`, `WebTtsPolisher`, WebView reader | Listen to web novels | `ArticleExtractor` (known containers → `<article>` → text density) + `WebTextPolisher`. Chapters are saved as **one book**; more are fetched as you listen; in-app browser for JS/captcha sites |
| `TTSEngine` (Android TTS) | Always-available voice | `SystemSpeechBackend` — also the automatic fallback |
| `EdgeTTSEngine` | Natural online voices | `EdgeTtsClient` (same handshake constants; strips frame headers instead of writing them into the MP3; clock recalibration kept) |
| `SherpaController`, `SherpaModelManager`, `SherpaVoiceCatalog` | Natural offline voices | `SherpaWorker` isolate + `SherpaModelManager` (atomic install, same catalog) |
| `SherpaPcClient`, `SherpaPcLivePlayer`, PC pre-render jobs/scheduler/recovery | Heavy voices on a PC, smooth on the phone | `PcServerClient` (same protocol: health, voices, preview, UDP discovery) + the unified cache. Job scheduler replaced by *prepare chapter for offline* |
| `SherpaPcmCache`, `SherpaCacheService`, `DocumentCache`… (4+ caches) | Instant, gapless playback; offline replay | **One** content-addressed `AudioCache` with LRU trimming, shared by all engines |
| `TTSService`, `NovelTTSOrchestrator` | Background listening, auto-next | `Narrator` (loop) + `ReadingController` (position, auto-advance, next book) + `AloudAudioHandler` (media session) |
| `RuleEngine` + `SherpaRules` + `TtsSpeechRules` (overlapping) | Skip junk, fix pronunciation, shape delivery | **One** `SpeechRule` model (6 trigger types × 9 actions), evaluated by one engine, with templates and a live tester |
| `TextNormaliser`, `SSMLBuilder` | Make text speakable | `TextNormalizer` (numbers, years, money, time, dates, units, %, ordinals, roman chapters, abbreviations, acronyms, markup) — tested; speed moved from SSML to the player so cache entries are reusable |
| `TranslationEngine` (7 providers) | Read in another language | `TranslationProvider` interface, 8 implementations, per-chapter disk cache, voice auto-switches to the target language |
| `ProgressStore` | Resume exactly where I stopped | `Doc.position` (section + sentence), saved debounced and on pause; maps through blocks when translation is toggled |
| Sleep timer, auto-next file | Fall asleep / keep going | Timer (minutes or end of chapter), auto-next chapter and next book on the shelf |
| `VaultManager` + hard-coded keyword in source | Keep a private library private | User-set passphrase (salted, 100 000-round digest), optional decoy library, separate data folders, provider scope disposed on lock. *No secret in source* |
| API keys in preferences | — | Android Keystore (`flutter_secure_storage`) |
| Share/Open-with intents in `MainActivity` | Send things *to* the app | One Kotlin channel; URLs open the web importer, files are imported, text becomes a book |
| `PdfPageView`, `PdfPageAdapter`, sentence/word highlight, double-tap to read | See the sentence (and word) on the real page; start from any sentence | `PdfReaderView`: highlight drawn from the PDF's own text positions (`PdfBlockAligner` → `PdfGeometry`), double-tap resolves the nearest word to its sentence in **any chapter** (`PdfSectionMap`), follows the speaker unless you are scrolling, page-number quick-scroll handle |
| Word highlight (`onRangeStart`) | Know which word is being spoken | Exact with the device voice (`SpokenOffsetSource`, mapped back to displayed words by `SpokenWordMap`). Neural engines have no word position and highlight the sentence — the Highlight sheet says so |
| Highlight colour / thickness / padding / offset, highlight mode | Make the highlight match the PDF | `Highlight & tapping` sheet: Both / Sentence / Word / Off, PDF colour and geometry sliders |
| Double-tap to seek (text reader) | Start from a sentence without accidents | First tap marks the sentence, second reads from it; single-tap and off are options |
| `WebViewFragment` quick-save FAB, "Next" snackbar | Save chapter after chapter without leaving the page | `BrowserPage`: **Save** reads the page as shown and adds it to one book, **Next** follows the site's next-chapter link, repeat. Also reachable from a web book (`Browse & add chapters`) |
