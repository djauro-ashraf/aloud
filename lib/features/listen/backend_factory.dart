import 'dart:async';

import 'package:aloud_core/aloud_core.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/prefs.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/storage/app_paths.dart';
import 'engines/audio_cache.dart';
import 'engines/clip_backend.dart';
import 'engines/edge_tts.dart';
import 'engines/fallback_backend.dart';
import 'engines/pc_server.dart';
import 'engines/sherpa_engine.dart';
import 'engines/sherpa_models.dart';
import 'engines/speech_backend.dart';
import 'engines/system_backend.dart';

/// Picks the voice to use for a given language from the user's settings.
///
/// Rule of thumb: honour the user's chosen voice, but when the text is in a
/// different language than that voice and the engine can speak the text's
/// language, switch automatically — a French novel should not be read by an
/// English voice just because that's the default.
abstract final class VoiceResolver {
  static EngineKind engineOf(Map<String, Object?> prefs) =>
      EngineKind.values.asNameMap()[Prefs.engine.read(prefs)] ?? EngineKind.system;

  static VoiceInfo resolve(Map<String, Object?> prefs, {String? language}) {
    final lang = language?.split(RegExp('[-_]')).first.toLowerCase();
    switch (engineOf(prefs)) {
      case EngineKind.system:
        final chosen = Prefs.systemVoice.read(prefs);
        if (chosen.isNotEmpty) {
          final locale = chosen.split('|').elementAtOrNull(1) ?? '';
          final voiceLang = locale.split(RegExp('[-_]')).first.toLowerCase();
          if (lang == null || voiceLang == lang) {
            return VoiceInfo(engine: EngineKind.system, id: chosen, name: chosen.split('|').first, locale: locale);
          }
        }
        // No voice chosen or language mismatch: let the OS pick by language.
        return VoiceInfo(engine: EngineKind.system, id: '|${lang ?? ''}', name: 'Device default', locale: lang ?? '');
      case EngineKind.edge:
        final chosen = EdgeCatalog.byId(Prefs.edgeVoice.read(prefs)) ??
            VoiceInfo(
              engine: EngineKind.edge,
              id: Prefs.edgeVoice.read(prefs),
              name: Prefs.edgeVoice.read(prefs),
              locale: Prefs.edgeVoice.read(prefs).split('-').take(2).join('-'),
            );
        if (lang != null && chosen.language != lang) {
          final alt = EdgeCatalog.defaultFor(lang);
          if (alt != null) return alt;
        }
        return chosen;
      case EngineKind.sherpa:
        final id = Prefs.sherpaVoice.read(prefs);
        return VoiceInfo(
          engine: EngineKind.sherpa,
          id: id,
          name: SherpaCatalog.byId(id)?.name ?? id,
          locale: 'en',
        );
      case EngineKind.pc:
        final id = Prefs.pcVoice.read(prefs);
        return VoiceInfo(engine: EngineKind.pc, id: id, name: id.isEmpty ? 'PC voice' : id, locale: 'en');
    }
  }
}

/// Builds and caches the [SpeechBackend] for the engine selected in settings.
///
/// Only one backend is alive at a time; switching engines disposes the old
/// one. The phone's TTS plugin allows a single instance, so the system
/// backend is created once and shared as everyone's fallback.
final class BackendFactory {
  BackendFactory({
    required AppPaths paths,
    required this._cache,
    required NativeBridge bridge,
    required this._secrets,
    required this._prefs,
    this.onFallback,
  })  : models = SherpaModelManager(paths, bridge),
        edge = EdgeTtsClient();

  final AudioCache _cache;
  final SecretsStore _secrets;
  final Map<String, Object?> Function() _prefs;
  final void Function(String reason)? onFallback;

  final SherpaModelManager models;
  final EdgeTtsClient edge;
  final SystemSpeechBackend system = SystemSpeechBackend();

  SpeechBackend? _current;
  String? _signature;
  SherpaSynthesizer? _sherpa;
  PcServerClient? _pc;

  /// The backend for the current settings. Call [prepare] first whenever
  /// settings may have changed.
  SpeechBackend get current => _current ?? system;

