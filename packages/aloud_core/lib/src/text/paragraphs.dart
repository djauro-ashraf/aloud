/// Turns raw plain text into paragraphs.
///
/// Plain-text novels come in two layouts that look identical to a naive
/// splitter but must be handled differently:
///
/// * **Hard-wrapped** (Project Gutenberg style): paragraphs are separated by
///   blank lines and every line is wrapped at ~70 columns. Single newlines
///   must be *joined*.
/// * **One-line-per-paragraph** (web copy/paste): a single newline is a
///   paragraph break.
abstract final class Paragraphs {
  /// Splits [raw] into trimmed, non-empty paragraphs.
  static List<String> parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = text
        .split(RegExp(r'\n[ \t]*\n+'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    if (blocks.isEmpty) return const [];

    final wrapped = _looksHardWrapped(blocks);
    final out = <String>[];
    for (final block in blocks) {
      final lines = block
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length == 1) {
        out.add(lines.first);
      } else if (wrapped) {
        out.add(_joinWrapped(lines));
      } else {
        out.addAll(lines);
      }
    }
    return out;
  }

  /// Hard-wrapped if most multi-line blocks have long, similarly sized lines
  /// that rarely end with terminal punctuation.
  static bool _looksHardWrapped(List<String> blocks) {
    var multi = 0;
    var wrappedVotes = 0;
    for (final b in blocks) {
      final lines = b.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.length < 3) continue;
      multi++;
      final body = lines.sublist(0, lines.length - 1);
      final avg = body.fold<int>(0, (s, l) => s + l.length) / body.length;
      final endsTerminal = body.where(_endsTerminal).length / body.length;
      if (avg >= 40 && endsTerminal < 0.5) wrappedVotes++;
    }
    return multi > 0 && wrappedVotes / multi >= 0.5;
  }

  static bool _endsTerminal(String l) {
    if (l.isEmpty) return false;
    final c = l[l.length - 1];
    return '.!?…"”’)'.contains(c);
  }

  static String _joinWrapped(List<String> lines) {
    final buf = StringBuffer(lines.first);
    for (var i = 1; i < lines.length; i++) {
      final prev = lines[i - 1];
      if (prev.endsWith('-') && !prev.endsWith(' -') && !prev.endsWith('--')) {
        // Soft hyphenation across a line break: "exam-" + "ple".
        final cur = lines[i];
        if (cur.isNotEmpty && cur[0] == cur[0].toLowerCase()) {
          final s = buf.toString();
          buf
            ..clear()
            ..write(s.substring(0, s.length - 1));
        } else {
          buf.write(' ');
        }
      } else {
        buf.write(' ');
      }
      buf.write(lines[i]);
    }
    return buf.toString();
  }
}
