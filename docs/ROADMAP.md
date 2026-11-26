# Roadmap

Deliberately **not** in this first cut, and why.

| Item | Note |
|---|---|
| Multi-select in the library | Single-item actions cover the flows; bulk move/delete is the first UX upgrade |
| PDF highlight rectangles on the page | The page view follows the spoken page; drawing the sentence box needs `pdfrx` char rects |
| CBR / RAR comics | Needs a native RAR reader; CBZ works and the error message says so |
| Picking individual speakers of multi-speaker Piper models | Engine supports `voiceId#spk<N>`; no picker UI yet |
| Bookmarks and notes | Resume position is automatic; named bookmarks not yet |
| Scheduled PC pre-render jobs | Replaced by the unified cache + "prepare chapter for offline"; a *background* bulk job (WorkManager) is the follow-up |
| Bluetooth/Android Auto browse tree | Media session controls work; library browsing in the car does not |
| iOS | Dart side is portable; needs `FilePort`/`NativeBridge` iOS implementations and plist entries |
| Instrumented integration tests | Needs a device/emulator |
