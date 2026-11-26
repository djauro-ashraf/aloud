import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';
import 'speech_backend.dart';

/// Turns text into an audio file's bytes. Implemented per engine.
abstract interface class ClipSynthesizer {
  /// File extension of the produced audio (`mp3`, `wav`).
  String get extension;

  /// Must throw [SpeechException] on failure.
  Future<Uint8List> synthesize(String text, VoiceInfo voice);
}

class _Slot {
  final AudioPlayer player = AudioPlayer();
  String? key;
  Future<void>? loading;
}

/// Speaks by synthesising clips (cache-first) and playing them with two
/// alternating players.
///
/// While one player speaks sentence N, the other already has sentence N+1
/// loaded, so sentence boundaries have no audible gap. Synthesis runs ahead
/// of playback ([prefetch]), hiding network/CPU latency.
final class ClipSpeechBackend implements SpeechBackend {
  ClipSpeechBackend({
    required this.kind,
    required ClipSynthesizer synthesizer,
    required this._cache,
    required this.cacheLimitBytes,
  })  : _synth = synthesizer;

  @override
  final EngineKind kind;
  final ClipSynthesizer _synth;
  final AudioCache _cache;
  final int cacheLimitBytes;

  final _slots = [_Slot(), _Slot()];
  _Slot? _active;
  final _inflight = <String, Future<File>>{};
  int _prefetchGen = 0;
  int _epoch = 0;
  Completer<SpeakOutcome>? _playing;
  bool _disposed = false;

  @override
  bool get pausesInPlace => true;

  Future<File> _file(SpeechItem item) {
    return _inflight[item.key] ??= () async {
      try {
        final cached = await _cache.lookup(item.key, _synth.extension);
        if (cached != null) return cached;
        final bytes = await _synth.synthesize(item.text, item.voice);
        final f = await _cache.store(item.key, _synth.extension, bytes);
        if (_cache.shouldTrim) unawaited(_cache.trim(cacheLimitBytes));
        return f;
      } finally {
        unawaited(Future<void>.microtask(() => _inflight.remove(item.key)));
      }
    }();
  }

  @override
  Future<void> prefetch(List<SpeechItem> upcoming) async {
    final gen = ++_prefetchGen;
    for (var i = 0; i < upcoming.length; i++) {
      if (gen != _prefetchGen || _disposed) return;
      try {
        final file = await _file(upcoming[i]);
        if (i == 0 && gen == _prefetchGen && !_disposed) await _preload(upcoming[0], file);
      } catch (_) {
        // Failures surface when the item is actually spoken.
      }
    }
  }

  Future<void> _preload(SpeechItem item, File file) async {
    final slot = _slots.firstWhere((s) => !identical(s, _active), orElse: () => _slots.first);
    if (slot.key == item.key) return;
    await slot.loading;
    if (slot.key == item.key || identical(slot, _active)) return;
    slot.key = null;
    final load = slot.player.setFilePath(file.path).then<void>((_) => slot.key = item.key);
    slot.loading = load.catchError((Object _) => slot.key = null);
    await slot.loading;
  }

  @override
  Future<void> renderAhead(
    List<SpeechItem> items, {
    void Function(int done)? onProgress,
    bool Function()? isCancelled,
  }) async {
    for (var i = 0; i < items.length; i++) {
      if (_disposed || (isCancelled?.call() ?? false)) return;
      await _file(items[i]); // throws SpeechException on failure
      onProgress?.call(i + 1);
    }
  }

  @override
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed}) async {
    final epoch = _epoch;
    final File file;
    try {
      file = await _file(item);
    } on SpeechException {
      rethrow;
    } catch (e) {
      throw SpeechException('Could not prepare audio: $e');
    }
    if (epoch != _epoch || _disposed) return SpeakOutcome.cancelled;

    var slot = _slots.where((s) => s.key == item.key).firstOrNull;
    slot ??= _slots.firstWhere((s) => !identical(s, _active), orElse: () => _slots.first);
    await slot.loading;
    if (epoch != _epoch) return SpeakOutcome.cancelled;

    try {
      if (slot.key != item.key) {
        slot.key = null;
        await slot.player.setFilePath(file.path);
        slot.key = item.key;
      }
      await slot.player.setSpeed(speed);
    } on PlayerException catch (e) {
      // A corrupt cache entry must never wedge playback: drop it and report.
      unawaited(file.delete().catchError((Object _) => file));
      throw SpeechException('Audio could not be played (${e.message ?? 'unknown error'}).');
    }
    if (epoch != _epoch) return SpeakOutcome.cancelled;

    _active = slot;
    final done = Completer<SpeakOutcome>();
    _playing = done;
    final sub = slot.player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && !done.isCompleted) done.complete(SpeakOutcome.completed);
    });
    try {
      unawaited(slot.player.play());
      return await done.future;
    } finally {
      await sub.cancel();
      slot.key = null;
      if (identical(_playing, done)) _playing = null;
    }
  }

  @override
  Future<void> pause() async => _active?.player.pause();

  @override
  Future<void> resume() async {
    final p = _active?.player;
    if (p != null) unawaited(p.play());
  }

  @override
  Future<void> stop() async {
    _epoch++;
    _prefetchGen++;
    final playing = _playing;
    if (playing != null && !playing.isCompleted) playing.complete(SpeakOutcome.cancelled);
    for (final s in _slots) {
      if (identical(s, _active)) {
        await s.player.stop();
        s.key = null;
      }
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    for (final s in _slots) {
      await s.player.setSpeed(speed);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    for (final s in _slots) {
      await s.player.dispose();
    }
  }
}
