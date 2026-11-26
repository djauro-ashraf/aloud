/// A sentence located inside its source text.
final class SentenceSpan {
  const SentenceSpan(this.text, this.start, this.end);

  /// Trimmed sentence text.
  final String text;

  /// Inclusive start offset in the source string.
  final int start;

  /// Exclusive end offset in the source string.
  final int end;

  @override
  String toString() => 'SentenceSpan($start..$end, "$text")';
}

/// Rule-based sentence segmentation tuned for fiction, articles and PDFs.
///
/// Why not a platform break-iterator? Dart has no equivalent, and a
/// deterministic splitter gives identical results on every platform — which
/// matters because sentence boundaries are used as cache keys and as saved
/// reading positions.
abstract final class SentenceSplitter {
  static const _terminals = {'.', '!', '?', '…', '。', '！', '？', '‼', '⁉'};
  static const _cjkTerminals = {'。', '！', '？'};
  static const _closers = {
    '"', "'", '”', '’', ')', ']', '}', '»', '」', '』', '*', '_',
  };

  static const _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'mt', 'vs', 'etc',
    'capt', 'col', 'gen', 'lt', 'sgt', 'cpl', 'pvt', 'gov', 'sen', 'rep',
    'rev', 'hon', 'fig', 'no', 'vol', 'pp', 'dept', 'corp', 'inc', 'ltd',
    'co', 'approx', 'est', 'ca', 'cf', 'ed', 'eds', 'al', 'op', 'ch',
    'e.g', 'i.e', 'a.m', 'p.m', 'u.s', 'u.k',
  };

  /// Abbreviations that may legitimately end a sentence ("…and so on, etc.").
  static const _sentenceFinalAbbreviations = {'etc', 'inc', 'ltd', 'co'};

  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\d');

  /// Sentences longer than this are split again at clause boundaries so TTS
  /// engines never receive huge inputs (latency, timeouts, voice instability).
  static const defaultMaxChars = 420;

  /// Splits [text] into sentences with their offsets in [text].
  static List<SentenceSpan> split(String text, {int maxChars = defaultMaxChars}) {
    final raw = <SentenceSpan>[];
    final n = text.length;
    var start = 0;
    var i = 0;
    while (i < n) {
      final c = text[i];
      if (!_terminals.contains(c)) {
        i++;
        continue;
      }
      // Whole run of terminal punctuation: "?!", "...", "!!!".
      var runEnd = i + 1;
      while (runEnd < n && _terminals.contains(text[runEnd])) {
        runEnd++;
      }
      // Closing quotes/brackets glued to the terminal: `end."`
      var j = runEnd;
      while (j < n && _closers.contains(text[j])) {
        j++;
      }
      if (_isBoundary(text, start, i, runEnd, j)) {
        _add(raw, text, start, j);
        start = j;
      }
      i = j;
    }
    _add(raw, text, start, n);
    return [for (final s in raw) ..._limit(s, maxChars)];
  }

  /// Convenience: just the strings.
  static List<String> sentences(String text, {int maxChars = defaultMaxChars}) =>
      [for (final s in split(text, maxChars: maxChars)) s.text];

  // ── Boundary decision ──────────────────────────────────────────────────

  static bool _isBoundary(String t, int sentenceStart, int termStart, int runEnd, int end) {
    final first = t[termStart];
    if (_cjkTerminals.contains(first)) return true;
    if (end >= t.length) return true;

    // Needs whitespace after the block, otherwise it's "3.14" or "a.b".
    if (!_isSpace(t[end])) return false;

    final next = _nextVisible(t, end);
    if (next == null) return true;

    // "Well... I think so." — a short interjection before an ellipsis is not
    // a sentence of its own.
    final isEllipsis = first == '…' || (first == '.' && runEnd - termStart > 1);
    if (isEllipsis) {
      final lead = t.substring(sentenceStart, termStart).trim();
      if (lead.split(RegExp(r'\s+')).length <= 2) return false;
    }

    final singleDot = first == '.' && runEnd == termStart + 1;
    if (singleDot) {
      final word = _wordBefore(t, termStart);
      if (word.isNotEmpty) {
        final lower = word.toLowerCase();
        if (_abbreviations.contains(lower)) {
          if (_sentenceFinalAbbreviations.contains(lower)) {
            return _isUpper(next) || _digit.hasMatch(next);
          }
          return false;
        }
        // Single capital initial: "J. K. Rowling".
        if (word.length == 1 && _isUpper(word)) return false;
      }
    }

    // Quoted speech: `"Stop!" he said.` — lowercase continuation ⇒ same sentence.
    if (_isLower(next)) return false;
    return true;
  }

  static String? _nextVisible(String t, int from) {
    for (var k = from; k < t.length; k++) {
      final c = t[k];
      if (_isSpace(c) || c == '*' || c == '_') continue;
      return c;
    }
    return null;
  }

  static String _wordBefore(String t, int end) {
    var k = end;
    while (k > 0) {
      final c = t[k - 1];
      if (_letter.hasMatch(c) || c == '.') {
        k--;
      } else {
        break;
      }
    }
    return t.substring(k, end);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static void _add(List<SentenceSpan> out, String t, int s, int e) {
    var a = s;
    var b = e;
    while (a < b && _isSpace(t[a])) {
      a++;
    }
    while (b > a && _isSpace(t[b - 1])) {
      b--;
    }
    if (b > a) out.add(SentenceSpan(t.substring(a, b), a, b));
  }

  static Iterable<SentenceSpan> _limit(SentenceSpan s, int maxChars) sync* {
    if (s.text.length <= maxChars) {
      yield s;
      return;
    }
    final text = s.text;
    var from = 0;
    while (text.length - from > maxChars) {
      final window = text.substring(from, from + maxChars);
      var cut = _lastClauseBreak(window);
      if (cut <= 0) cut = window.lastIndexOf(' ');
      if (cut <= 0) cut = maxChars;
      final piece = text.substring(from, from + cut).trim();
      if (piece.isNotEmpty) {
        yield SentenceSpan(piece, s.start + from, s.start + from + cut);
      }
      from += cut;
    }
    final tail = text.substring(from).trim();
    if (tail.isNotEmpty) yield SentenceSpan(tail, s.start + from, s.end);
  }

  static int _lastClauseBreak(String w) {
    final floor = (w.length * 0.4).floor();
    for (var k = w.length - 1; k >= floor; k--) {
      final c = w[k];
      if (c == ';' || c == ':' || c == '—' || c == ',') return k + 1;
    }
    return -1;
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u00A0';
  static bool _isUpper(String c) => c != c.toLowerCase() && c == c.toUpperCase();
  static bool _isLower(String c) => c != c.toUpperCase() && c == c.toLowerCase();
}
