/// Splits text into chunks no longer than [maxLen], preferring sentence and
/// clause boundaries.
abstract final class TextChunker {
  static List<String> chunk(String text, int maxLen) {
    final t = text.trim();
    if (t.length <= maxLen) return t.isEmpty ? const [] : [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > maxLen) {
      final window = rest.substring(0, maxLen);
      var cut = _lastIndexOfAny(window, ['. ', '! ', '? ', '。', '！', '？']);
      if (cut < maxLen ~/ 3) cut = _lastIndexOfAny(window, ['; ', ': ', ', ', '、', '，']);
      if (cut < maxLen ~/ 3) cut = window.lastIndexOf(' ');
      if (cut <= 0) cut = maxLen - 1;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static int _lastIndexOfAny(String s, List<String> needles) {
    var best = -1;
    for (final n in needles) {
      final i = s.lastIndexOf(n);
      if (i >= 0) {
        final end = i + n.length - 1;
        if (end > best) best = end;
      }
    }
    return best;
  }
}

/// One piece of one source text queued for a provider call.
final class BatchItem {
  const BatchItem(this.source, this.part, this.text);

  final int source;
  final int part;
  final String text;
}

/// Groups texts into provider-sized batches and reassembles the results.
///
/// Providers differ in limits (DeepL ≈ 50 texts, MyMemory ≈ 480 chars, …);
/// this keeps that arithmetic out of the provider adapters.
final class BatchPlan {
  const BatchPlan._(this.batches, this.count, this._parts);

  final List<List<BatchItem>> batches;

  /// Number of source texts.
  final int count;
  final Map<int, List<String>> _parts;

  static BatchPlan build(List<String> texts, {required int maxTexts, required int maxChars}) {
    final batches = <List<BatchItem>>[];
    final parts = <int, List<String>>{};
    var current = <BatchItem>[];
    var chars = 0;

    void flush() {
      if (current.isNotEmpty) batches.add(current);
      current = <BatchItem>[];
      chars = 0;
    }

    for (var i = 0; i < texts.length; i++) {
      final pieces = TextChunker.chunk(texts[i], maxChars);
      parts[i] = pieces;
      for (var p = 0; p < pieces.length; p++) {
        final piece = pieces[p];
        if (current.length >= maxTexts || chars + piece.length > maxChars) flush();
        current.add(BatchItem(i, p, piece));
        chars += piece.length;
      }
    }
    flush();
    return BatchPlan._(batches, texts.length, parts);
  }

  /// Key used in the results map passed to [assemble].
  static String key(BatchItem item) => '${item.source}:${item.part}';

  /// [results] maps [key] → translated text. A missing entry falls back to
  /// the original piece so a failed chunk never loses content.
  List<String> assemble(Map<String, String> results) => [
        for (var i = 0; i < count; i++)
          [
            for (var p = 0; p < (_parts[i]?.length ?? 0); p++)
              results['$i:$p'] ?? _parts[i]![p],
          ].join(' '),
      ];
}
