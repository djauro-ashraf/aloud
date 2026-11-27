/// Word-level helpers shared by the highlighter and the PDF text matcher.
///
/// A "word" is a run of letters/digits, optionally joined by an inner
/// apostrophe ("don't"). Punctuation and whitespace are never part of a word,
/// so two texts that differ only in punctuation tokenise identically.
library;

/// A word inside a string, as a half-open character range.
final class WordSpan {
  const WordSpan(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  String slice(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is WordSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'WordSpan($start, $end)';
}

abstract final class WordTokenizer {
  static final RegExp _word = RegExp(
    r"[\p{L}\p{N}\p{M}]+(?:['’][\p{L}\p{N}\p{M}]+)*",
    unicode: true,
  );

  static const Map<String, String> _ligatures = {
    'ﬀ': 'ff',
    'ﬁ': 'fi',
    'ﬂ': 'fl',
    'ﬃ': 'ffi',
    'ﬄ': 'ffl',
    'ﬅ': 'st',
    'ﬆ': 'st',
  };

  /// Every word in [text], in order.
  static List<WordSpan> spans(String text) =>
      [for (final m in _word.allMatches(text)) WordSpan(m.start, m.end)];

  /// Comparison key for a word: lower-case, no apostrophes, no soft hyphens,
  /// ligatures expanded. Two renderings of the same word share a key.
  static String key(String word) {
    final b = StringBuffer();
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == "'" || ch == '’' || ch == '\u00AD') continue;
      b.write(_ligatures[ch] ?? ch);
    }
    return b.toString().toLowerCase();
  }

  /// Keys of every word in [text].
  static List<String> keys(String text) =>
      [for (final s in spans(text)) key(s.slice(text))];
}
