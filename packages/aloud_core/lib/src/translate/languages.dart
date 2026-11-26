/// A translation/reading language.
final class Language {
  const Language(this.code, this.name);

  final String code;
  final String name;
}

abstract final class Languages {
  static const all = <Language>[
    Language('en', 'English'),
    Language('es', 'Spanish'),
    Language('fr', 'French'),
    Language('de', 'German'),
    Language('it', 'Italian'),
    Language('pt', 'Portuguese'),
    Language('nl', 'Dutch'),
    Language('ru', 'Russian'),
    Language('uk', 'Ukrainian'),
    Language('pl', 'Polish'),
    Language('tr', 'Turkish'),
    Language('ar', 'Arabic'),
    Language('hi', 'Hindi'),
    Language('bn', 'Bengali'),
    Language('ur', 'Urdu'),
    Language('id', 'Indonesian'),
    Language('vi', 'Vietnamese'),
    Language('th', 'Thai'),
    Language('zh', 'Chinese'),
    Language('ja', 'Japanese'),
    Language('ko', 'Korean'),
  ];

  static String nameOf(String code) {
    final base = code.split(RegExp('[-_]')).first.toLowerCase();
    for (final l in all) {
      if (l.code == base) return l.name;
    }
    return code;
  }

  /// Rough script-based guess for unlabeled text, or `null` if unsure.
  static String? detect(String text) {
    var latin = 0, cjk = 0, kana = 0, hangul = 0, cyr = 0, arab = 0, deva = 0, other = 0;
    for (final r in text.runes.take(600)) {
      if (r < 0x250) {
        if (String.fromCharCode(r).toLowerCase() != String.fromCharCode(r).toUpperCase()) latin++;
      } else if (r >= 0x4E00 && r <= 0x9FFF) {
        cjk++;
      } else if (r >= 0x3040 && r <= 0x30FF) {
        kana++;
      } else if (r >= 0xAC00 && r <= 0xD7AF) {
        hangul++;
      } else if (r >= 0x400 && r <= 0x4FF) {
        cyr++;
      } else if (r >= 0x600 && r <= 0x6FF) {
        arab++;
      } else if (r >= 0x900 && r <= 0x97F) {
        deva++;
      } else {
        other++;
      }
    }
    final total = latin + cjk + kana + hangul + cyr + arab + deva + other;
    if (total < 8) return null;
    final best = <String, int>{
      'latin': latin,
      'ja': kana,
      'zh': cjk,
      'ko': hangul,
      'ru': cyr,
      'ar': arab,
      'hi': deva,
    }.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value / total < 0.5) return null;
    if (kana > 0 && cjk > 0) return 'ja';
    return best.key == 'latin' ? null : best.key;
  }
}
