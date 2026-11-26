import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

void main() {
  group('SectionIndex', () {
    const section = ReaderSection(title: 'T', blocks: [
      ReaderBlock.heading('Chapter 1'),
      ReaderBlock.paragraph('One. Two. Three.'),
      ReaderBlock(kind: BlockKind.image, imageRef: 'a.png'),
      ReaderBlock(kind: BlockKind.sceneBreak, text: '***'),
      ReaderBlock.paragraph('Four.'),
    ]);
    final idx = SectionIndex.build(section);

    test('flattens sentences across blocks, skipping images', () {
      expect(idx.sentences.map((s) => s.text).toList(),
          ['Chapter 1', 'One.', 'Two.', 'Three.', '***', 'Four.']);
      expect(idx.sentences.map((s) => s.block).toList(), [0, 1, 1, 1, 3, 4]);
    });
    test('block → first sentence', () {
      expect(idx.firstSentenceAtOrAfterBlock(1), 1);
      expect(idx.firstSentenceAtOrAfterBlock(2), 4); // image has none → next block
      expect(idx.firstSentenceAtOrAfterBlock(9), isNull);
    });
    test('character offset → sentence', () {
      expect(idx.sentenceAt(1, 0), 1);
      expect(idx.sentenceAt(1, 6), 2);
      expect(idx.sentenceAt(1, 999), 3);
    });
    test('json round trip', () {
      final back = ReaderSection.fromJson(section.toJson());
      expect(back.blocks.length, 5);
      expect(back.blocks[0].kind, BlockKind.heading);
      expect(back.blocks[2].imageRef, 'a.png');
    });
  });

  group('ReadingProgress', () {
    test('fraction and percent', () {
      final f = ReadingProgress.fraction(section: 1, sectionCount: 4, sentence: 4, sentenceCount: 10);
      expect(f, closeTo(0.375, 1e-9));
      expect(ReadingProgress.percent(f, started: true), 37);
      expect(ReadingProgress.percent(0, started: false), 0);
      expect(ReadingProgress.percent(0.999, started: true), 99);
      expect(ReadingProgress.percent(0.5, started: true, completed: true), 100);
    });
  });

  group('BlockClassifier / ChapterSplitter', () {
    test('classification', () {
      expect(BlockClassifier.classify('# Title').kind, BlockKind.heading);
      expect(BlockClassifier.classify('Chapter 12: The Storm').kind, BlockKind.heading);
      expect(BlockClassifier.classify('* * *').kind, BlockKind.sceneBreak);
      expect(BlockClassifier.classify('> quoted').kind, BlockKind.quote);
      expect(BlockClassifier.classify('He walked home.').kind, BlockKind.paragraph);
      expect(BlockClassifier.classify('Chapter one of the long book is quite lengthy and rambling indeed.').kind,
          BlockKind.paragraph);
    });
    test('splits at chapters when enough headings', () {
      final blocks = BlockClassifier.classifyAll([
        'Preface text.',
        'Chapter 1', 'a.', 'b.',
        'Chapter 2', 'c.',
        'Chapter 3', 'd.',
      ]);
      final secs = ChapterSplitter.split(blocks, fallbackTitle: 'Book');
      expect(secs.map((s) => s.title).toList(), ['Book', 'Chapter 1', 'Chapter 2', 'Chapter 3']);
      expect(secs[1].blocks.length, 3);
    });
    test('single section when few headings', () {
      final blocks = BlockClassifier.classifyAll(['Chapter 1', 'a.', 'b.']);
      expect(ChapterSplitter.split(blocks, fallbackTitle: 'Book').length, 1);
    });
    test('very long text is chunked', () {
      final blocks = [for (var i = 0; i < 1300; i++) ReaderBlock.paragraph('p$i.')];
      final secs = ChapterSplitter.split(blocks, fallbackTitle: 'B', maxBlocksPerSection: 600);
      expect(secs.length, 3);
      expect(secs.first.title, 'Part 1');
    });
  });
}
