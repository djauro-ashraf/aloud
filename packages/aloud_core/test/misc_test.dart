import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

void main() {
  group('Batching', () {
    test('chunker respects max length', () {
      final c = TextChunker.chunk('${'word ' * 100}.', 50);
      expect(c.every((p) => p.length <= 50), isTrue);
      expect(c.join(' ').replaceAll(RegExp(r'\s+'), ' ').contains('word'), isTrue);
    });
    test('plan groups by count and chars, assemble restores order', () {
      final texts = ['a', 'b', 'c', 'd', 'e'];
      final plan = BatchPlan.build(texts, maxTexts: 2, maxChars: 100);
      expect(plan.batches.length, 3);
      final results = <String, String>{
        for (final b in plan.batches)
          for (final it in b) BatchPlan.key(it): it.text.toUpperCase(),
      };
      expect(plan.assemble(results), ['A', 'B', 'C', 'D', 'E']);
    });
    test('long text splits and reassembles; missing chunk falls back', () {
      final long = '${'alpha ' * 30}.';
      final plan = BatchPlan.build([long, 'short'], maxTexts: 10, maxChars: 60);
      final items = [for (final b in plan.batches) ...b];
      expect(items.where((i) => i.source == 0).length > 1, isTrue);
      final partial = {BatchPlan.key(items.firstWhere((i) => i.source == 1)): 'SHORT'};
      final out = plan.assemble(partial);
      expect(out[1], 'SHORT');
      expect(out[0].contains('alpha'), isTrue); // fell back to original pieces
    });
  });

  group('ShelfTree', () {
    final tree = ShelfTree(const [
      ShelfNode('a', null, 'Fiction'),
      ShelfNode('b', 'a', 'Sci-Fi'),
      ShelfNode('c', 'b', 'Pulp'),
      ShelfNode('d', null, 'Articles'),
    ]);
    test('children sorted, descendants, path', () {
      expect(tree.childrenOf(null).map((n) => n.name).toList(), ['Articles', 'Fiction']);
      expect(tree.descendantIds('a').toSet(), {'b', 'c'});
      expect(tree.pathTo('c').map((n) => n.name).toList(), ['Fiction', 'Sci-Fi', 'Pulp']);
    });
    test('cycle prevention', () {
      expect(tree.canMove('a', 'c'), isFalse);
      expect(tree.canMove('a', 'a'), isFalse);
      expect(tree.canMove('c', 'd'), isTrue);
      expect(tree.canMove('c', null), isTrue);
    });
    test('rows honour expansion', () {
      expect(tree.rows({}).length, 2);
      expect(tree.rows({'a'}).length, 3);
      expect(tree.rows({'a', 'b'}).map((r) => r.depth).toList(), [0, 0, 1, 2]);
    });
  });

  group('Sorting and names', () {
    test('natural name order', () {
      final keys = ['Chapter 10', 'Chapter 2', 'Chapter 1']
          .map((t) => SortKey(title: t, addedAt: 0))
          .toList()
        ..sort((a, b) => LibrarySorter.compare(LibrarySort.nameAz, a, b));
      expect(keys.map((k) => k.title).toList(), ['Chapter 1', 'Chapter 2', 'Chapter 10']);
    });
    test('recent falls back to added date', () {
      const a = SortKey(title: 'a', addedAt: 5, openedAt: 10);
      const b = SortKey(title: 'b', addedAt: 20);
      expect(LibrarySorter.compare(LibrarySort.recent, a, b) > 0, isTrue); // b (20) before a (10)
    });
    test('sanitize and unique', () {
      expect(Names.sanitize('a/b:c*?'), 'a b c');
      expect(Names.sanitize('...'), 'Untitled');
      expect(Names.unique('Book', ['book', 'Book (2)']), 'Book (3)');
      expect(Names.titleFromFileName('my_great-book.v2.epub'), 'my great book v2');
    });
  });

  group('TTS helpers', () {
    test('ssml', () {
      final s = SsmlBuilder.build(text: 'Tom & "Jerry" <3', voice: 'en-GB-SoniaNeural', ratePercent: -5);
      expect(s.contains("xml:lang='en-GB'"), isTrue);
      expect(s.contains('Tom &amp; &quot;Jerry&quot; &lt;3'), isTrue);
      expect(s.contains("rate='-5%'"), isTrue);
      expect(SsmlBuilder.localeOfVoice('zh-CN-XiaoxiaoNeural'), 'zh-CN');
    });
    test('voice keys', () {
      const v = VoiceInfo(engine: EngineKind.edge, id: 'en-US-JennyNeural', name: 'Jenny', locale: 'en-US');
      expect(v.key, 'edge:en-US-JennyNeural');
      expect(VoiceInfo.parseKey(v.key), (EngineKind.edge, 'en-US-JennyNeural'));
      expect(VoiceInfo.fromJson(v.toJson()), v);
      expect(v.language, 'en');
    });
    test('sherpa catalog', () {
      expect(SherpaCatalog.byId('kokoro_bella')!.speakerId, 1);
      expect(SherpaCatalog.byId('kokoro_bella')!.modelFolder, SherpaCatalog.kokoroFolder);
      expect(SherpaCatalog.byId('piper_amy')!.modelFolder, 'piper_amy');
      expect(SherpaCatalog.all.map((v) => v.id).toSet().length, SherpaCatalog.all.length);
    });
    test('language detection', () {
      expect(Languages.detect('Hello there, this is plain English text.'), isNull);
      expect(Languages.detect('これは日本語の文章です。ありがとうございます'), 'ja');
      expect(Languages.detect('Привет, это русский текст для проверки'), 'ru');
      expect(Languages.nameOf('es-MX'), 'Spanish');
    });
  });
}
