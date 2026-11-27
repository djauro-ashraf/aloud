import 'package:aloud_core/aloud_core.dart';
import 'package:pdfrx/pdfrx.dart';

/// What to paint on the pages: rectangles in PDF page space, keyed by the
/// zero-based page index they belong to.
final class PdfHighlight {
  const PdfHighlight({this.lines = const {}, this.words = const {}, this.markedPage});

  /// One box per text line of the sentence being read.
  final Map<int, List<PageBox>> lines;

  /// The word being spoken, when the voice reports one.
  final Map<int, List<PageBox>> words;

  /// A page to mark as a whole because the sentence cannot be located on it
  /// (a scanned page has no text layer to match against).
  final int? markedPage;

  static const none = PdfHighlight();

  bool get isEmpty => lines.isEmpty && words.isEmpty && markedPage == null;
}

/// Where one sentence sits on the PDF, ready to be painted.
final class SentenceGeometry {
  const SentenceGeometry._({
    required this.lines,
    required this._placement,
    required this._firstWord,
    required this._texts,
  });

  /// One box per text line, by page.
  final Map<int, List<PageBox>> lines;

  final BlockPlacement _placement;
  final int _firstWord;
  final Map<int, PdfPageRawText> _texts;

  /// Page and box of the first line, where the view should scroll to.
  (int page, PageBox box)? get firstLine {
    if (lines.isEmpty) return null;
    final page = lines.keys.reduce((a, b) => a < b ? a : b);
    return (page, lines[page]!.first);
  }

  /// Boxes of the [word]-th word of the sentence (usually one; two when the
  /// word was hyphenated across lines). Empty if it was not found on the page.
  Map<int, List<PageBox>> wordBoxes(int word) {
    final index = _firstWord + word;
    if (index < 0 || index >= _placement.words.length) return const {};
    final out = <int, List<PageBox>>{};
    for (final piece in _placement.piecesOf(index) ?? const <PagePiece>[]) {
      final text = _texts[piece.page];
      final box = text == null ? null : PdfGeometry.boxOf(text, piece);
      if (box != null) out.putIfAbsent(piece.page, () => []).add(box);
    }
    return out;
  }
}

/// Turns the reader's sentences into positions on the original PDF pages.
///
/// The reader speaks cleaned text; this finds where that text sits in the
/// PDF's own text layer ([PdfBlockAligner]) and converts it into rectangles
/// from the engine's per-character bounds. It opens its own handle on the file
/// so it works independently of the viewer widget.
final class PdfGeometry {
  PdfGeometry(this._path);

  final String _path;

  /// Blocks are looked for on this many pages from where they start.
  static const _maxSpan = 4;
  static const _maxCachedPages = 24;

  Future<PdfDocument>? _document;
  final _texts = <int, PdfPageRawText?>{};
  final _loading = <int, Future<PdfPageRawText?>>{};

  /// Placements per loaded section, keyed by the section object itself so a
  /// reloaded chapter starts clean and old ones are collected with it.
  final _placements = Expando<Map<int, BlockPlacement?>>('placements');

  Future<PdfDocument> _open() => _document ??= PdfDocument.openFile(_path);

  Future<int> pageCount() async => (await _open()).pages.length;

  /// Page text, or null when the page has none we can trust.
  Future<PdfPageRawText?> _text(int page) {
    if (_texts.containsKey(page)) return Future.value(_texts[page]);
    return _loading[page] ??= _load(page).whenComplete(() => _loading.remove(page));
  }

  Future<PdfPageRawText?> _load(int page) async {
    final doc = await _open();
    if (page < 0 || page >= doc.pages.length) return null;
    final raw = await doc.pages[page].loadText();
    final usable = raw == null ? null : _perCodeUnit(raw);
    if (_texts.length >= _maxCachedPages) _texts.remove(_texts.keys.first);
    _texts[page] = usable;
    return usable;
  }

