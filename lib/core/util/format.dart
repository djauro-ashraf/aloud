/// Human-readable formatting helpers (no `intl` dependency needed).
abstract final class Fmt {
  static String bytes(int b) {
    if (b < 1024) return '$b B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var v = b / 1024;
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
  }

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  /// "just now", "5 min ago", "3 h ago", "yesterday", "12 days ago", "Mar 4".
  static String ago(DateTime when, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final d = n.difference(when);
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 14) return '${d.inDays} days ago';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[when.month - 1]} ${when.day}';
  }

  /// `1.0×`, `1.25×`, `0.9×`.
  static String speed(double s) {
    final t = s.toStringAsFixed(2);
    final trimmed = t.endsWith('0') ? t.substring(0, t.length - 1) : t;
    return '$trimmed×';
  }
}
