import '../text/word_tokens.dart';
import 'rule_engine.dart';

/// Maps a position in the text handed to a voice back to the word the reader
/// is looking at.
///
/// The voice is given [SpeechPlan.fullSpeech], which can differ from what is
/// on screen ("42" becomes "forty two", "Dr." becomes "Doctor", rules may
/// replace text). Highlighting must follow the *displayed* words, so this maps
/// each spoken word onto the displayed word it came from.
final class SpokenWordMap {
  SpokenWordMap._(this._spokenStart, this._spokenWords, this._toOriginal);

  /// Builds the map for one planned sentence. A skipped or empty sentence
  /// yields a map that never resolves a word.
  factory SpokenWordMap.fromPlan(SpeechPlan plan) {
    if (plan.skip || plan.spoken.trim().isEmpty) {
      return SpokenWordMap._(0, const [], const []);
    }
    // Same assembly as SpeechPlan.fullSpeech, tracking where `spoken` lands.
    var offset = 0;
    for (final part in plan.before) {
      if (part.trim().isEmpty) continue;
      offset += part.length + 1;
    }
    final spokenWords = WordTokenizer.spans(plan.spoken);
    final mapping = WordAligner.spokenToOriginal(plan.original, plan.spoken);
    return SpokenWordMap._(offset, spokenWords, mapping);
  }

  final int _spokenStart;
  final List<WordSpan> _spokenWords;
  final List<int> _toOriginal;

  bool get isEmpty => _spokenWords.isEmpty;

  /// Index of the displayed word being spoken at [offset] in the full speech
  /// text, or null while the voice is outside the sentence itself (a lead-in
  /// phrase, or a trailing one).
  int? originalWordAt(int offset) {
    if (_spokenWords.isEmpty) return null;
    final local = offset - _spokenStart;
    if (local < 0) return null;
    // Last word that starts at or before the offset.
    var lo = 0;
    var hi = _spokenWords.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_spokenWords[mid].start <= local) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return _toOriginal.first;
    return _toOriginal[found];
  }
}

/// Aligns the words of a spoken rendering to the words of the original text.
abstract final class WordAligner {
  /// How far ahead an unmatched spoken word may look for its original.
  static const int _window = 4;

  /// For each word of [spoken], the index of the word in [original] it was
  /// derived from. The result is monotone non-decreasing and every entry is a
  /// valid index into [original]'s words (empty when [original] has none).
  ///
  /// Words present in both texts anchor the alignment. Runs of spoken words
  /// with no counterpart ("forty two" for "42") are spread across the original
  /// words that sit between the surrounding anchors.
  static List<int> spokenToOriginal(String original, String spoken) {
    final o = WordTokenizer.keys(original);
    final s = WordTokenizer.keys(spoken);
    if (o.isEmpty || s.isEmpty) return List.filled(s.length, 0);

    final anchor = List<int>.filled(s.length, -1);
    var j = 0;
    for (var i = 0; i < s.length; i++) {
      final limit = (j + _window).clamp(0, o.length - 1);
      for (var k = j; k <= limit; k++) {
        if (o[k] == s[i]) {
          anchor[i] = k;
          j = k + 1;
          break;
        }
      }
    }

    final result = List<int>.filled(s.length, 0);
    var prevOriginal = -1;
    var i = 0;
    while (i < s.length) {
      if (anchor[i] >= 0) {
        result[i] = anchor[i];
        prevOriginal = anchor[i];
        i++;
        continue;
      }
      var end = i;
      while (end < s.length && anchor[end] < 0) {
        end++;
      }
      final nextOriginal = end < s.length ? anchor[end] : o.length;
      final from = prevOriginal + 1;
      final to = nextOriginal - 1;
      final runLength = end - i;
      for (var t = 0; t < runLength; t++) {
        result[i + t] = from <= to
            ? from + (t * (to - from + 1)) ~/ runLength
            : (prevOriginal >= 0 ? prevOriginal : 0);
      }
      i = end;
    }
    return result;
  }
}
