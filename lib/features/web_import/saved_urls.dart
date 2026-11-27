/// The pages already saved during one visit to the in-app browser, so tapping
/// Save twice on the same chapter does not add it twice.
final class SavedUrls {
  SavedUrls([Iterable<Uri> initial = const []]) {
    initial.forEach(add);
  }

  final _keys = <String>{};

  bool contains(Uri url) => _keys.contains(keyOf(url));

  void add(Uri url) => _keys.add(keyOf(url));

  void clear() => _keys.clear();

  /// Two addresses that open the same page share a key: the part after `#` and
  /// a trailing slash make no difference.
  static String keyOf(Uri url) {
    final s = url.toString();
    final hash = s.indexOf('#');
    final bare = hash < 0 ? s : s.substring(0, hash);
    return bare.endsWith('/') ? bare.substring(0, bare.length - 1) : bare;
  }
}
