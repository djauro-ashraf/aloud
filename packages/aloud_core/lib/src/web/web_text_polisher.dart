/// Cleans paragraphs extracted from web pages so they read like a book, not a
/// website. Only used for web-sourced documents; other formats are untouched.
abstract final class WebTextPolisher {
  static final _noise = <RegExp>[
    RegExp(r'^(?:share|tweet|pin it|like|comments?|follow us|subscribe|advertisement|sponsored|loading\.*|read more|click here|log ?in|sign ?up|related (?:posts|articles|chapters)|recommended|you may also like|tags?:|categories:|posted (?:on|by)|all rights reserved|privacy policy|terms of (?:service|use)|report (?:chapter|error)|bookmark|add to library)\b.{0,60}$', caseSensitive: false),
    RegExp(r'^(?:©|copyright\b).{0,120}$', caseSensitive: false),
    RegExp(r'^(?:translator|editor|proofreader|tl|ed)\s*[:：]', caseSensitive: false),
    RegExp(r'^(?:<\s*)?(?:prev(?:ious)?|next)\s+(?:chapter|page)(?:\s*>)?$', caseSensitive: false),
    RegExp(r'^(?:<\s*)?(?:prev(?:ious)?|next|index|table of contents)(?:\s*[|·•]\s*(?:prev(?:ious)?|next|index|table of contents))+(?:\s*>)?$', caseSensitive: false),
    RegExp(r'^\W*(?:\d+\s+)?(?:comments?|shares?|views?)\W*$', caseSensitive: false),
    RegExp(r'\b(?:novelfull|webnovel|wuxiaworld|lightnovelpub|royalroad|mtlnovel|freewebnovel|boxnovel|readnovelfull|novelbin)\b.{0,80}$', caseSensitive: false),
    RegExp(r'^(?:support|read|find) .{0,60}\b(?:on|at|only at)\b.{0,40}\.(?:com|net|org|io)\b', caseSensitive: false),
  ];

  static final _heading = RegExp(
    r'^(?:#{1,6}\s+.+|(?:chapter|prologue|epilogue|prelude|interlude|part|book|volume)\b.{0,90})$',
    caseSensitive: false,
  );
  static final _sceneBreak = RegExp(r'^[\s*\-_~#=•·◆◇◊—–]{3,}$');

  /// Returns cleaned paragraphs. Headings that came from `<h1>`–`<h3>` are
  /// expected to be marked with a leading `# ` by the extractor.
  static List<String> polish(List<String> paragraphs, {String? title}) {
    final out = <String>[];
    for (final raw in paragraphs) {
      final p = _normalize(raw);
      if (p.isEmpty) continue;
      if (_isNoise(p)) continue;
      out.add(p);
    }
    return _dropLeadingTitle(out, title);
  }

  static bool isHeading(String text) => _heading.hasMatch(text.trim());

  static bool isSceneBreak(String text) {
    final t = text.trim();
    return t.length >= 3 && _sceneBreak.hasMatch(t);
  }

  /// Removes the `# ` marker for display/speech.
  static String stripHeadingMarker(String text) =>
      text.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();

  static bool _isNoise(String p) {
    if (p.length > 160) return false; // long lines are content, not chrome
    final bare = stripHeadingMarker(p);
    return _noise.any((rx) => rx.hasMatch(bare));
  }

  static String _normalize(String s) => s
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  static List<String> _dropLeadingTitle(List<String> ps, String? title) {
    if (ps.isEmpty || title == null || title.trim().isEmpty) return ps;
    final t = _loose(title);
    // Drop at most two leading duplicates of the page title / chapter title.
    var i = 0;
    while (i < ps.length && i < 2 && _loose(stripHeadingMarker(ps[i])) == t) {
      i++;
    }
    // Keep one copy as the visible heading when the first block was a heading.
    if (i > 0 && isHeading(ps.first)) return [ps.first, ...ps.sublist(i)];
    return ps.sublist(i);
  }

  static String _loose(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
}
