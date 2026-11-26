import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

String n(String s) => TextNormalizer.normalize(s);

void main() {
  group('NumberWords', () {
    test('cardinal', () {
      expect(NumberWords.cardinal(0), 'zero');
      expect(NumberWords.cardinal(21), 'twenty-one');
      expect(NumberWords.cardinal(1234), 'one thousand two hundred thirty-four');
      expect(NumberWords.cardinal(1000000), 'one million');
      expect(NumberWords.cardinal(-5), 'minus five');
    });
    test('ordinal', () {
      expect(NumberWords.ordinal(1), 'first');
      expect(NumberWords.ordinal(2), 'second');
      expect(NumberWords.ordinal(12), 'twelfth');
      expect(NumberWords.ordinal(21), 'twenty-first');
      expect(NumberWords.ordinal(20), 'twentieth');
      expect(NumberWords.ordinal(100), 'one hundredth');
    });
    test('year', () {
      expect(NumberWords.year(1999), 'nineteen ninety-nine');
      expect(NumberWords.year(2005), 'two thousand five');
      expect(NumberWords.year(1905), 'nineteen oh five');
      expect(NumberWords.year(1900), 'nineteen hundred');
    });
  });

  group('SentenceSplitter', () {
    test('basic', () {
      expect(SentenceSplitter.sentences('Hello world. How are you? Fine!'),
          ['Hello world.', 'How are you?', 'Fine!']);
    });
    test('abbreviations and initials do not split', () {
      expect(SentenceSplitter.sentences('Mr. Smith met Dr. Jones. They talked.'),
          ['Mr. Smith met Dr. Jones.', 'They talked.']);
      expect(SentenceSplitter.sentences('J. K. Rowling wrote it. Yes.'),
          ['J. K. Rowling wrote it.', 'Yes.']);
    });
    test('decimals do not split', () {
      expect(SentenceSplitter.sentences('Pi is 3.14 roughly. Next.'),
          ['Pi is 3.14 roughly.', 'Next.']);
    });
    test('quoted speech', () {
      expect(SentenceSplitter.sentences('"Stop!" he said. She ran.'),
          ['"Stop!" he said.', 'She ran.']);
      expect(SentenceSplitter.sentences('He left. "Wait!" she cried.'),
          ['He left.', '"Wait!" she cried.']);
    });
    test('ellipsis', () {
      expect(SentenceSplitter.sentences('Well... I think so. Maybe.'),
          ['Well... I think so.', 'Maybe.']);
    });
    test('offsets map back into the source', () {
      const src = 'One. Two three. Four?';
      for (final s in SentenceSplitter.split(src)) {
        expect(src.substring(s.start, s.end), s.text);
      }
    });
    test('long sentences are bounded', () {
      final long = List.filled(200, 'word').join(' ');
      final parts = SentenceSplitter.sentences('$long.', maxChars: 100);
      expect(parts.every((p) => p.length <= 100), isTrue);
      expect(parts.length > 1, isTrue);
    });
    test('cjk', () {
      expect(SentenceSplitter.sentences('你好。我是谁？再见！'), ['你好。', '我是谁？', '再见！']);
    });
    test('empty', () {
      expect(SentenceSplitter.sentences('   '), isEmpty);
    });
  });

  group('Paragraphs', () {
    test('blank lines separate', () {
      expect(Paragraphs.parse('a b\n\nc d'), ['a b', 'c d']);
    });
    test('one paragraph per line', () {
      expect(Paragraphs.parse('First line.\nSecond line.\nThird line.'),
          ['First line.', 'Second line.', 'Third line.']);
    });
    test('hard wrapped text is unwrapped', () {
      const raw = 'It was the best of times, it was the worst of times,\n'
          'it was the age of wisdom, it was the age of foolishness,\n'
          'it was the epoch of belief, it was the epoch of incredulity,\n'
          'it was the season of Light.\n\n'
          'There were a king with a large jaw and a queen with a plain face,\n'
          'on the throne of England; there were a king with a large jaw and\n'
          'a queen with a fair face, on the throne of France.';
      final p = Paragraphs.parse(raw);
      expect(p.length, 2);
      expect(p.first.startsWith('It was the best of times, it was the worst'), isTrue);
    });
  });

  group('TextNormalizer', () {
    test('integers and decimals', () {
      expect(n('I have 3 cats'), 'I have three cats');
      expect(n('Pi is 3.14'), 'Pi is three point one four');
    });
    test('thousands separators', () {
      expect(n('1,234 people'), 'one thousand two hundred thirty-four people');
    });
    test('currency', () {
      expect(n(r'It costs $42.50'), 'It costs forty-two dollars and fifty cents');
      expect(n(r'Pay $1 now'), 'Pay one dollar now');
      expect(n(r'He has $2 million'), 'He has two million dollars');
    });
    test('percent', () {
      expect(n('50% done'), 'fifty percent done');
      expect(n('3.50% rate'), 'three point five zero percent rate');
    });
    test('time', () {
      expect(n('Meet at 3:45 PM'), 'Meet at three forty-five p m');
      expect(n('At 7:05'), 'At seven oh five');
      expect(n('At 9:00'), "At nine o'clock");
    });
    test('iso date', () {
      expect(n('On 2024-01-15 we met'), 'On January fifteenth, twenty twenty-four we met');
    });
    test('units and temperature', () {
      expect(n('Run 5 km'), 'Run five kilometers');
      expect(n('1 kg of rice'), 'one kilogram of rice');
      expect(n('It was 42°C'), 'It was forty-two degrees Celsius');
    });
    test('ordinals', () {
      expect(n('the 21st century'), 'the twenty-first century');
    });
    test('years', () {
      expect(n('Born in 1999.'), 'Born in nineteen ninety-nine.');
      expect(n('In May 2005 it began'), 'In May two thousand five it began');
      expect(n('He had 1999 coins'), 'He had one thousand nine hundred ninety-nine coins');
    });
    test('abbreviations', () {
      expect(n('Mr. Smith and Dr. Jones'), 'Mister Smith and Doctor Jones');
      expect(n('St. Patrick'), 'Saint Patrick');
      expect(n('Visit 5 St. 3'), 'Visit five Street three');
      expect(n('No. 5 is alive'), 'Number five is alive');
    });
    test('roman chapter headings', () {
      expect(n('Chapter IV begins'), 'Chapter four begins');
    });
    test('urls and emails', () {
      expect(n('See https://example.com/x now'), 'See now');
      expect(n('Mail me at a@b.com'), 'Mail me at email address');
    });
    test('acronyms', () {
      expect(n('The FBI arrived'), 'The F B I arrived');
      expect(n('NASA launched'), 'NASA launched');
      expect(n('He yelled STOP now'), 'He yelled stop now');
      expect(n('STOP RIGHT THERE'), 'stop right there');
    });
    test('markup and emphasis', () {
      expect(n('This is *very* good'), 'This is very good');
      expect(n('A _quiet_ night'), 'A quiet night');
    });
    test('ellipsis and punctuation', () {
      expect(n('Well... maybe'), 'Well, maybe');
      expect(n('He paused...'), 'He paused.');
      expect(n('What?!?!'), 'What?');
    });
    test('non-english keeps text but strips noise', () {
      const o = NormalizerOptions(language: 'fr');
      expect(TextNormalizer.normalize('Il a 3 chats https://x.y', options: o), 'Il a 3 chats');
    });
    test('never throws on odd input', () {
      for (final s in ['', '   ', r'$', '%', '1.', '...', '\u200B', '9' * 40, 'A.B.C.']) {
        TextNormalizer.normalize(s);
      }
    });
  });
}
