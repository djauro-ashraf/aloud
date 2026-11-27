import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

// PDF space: y grows upward, so top > bottom.
PageBox box(double l, double b, double r, double t) => PageBox(l, t, r, b);

void main() {
  group('PageBox', () {
    test('empty boxes carry no position', () {
      expect(box(1, 1, 1, 5).isEmpty, isTrue);
      expect(box(1, 1, 5, 1).isEmpty, isTrue);
      expect(box(1, 1, 5, 5).isEmpty, isFalse);
    });

    test('union covers both boxes', () {
      final u = box(0, 0, 2, 2).union(box(5, 1, 6, 4));
      expect(u, box(0, 0, 6, 4));
    });

    test('unionOf skips empty boxes and returns null when nothing remains', () {
      expect(PageBox.unionOf([box(0, 0, 0, 0), box(1, 1, 3, 3)]), box(1, 1, 3, 3));
      expect(PageBox.unionOf([box(0, 0, 0, 0)]), isNull);
      expect(PageBox.unionOf(const []), isNull);
    });

    test('distance is zero inside and euclidean outside', () {
      final b = box(0, 0, 10, 10);
      expect(b.distanceTo(5, 5), 0);
      expect(b.distanceTo(13, 5), 3);
      expect(b.distanceTo(13, 14), 5);
    });
  });

  group('TextLines.group', () {
    test('words on one baseline merge into one line box', () {
      final lines = TextLines.group([box(0, 0, 10, 10), box(12, 0, 30, 10), box(32, 1, 40, 9)]);
      expect(lines, [box(0, 0, 40, 10)]);
    });

    test('a new line starts when the vertical overlap is too small', () {
      final lines = TextLines.group([box(0, 20, 10, 30), box(12, 20, 20, 30), box(0, 5, 15, 15)]);
      expect(lines.length, 2);
      expect(lines.first, box(0, 20, 20, 30));
      expect(lines.last, box(0, 5, 15, 15));
    });

    test('a tall glyph on the same line does not split it', () {
      final lines = TextLines.group([box(0, 0, 10, 10), box(12, -2, 20, 14)]);
      expect(lines.length, 1);
    });

    test('empty words are ignored', () {
      expect(TextLines.group([box(0, 0, 0, 0)]), isEmpty);
    });
  });

  group('TextLines.nearest', () {
    final boxes = [box(0, 0, 10, 10), box(20, 0, 30, 10), box(40, 0, 50, 10)];

    test('picks the closest box within range', () {
      expect(TextLines.nearest(boxes, 24, 5, maxDistance: 20), 1);
      expect(TextLines.nearest(boxes, 5, 5, maxDistance: 20), 0);
    });

    test('returns null when nothing is close enough', () {
      expect(TextLines.nearest(boxes, 200, 200, maxDistance: 20), isNull);
    });
  });

  group('PdfSectionMap', () {
    // Chapters cut at uneven page counts, as heading-based splitting does.
    final sections = <List<int?>>[
      [0, 1, 2],
      [3, 4, 5, 6, 7],
      [8],
      [9, 10, 11, 12],
    ];
    ReaderSection section(List<int?> pages) => ReaderSection(
          title: '',
          blocks: [for (final p in pages) ReaderBlock.paragraph('text', page: p)],
        );

    PdfSectionMap map({List<List<int?>>? data, List<int>? log}) => PdfSectionMap(
          count: (data ?? sections).length,
          read: (i) async {
            log?.add(i);
            return section((data ?? sections)[i]);
          },
        );

    test('finds the section for every page, regardless of chapter sizes', () async {
      final m = map();
      for (var s = 0; s < sections.length; s++) {
        for (final p in sections[s]) {
          expect(await m.sectionOfPage(p!), s);
        }
      }
    });

    test('a page with no readable text belongs to no section', () async {
      final m = map(data: [
        [0, 1],
        [4, 5],
      ]);
      expect(await m.sectionOfPage(2), isNull);
      expect(await m.sectionOfPage(99), isNull);
    });

    test('sections without paged text are skipped over', () async {
      final m = map(data: [
        [0, 1],
        [null],
        [4, 5],
      ]);
      expect(await m.sectionOfPage(5), 2);
      expect(await m.sectionOfPage(1), 0);
    });

    test('reads each section at most once', () async {
      final log = <int>[];
      final m = map(log: log);
      await m.sectionOfPage(12);
      await m.sectionOfPage(12);
      await m.sectionOfPage(0);
      expect(log.length, log.toSet().length);
    });

    test('a single-section document works', () async {
      final m = map(data: [
        [0, 1, 2]
      ]);
      expect(await m.sectionOfPage(1), 0);
    });
  });
}