  /// The engine reports one box per code point; [PagePiece]s index code
  /// units. Null when the boxes cannot be lined up with the text at all.
  static PdfPageRawText? _perCodeUnit(PdfPageRawText raw) {
    final rects = perCodeUnit(raw.fullText, raw.charRects);
    return rects == null ? null : PdfPageRawText(raw.fullText, rects);
  }

  /// Where the words of [block] of [section] sit on the pages, or null if the
  /// block has no page or none of it can be found.
  Future<BlockPlacement?> placementOf(ReaderSection section, int block) async {
    final cache = _placements[section] ??= <int, BlockPlacement?>{};
    if (cache.containsKey(block)) return cache[block];

    final b = section.blocks[block];
    final page = b.page;
    BlockPlacement? placement;
    if (page != null && b.text.isNotEmpty) {
      final pageCount = await this.pageCount();
      for (var span = 1; span <= _maxSpan && page + span - 1 < pageCount; span++) {
        // The block starts on a page without text: nothing to match.
        if (await _text(page + span - 1) == null && span == 1) break;
        placement = PdfBlockAligner.align(
          blockText: b.text,
          startPage: page,
          pageCount: pageCount,
          pageText: (p) => _texts[p]?.fullText,
          maxPages: span,
        );
        final words = placement.words;
        if (words.isEmpty || placement.piecesOf(words.length - 1) != null) break;
      }
      if (placement != null && !placement.isPlaced) placement = null;
    }
    cache[block] = placement;
    return placement;
  }

  /// Geometry of one sentence, or null when it cannot be located.
  Future<SentenceGeometry?> sentence(ReaderSection section, SentenceRef s) async {
    final placement = await placementOf(section, s.block);
    if (placement == null) return null;

    final byPage = <int, List<PageBox>>{};
    for (final piece in placement.piecesInRange(s.start, s.end)) {
      final text = _texts[piece.page];
      final box = text == null ? null : boxOf(text, piece);
      if (box != null) byPage.putIfAbsent(piece.page, () => []).add(box);
    }
    if (byPage.isEmpty) return null;
    return SentenceGeometry._(
      lines: {for (final e in byPage.entries) e.key: TextLines.group(e.value)},
      placement: placement,
      firstWord: placement.wordAtOrAfter(s.start) ?? 0,
      texts: {for (final page in byPage.keys) page: _texts[page]!},
    );
  }

  /// The sentence whose word is nearest to ([x], [y]) on zero-based [page],
  /// within [maxDistance] PDF points; null if there is none.
  Future<int?> sentenceAt(
    ReaderSection section,
    SectionIndex index,
    int page,
    double x,
    double y, {
    required double maxDistance,
  }) async {
    final text = await _text(page);
    if (text == null) return null;

    int? bestBlock;
    var bestOffset = 0;
    var best = maxDistance;
    for (var b = 0; b < section.blocks.length; b++) {
      final start = section.blocks[b].page;
      // A block can only reach this page if it starts a few pages before it.
      if (start == null || start > page || start < page - _maxSpan + 1) continue;
      final placement = await placementOf(section, b);
      if (placement == null) continue;
      for (var w = 0; w < placement.words.length; w++) {
        for (final piece in placement.piecesOf(w) ?? const <PagePiece>[]) {
          if (piece.page != page) continue;
          final box = boxOf(text, piece);
          if (box == null) continue;
          final d = box.distanceTo(x, y);
          if (d <= best) {
            best = d;
            bestBlock = b;
            bestOffset = placement.words[w].start;
          }
        }
      }
    }
    return bestBlock == null ? null : index.sentenceAt(bestBlock, bestOffset);
  }

  /// Bounding box of the characters of [piece] on its page.
  static PageBox? boxOf(PdfPageRawText text, PagePiece piece) => PageBox.unionOf(
        text.charRects
            .getRange(piece.start, piece.end)
            .map((r) => PageBox(r.left, r.top, r.right, r.bottom)),
      );

  Future<void> dispose() async {
    final doc = _document;
    _document = null;
    if (doc != null) await (await doc).dispose();
  }
}
