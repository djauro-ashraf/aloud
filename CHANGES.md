# Changes: PDF highlighting, word highlight, tap-to-read, web quick-save

Restores the parts of the old app that mattered most for daily use, without
reintroducing the old code's complexity. See `docs/FEATURE_MAP.md` for the
old → new mapping and `docs/ARCHITECTURE.md` ("Highlighting") for the design.

## What you get

**PDF page view** (`lib/features/reader/pdf_reader_view.dart`)
- Sentence highlight drawn on the real page, one box per line.
- Word outline with the device voice. Neural voices mark the sentence only.
- Double-tap a word → reads from its sentence, in any chapter (the old
  `page ~/ 25` guess was wrong for PDFs split by headings).
- Follows the speaker; pauses for 4 s after you scroll or tap.
- Page-number quick-scroll handle; "Read from this page" button.
- Scanned pages (no text layer): the page is outlined instead of the sentence.

**Text view**: first tap marks a sentence, second tap reads from it (the old
double-tap behaviour). Word highlight with the device voice.

**Highlight & tapping sheet** (Appearance sheet, or the ✎ button in PDF view):
Both / Sentence / Word / Off, word style, tap mode (double / single / off), PDF
colour, outline thickness, padding, vertical offset. It states plainly what the
current voice can highlight.

**Web quick-save** (`lib/features/web_import/browser_page.dart`)
Browse & save → **Save** → **Next** → **Save** …, without leaving the page.
Every Save reads the live page and adds it as the next chapter of *one* book.
Also: "Browse & add chapters" in a web book's menu, rename book, start a new
book, optional auto-open of the next chapter, duplicate-page protection.

## Word highlight: why only the device voice
Neural engines synthesise a whole sentence into one audio file; they cannot say
which word is being spoken. Rather than guess, they highlight the sentence.

## Verified here
- `aloud_core`: 131 tests pass, 0 lint issues (49 new tests).
- App tests that need no device: narrator 15/15 (3 new, covering word events
  and the "neural = no word events" guarantee), highlight 9/9, saved URLs 4/4.
- `dart analyze` with the project's own lint rules against the real Flutter,
  `material_ui`, Riverpod, pdfrx, go_router and webview_flutter sources:
  0 issues in every changed file, and 0 new issues anywhere else in the project.

## NOT verified here (no Flutter toolchain, no device)
The app was not built or run. Please run:

    flutter pub get && flutter analyze && flutter test
    (cd packages/aloud_core && dart test)

## Device checklist
1. PDF with the device voice: sentence + word marked; word moves as it speaks.
2. Same PDF with a neural voice: sentence only; the Highlight sheet says why.
3. Double-tap a word on another chapter's page → reading starts there.
4. Scroll while listening → view stays put ~4 s, then follows again.
5. A PDF with emoji / a scanned PDF: no crash; scanned page gets an outline.
6. Highlight sliders move the highlight live; "Reset PDF highlight" restores it.
7. Browser: Save, Next, Save → one book with 2 chapters; Save twice on one
   page → "Already saved".
8. If highlights sit slightly high/low on some PDFs, use "Move highlight".

## Known gaps (also in docs/ROADMAP.md)
Password-protected PDFs, reviewing removed headers/footers, one-step "skip this
sentence" rule from the reader. These regressed from the old app and are not
part of this change.
