import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'clip_backend.dart';
import 'sherpa_models.dart';
import 'speech_backend.dart';

/// Everything needed to load one model in the worker isolate. Plain data so
/// it can cross the isolate boundary.
final class SherpaSpec {
  const SherpaSpec({
    required this.dir,
    required this.kokoro,
    required this.threads,
    required this.noise,
    required this.noiseW,
  });

  final String dir;
  final bool kokoro;
  final int threads;
  final double noise;
  final double noiseW;

  String get id => '$dir|$kokoro|$threads|$noise|$noiseW';

  List<Object?> toMessage() => [dir, kokoro, threads, noise, noiseW];
  static SherpaSpec fromMessage(List<Object?> m) => SherpaSpec(
        dir: m[0]! as String,
        kokoro: m[1]! as bool,
        threads: m[2]! as int,
        noise: (m[3]! as num).toDouble(),
        noiseW: (m[4]! as num).toDouble(),
      );
}

/// Entry point of the worker isolate. Model loading and inference are CPU
/// heavy and block for hundreds of milliseconds; doing them on the UI isolate
/// would freeze the interface.
void _sherpaWorkerMain(List<Object?> args) {
  final toMain = args[0]! as SendPort;
  final spec = SherpaSpec.fromMessage(args[1]! as List<Object?>);
  final inbox = ReceivePort();
  sherpa.OfflineTts? tts;
  try {
    sherpa.initBindings();
    final d = spec.dir;
    final model = spec.kokoro
        ? sherpa.OfflineTtsModelConfig(
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: '$d/model.onnx',
              voices: '$d/voices.bin',
              tokens: '$d/tokens.txt',
              dataDir: '$d/espeak-ng-data',
            ),
            numThreads: spec.threads,
            debug: false,
          )
        : sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: '$d/model.onnx',
              tokens: '$d/tokens.txt',
              dataDir: '$d/espeak-ng-data',
              noiseScale: spec.noise,
              noiseScaleW: spec.noiseW,
            ),
            numThreads: spec.threads,
            debug: false,
          );
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: model));
    toMain.send(['ready', inbox.sendPort, tts.numSpeakers]);
  } catch (e) {
    toMain.send(['error', '$e']);
    return;
  }

  inbox.listen((Object? msg) {
    final m = msg! as List<Object?>;
    if (m[0] == 'close') {
      tts?.free();
      inbox.close();
      return;
    }
    // ['synth', id, text, speakerId]
    final id = m[1]! as int;
    try {
      // Speed is applied at playback, so the cached audio is speed-independent.
      final audio = tts!.generate(text: m[2]! as String, sid: m[3]! as int, speed: 1.0);
      final wav = WavCodec.encodeFloat(audio.samples, audio.sampleRate);
      toMain.send(['audio', id, TransferableTypedData.fromList([wav])]);
    } catch (e) {
      toMain.send(['fail', id, '$e']);
    }
  });
}

/// Handle to a running worker isolate with one loaded model.
final class SherpaWorker {
  SherpaWorker._(this.spec, this._isolate, this._toWorker, this._fromWorker, this.speakerCount);

  final SherpaSpec spec;
  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final int speakerCount;

  final _pending = <int, Completer<Uint8List>>{};
  int _nextId = 0;

  static Future<SherpaWorker> start(SherpaSpec spec) async {
    final fromWorker = ReceivePort();
    final ready = Completer<List<Object?>>();
    SherpaWorker? worker;
    fromWorker.listen((Object? msg) {
      final m = msg! as List<Object?>;
      if (!ready.isCompleted) {
        ready.complete(m);
      } else {
        worker?._onMessage(m);
      }
    });
    final iso = await Isolate.spawn(_sherpaWorkerMain, [fromWorker.sendPort, spec.toMessage()]);
    final first = await ready.future.timeout(const Duration(seconds: 90), onTimeout: () {
      return <Object?>['error', 'Loading the voice model timed out.'];
    });
    if (first[0] != 'ready') {
      iso.kill(priority: Isolate.immediate);
      fromWorker.close();
      throw SpeechException('Offline voice failed to load: ${first.length > 1 ? first[1] : 'unknown error'}',
          retryable: false);
    }
    return worker = SherpaWorker._(spec, iso, first[1]! as SendPort, fromWorker, (first[2]! as num).toInt());
  }

  void _onMessage(Object? msg) {
    final m = msg! as List<Object?>;
    final id = m[1]! as int;
    final c = _pending.remove(id);
    if (c == null) return;
    if (m[0] == 'audio') {
      c.complete((m[2]! as TransferableTypedData).materialize().asUint8List());
    } else {
      c.completeError(SpeechException('Offline voice failed: ${m[2]}'));
    }
  }

  Future<Uint8List> synth(String text, int speakerId) {
    final id = _nextId++;
    final c = _pending[id] = Completer<Uint8List>();
    _toWorker.send(['synth', id, text, speakerId]);
    return c.future.timeout(const Duration(seconds: 60), onTimeout: () {
      _pending.remove(id);
      throw const SpeechException('Offline voice took too long to respond.');
    });
  }

  Future<void> close() async {
    _toWorker.send(['close']);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const SpeechException('Voice closed.', retryable: false));
    }
    _pending.clear();
    // Give the isolate a moment to free native memory before the hard kill.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _fromWorker.close();
  }
}

/// On-device neural voices as a [ClipSynthesizer].
///
/// Keeps at most one model in memory: switching voices (or changing thread
/// count / noise settings) restarts the worker.
final class SherpaSynthesizer implements ClipSynthesizer {
  SherpaSynthesizer({
    required this.models,
    required this.threads,
    required this.noise,
    required this.noiseW,
  });

  final SherpaModelManager models;
  final int Function() threads;
  final double Function() noise;
  final double Function() noiseW;

  SherpaWorker? _worker;
  Future<SherpaWorker>? _starting;

  @override
  String get extension => 'wav';

  @override
  Future<Uint8List> synthesize(String text, VoiceInfo voice) async {
    final entry = SherpaCatalog.byId(voice.id);
    if (entry == null) throw SpeechException('Unknown offline voice "${voice.id}".', retryable: false);
    if (!models.isInstalled(entry)) {
      throw SpeechException('The offline voice "${entry.name}" is not downloaded yet.', retryable: false);
    }
    final spec = SherpaSpec(
      dir: models.dirFor(entry).path,
      kokoro: entry.family == SherpaFamily.kokoro,
      threads: threads(),
      noise: noise(),
      noiseW: noiseW(),
    );
    final worker = await _ensure(spec);
    final speaker = _speakerFor(voice.id, entry, worker.speakerCount);
    return worker.synth(text, speaker);
  }

  int _speakerFor(String voiceId, SherpaVoice entry, int speakerCount) {
    // Multi-speaker Piper voices are addressed as `piper_id#spk42`.
    final m = RegExp(r'#spk(\d+)$').firstMatch(voiceId);
    final requested = m == null ? entry.speakerId : int.parse(m.group(1)!);
    return requested.clamp(0, speakerCount > 0 ? speakerCount - 1 : 0);
  }

  Future<SherpaWorker> _ensure(SherpaSpec spec) async {
    final current = _worker;
    if (current != null && current.spec.id == spec.id) return current;
    return _starting ??= () async {
      try {
        await _worker?.close();
        _worker = null;
        final w = await SherpaWorker.start(spec);
        _worker = w;
        return w;
      } finally {
        _starting = null;
      }
    }();
  }

  Future<void> dispose() async {
    await _worker?.close();
    _worker = null;
  }
}
