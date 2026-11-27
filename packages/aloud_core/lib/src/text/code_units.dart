/// Aligns per-character data with Dart's UTF-16 string indices.
///
/// PDF engines report one bounding box per Unicode *code point*, but Dart
/// strings are indexed per UTF-16 *code unit*. The two agree for ordinary text
/// and differ once a character outside the Basic Multilingual Plane (an emoji,
/// a rare ideograph) appears, shifting every later index.
///
/// Returns one entry per code unit of [text]: [perCodePoint] itself when it
/// already lines up, otherwise a copy with each code point's value repeated for
/// both halves of its surrogate pair. Returns null when [perCodePoint] matches
/// neither layout, meaning the data cannot be trusted.
List<T>? perCodeUnit<T>(String text, List<T> perCodePoint) {
  if (perCodePoint.length == text.length) return perCodePoint;
  final out = <T>[];
  var i = 0;
  for (final rune in text.runes) {
    if (i >= perCodePoint.length) return null;
    out.add(perCodePoint[i]);
    if (rune > 0xFFFF) out.add(perCodePoint[i]);
    i++;
  }
  return i == perCodePoint.length ? out : null;
}
