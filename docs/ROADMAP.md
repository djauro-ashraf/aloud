# Roadmap

Deliberately **not** in this first cut, and why.

| Item | Note |
|---|---|
| Multi-select in the library | Single-item actions cover the flows; bulk move/delete is the first UX upgrade |
| CBR / RAR comics | Needs a native RAR reader; CBZ works and the error message says so |
| Picking individual speakers of multi-speaker Piper models | Engine supports `voiceId#spk<N>`; no picker UI yet |
| Bookmarks and notes | Resume position is automatic; named bookmarks not yet |
| Scheduled PC pre-render jobs | Replaced by the unified cache + "prepare chapter for offline"; a *background* bulk job (WorkManager) is the follow-up |
| Bluetooth/Android Auto browse tree | Media session controls work; library browsing in the car does not |
| iOS | Dart side is portable; needs `FilePort`/`NativeBridge` iOS implementations and plist entries |
| Instrumented integration tests | Needs a device/emulator |
| Password-protected PDFs | The importer and viewer open files without a password; the old app prompted for one |
| Reviewing removed headers/footers | `PdfCleanup` already returns what it removed; there is no screen to review or undo it yet |
| Quick "skip this sentence / word" from the reader | The old app could turn a highlighted sentence into a rule in one step; today rules are made in the rules editor |
| Word highlight with neural voices | Not planned. Neural engines synthesise whole sentences, so they cannot say which word is being spoken; they highlight the sentence rather than guess |
| Highlight on pages that need OCR | Scanned pages have no text layer to match; the page is outlined instead of the sentence |
