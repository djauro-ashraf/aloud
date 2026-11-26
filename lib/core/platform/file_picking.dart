import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// A picked document copied into the app's temp folder.
final class PickedFile {
  const PickedFile({required this.path, required this.name});

  final String path;
  final String name;
}

/// The only place that touches the `file_picker` package.
///
/// Android hands back content:// URIs, so each file is streamed into a temp
/// file (never loaded into memory) and callers get ordinary paths.
abstract final class FilePort {
  static Future<List<PickedFile>> pickDocuments(
    Directory tempDir, {
    required List<String> extensions,
  }) async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    await tempDir.create(recursive: true);
    final out = <PickedFile>[];
    for (final f in picked) {
      final dest = File(p.join(tempDir.path, '${DateTime.now().microsecondsSinceEpoch}_${f.name}'));
      final sink = dest.openWrite();
      try {
        await sink.addStream(f.readAsByteStream());
      } finally {
        await sink.close();
      }
      out.add(PickedFile(path: dest.path, name: f.name));
    }
    return out;
  }
}
