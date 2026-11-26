import '../rules/rule_model.dart';
import '../text/sentence_splitter.dart';

/// Kinds of content a reader can show.
enum BlockKind { heading, paragraph, quote, sceneBreak, image }

/// One displayable unit of a section.
final class ReaderBlock {
  const ReaderBlock({
    required this.kind,
    this.text = '',
    this.imageRef,
    this.context = SentenceContext.none,
    this.page,
  });

  const ReaderBlock.paragraph(String text, {SentenceContext context = SentenceContext.none, int? page})
      : this(kind: BlockKind.paragraph, text: text, context: context, page: page);

  const ReaderBlock.heading(String text, {int? page})
      : this(kind: BlockKind.heading, text: text, context: const SentenceContext(larger: true), page: page);

  final BlockKind kind;
  final String text;

  /// Relative path of an image resource for [BlockKind.image].
  final String? imageRef;
  final SentenceContext context;

  /// Source page number (PDF), 0-based.
  final int? page;

  bool get isSpeakable => kind != BlockKind.image && text.trim().isNotEmpty;

  /// Same block attributed to a source [page].
  ReaderBlock withPage(int? page) =>
      ReaderBlock(kind: kind, text: text, imageRef: imageRef, context: context, page: page);

  /// Same block with different text (e.g. a translation).
  ReaderBlock withText(String text) =>
      ReaderBlock(kind: kind, text: text, imageRef: imageRef, context: context, page: page);

  Map<String, Object?> toJson() => {
        'k': kind.index,
        if (text.isNotEmpty) 't': text,
        if (imageRef != null) 'i': imageRef,
        if (context.italic) 'it': true,
        if (context.bold) 'b': true,
        if (context.larger) 'lg': true,
        if (context.smaller) 'sm': true,
        if (page != null) 'p': page,
      };

  static ReaderBlock fromJson(Map<String, Object?> j) => ReaderBlock(
        kind: BlockKind.values[((j['k'] as num?) ?? 1).toInt().clamp(0, BlockKind.values.length - 1)],
        text: (j['t'] as String?) ?? '',
        imageRef: j['i'] as String?,
        page: (j['p'] as num?)?.toInt(),
        context: SentenceContext(
          italic: (j['it'] as bool?) ?? false,
          bold: (j['b'] as bool?) ?? false,
          larger: (j['lg'] as bool?) ?? false,
          smaller: (j['sm'] as bool?) ?? false,
        ),
      );
}

/// A chapter (or page group / whole text file).
final class ReaderSection {
  const ReaderSection({required this.title, required this.blocks});

  final String title;
  final List<ReaderBlock> blocks;

  Map<String, Object?> toJson() => {
        'title': title,
        'blocks': [for (final b in blocks) b.toJson()],
      };

  static ReaderSection fromJson(Map<String, Object?> j) => ReaderSection(
        title: (j['title'] as String?) ?? '',
        blocks: [
          for (final b in (j['blocks'] as List<Object?>? ?? const []))
            ReaderBlock.fromJson((b! as Map).cast<String, Object?>()),
        ],
      );
}

/// A sentence inside a section, addressable by a flat index.
final class SentenceRef {
  const SentenceRef({
    required this.index,
    required this.block,
    required this.inBlock,
    required this.text,
    required this.start,
    required this.end,
  });

  /// Position in the section's flat sentence list (what playback tracks).
  final int index;

  /// Index into [ReaderSection.blocks].
  final int block;

  /// Index of this sentence within its block.
  final int inBlock;
  final String text;

  /// Character range within the block's text (for highlighting).
  final int start;
  final int end;
}

/// Flat, binary-searchable sentence index over one [ReaderSection].
///
/// Playback, highlighting, resume positions and "tap a sentence to start
/// here" all speak in flat sentence indices; this class translates between
/// that and blocks.
final class SectionIndex {
  SectionIndex._(this.sentences, this._firstInBlock, this._blockCount);

