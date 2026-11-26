import 'package:aloud_core/aloud_core.dart';

import 'speech_backend.dart';

/// Wraps a primary engine with an automatic fallback (normally the device
/// voice) so listening never just stops because Wi-Fi dropped or a model
/// failed.
///
/// After [failureThreshold] consecutive failures the primary is considered
/// unhealthy and skipped for [cooldown], which avoids paying a slow timeout
/// on every sentence while offline.
final class FallbackSpeechBackend implements SpeechBackend {
  FallbackSpeechBackend({
    required this._primary,
    required this._fallback,
    required this._fallbackVoice,
    this.onFallback,
    this.failureThreshold = 2,
    this.cooldown = const Duration(seconds: 60),
    this.disposeFallback = true,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now;

  final SpeechBackend _primary;
  final SpeechBackend _fallback;
  final VoiceInfo Function() _fallbackVoice;
  final void Function(String reason)? onFallback;
  final int failureThreshold;
  final Duration cooldown;

  /// Set to false when the fallback is shared and owned elsewhere (the
  /// system TTS plugin allows only one live instance).
  final bool disposeFallback;
  final DateTime Function() _clock;

  late SpeechBackend _current = _primary;
  int _failures = 0;
  DateTime? _unhealthyUntil;

  @override
  EngineKind get kind => _primary.kind;

  @override
  bool get pausesInPlace => _current.pausesInPlace;

  bool get _primaryHealthy {
    final until = _unhealthyUntil;
    if (until == null) return true;
    if (_clock().isAfter(until)) {
      _unhealthyUntil = null;
      _failures = 0;
      return true;
    }
    return false;
  }

  @override
  Future<void> prefetch(List<SpeechItem> upcoming) async {
    if (_primaryHealthy) await _primary.prefetch(upcoming);
  }

  @override
  Future<void> renderAhead(
    List<SpeechItem> items, {
    void Function(int done)? onProgress,
    bool Function()? isCancelled,
  }) =>
      _primary.renderAhead(items, onProgress: onProgress, isCancelled: isCancelled);

  @override
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed}) async {
    if (_primaryHealthy) {
      _current = _primary;
      try {
        final outcome = await _primary.speak(item, speed: speed);
        _failures = 0;
        return outcome;
      } on SpeechException catch (e) {
        _failures++;
        if (e.retryable == false || _failures >= failureThreshold) {
          _unhealthyUntil = _clock().add(cooldown);
        }
        onFallback?.call(e.message);
      }
    }
    _current = _fallback;
    final voice = _fallbackVoice();
    return _fallback.speak(
      SpeechItem(text: item.text, voice: voice, key: item.key),
      speed: speed,
    );
  }

  @override
  Future<void> pause() => _current.pause();

  @override
  Future<void> resume() => _current.resume();

  @override
  Future<void> stop() async {
    await _primary.stop();
    await _fallback.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _primary.setSpeed(speed);
    await _fallback.setSpeed(speed);
  }

  @override
  Future<void> dispose() async {
    await _primary.dispose();
    if (disposeFallback) await _fallback.dispose();
  }
}
