import '../reading/reading_model.dart';

/// Finds which section (chapter) of a document holds a given PDF page.
///
/// Sections are cut either at chapter headings or at fixed page counts, so the
/// page range of a section cannot be guessed from its number. This reads each
/// section lazily, remembers its first and last page, and binary-searches —
/// sections are stored in page order.
final class PdfSectionMap {
  PdfSectionMap({required this.count, required this._read});

  final int count;
  final Future<ReaderSection> Function(int section) _read;
  final _ranges = <int, ({int first, int last})?>{};

  /// The section containing zero-based [page], or null when no section has
  /// readable text on it (a blank or image-only page).
  Future<int?> sectionOfPage(int page) async {
    var lo = 0;
    var hi = count - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      // Sections without paged text (pure images) cannot be ordered; compare
      // against the first one at or after the midpoint that has text.
      final probe = await _firstNonEmpty(mid, hi);
      if (probe == null) {
        hi = mid - 1;
        continue;
      }
      final r = (await _range(probe))!;
      if (page < r.first) {
        hi = mid - 1;
      } else if (page > r.last) {
        lo = probe + 1;
      } else {
        return probe;
      }
    }
    return null;
  }

  Future<int?> _firstNonEmpty(int from, int to) async {
    for (var i = from; i <= to; i++) {
      if (await _range(i) != null) return i;
    }
    return null;
  }

  Future<({int first, int last})?> _range(int section) async {
    if (_ranges.containsKey(section)) return _ranges[section];
    final content = await _read(section);
    int? first;
    int? last;
    for (final b in content.blocks) {
      final p = b.page;
      if (p == null) continue;
      if (first == null || p < first) first = p;
      if (last == null || p > last) last = p;
    }
    final range = first == null ? null : (first: first, last: last!);
    _ranges[section] = range;
    return range;
  }
}
