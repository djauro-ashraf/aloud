import 'reading_model.dart';

/// Turns plain paragraphs (TXT, web, OCR) into typed blocks and chapters.
abstract final class BlockClassifier {
  static final _chapterHeading = RegExp(
    r'^(?:chapter|chap\.?|ch\.?|part|book|volume|vol\.?|prologue|epilogue|prelude|interlude|act|section|appendix)\b[\s.:\-–—]*[\p{L}\p{N}IVXLCDM]{0,3}.{0,80}$',
    caseSensitive: false,
    unicode: true,
  );
  static final _numberedHeading = RegExp(r'^\d{1,4}\s*[.):\-–]\s+\S.{0,70}$');
  static final _markdownHeading = RegExp(r'^#{1,6}\s+(.+)$');
  static final _sceneBreak = RegExp(r'^[\s*\-_~#=•·◆◇◊—–]{3,}$');
  static final _quote = RegExp(r'^>\s?(.*)$');

  static bool isSceneBreak(String p) {
    final t = p.trim();
    return t.length >= 3 && _sceneBreak.hasMatch(t) && RegExp(r'[*\-_~#=•·◆◇◊—–]').hasMatch(t);
  }

  /// Whether [p] looks like a chapter-level heading.
  static bool isChapterHeading(String p) {
    final t = p.trim();
    if (t.isEmpty || t.length > 100) return false;
    final md = _markdownHeading.firstMatch(t);
    if (md != null) return true;
    if (_chapterHeading.hasMatch(t)) {
      // "Chapter one of the book is long and rambling." is prose, not a title.
      return !(t.endsWith('.') && t.split(' ').length > 8);
    }
    return false;
  }

  static ReaderBlock classify(String paragraph) {
    final t = paragraph.trim();
    final md = _markdownHeading.firstMatch(t);
    if (md != null) return ReaderBlock.heading(md.group(1)!.trim());
    if (isSceneBreak(t)) return ReaderBlock(kind: BlockKind.sceneBreak, text: t);
    final q = _quote.firstMatch(t);
    if (q != null) return ReaderBlock(kind: BlockKind.quote, text: q.group(1)!.trim());
    if (isChapterHeading(t) || (_numberedHeading.hasMatch(t) && t.length <= 60 && !t.endsWith('.'))) {
      return ReaderBlock.heading(t);
    }
    return ReaderBlock.paragraph(t);
  }

  static List<ReaderBlock> classifyAll(Iterable<String> paragraphs) =>
      [for (final p in paragraphs) classify(p)];
}

/// Splits a long list of blocks into chapters at headings.
abstract final class ChapterSplitter {
  /// Only splits when at least [minHeadings] chapter headings exist and the
  /// text is long enough to benefit from navigation.
  static List<ReaderSection> split(
    List<ReaderBlock> blocks, {
    required String fallbackTitle,
    int minHeadings = 3,
    int maxBlocksPerSection = 600,
  }) {
    final headingIdx = <int>[
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == BlockKind.heading && BlockClassifier.isChapterHeading(blocks[i].text)) i,
    ];

    if (headingIdx.length < minHeadings) {
      return _chunk(blocks, fallbackTitle, maxBlocksPerSection);
    }

    final sections = <ReaderSection>[];
    if (headingIdx.first > 0) {
      sections.add(ReaderSection(title: fallbackTitle, blocks: blocks.sublist(0, headingIdx.first)));
    }
    for (var h = 0; h < headingIdx.length; h++) {
      final from = headingIdx[h];
      final to = h + 1 < headingIdx.length ? headingIdx[h + 1] : blocks.length;
      sections.add(ReaderSection(title: blocks[from].text.trim(), blocks: blocks.sublist(from, to)));
    }
    return sections;
  }

  static List<ReaderSection> _chunk(List<ReaderBlock> blocks, String title, int size) {
    if (blocks.length <= size) return [ReaderSection(title: title, blocks: blocks)];
    final out = <ReaderSection>[];
    var part = 1;
    for (var i = 0; i < blocks.length; i += size) {
      final end = (i + size).clamp(0, blocks.length);
      out.add(ReaderSection(title: 'Part $part', blocks: blocks.sublist(i, end)));
      part++;
    }
    return out;
  }
}
