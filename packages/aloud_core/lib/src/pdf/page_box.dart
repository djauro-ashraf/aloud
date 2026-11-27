import 'dart:math' as math;

/// A rectangle on a PDF page, in PDF page space: the origin is the bottom-left
/// corner and y grows upward, so [top] is greater than [bottom].
///
/// Not called `TextBox` because Flutter's painting library already exports a
/// class of that name.
final class PageBox {
  const PageBox(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => top - bottom;

  /// Zero-area boxes (spaces, control characters) carry no position.
  bool get isEmpty => right <= left || top <= bottom;

  PageBox union(PageBox other) => PageBox(
        math.min(left, other.left),
        math.max(top, other.top),
        math.max(right, other.right),
        math.min(bottom, other.bottom),
      );

  /// Distance from the point to the box; zero when the point is inside.
  double distanceTo(double x, double y) {
    final dx = x < left ? left - x : (x > right ? x - right : 0.0);
    final dy = y < bottom ? bottom - y : (y > top ? y - top : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Union of the non-empty boxes, or null if there are none.
  static PageBox? unionOf(Iterable<PageBox> boxes) {
    PageBox? out;
    for (final b in boxes) {
      if (b.isEmpty) continue;
      out = out == null ? b : out.union(b);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is PageBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'PageBox($left, $top, $right, $bottom)';
}

abstract final class TextLines {
  /// Merges word boxes given in reading order into one box per visual line.
  ///
  /// A word joins the current line when it overlaps it vertically by at least
  /// half of the smaller height, so a tall capital or a descender does not
  /// start a new line but a genuine line break does.
  static List<PageBox> group(Iterable<PageBox> words) {
    final lines = <PageBox>[];
    for (final w in words) {
      if (w.isEmpty) continue;
      if (lines.isNotEmpty && _sameLine(lines.last, w)) {
        lines[lines.length - 1] = lines.last.union(w);
      } else {
        lines.add(w);
      }
    }
    return lines;
  }

  static bool _sameLine(PageBox line, PageBox word) {
    final overlap = math.min(line.top, word.top) - math.max(line.bottom, word.bottom);
    return overlap >= 0.5 * math.min(line.height, word.height);
  }

  /// Index of the box nearest to ([x], [y]) within [maxDistance], or null.
  static int? nearest(List<PageBox> boxes, double x, double y, {required double maxDistance}) {
    int? best;
    var bestDistance = maxDistance;
    for (var i = 0; i < boxes.length; i++) {
      final d = boxes[i].distanceTo(x, y);
      if (d <= bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }
}
