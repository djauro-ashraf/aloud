import '../text/word_tokens.dart';

/// Part of a displayed word as it sits on a PDF page: a character range into
/// that page's text. Characters index the page text one-to-one with the
/// character rectangles the PDF engine reports, so a piece can be turned
/// into geometry directly.
final class PagePiece {
  const PagePiece(this.page, this.start, this.end);

  /// Zero-based page index.
  final int page;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is PagePiece && other.page == page && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(page, start, end);

  @override
  String toString() => 'PagePiece(p$page, $start-$end)';
}

/// Where each word of one reading block lives on the PDF.
///
/// A word is normally one piece; a word that was hyphenated across a line is
/// two. A word that could not be found (OCR noise, a symbol the cleaner
/// dropped) has no pieces — callers simply skip it.
final class BlockPlacement {
  const BlockPlacement._(this.words, this._pieces);

  /// Words of the block text, in order.
  final List<WordSpan> words;
  final List<List<PagePiece>?> _pieces;

  /// Pieces of word [index], or null when it was not found on any page.
  List<PagePiece>? piecesOf(int index) => _pieces[index];

  /// True when at least one word was placed.
  bool get isPlaced => _pieces.any((p) => p != null);

  /// Pieces of every placed word whose text lies inside [start, end) of the
  /// block text — typically one sentence.
  List<PagePiece> piecesInRange(int start, int end) {
    final out = <PagePiece>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.start >= end) break;
      if (w.end <= start) continue;
      final p = _pieces[i];
      if (p != null) out.addAll(p);
    }
    return out;
  }

  /// Index of the word that contains [offset] in the block text, or the next
  /// word after it; null past the last word.
  int? wordAtOrAfter(int offset) {
    for (var i = 0; i < words.length; i++) {
      if (words[i].end > offset) return i;
    }
    return null;
  }

  /// Index of the word that owns character [charIndex] of page [page]'s text;
  /// null when no placed word covers it.
  int? wordAtPageChar(int page, int charIndex) {
    for (var i = 0; i < _pieces.length; i++) {
      final pieces = _pieces[i];
      if (pieces == null) continue;
      for (final p in pieces) {
        if (p.page == page && charIndex >= p.start && charIndex < p.end) return i;
      }
    }
    return null;
  }
}

abstract final class PdfBlockAligner {
  /// Consecutive words that must agree before a match is trusted.
  static const int _anchorWords = 3;

  /// Places the words of [blockText] onto the pages starting at [startPage].
  ///
  /// [blockText] is the cleaned paragraph the reader speaks; [pageText]
  /// returns the raw text of a page (null if unavailable). The cleaner joined
  /// lines, removed hyphenation and dropped headers/footers, so the matcher
  /// is deliberately tolerant: it anchors on a short run of agreeing words,
  /// then follows the block word by word, joining hyphen-split page words and
  /// stepping over stray page words.
  static BlockPlacement align({
    required String blockText,
    required int startPage,
    required int pageCount,
    required String? Function(int page) pageText,
    int maxPages = 4,
  }) {
    final words = WordTokenizer.spans(blockText);
    final keys = [for (final w in words) WordTokenizer.key(w.slice(blockText))];
    final pieces = List<List<PagePiece>?>.filled(words.length, null);

    var t = 0;
    final lastPage = (startPage + maxPages).clamp(0, pageCount);
    for (var page = startPage; page < lastPage && t < keys.length; page++) {
      final text = pageText(page);
      if (text == null) continue;
      final pw = WordTokenizer.spans(text);
      final pk = [for (final w in pw) WordTokenizer.key(w.slice(text))];

      var from = 0;
      while (t < keys.length && from < pk.length) {
        final anchor = _findAnchor(keys, t, pk, from);
        if (anchor < 0) break;
        var p = anchor;
        while (t < keys.length && p < pk.length) {
          final step = _step(keys, t, pk, p);
          if (step == null) break;
          if (step.used > 0) {
            pieces[t] = [
              for (var q = step.start; q < step.start + step.used; q++)
                PagePiece(page, pw[q].start, pw[q].end),
            ];
          }
          t = step.t;
          p = step.p;
        }
        from = p;
      }
    }
    return BlockPlacement._(words, pieces);
  }

  /// Earliest page word index ≥ [from] where the next few block words agree,
  /// allowing a single slip (a stray page word or a missing displayed word).
  static int _findAnchor(List<String> keys, int t, List<String> pk, int from) {
    final goal = (keys.length - t).clamp(1, _anchorWords);
    for (var q = from; q < pk.length; q++) {
      var tt = t;
      var p = q;
      var placed = 0;
      var slack = 1;
      while (placed < goal && tt < keys.length && p < pk.length) {
        final step = _step(keys, tt, pk, p);
        if (step == null) break;
        if (step.tolerated && slack-- == 0) break;
        if (step.used > 0) placed++;
        tt = step.t;
        p = step.p;
      }
      if (placed >= goal || (tt == keys.length && placed >= 2)) return q;
    }
    return -1;
  }

  /// Advances one block word against the page words at [p].
  ///
  /// Matches the word directly, or after stepping over one stray page word,
  /// or — when the next block word matches here instead — treats the current
  /// block word as absent from the page. Returns null when stuck.
  static ({int t, int p, int start, int used, bool tolerated})? _step(
    List<String> keys,
    int t,
    List<String> pk,
    int p,
  ) {
    final direct = _matchAt(keys[t], pk, p);
    if (direct > 0) return (t: t + 1, p: p + direct, start: p, used: direct, tolerated: false);
    if (p + 1 < pk.length) {
      final stray = _matchAt(keys[t], pk, p + 1);
      if (stray > 0) return (t: t + 1, p: p + 1 + stray, start: p + 1, used: stray, tolerated: true);
    }
    if (t + 1 < keys.length && _matchAt(keys[t + 1], pk, p) > 0) {
      return (t: t + 1, p: p, start: p, used: 0, tolerated: true);
    }
    return null;
  }

  /// How many page words (1–3) make up [key] at [p]; 0 if they do not.
  static int _matchAt(String key, List<String> pk, int p) {
    if (pk[p] == key) return 1;
    if (p + 1 < pk.length && pk[p] + pk[p + 1] == key) return 2;
    if (p + 2 < pk.length && pk[p] + pk[p + 1] + pk[p + 2] == key) return 3;
    return 0;
  }
}