  factory SectionIndex.build(ReaderSection section, {int maxChars = SentenceSplitter.defaultMaxChars}) {
    final out = <SentenceRef>[];
    final first = List<int>.filled(section.blocks.length, -1);
    for (var b = 0; b < section.blocks.length; b++) {
      final block = section.blocks[b];
      if (!block.isSpeakable) continue;
      final spans = switch (block.kind) {
        // Headings and dividers are spoken as a single unit.
        BlockKind.heading || BlockKind.sceneBreak => [
            SentenceSpan(block.text.trim(), 0, block.text.length),
          ],
        _ => SentenceSplitter.split(block.text, maxChars: maxChars),
      };
      for (var s = 0; s < spans.length; s++) {
        if (s == 0) first[b] = out.length;
        out.add(SentenceRef(
          index: out.length,
          block: b,
          inBlock: s,
          text: spans[s].text,
          start: spans[s].start,
          end: spans[s].end,
        ));
      }
    }
    return SectionIndex._(List.unmodifiable(out), first, section.blocks.length);
  }

  final List<SentenceRef> sentences;
  final List<int> _firstInBlock;
  final int _blockCount;

  int get length => sentences.length;
  bool get isEmpty => sentences.isEmpty;

  /// Flat index of the first sentence of [block], or the next block that has
  /// one; `null` if none follows.
  int? firstSentenceAtOrAfterBlock(int block) {
    for (var b = block.clamp(0, _blockCount); b < _blockCount; b++) {
      if (_firstInBlock[b] >= 0) return _firstInBlock[b];
    }
    return null;
  }

  /// All sentences belonging to [block].
  Iterable<SentenceRef> inBlock(int block) sync* {
    final f = block < _blockCount ? _firstInBlock[block] : -1;
    if (f < 0) return;
    for (var i = f; i < sentences.length && sentences[i].block == block; i++) {
      yield sentences[i];
    }
  }

  /// Sentence containing character [offset] of [block]; clamps to the nearest.
  int? sentenceAt(int block, int offset) {
    SentenceRef? best;
    for (final s in inBlock(block)) {
      best = s;
      if (offset < s.end) break;
    }
    return best?.index;
  }

  /// Sentence index for a page (PDF), or the closest following one.
  int? firstSentenceOnPage(ReaderSection section, int page) {
    for (final s in sentences) {
      final p = section.blocks[s.block].page;
      if (p != null && p >= page) return s.index;
    }
    return null;
  }
}

/// Where the user is in a document.
final class ReadingPosition {
  const ReadingPosition({this.section = 0, this.sentence = 0});

  static const start = ReadingPosition();

  final int section;
  final int sentence;

  ReadingPosition copyWith({int? section, int? sentence}) =>
      ReadingPosition(section: section ?? this.section, sentence: sentence ?? this.sentence);

  Map<String, Object?> toJson() => {'s': section, 'n': sentence};

  static ReadingPosition fromJson(Map<String, Object?>? j) => j == null
      ? start
      : ReadingPosition(
          section: ((j['s'] as num?) ?? 0).toInt(),
          sentence: ((j['n'] as num?) ?? 0).toInt(),
        );

  @override
  bool operator ==(Object other) =>
      other is ReadingPosition && other.section == section && other.sentence == sentence;

  @override
  int get hashCode => Object.hash(section, sentence);

  @override
  String toString() => 'ReadingPosition($section:$sentence)';
}

/// Progress arithmetic shared by library cards and readers.
abstract final class ReadingProgress {
  /// 0‥1 through the document, weighting sections equally.
  static double fraction({
    required int section,
    required int sectionCount,
    required int sentence,
    required int sentenceCount,
    bool completed = false,
  }) {
    if (completed) return 1;
    if (sectionCount <= 0) return 0;
    final within = sentenceCount <= 0 ? 0.0 : (sentence + 1) / sentenceCount;
    return ((section + within.clamp(0.0, 1.0)) / sectionCount).clamp(0.0, 1.0);
  }

  /// Whole percent, never 0 once started and never 100 until completed.
  static int percent(double fraction, {required bool started, bool completed = false}) {
    if (completed) return 100;
    if (!started) return 0;
    return (fraction * 100).floor().clamp(1, 99);
  }
}