  /// (Re)builds the backend if the relevant settings changed.
  Future<void> prepare() async {
    final prefs = _prefs();
    final engine = VoiceResolver.engineOf(prefs);
    final pcToken = engine == EngineKind.pc ? (await _secrets.read(SecretKeys.pcToken)) ?? '' : '';
    final sig = [
      engine.name,
      Prefs.fallbackToSystem.read(prefs),
      Prefs.cacheLimitMb.read(prefs),
      if (engine == EngineKind.pc) '${Prefs.pcUrl.read(prefs)}|$pcToken',
    ].join('|');
    if (sig == _signature && _current != null) return;

    final old = _current;
    _current = null;
    if (old != null && !identical(old, system)) unawaited(old.dispose());
    _signature = sig;

    if (engine == EngineKind.system) {
      _current = system;
      return;
    }
    final primary = _buildClip(engine, prefs, pcToken);
    _current = Prefs.fallbackToSystem.read(prefs)
        ? FallbackSpeechBackend(
            primary: primary,
            fallback: system,
            disposeFallback: false,
            fallbackVoice: () => VoiceInfo(
              engine: EngineKind.system,
              id: Prefs.systemVoice.read(_prefs()),
              name: 'Device voice',
            ),
            onFallback: onFallback,
          )
        : primary;
  }

  ClipSpeechBackend _buildClip(EngineKind engine, Map<String, Object?> prefs, String pcToken) {
    final limit = Prefs.cacheLimitMb.read(prefs) * 1024 * 1024;
    switch (engine) {
      case EngineKind.edge:
        return ClipSpeechBackend(
          kind: EngineKind.edge,
          synthesizer: EdgeSynthesizer(edge),
          cache: _cache,
          cacheLimitBytes: limit,
        );
      case EngineKind.sherpa:
        _sherpa ??= SherpaSynthesizer(
          models: models,
          threads: () => Prefs.sherpaThreads.read(_prefs()),
          noise: () => Prefs.sherpaNoise.read(_prefs()),
          noiseW: () => Prefs.sherpaNoiseW.read(_prefs()),
        );
        return ClipSpeechBackend(
          kind: EngineKind.sherpa,
          synthesizer: _sherpa!,
          cache: _cache,
          cacheLimitBytes: limit,
        );
      case EngineKind.pc:
        _pc?.close();
        _pc = PcServerClient(baseUrl: Prefs.pcUrl.read(prefs), token: pcToken);
        return ClipSpeechBackend(
          kind: EngineKind.pc,
          synthesizer: PcSynthesizer(
            _pc!,
            noise: () => Prefs.sherpaNoise.read(_prefs()),
            noiseW: () => Prefs.sherpaNoiseW.read(_prefs()),
          ),
          cache: _cache,
          cacheLimitBytes: limit,
        );
      case EngineKind.system:
        throw ArgumentError('System voice is not a clip engine.');
    }
  }

  // ── Voice preview ──────────────────────────────────────────────────────

  SpeechBackend? _previewing;

  /// Speaks [sample] with [voice] on a throwaway backend, independent of the
  /// reading session. Throws [SpeechException] if the voice can't speak.
  Future<void> preview(VoiceInfo voice, String sample) async {
    await stopPreview();
    final SpeechBackend backend;
    if (voice.engine == EngineKind.system) {
      backend = system;
    } else {
      final token = voice.engine == EngineKind.pc ? (await _secrets.read(SecretKeys.pcToken)) ?? '' : '';
      backend = _buildClip(voice.engine, _prefs(), token);
    }
    _previewing = backend;
    try {
      await backend.speak(
        SpeechItem(text: sample, voice: voice, key: SpeechItem.keyFor(voice, sample, 'preview')),
        speed: 1.0,
      );
    } finally {
      if (identical(_previewing, backend)) _previewing = null;
      if (!identical(backend, system)) unawaited(backend.dispose());
    }
  }

  Future<void> stopPreview() async {
    final b = _previewing;
    _previewing = null;
    await b?.stop();
  }

  Future<void> dispose() async {
    await _current?.dispose();
    await _sherpa?.dispose();
    _pc?.close();
    await system.dispose();
  }
}
