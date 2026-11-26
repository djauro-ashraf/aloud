import 'dart:async';

import 'package:flutter/services.dart';

/// Something other apps handed to Aloud ("Share" / "Open with").
final class SharedItem {
  const SharedItem.text(String this.text)
      : path = null,
        name = null;
  const SharedItem.file({required String this.path, required String this.name}) : text = null;

  final String? text;

  /// Absolute path of a copy inside the app's cache.
  final String? path;
  final String? name;

  bool get isText => text != null;

  static SharedItem? fromMap(Map<Object?, Object?> m) {
    final text = m['text'] as String?;
    if (text != null && text.isNotEmpty) return SharedItem.text(text);
    final path = m['path'] as String?;
    final name = m['name'] as String?;
    if (path != null && name != null) return SharedItem.file(path: path, name: name);
    return null;
  }
}

/// The only place the app talks to custom Kotlin code.
///
/// Keeping every `MethodChannel` call here means the Dart side of the
/// native contract is documented (and mockable) in one file.
///
/// Native contract (see `android/app/src/main/kotlin/.../MainActivity.kt`):
///  * `takeSharedItems()` → `List<Map>` of `{text}` or `{path, name}`; clears
///    the pending items.
///  * `extractTarBz2({archive, dest})` → `true`; streams
///    `extractProgress(bytesRead)` calls back while running.
///  * native → Dart: `sharedItemsAvailable()` when a new share arrives while
///    the app is already running.
final class NativeBridge {
  NativeBridge() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('dev.aloud/native');

  final _shared = StreamController<void>.broadcast();
  void Function(int bytes)? _progress;

  /// Fires when new shared items are waiting; call [takeSharedItems].
  Stream<void> get sharedItemsAvailable => _shared.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'sharedItemsAvailable':
        _shared.add(null);
      case 'extractProgress':
        _progress?.call((call.arguments as num).toInt());
    }
    return null;
  }

  Future<List<SharedItem>> takeSharedItems() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('takeSharedItems') ?? const [];
      return [for (final m in raw) ?SharedItem.fromMap(m)];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Extracts a `.tar.bz2` on a native background thread (large archives
  /// would exhaust Dart's memory).
  Future<void> extractTarBz2(String archive, String dest, {void Function(int bytes)? onProgress}) async {
    _progress = onProgress;
    try {
      await _channel.invokeMethod<bool>('extractTarBz2', {'archive': archive, 'dest': dest});
    } finally {
      _progress = null;
    }
  }
}
