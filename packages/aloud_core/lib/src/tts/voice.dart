/// Speech back-ends the app can use.
enum EngineKind {
  /// The phone's built-in text-to-speech service. Free, instant, offline.
  system('Device voice'),

  /// Microsoft Edge neural voices. Online, very natural.
  edge('Edge neural (online)'),

  /// On-device neural voices (Sherpa-ONNX: Kokoro / Piper). Offline.
  sherpa('Offline neural'),

  /// Neural voices rendered on your own PC over the local network.
  pc('PC server');

  const EngineKind(this.label);
  final String label;

  /// Engines that produce audio files (vs. speaking directly).
  bool get producesAudio => this != system;
}

/// One selectable voice.
final class VoiceInfo {
  const VoiceInfo({
    required this.engine,
    required this.id,
    required this.name,
    this.locale = '',
    this.gender,
    this.detail = '',
  });

  final EngineKind engine;

  /// Engine-specific identifier (Edge short name, Sherpa catalog id, …).
  final String id;
  final String name;

  /// BCP-47, e.g. `en-US`.
  final String locale;
  final String? gender;
  final String detail;

  /// Globally unique key, safe in file names: `edge:en-US-JennyNeural`.
  String get key => '${engine.name}:$id';

  String get language => locale.split(RegExp('[-_]')).first.toLowerCase();

  Map<String, Object?> toJson() => {
        'engine': engine.name,
        'id': id,
        'name': name,
        'locale': locale,
        if (gender != null) 'gender': gender,
        'detail': detail,
      };

  static VoiceInfo fromJson(Map<String, Object?> j) => VoiceInfo(
        engine: EngineKind.values.asNameMap()[j['engine']] ?? EngineKind.system,
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        locale: (j['locale'] as String?) ?? '',
        gender: j['gender'] as String?,
        detail: (j['detail'] as String?) ?? '',
      );

  /// Parses a [key] back to (engine, id).
  static (EngineKind, String)? parseKey(String key) {
    final i = key.indexOf(':');
    if (i <= 0) return null;
    final engine = EngineKind.values.asNameMap()[key.substring(0, i)];
    return engine == null ? null : (engine, key.substring(i + 1));
  }

  @override
  bool operator ==(Object other) => other is VoiceInfo && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
