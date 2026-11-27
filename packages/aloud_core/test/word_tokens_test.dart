import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

void main() {
  group('WordTokenizer', () {
    test('finds words and ignores punctuation', () {
      const t = 'Hello, world! It\'s "fine".';
      final words = WordTokenizer.spans(t).map((s) => s.slice(t)).toList();
      expect(words, ['Hello', 'world', 'It\'s', 'fine']);
    });

    test('spans are exact character ranges', () {
      const t = 'ab cd';
      expect(WordTokenizer.spans(t), [const WordSpan(0, 2), const WordSpan(3, 5)]);
    });

    test('keys ignore case, apostrophes, soft hyphens and ligatures', () {
      expect(WordTokenizer.key('Don’t'), 'dont');
      expect(WordTokenizer.key("DON'T"), 'dont');
      expect(WordTokenizer.key('ﬁnal'), 'final');
      expect(WordTokenizer.key('co\u00ADop'), 'coop');
    });

    test('handles non-latin letters and digits', () {
      expect(WordTokenizer.keys('Привет мир 42'), ['привет', 'мир', '42']);
    });

    test('empty and punctuation-only text has no words', () {
      expect(WordTokenizer.spans(''), isEmpty);
      expect(WordTokenizer.spans('... — !?'), isEmpty);
    });
  });

  group('WordAligner', () {
    test('identical text maps one to one', () {
      expect(WordAligner.spokenToOriginal('one two three', 'one two three'), [0, 1, 2]);
    });

    test('a number spoken as several words maps to the one displayed word', () {
      // "I have 42 apples" -> "I have forty two apples"
      expect(
        WordAligner.spokenToOriginal('I have 42 apples', 'I have forty two apples'),
        [0, 1, 2, 2, 3],
      );
    });

    test('an abbreviation expanded to one word keeps its place', () {
      expect(
        WordAligner.spokenToOriginal('Dr. Smith left', 'Doctor Smith left'),
        [0, 1, 2],
      );
    });

    test('extra spoken words after the last anchor map to the last word', () {
      expect(WordAligner.spokenToOriginal('see you', 'see you soon'), [0, 1, 1]);
    });

    test('result is monotone and in range for scrambled input', () {
      final m = WordAligner.spokenToOriginal('a b c d', 'd x y a');
      for (var i = 1; i < m.length; i++) {
        expect(m[i] >= m[i - 1], isTrue);
      }
      expect(m.every((i) => i >= 0 && i < 4), isTrue);
    });

    test('no original words gives index zero', () {
      expect(WordAligner.spokenToOriginal('...', 'hello there'), [0, 0]);
    });
  });

  group('SpokenWordMap', () {
    SpeechPlan plan(String original, String spoken,
            {List<String> before = const [], bool skip = false}) =>
        SpeechPlan(original: original, spoken: spoken, before: before, skip: skip);

    test('resolves the displayed word under a speech offset', () {
      final map = SpokenWordMap.fromPlan(plan('one two three', 'one two three'));
      expect(map.originalWordAt(0), 0);
      expect(map.originalWordAt(4), 1);
      expect(map.originalWordAt(9), 2);
    });

    test('an offset inside a word belongs to that word', () {
      final map = SpokenWordMap.fromPlan(plan('alpha beta', 'alpha beta'));
      expect(map.originalWordAt(2), 0);
      expect(map.originalWordAt(7), 1);
    });

    test('offsets account for a spoken lead-in phrase', () {
      final p = plan('hello there', 'hello there', before: ['Chapter one']);
      final map = SpokenWordMap.fromPlan(p);
      expect(p.fullSpeech, 'Chapter one hello there');
      expect(map.originalWordAt(3), isNull); // still in the lead-in
      expect(map.originalWordAt('Chapter one '.length), 0);
      expect(map.originalWordAt(p.fullSpeech.indexOf('there')), 1);
    });

    test('works with the real normaliser output', () {
      final e = RuleEngine(const []);
      final p = e.plan('I owe Dr. Smith 42 dollars.');
      final map = SpokenWordMap.fromPlan(p);
      final full = p.fullSpeech;
      // Last spoken word must resolve to the last displayed word ("dollars").
      expect(map.originalWordAt(full.lastIndexOf('dollars')), 5);
      // First spoken word resolves to the first displayed word.
      expect(map.originalWordAt(0), 0);
    });

    test('skipped or empty sentences never resolve a word', () {
      expect(SpokenWordMap.fromPlan(plan('hi', 'hi', skip: true)).originalWordAt(0), isNull);
      expect(SpokenWordMap.fromPlan(plan('...', '')).isEmpty, isTrue);
    });
  });

  group('perCodeUnit', () {
    test('plain text already lines up and is returned as is', () {
      final rects = [1, 2, 3];
      expect(identical(perCodeUnit('abc', rects), rects), isTrue);
    });

    test('a character outside the BMP covers two code units', () {
      // "a😀b": 4 UTF-16 units, 3 code points.
      expect(perCodeUnit('a😀b', [10, 20, 30]), [10, 20, 20, 30]);
    });

    test('several astral characters keep later indices aligned', () {
      const text = '😀😀x';
      final out = perCodeUnit(text, [1, 2, 3])!;
      expect(out.length, text.length);
      expect(out[text.indexOf('x')], 3);
    });

    test('data that matches neither layout is rejected', () {
      expect(perCodeUnit('abc', [1, 2]), isNull);
      expect(perCodeUnit('a😀b', [1, 2]), isNull);
      expect(perCodeUnit('ab', [1, 2, 3, 4]), isNull);
    });

    test('empty text with no data is fine', () {
      expect(perCodeUnit('', <int>[]), isEmpty);
    });
  });
}
