import 'dart:async';
import 'dart:io';

import 'package:aloud_core/aloud_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../core/platform/native_bridge.dart';
import '../../../data/storage/app_paths.dart';
import 'speech_backend.dart';

/// Cooperative cancellation for long operations.
final class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Downloads, validates and removes offline voice models.
///
/// Install is crash-safe: everything happens in a temp folder that is renamed
/// into place only after validation, so an interrupted install never leaves a
/// model that looks installed but is broken.
final class SherpaModelManager {
  SherpaModelManager(this._paths, this._bridge, {http.Client? client}) : _client = client ?? http.Client();

  final AppPaths _paths;
  final NativeBridge _bridge;
  final http.Client _client;

  Directory dirFor(SherpaVoice v) => Directory(p.join(_paths.modelsDir.path, v.modelFolder));

  bool isInstalled(SherpaVoice v) {
    final d = dirFor(v);
    return v.requiredFiles.every((name) {
      final path = p.join(d.path, name);
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    });
  }

  Future<void> install(
    SherpaVoice v, {
    void Function(double fraction, String status)? onProgress,
    CancelToken? cancel,
  }) async {
    if (isInstalled(v)) return;
    await _paths.modelsDir.create(recursive: true);
    final work = Directory(p.join(_paths.modelsDir.path, '.tmp_${v.modelFolder}'));
    final archive = File(p.join(_paths.modelsDir.path, '.dl_${v.modelFolder}.tar.bz2'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);

    try {
      // 1. Download (0–70 %)
      onProgress?.call(0, 'Downloading ${v.name}');
      await _download(Uri.parse(v.archiveUrl), archive, (f) => onProgress?.call(f * 0.7, 'Downloading ${v.name}'), cancel);

      // 2. Extract on a native thread (70–95 %)
      onProgress?.call(0.7, 'Unpacking');
      final total = await archive.length();
      await _bridge.extractTarBz2(
        archive.path,
        work.path,
        onProgress: (read) => onProgress?.call(0.7 + 0.25 * (read / (total == 0 ? 1 : total)).clamp(0.0, 1.0), 'Unpacking'),
      );
      if (cancel?.isCancelled ?? false) throw const SpeechException('Cancelled', retryable: false);

      // 3. Normalise + validate
      onProgress?.call(0.96, 'Verifying');
      final root = _modelRoot(work);
      await _normalise(root);
      for (final name in v.requiredFiles) {
        if (FileSystemEntity.typeSync(p.join(root.path, name)) == FileSystemEntityType.notFound) {
          throw SpeechException('The downloaded model is incomplete (missing $name).', retryable: false);
        }
      }

      // 4. Atomic swap into place
      final dest = dirFor(v);
      if (await dest.exists()) await dest.delete(recursive: true);
      await root.rename(dest.path);
      onProgress?.call(1, 'Ready');
    } finally {
      if (await archive.exists()) await archive.delete();
      if (await work.exists()) await work.delete(recursive: true);
    }
  }

  Future<void> uninstall(SherpaVoice v) async {
    final d = dirFor(v);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Size on disk of an installed model folder.
  Future<int> sizeOf(SherpaVoice v) async {
    final d = dirFor(v);
    if (!await d.exists()) return 0;
    var total = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<void> _download(Uri url, File dest, void Function(double) onFraction, CancelToken? cancel) async {
    final res = await _client.send(http.Request('GET', url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw SpeechException('Download failed (HTTP ${res.statusCode}).');
    }
    final total = res.contentLength ?? 0;
    var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in res.stream) {
        if (cancel?.isCancelled ?? false) throw const SpeechException('Cancelled', retryable: false);
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onFraction(received / total);
      }
    } finally {
      await sink.close();
    }
  }

  /// Archives wrap everything in one top-level folder; unwrap it.
  Directory _modelRoot(Directory extracted) {
    final children = extracted.listSync().where((e) => !p.basename(e.path).startsWith('.')).toList();
    if (children.length == 1 && children.first is Directory) return children.first as Directory;
    return extracted;
  }

  /// Piper ships `en_US-name-quality.onnx`; the engine config expects
  /// `model.onnx`.
  Future<void> _normalise(Directory root) async {
    final target = File(p.join(root.path, 'model.onnx'));
    if (await target.exists()) return;
    for (final e in root.listSync()) {
      if (e is File && e.path.endsWith('.onnx') && !e.path.endsWith('.onnx.json')) {
        await e.rename(target.path);
        return;
      }
    }
  }
}
