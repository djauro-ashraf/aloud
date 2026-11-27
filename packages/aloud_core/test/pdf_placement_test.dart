import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

BlockPlacement place(String block, List<String> pages, {int start = 0}) =>
    PdfBlockAligner.align(
      blockText: block,
      startPage: start,
      pageCount: pages.length,
      pageText: (p) => p < pages.length ? pages[p] : null,
    );

String slice(List<String> pages, PagePiece p) => pages[p.page].substring(p.start, p.end);

void main() {
  group('PdfBlockAligner', () {
    test('places a block that matches the page text exactly', () {
      final pages = ['The quick brown fox jumps over the lazy dog.'];
      final r = place('The quick brown fox jumps over the lazy dog.', pages);
      expect(r.isPlaced, isTrue);
      expect(r.words.length, 9);
      for (var i = 0; i < 9; i++) {
        expect(r.piecesOf(i), isNotNull);
      }
      expect(slice(pages, r.piecesOf(1)!.single), 'quick');
    });

    test('skips a header that cleaning removed', () {
      final pages = ['My Book Title 12\nIt was a dark night. Rain fell.'];
      final r = place('It was a dark night. Rain fell.', pages);
      expect(slice(pages, r.piecesOf(0)!.single), 'It');
      expect(slice(pages, r.piecesOf(r.words.length - 1)!.single), 'fell');
    });

    test('rejoins a word hyphenated across lines', () {
      final pages = ['She felt an inform-\nation overload coming on.'];
      final r = place('She felt an information overload coming on.', pages);
      final info = r.piecesOf(3)!;
      expect(info.length, 2);
      expect(info.map((p) => slice(pages, p)).join(), 'information');
      expect(slice(pages, r.piecesOf(4)!.single), 'overload');
    });

    test('follows a paragraph across a page break and skips the running head', () {
      final pages = [
        'First line of the story goes here and then the para-\ngraph continues',
        'CHAPTER ONE   2\nonto the next page where it finally ends.',
      ];
      final r = place(
        'First line of the story goes here and then the paragraph continues onto the next page where it finally ends.',
        pages,
      );
      final last = r.piecesOf(r.words.length - 1)!.single;
      expect(last.page, 1);
      expect(slice(pages, last), 'ends');
      final first = r.piecesOf(0)!.single;
      expect(first.page, 0);
      expect(r.piecesOf(10), isNotNull); // "continues" on page 0
    });

    test('steps over a stray page word inside a line', () {
      final pages = ['He paused[1] and listened to the wind.'];
      final r = place('He paused and listened to the wind.', pages);
      expect(r.piecesOf(2), isNotNull);
      expect(slice(pages, r.piecesOf(2)!.single), 'and');
    });

    test('leaves a word unplaced when the page lacks it', () {
      final pages = ['one two four five six'];
      final r = place('one two three four five six', pages);
      expect(r.piecesOf(2), isNull);
      expect(slice(pages, r.piecesOf(3)!.single), 'four');
    });

    test('a block that is not on the pages stays unplaced', () {
      final pages = ['completely different words appear here today'];
      final r = place('nothing like that at all anywhere', pages);
      expect(r.isPlaced, isFalse);
    });

    test('matching ignores case, ligatures and curly apostrophes', () {
      final pages = ['The ﬁnal answer isn’t known.'];
      final r = place("the final answer isn't known.", pages);
      expect(r.piecesOf(1), isNotNull);
      expect(r.piecesOf(3), isNotNull);
    });

    test('never looks past maxPages', () {
      final pages = ['x y z', 'x y z', 'x y z', 'x y z', 'alpha beta gamma delta'];
      final r = place('alpha beta gamma delta', pages);
      expect(r.isPlaced, isFalse);
    });

    test('piecesInRange returns just the words of one sentence', () {
      const block = 'Alpha beta. Gamma delta.';
      final pages = [block];
      final r = place(block, pages);
      final second = r.piecesInRange(12, 24);
      expect(second.map((p) => slice(pages, p)).toList(), ['Gamma', 'delta']);
    });

    test('wordAtPageChar finds the word under a character', () {
      const block = 'Alpha beta gamma';
      final pages = [block];
      final r = place(block, pages);
      expect(r.wordAtPageChar(0, 7), 1);
      expect(r.wordAtPageChar(0, 5), isNull); // the space
      expect(r.wordAtPageChar(1, 7), isNull); // another page
    });

    test('wordAtOrAfter snaps an offset to a word', () {
      final r = place('Alpha beta gamma', ['Alpha beta gamma']);
      expect(r.wordAtOrAfter(0), 0);
      expect(r.wordAtOrAfter(5), 1);
      expect(r.wordAtOrAfter(100), isNull);
    });
  });

  group('PdfCleanup -> PdfBlockAligner', () {
    test('every cleaned paragraph of a realistic book maps back onto its pages', () {
      final lines = <List<String>>[];
      const body = [
        'The harbour was quiet that morning, and the fishermen had not yet',
        'returned. Maria stood at the end of the pier, watching the hori-',
        'zon for any sign of the boats. She had waited many years for this',
        'day.',
        'When the first sail appeared she did not move. Her father had always',
        'said that patience was the only honest prayer a sailor\'s daughter',
        'could make.',
      ];
      for (var p = 0; p < 6; p++) {
        lines.add([
          'THE LONG VOYAGE',
          ...body.map((l) => l),
          '${p + 1}',
        ]);
      }
      final result = PdfCleanup.clean(lines);
      expect(result.paragraphs.isNotEmpty, isTrue);
      final rawPages = [for (final l in lines) l.join('\n')];
      for (final para in result.paragraphs) {
        final r = PdfBlockAligner.align(
          blockText: para.text,
          startPage: para.page,
          pageCount: rawPages.length,
          pageText: (p) => p < rawPages.length ? rawPages[p] : null,
        );
        final placed = [for (var i = 0; i < r.words.length; i++) if (r.piecesOf(i) != null) i].length;
        expect(placed / r.words.length, greaterThan(0.95));
      }
    });
  });
}
