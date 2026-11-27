import 'package:aloud_core/aloud_core.dart';

/// One utterance to speak.
final class SpeechItem {
  const SpeechItem({required this.text, required this.voice, required this.key});

  final String text;
  final VoiceInfo voice;

  /// Content-addressed identity (voice + text + rules fingerprint). Two items
  /// with the same key sound identical, so audio can be cached and shared
  /// across documents.
  final String key;

  static String keyFor(VoiceInfo voice, String text, String fingerprint) =>
      Hashing.hex64('${voice.key}|$fingerprint|$text');
}

/// How a [SpeechBackend.speak] call ended.
enum SpeakOutcome { completed, cancelled }

/// A recoverable or fatal speech failure with a user-presentable message.
final class SpeechException implements Exception {
  const SpeechException(this.message, {this.retryable = true});

  final String message;

  /// Whether trying the same item again may help (network blips) as opposed
  /// to a configuration problem (missing model, bad token).
  final bool retryable;

  @override
  String toString() => message;
}

/// An engine that can tell *where* in the text it currently is.
///
/// Only the device voice really knows: it announces each word as it reaches
/// it. Neural engines synthesise a whole sentence into one audio clip and play
/// it back, so they have no honest word position and do not implement this —
/// the reader highlights those at sentence level rather than guessing.
abstract interface class SpokenOffsetSource {
  /// Character offsets into the text of the item being spoken, one per word
  /// the voice starts. Silent between items.
  Stream<int> get spokenOffsets;
}

/// Something that can speak text aloud.
///
/// Two families implement this: *direct* engines that speak through the OS
/// (system TTS), and *clip* engines that synthesise audio files (Edge,
/// offline neural, PC) which are cached and played by an audio player. The
/// narrator treats both identically.
abstract interface class SpeechBackend {
  EngineKind get kind;

  /// Whether [pause] freezes playback mid-sentence (so [resume] continues).
  /// If `false`, the narrator re-speaks the current sentence on resume.
  bool get pausesInPlace;

  /// Hint: these items will be spoken next, in order. Implementations should
  /// prepare them in the background and never throw.
  Future<void> prefetch(List<SpeechItem> upcoming);

  /// Speaks [item]. Completes when finished ([SpeakOutcome.completed]) or when
  /// [stop] interrupts it ([SpeakOutcome.cancelled]). Throws
  /// [SpeechException] on failure.
  Future<SpeakOutcome> speak(SpeechItem item, {required double speed});

  /// Synthesises [items] into the audio cache without playing them (offline
  /// preparation). Independent of [prefetch], so it keeps running while the
  /// user listens. Engines without audio output (system TTS) do nothing.
  Future<void> renderAhead(
    List<SpeechItem> items, {
    void Function(int done)? onProgress,
    bool Function()? isCancelled,
  });

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}
