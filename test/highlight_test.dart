import 'package:aloud/core/highlight.dart';
import 'package:aloud/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HighlightMode', () {
    test('auto marks the sentence and the word when one is known', () {
      expect(HighlightMode.auto.showsSentence(hasWord: true), isTrue);
      expect(HighlightMode.auto.showsWord(hasWord: true), isTrue);
    });

    test('auto without a word position is sentence only (neural voices)', () {
      expect(HighlightMode.auto.showsSentence(hasWord: false), isTrue);
      expect(HighlightMode.auto.showsWord(hasWord: false), isFalse);
    });

    test('word mode falls back to the sentence when no word is known', () {
      expect(HighlightMode.word.showsSentence(hasWord: false), isTrue);
      expect(HighlightMode.word.showsWord(hasWord: false), isFalse);
    });

    test('word mode with a word marks only the word', () {
      expect(HighlightMode.word.showsSentence(hasWord: true), isFalse);
      expect(HighlightMode.word.showsWord(hasWord: true), isTrue);
    });

    test('sentence mode never marks a word; off marks nothing', () {
      expect(HighlightMode.sentence.showsWord(hasWord: true), isFalse);
      expect(HighlightMode.off.showsSentence(hasWord: true), isFalse);
      expect(HighlightMode.off.showsWord(hasWord: true), isFalse);
    });

    test('unknown stored values fall back to sensible defaults', () {
      expect(HighlightMode.parse('garbage'), HighlightMode.auto);
      expect(WordStyle.parse('garbage'), WordStyle.soft);
      expect(TapToRead.parse('garbage'), TapToRead.doubleTap);
    });

    test('tap mode round-trips through its stored form', () {
      for (final m in TapToRead.values) {
        expect(TapToRead.parse(m.stored), m);
      }
    });
  });

  group('PdfHighlightStyle', () {
    test('reads the old app defaults', () {
      final s = PdfHighlightStyle.from(const {});
      expect(s.color, 0xFFE53935);
      expect(s.thickness, 3);
      expect(s.padH, 2);
      expect(s.padV, 3);
      expect(s.offsetY, 0);
    });

    test('reflects stored settings and compares by value', () {
      final a = PdfHighlightStyle.from({Prefs.pdfHighlightThickness.key: 5});
      final b = PdfHighlightStyle.from({Prefs.pdfHighlightThickness.key: 5});
      expect(a.thickness, 5);
      expect(a, b);
    });
  });
}
