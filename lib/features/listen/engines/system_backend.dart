import 'dart:async';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_backend.dart';

/// Speaks through the phone's built-in text-to-speech service.
///
/// Always available, instant, works offline — which is why it is also the
/// automatic fallback when a network or neural engine fails.
final class SystemSpeechBackend implements SpeechBackend {
  SystemSpeechBackend() {
    _tts
      ..setCompletionHandler(() => _finish(SpeakOutcome.completed))
      ..setCancelHandler(() => _finish(SpeakOutcome.cancelled))
      ..setErrorHandler((Object? message) => _fail('$message'));
  }

  final FlutterTts _tts = FlutterTts();
  Completer<SpeakOutcome>? _current;
  String? _appliedVoice;
  bool _disposed = false;

  @override
  EngineKind get kind => EngineKind.system;

  /// The OS cannot freeze a running utterance reliably, so pausing stops it
  /// and the narrator re-speaks the sentence on resume.
  @override
  bool get pausesInPlace => false;

  void _finish(SpeakOutcome outcome) {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete(outcome);
  }

  void _fail(String message) {
    final c = _current;
    if (c != null && !c.isCompleted) c.completeError(SpeechException('Device voice failed: $message'));
  }

  @override
  Future<void> prefetch(List<SpeechItem> upcoming) async {}

  @override
  Future<void> renderAhead(
    List<SpeechItem> items, {
    void Function(int done)? onProgress,
    bool Function()? isCancelled,
  }) async {}

  /// Android maps rate 0.5 → normal speed and 1.0 → double speed.
  static double rateFor(double speed) => (speed * 0.5).clamp(0.05, 1.0);

  @override
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed}) async {
    if (_disposed) return SpeakOutcome.cancelled;
    await _applyVoice(item.voice);
    await _tts.setSpeechRate(rateFor(speed));
    final done = Completer<SpeakOutcome>();
    _current = done;
    try {
      final res = await _tts.speak(item.text);
      // Some engines answer 0 when they refuse the request.
      if (res == 0) throw const SpeechException('The device voice refused to speak.');
      return await done.future;
    } finally {
      if (identical(_current, done)) _current = null;
    }
  }

  Future<void> _applyVoice(VoiceInfo voice) async {
    if (_appliedVoice == voice.key) return;
    final parts = voice.id.split('|');
    final name = parts.first;
    final locale = parts.length > 1 ? parts[1] : voice.locale;
    if (name.isNotEmpty) {
      await _tts.setVoice({'name': name, 'locale': locale});
    } else if (locale.isNotEmpty) {
      await _tts.setLanguage(locale);
    }
    _appliedVoice = voice.key;
  }

  @override
  Future<void> pause() => stop();

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    _finish(SpeakOutcome.cancelled);
    await _tts.stop();
  }

  @override
  Future<void> setSpeed(double speed) => _tts.setSpeechRate(rateFor(speed));

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

  /// Installed voices as `name|locale` ids.
  Future<List<VoiceInfo>> listVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final out = <VoiceInfo>[];
      for (final v in raw) {
        if (v is! Map) continue;
        final name = '${v['name'] ?? ''}';
        final locale = '${v['locale'] ?? ''}'.replaceAll('_', '-');
        if (name.isEmpty) continue;
        out.add(VoiceInfo(
          engine: EngineKind.system,
          id: '$name|$locale',
          name: name,
          locale: locale,
          detail: v['network_required'] == '1' || v['network_required'] == true ? 'needs network' : 'offline',
        ));
      }
      out.sort((a, b) => a.locale.compareTo(b.locale));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static const defaultVoice = VoiceInfo(engine: EngineKind.system, id: '', name: 'Device default');
}
