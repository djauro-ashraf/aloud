/// Minimal node for shelf (folder) tree operations.
final class ShelfNode {
  const ShelfNode(this.id, this.parentId, this.name);

  final String id;
  final String? parentId;
  final String name;
}

/// A visible row of the shelf tree.
final class ShelfRow {
  const ShelfRow({
    required this.node,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
  });

  final ShelfNode node;
  final int depth;
  final bool hasChildren;
  final bool expanded;
}

/// Pure tree helpers over a flat list of shelves (stored with `parentId`).
final class ShelfTree {
  ShelfTree(Iterable<ShelfNode> nodes)
      : _byId = {for (final n in nodes) n.id: n},
        _children = _group(nodes);

  final Map<String, ShelfNode> _byId;
  final Map<String?, List<ShelfNode>> _children;

  static Map<String?, List<ShelfNode>> _group(Iterable<ShelfNode> nodes) {
    final m = <String?, List<ShelfNode>>{};
    for (final n in nodes) {
      (m[n.parentId] ??= []).add(n);
    }
    for (final l in m.values) {
      l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return m;
  }

  ShelfNode? node(String id) => _byId[id];

  List<ShelfNode> childrenOf(String? parentId) => _children[parentId] ?? const [];

  /// Ids of every shelf below [id] (not including it), deepest-last.
  List<String> descendantIds(String id) {
    final out = <String>[];
    final queue = [id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final c in childrenOf(cur)) {
        out.add(c.id);
        queue.add(c.id);
      }
    }
    return out;
  }

  /// Root → leaf names, e.g. `[Fiction, Sci-Fi]`.
  List<ShelfNode> pathTo(String id) {
    final out = <ShelfNode>[];
    String? cur = id;
    final seen = <String>{};
    while (cur != null && seen.add(cur)) {
      final n = _byId[cur];
      if (n == null) break;
      out.insert(0, n);
      cur = n.parentId;
    }
    return out;
  }

  /// A shelf can't move into itself or any of its descendants.
  bool canMove(String id, String? newParentId) {
    if (newParentId == null) return true;
    if (newParentId == id) return false;
    return !descendantIds(id).contains(newParentId);
  }

  /// Rows for a tree view honouring the [expanded] set.
  List<ShelfRow> rows(Set<String> expanded) {
    final out = <ShelfRow>[];
    void walk(String? parent, int depth) {
      for (final n in childrenOf(parent)) {
        final has = childrenOf(n.id).isNotEmpty;
        final isOpen = expanded.contains(n.id);
        out.add(ShelfRow(node: n, depth: depth, hasChildren: has, expanded: isOpen));
        if (has && isOpen) walk(n.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }
}

/// Library sort orders.
enum LibrarySort {
  recent('Recently opened'),
  newest('Newest first'),
  oldest('Oldest first'),
  nameAz('Name A–Z'),
  nameZa('Name Z–A'),
  largest('Largest first');

  const LibrarySort(this.label);
  final String label;
}

/// What the sorter needs from a document.
final class SortKey {
  const SortKey({
    required this.title,
    required this.addedAt,
    this.openedAt,
    this.sizeBytes = 0,
  });

  final String title;
  final int addedAt;
  final int? openedAt;
  final int sizeBytes;
}

abstract final class LibrarySorter {
  static int compare(LibrarySort sort, SortKey a, SortKey b) {
    int byName() => _natural(a.title.toLowerCase(), b.title.toLowerCase());
    switch (sort) {
      case LibrarySort.recent:
        final c = (b.openedAt ?? b.addedAt).compareTo(a.openedAt ?? a.addedAt);
        return c != 0 ? c : byName();
      case LibrarySort.newest:
        final c = b.addedAt.compareTo(a.addedAt);
        return c != 0 ? c : byName();
      case LibrarySort.oldest:
        final c = a.addedAt.compareTo(b.addedAt);
        return c != 0 ? c : byName();
      case LibrarySort.nameAz:
        return byName();
      case LibrarySort.nameZa:
        return -byName();
      case LibrarySort.largest:
        final c = b.sizeBytes.compareTo(a.sizeBytes);
        return c != 0 ? c : byName();
    }
  }

  /// Natural order: "Chapter 2" < "Chapter 10".
  static int _natural(String a, String b) {
    final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
    final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final x = ra[i];
      final y = rb[i];
      final nx = int.tryParse(x);
      final ny = int.tryParse(y);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return ra.length.compareTo(rb.length);
  }
}

/// File / shelf name helpers.
abstract final class Names {
  static final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  /// Display title: control characters removed, whitespace collapsed,
  /// length-limited by code points. Punctuation such as `:` is preserved.
  static String title(String raw, {int maxChars = 120, String fallback = 'Untitled'}) {
    final s = raw.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final runes = s.runes.toList();
    final cut = runes.length > maxChars ? String.fromCharCodes(runes.take(maxChars)).trim() : s;
    return cut.isEmpty ? fallback : cut;
  }

  /// Safe file/shelf stem: illegal path characters replaced, collapsed and
  /// length-limited by code points.
  static String sanitize(String raw, {int maxChars = 80, String fallback = 'Untitled'}) {
    var s = raw.replaceAll(_illegal, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^\.+'), '').trim();
    final runes = s.runes.toList();
    if (runes.length > maxChars) s = String.fromCharCodes(runes.take(maxChars)).trim();
    return s.isEmpty ? fallback : s;
  }

  /// `Name`, `Name (2)`, `Name (3)` … avoiding [existing] (case-insensitive).
  static String unique(String name, Iterable<String> existing) {
    final taken = {for (final e in existing) e.toLowerCase()};
    if (!taken.contains(name.toLowerCase())) return name;
    var i = 2;
    while (taken.contains('$name ($i)'.toLowerCase())) {
      i++;
    }
    return '$name ($i)';
  }

  /// "my_great-book.v2.epub" → "my great book v2".
  static String titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return sanitize(stem.replaceAll(RegExp(r'[_\-.]+'), ' '));
  }
}
