import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'import_exception.dart';

/// Extracts the page images of a CBZ (zip of images) to disk, in reading
/// order. Pages are stored as plain files so the viewer can stream them
/// without holding the archive in memory.
abstract final class ComicImporter {
  static const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

  /// Returns the number of pages written to [pagesDir].
  static Future<int> extract(String archivePath, String pagesDir) {
    return Isolate.run(() => _extract(archivePath, pagesDir));
  }

  static Future<int> _extract(String archivePath, String pagesDir) async {
    final input = InputFileStream(archivePath);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
      } catch (_) {
        throw const ImportException(
          'Could not open this comic. Only CBZ (zip) is supported; convert CBR/RAR files to CBZ first.',
        );
      }
      final entries = [
        for (final f in archive)
          if (f.isFile &&
              imageExtensions.contains(p.extension(f.name).toLowerCase()) &&
              !p.basename(f.name).startsWith('.') &&
              !f.name.contains('__MACOSX'))
            f,
      ]..sort((a, b) => _natural(a.name.toLowerCase(), b.name.toLowerCase()));
      if (entries.isEmpty) throw const ImportException('No images found in this archive.');

      final dir = Directory(pagesDir)..createSync(recursive: true);
      for (var i = 0; i < entries.length; i++) {
        final bytes = entries[i].readBytes();
        if (bytes == null) continue;
        final ext = p.extension(entries[i].name).toLowerCase();
        File(p.join(dir.path, '${i.toString().padLeft(4, '0')}$ext')).writeAsBytesSync(bytes);
      }
      return entries.length;
    } finally {
      await input.close();
    }
  }

  /// Natural order so "page2" sorts before "page10".
  static int _natural(String a, String b) {
    final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
    final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
    for (var i = 0; i < ra.length && i < rb.length; i++) {
      final nx = int.tryParse(ra[i]);
      final ny = int.tryParse(rb[i]);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : ra[i].compareTo(rb[i]);
      if (c != 0) return c;
    }
    return ra.length.compareTo(rb.length);
  }

  /// Sorted page files of an already extracted comic.
  static List<File> pages(Directory pagesDir) {
    if (!pagesDir.existsSync()) return const [];
    return pagesDir.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
  }
}
