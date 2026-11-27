/// A typed key into the settings map.
///
/// Settings are stored as one JSON-friendly map; each [Pref] knows its key,
/// type and default, so call sites stay type-safe without a class full of
/// boilerplate getters and `copyWith`s.
final class Pref<T> {
  const Pref(this.key, this.defaultValue);

  final String key;
  final T defaultValue;

  T read(Map<String, Object?> map) {
    final v = map[key];
    if (v is T) return v;
    if (defaultValue is double && v is num) return v.toDouble() as T;
    if (defaultValue is int && v is num) return v.toInt() as T;
    return defaultValue;
  }
}

/// Every user setting, grouped by area.
abstract final class Prefs {
  // Appearance
  static const themeMode = Pref<String>('themeMode', 'system'); // system|light|dark
  static const accent = Pref<int>('accent', 0xFF2F6F6A);

  // Reading
  static const readerTheme = Pref<String>('readerTheme', 'app'); // app|paper|sepia|night|black
  static const fontFamily = Pref<String>('fontFamily', 'serif'); // serif|sans|mono
  static const fontScale = Pref<double>('fontScale', 1.0);
  static const lineHeight = Pref<double>('lineHeight', 1.6);
  static const pageMargin = Pref<double>('pageMargin', 20);
  static const justify = Pref<bool>('justify', false);
  static const autoScroll = Pref<bool>('autoScroll', true);
  static const keepScreenOn = Pref<bool>('keepScreenOn', true);

  // Highlighting and tapping (see highlight.dart)
  static const highlightMode = Pref<String>('highlightMode', 'auto'); // auto|sentence|word|off
  static const wordStyle = Pref<String>('wordStyle', 'soft'); // soft|strong|underline
  static const tapToRead = Pref<String>('tapToRead', 'double'); // double|single|off
  static const pdfHighlightColor = Pref<int>('pdfHighlightColor', 0xFFE53935);
  static const pdfHighlightThickness = Pref<double>('pdfHighlightThickness', 3);
  static const pdfHighlightPadH = Pref<double>('pdfHighlightPadH', 2);
  static const pdfHighlightPadV = Pref<double>('pdfHighlightPadV', 3);
  static const pdfHighlightOffsetY = Pref<double>('pdfHighlightOffsetY', 0);
  static const seenTapHint = Pref<bool>('seenTapHint', false);

  // Web
  static const browserAutoNext = Pref<bool>('browserAutoNext', false);

  // Listening
  static const engine = Pref<String>('engine', 'system'); // EngineKind.name
  static const voiceKey = Pref<String>('voiceKey', '');
  static const speed = Pref<double>('speed', 1.0);
  static const paragraphPauseMs = Pref<int>('paragraphPauseMs', 350);
  static const sentencePauseMs = Pref<int>('sentencePauseMs', 80);
  static const autoNextSection = Pref<bool>('autoNextSection', true);
  static const autoNextDocument = Pref<bool>('autoNextDocument', false);
  static const prefetch = Pref<int>('prefetch', 3);
  static const normalizeText = Pref<bool>('normalizeText', true);
  static const expandAbbreviations = Pref<bool>('expandAbbreviations', true);
  static const spellAcronyms = Pref<bool>('spellAcronyms', true);
  static const fallbackToSystem = Pref<bool>('fallbackToSystem', true);
  static const sleepDefaultMinutes = Pref<int>('sleepDefaultMinutes', 30);

  // Engines
  static const edgeVoice = Pref<String>('edgeVoice', 'en-US-AriaNeural');
  static const systemVoice = Pref<String>('systemVoice', ''); // "name|locale"
  static const sherpaVoice = Pref<String>('sherpaVoice', 'kokoro_af');
  static const sherpaThreads = Pref<int>('sherpaThreads', 2);
  static const sherpaNoise = Pref<double>('sherpaNoise', 0.667);
  static const sherpaNoiseW = Pref<double>('sherpaNoiseW', 0.8);
  static const pcUrl = Pref<String>('pcUrl', '');
  static const pcVoice = Pref<String>('pcVoice', '');
  static const cacheLimitMb = Pref<int>('cacheLimitMb', 500);

  // Translation
  static const translateProvider = Pref<String>('translateProvider', 'mlkit');
  static const translateTarget = Pref<String>('translateTarget', 'en');

  // Onboarding
  static const askedNotifications = Pref<bool>('askedNotifications', false);

  // Library
  static const librarySort = Pref<String>('librarySort', 'recent');
  static const libraryGrid = Pref<bool>('libraryGrid', false);
}
