/// Model families supported by the offline engine.
enum SherpaFamily { kokoro, piper }

/// One downloadable offline voice.
final class SherpaVoice {
  const SherpaVoice({
    required this.id,
    required this.name,
    required this.family,
    required this.archiveUrl,
    required this.sizeLabel,
    this.speakerId = 0,
    this.accent = '',
    this.speakerRange,
  });

  final String id;
  final String name;
  final SherpaFamily family;
  final String archiveUrl;
  final String sizeLabel;
  final int speakerId;
  final String accent;

  /// Inclusive speaker-id range for multi-speaker Piper models.
  final (int, int)? speakerRange;

  /// Voices that share one model download (all Kokoro voices) map to one
  /// folder; others get their own.
  String get modelFolder => family == SherpaFamily.kokoro ? SherpaCatalog.kokoroFolder : id;

  /// Files that must exist in the model folder for the install to be valid.
  List<String> get requiredFiles => family == SherpaFamily.kokoro
      ? const ['model.onnx', 'voices.bin', 'tokens.txt', 'espeak-ng-data']
      : const ['model.onnx', 'tokens.txt', 'espeak-ng-data'];
}

/// Static catalog of offline voices (ported from the original app).
abstract final class SherpaCatalog {
  static const kokoroFolder = 'kokoro_shared_model';

  static const _gh = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';
  static const _kokoro = '$_gh/kokoro-en-v0_19.tar.bz2';

  static SherpaVoice _k(String id, String name, int sid, String accent) => SherpaVoice(
        id: id,
        name: name,
        family: SherpaFamily.kokoro,
        archiveUrl: _kokoro,
        sizeLabel: '~350 MB',
        speakerId: sid,
        accent: accent,
      );

  static SherpaVoice _p(String id, String name, String file, String size, String accent,
          {(int, int)? speakers}) =>
      SherpaVoice(
        id: id,
        name: name,
        family: SherpaFamily.piper,
        archiveUrl: '$_gh/$file.tar.bz2',
        sizeLabel: size,
        accent: accent,
        speakerRange: speakers,
      );

  static final List<SherpaVoice> all = [
    _k('kokoro_af', 'Default', 0, 'American'),
    _k('kokoro_bella', 'Bella', 1, 'American'),
    _k('kokoro_nicole', 'Nicole', 2, 'American'),
    _k('kokoro_sarah', 'Sarah', 3, 'American'),
    _k('kokoro_sky', 'Sky', 4, 'American'),
    _k('kokoro_adam', 'Adam', 5, 'American'),
    _k('kokoro_michael', 'Michael', 6, 'American'),
    _k('kokoro_emma', 'Emma', 7, 'British'),
    _k('kokoro_isabella', 'Isabella', 8, 'British'),
    _k('kokoro_george', 'George', 9, 'British'),
    _k('kokoro_lewis', 'Lewis', 10, 'British'),
    _p('piper_ryan_high', 'Ryan (high)', 'vits-piper-en_US-ryan-high', '~65 MB', 'American'),
    _p('piper_lessac', 'Lessac (high)', 'vits-piper-en_US-lessac-high', '~65 MB', 'American'),
    _p('piper_ljspeech', 'LJ (high)', 'vits-piper-en_US-ljspeech-high', '~65 MB', 'American'),
    _p('piper_libritts_high', 'LibriTTS (high)', 'vits-piper-en_US-libritts-high', '~65 MB', 'American',
        speakers: (0, 903)),
    _p('piper_libritts_r', 'LibriTTS-R', 'vits-piper-en_US-libritts_r-medium', '~63 MB', 'American',
        speakers: (0, 903)),
    _p('piper_hfc_female', 'HFC Female', 'vits-piper-en_US-hfc_female-medium', '~63 MB', 'American'),
    _p('piper_glados_high', 'GLaDOS (high)', 'vits-piper-en_US-glados-high', '~65 MB', 'American'),
    _p('piper_amy', 'Amy (compact)', 'vits-piper-en_US-amy-low', '~6 MB', 'American'),
    _p('piper_kathleen', 'Kathleen (compact)', 'vits-piper-en_US-kathleen-low', '~6 MB', 'American'),
    _p('piper_cori', 'Cori (high)', 'vits-piper-en_GB-cori-high', '~65 MB', 'British'),
    _p('piper_dii_high', 'Dii (high)', 'vits-piper-en_GB-dii-high', '~65 MB', 'British'),
    _p('piper_jenny_dioco', 'Jenny', 'vits-piper-en_GB-jenny_dioco-medium', '~63 MB', 'British'),
    _p('piper_alba', 'Alba', 'vits-piper-en_GB-alba-medium', '~63 MB', 'Scottish'),
    _p('piper_southern_english_female', 'Southern English', 'vits-piper-en_GB-southern_english_female-low',
        '~6 MB', 'British'),
  ];

  static SherpaVoice? byId(String id) {
    final base = id.split('#spk').first;
    for (final v in all) {
      if (v.id == base) return v;
    }
    return null;
  }
}
