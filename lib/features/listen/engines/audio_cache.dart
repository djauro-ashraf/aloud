import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Disk cache of synthesised sentences, keyed by content hash.
///
/// One cache serves every engine and every document: if two books contain the
/// same sentence read by the same voice, it is synthesised once. Playback
/// speed is *not* part of the key (speed is applied at playback), so changing
/// speed never invalidates anything.
final class AudioCache {
  AudioCache(this.dir);

  final Directory dir;
  int _writesSinceTrim = 0;

  File _file(String key, String ext) => File(p.join(dir.path, '$key.$ext'));

  /// Returns the cached file and marks it recently used, or `null`.
  Future<File?> lookup(String key, String ext) async {
    final f = _file(key, ext);
    try {
      if (await f.exists() && await f.length() > 0) {
        await f.setLastModified(DateTime.now());
        return f;
      }
    } on FileSystemException {
      // Treat unreadable entries as a miss.
    }
    return null;
  }

  /// Atomically stores [bytes] (write to temp, then rename) so a crash can
  /// never leave a half-written clip that would later play as garbage.
  Future<File> store(String key, String ext, Uint8List bytes) async {
    await dir.create(recursive: true);
    final tmp = File(p.join(dir.path, '$key.$ext.part'));
    await tmp.writeAsBytes(bytes, flush: true);
    final dest = _file(key, ext);
    await tmp.rename(dest.path);
    _writesSinceTrim++;
    return dest;
  }

  Future<int> sizeBytes() async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Deletes least-recently-used clips until the cache is below 80% of
  /// [maxBytes]. Cheap enough to call after every ~50 writes.
  Future<void> trim(int maxBytes) async {
    if (!await dir.exists()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      if (e.path.endsWith('.part')) {
        await e.delete();
        continue;
      }
      final len = await e.length();
      total += len;
      files.add((e, len, await e.lastModified()));
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    final target = (maxBytes * 0.8).floor();
    for (final (f, len, _) in files) {
      if (total <= target) break;
      await f.delete();
      total -= len;
    }
    _writesSinceTrim = 0;
  }

  /// Whether enough writes happened that a trim is worthwhile.
  bool get shouldTrim => _writesSinceTrim >= 50;

  Future<void> clear() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }
}
