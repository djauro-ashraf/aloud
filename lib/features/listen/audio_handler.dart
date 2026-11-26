import 'package:audio_service/audio_service.dart';

/// Bridges the narrator to the Android media session: notification, lock
/// screen controls, headset buttons, Bluetooth and Android Auto.
///
/// The handler is created once at startup (before any document is open) and
/// the reading controller binds callbacks to it. It contains no playback
/// logic of its own.
final class AloudAudioHandler extends BaseAudioHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function()? onStop;

  static Future<AloudAudioHandler> init() => AudioService.init(
        builder: AloudAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.aloud.playback',
          androidNotificationChannelName: 'Listening',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_stat_aloud',
        ),
      );

  /// Shows what is being read and whether it is playing.
  void publish({
    required String title,
    required String subtitle,
    required bool playing,
    required bool active,
  }) {
    if (!active) {
      mediaItem.add(null);
      playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
      return;
    }
    mediaItem.add(MediaItem(id: title, title: title, artist: subtitle));
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.skipToNext, MediaAction.skipToPrevious},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
    ));
  }

  @override
  Future<void> play() async => onPlay?.call();

  @override
  Future<void> pause() async => onPause?.call();

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> stop() async {
    await onStop?.call();
    await super.stop();
  }
}
