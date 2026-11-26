import 'dart:convert';
import 'dart:io';

import 'package:aloud_core/aloud_core.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Reads and writes a document's parsed content (sections as JSON files).
///
/// One file per section keeps memory low: only the chapter being read is
/// ever loaded, however large the book is.
final class ContentStore {
  ContentStore(this._paths);

  final AppPaths _paths;

  File _toc(String docId) => File(p.join(_paths.docDir(docId).path, 'toc.json'));

  Future<void> writeSection(String docId, int index, ReaderSection s) async {
    final f = _paths.sectionFile(docId, index);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(s.toJson()), flush: false);
  }

  Future<void> writeAll(String docId, List<ReaderSection> sections) async {
    for (var i = 0; i < sections.length; i++) {
      await writeSection(docId, i, sections[i]);
    }
    await writeToc(docId, [for (final s in sections) s.title]);
  }

  /// Appends sections after the existing ones (web novels).
  Future<int> append(String docId, List<ReaderSection> sections) async {
    final titles = await readToc(docId);
    for (var i = 0; i < sections.length; i++) {
      await writeSection(docId, titles.length + i, sections[i]);
    }
    await writeToc(docId, [...titles, for (final s in sections) s.title]);
    return titles.length + sections.length;
  }

  Future<ReaderSection> readSection(String docId, int index) async {
    final f = _paths.sectionFile(docId, index);
    if (!await f.exists()) return const ReaderSection(title: '', blocks: []);
    final raw = await f.readAsString();
    return ReaderSection.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
  }

  Future<void> writeToc(String docId, List<String> titles) async {
    final f = _toc(docId);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(titles));
  }

  Future<List<String>> readToc(String docId) async {
    final f = _toc(docId);
    if (!await f.exists()) return const [];
    final raw = jsonDecode(await f.readAsString()) as List<Object?>;
    return [for (final t in raw) t! as String];
  }

  /// Absolute path of a stored image (`images/<name>`).
  File image(String docId, String ref) => File(p.join(_paths.docDir(docId).path, ref));
}
