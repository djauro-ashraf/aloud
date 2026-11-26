/// A line removed by clean-up, kept so the user can review/undo.
final class RemovedLine {
  const RemovedLine({required this.page, required this.text, required this.reason});

  final int page;
  final String text;
  final String reason;
}

/// A reflowed paragraph with the page it starts on.
final class PdfParagraph {
  const PdfParagraph(this.text, this.page);

  final String text;

  /// 0-based page index where the paragraph begins.
  final int page;
}

final class PdfCleanupConfig {
  const PdfCleanupConfig({
    this.removeRepeatedEdges = true,
    this.removePageNumbers = true,
    this.joinHyphenation = true,
    this.edgeLines = 3,
    this.minRepeatRatio = 0.3,
    this.minPagesForRepeats = 4,
    this.extraRemove = const [],
  });

  final bool removeRepeatedEdges;
  final bool removePageNumbers;
  final bool joinHyphenation;

  /// How many lines at the top and bottom of each page are inspected.
  final int edgeLines;

  /// A line is a header/footer if it repeats on at least this share of pages.
  final double minRepeatRatio;
  final int minPagesForRepeats;

  /// User-defined extra patterns that are always removed.
  final List<RegExp> extraRemove;
}

final class PdfCleanupResult {
  const PdfCleanupResult({required this.paragraphs, required this.removed});

  final List<PdfParagraph> paragraphs;
  final List<RemovedLine> removed;
}

/// Cleans text extracted from PDFs for listening: removes running headers,
/// footers and page numbers, re-joins hyphenated words and rebuilds
/// paragraphs from hard-wrapped lines (including across page breaks).
abstract final class PdfCleanup {
  static final _pageNumber = RegExp(
    r'^\s*(?:page\s*)?\d{1,4}(?:\s*(?:/|of)\s*\d{1,4})?\s*$|^\s*[-–—]\s*\d{1,4}\s*[-–—]\s*$|^\s*[ivxlc]{1,6}\s*$',
    caseSensitive: false,
  );
  static final _terminal = RegExp(r'[.!?…:"”’)\]]\s*$');
  static final _startsNew = RegExp(r'^(?:[A-Z"“‘(\[]|\d+[.)]\s|[•\-–—*]\s)');

  static PdfCleanupResult clean(List<List<String>> pages, {PdfCleanupConfig config = const PdfCleanupConfig()}) {
    final removed = <RemovedLine>[];
    final kept = <List<(String, int)>>[]; // (line, page)

    final repeats = config.removeRepeatedEdges ? _repeatedEdges(pages, config) : const <String>{};

    for (var p = 0; p < pages.length; p++) {
      final lines = [for (final l in pages[p]) l.trimRight()];
      final nonEmptyIdx = [for (var i = 0; i < lines.length; i++) if (lines[i].trim().isNotEmpty) i];
      final edge = <int>{
        ...nonEmptyIdx.take(config.edgeLines),
        ...nonEmptyIdx.reversed.take(config.edgeLines),
      };
      final pageKept = <(String, int)>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) {
          pageKept.add(('', p));
          continue;
        }
        final isEdge = edge.contains(i);
        if (config.extraRemove.any((rx) => rx.hasMatch(line))) {
          removed.add(RemovedLine(page: p, text: line, reason: 'custom pattern'));
          continue;
        }
        if (isEdge && config.removePageNumbers && _pageNumber.hasMatch(line)) {
          removed.add(RemovedLine(page: p, text: line, reason: 'page number'));
          continue;
        }
        if (isEdge && repeats.contains(_signature(line))) {
          removed.add(RemovedLine(page: p, text: line, reason: 'repeated header/footer'));
          continue;
        }
        pageKept.add((line, p));
      }
      kept.add(pageKept);
    }

    return PdfCleanupResult(
      paragraphs: _rebuild(kept, config),
      removed: removed,
    );
  }

  /// Normalised form of a line used to detect repetition: digits collapse so
  /// "Chapter 3 · 12" and "Chapter 3 · 13" match.
  static String _signature(String line) =>
      line.toLowerCase().replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ').trim();

  static Set<String> _repeatedEdges(List<List<String>> pages, PdfCleanupConfig c) {
    if (pages.length < c.minPagesForRepeats) return const {};
    final counts = <String, int>{};
    for (final page in pages) {
      final lines = [for (final l in page) if (l.trim().isNotEmpty) l];
      final edge = {
        ...lines.take(c.edgeLines),
        ...lines.reversed.take(c.edgeLines),
      };
      for (final sig in {for (final l in edge) _signature(l)}) {
        if (sig.length < 2 || sig.length > 120) continue;
        counts[sig] = (counts[sig] ?? 0) + 1;
      }
    }
    final threshold = (pages.length * c.minRepeatRatio).ceil();
    return {
      for (final e in counts.entries)
        if (e.value >= threshold && e.value >= 3) e.key,
    };
  }

  static List<PdfParagraph> _rebuild(List<List<(String, int)>> pages, PdfCleanupConfig config) {
    // Typical full-line width, used to tell a wrapped line from a paragraph end.
    final lengths = <int>[
      for (final p in pages)
        for (final (l, _) in p)
          if (l.trim().length > 20) l.trim().length,
    ]..sort();
    final full = lengths.isEmpty ? 60 : lengths[(lengths.length * 0.9).floor().clamp(0, lengths.length - 1)];

    final out = <PdfParagraph>[];
    final buf = StringBuffer();
    var startPage = 0;
    String prev = '';

    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) out.add(PdfParagraph(t, startPage));
      buf.clear();
      prev = '';
    }

    for (final page in pages) {
      for (final (raw, p) in page) {
        final line = raw.trim();
        if (line.isEmpty) {
          // Blank lines inside a page separate paragraphs.
          flush();
          continue;
        }
        if (buf.isEmpty) {
          startPage = p;
          buf.write(line);
          prev = line;
          continue;
        }
        final prevShort = prev.length < full * 0.7;
        final prevEnds = _terminal.hasMatch(prev);
        final newPara = prevEnds && prevShort && _startsNew.hasMatch(line);
        if (newPara) {
          flush();
          startPage = p;
          buf.write(line);
          prev = line;
          continue;
        }
        if (config.joinHyphenation &&
            prev.endsWith('-') &&
            prev.length > 2 &&
            RegExp(r'\p{L}-$', unicode: true).hasMatch(prev) &&
            RegExp(r'^\p{Ll}', unicode: true).hasMatch(line)) {
          final s = buf.toString();
          buf
            ..clear()
            ..write(s.substring(0, s.length - 1))
            ..write(line);
        } else {
          buf
            ..write(' ')
            ..write(line);
        }
        prev = line;
      }
    }
    flush();
    return out;
  }
}
