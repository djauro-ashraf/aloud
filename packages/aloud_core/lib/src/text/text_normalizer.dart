import 'number_words.dart';

/// Tunables for [TextNormalizer].
final class NormalizerOptions {
  const NormalizerOptions({
    this.language = 'en',
    this.expandNumbers = true,
    this.expandAbbreviations = true,
    this.spellAcronyms = true,
    this.stripMarkup = true,
  });

  /// BCP-47 language code. English-specific expansions only run for `en*`.
  final String language;
  final bool expandNumbers;
  final bool expandAbbreviations;
  final bool spellAcronyms;
  final bool stripMarkup;

  bool get isEnglish => language.isEmpty || language.toLowerCase().startsWith('en');

  /// Stable string used in audio-cache keys.
  String get fingerprint =>
      '${isEnglish ? 'en' : language}'
      '${expandNumbers ? 'n' : '-'}${expandAbbreviations ? 'a' : '-'}'
      '${spellAcronyms ? 's' : '-'}${stripMarkup ? 'm' : '-'}';
}

/// Converts display text into text that speech engines read naturally.
///
/// Pure and deterministic. The *display* text never changes — only what is
/// sent to the voice. Step order matters: each step assumes the earlier ones
/// have already run (e.g. currency before plain integers).
abstract final class TextNormalizer {
  /// Bump when behaviour changes so cached audio is regenerated.
  static const version = 'norm-3';

  static String normalize(String input, {NormalizerOptions options = const NormalizerOptions()}) {
    var t = _unifyUnicode(input);
    if (t.trim().isEmpty) return '';

    t = t.replaceAll(_url, ' ');
    t = t.replaceAll(_email, 'email address');
    if (options.stripMarkup) t = _stripMarkup(t);

    if (options.isEnglish) {
      if (options.expandNumbers) {
        t = t.replaceAllMapped(_thousands, (m) => m[0]!.replaceAll(',', ''));
        t = _currency(t);
        t = _times(t);
        t = _isoDates(t);
        t = _temperatures(t);
        t = _units(t);
        t = _percent(t);
        t = t.replaceAllMapped(_ordinal, (m) => NumberWords.ordinal(int.parse(m[1]!)));
        t = _romanHeadings(t);
      }
      if (options.expandAbbreviations) t = _abbreviations(t);
      if (options.expandNumbers) {
        t = _years(t);
        t = _decimals(t);
        t = _integers(t);
      }
      if (options.spellAcronyms) t = _acronyms(t);
    }

    t = t.replaceAll(_emoticon, ' ');
    t = _ellipsis(t);
    t = t.replaceAllMapped(_multiPunct, (m) => m[1]!);
    t = t.replaceAll(RegExp(r'[#*_~`|\\^]+'), ' ');
    t = t.replaceAllMapped(_spaceBeforePunct, (m) => m[1]!);
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return t;
  }

  // ── Regexes (compiled once) ────────────────────────────────────────────

  static final _url = RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false);
  static final _email = RegExp(r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+');
  static final _thousands = RegExp(r'(?<![\d,.])\d{1,3}(?:,\d{3})+(?![\d,])');
  static final _currencyRx = RegExp(
    r'([$£€¥])\s?(\d+(?:\.\d+)?)(?:\s?(thousand|million|billion|trillion|k|m|bn|b)\b)?',
    caseSensitive: false,
  );
  static final _timeRx = RegExp(r'\b(\d{1,2}):(\d{2})(?!\d)(?:\s?([ap])\.?m\.?\b)?', caseSensitive: false);
  static final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
  static final _tempRx = RegExp(r'(-?\d+(?:\.\d+)?)\s?°\s?([CcFf])\b');
  static final _unitRx = RegExp(
    r'\b(\d+(?:\.\d+)?)\s?(km/h|kph|mph|km|cm|mm|mg|kg|ml|lbs|lb|oz|mi|ft|kb|mb|gb|tb|khz|mhz|ghz|hz)\b',
    caseSensitive: false,
  );
  static final _percentRx = RegExp(r'(\d+(?:\.\d+)?)\s?%');
  static final _ordinal = RegExp(r'\b(\d{1,3})(?:st|nd|rd|th)\b', caseSensitive: false);
  static final _romanHeading = RegExp(
    r'\b(Chapter|Part|Book|Volume|Act|Scene|Section|Appendix|Canto|Stave)\s+([IVXLCDM]{1,7})\b',
  );
  static final _decimalRx = RegExp(r'(?<![\d.])(\d+)\.(\d+)(?![\d.])');
  static final _integerRx = RegExp(r'(?<![\w.])\d{1,15}(?![\w])');
  static final _monthYear = RegExp(
    r'\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\.?\s+(\d{4})\b',
  );
  static final _yearAfterPreposition = RegExp(
    r'\b(in|since|from|until|till|by|during|of|year|circa|before|after|between|through|to)\s+(1[0-9]{3}|20[0-9]{2})\b(?!\s?(?:people|dollars|years|miles|men|times|words|items|units|km|kg))',
    caseSensitive: false,
  );
  static final _emoticon = RegExp(r"(?<=\s|^)(?:[:;=8][\-o*']?[)(\]\[DdPpOo3|/\\]|<3|XD|xD)(?=\s|$)");
  static final _multiPunct = RegExp(r'([!?])[!?]+');
  static final _spaceBeforePunct = RegExp(r'\s+([,.;:!?])');
  static final _acronymRx = RegExp(r'\b[A-Z][A-Z0-9]{1,6}\b');

  // ── Steps ──────────────────────────────────────────────────────────────

  static String _unifyUnicode(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      switch (r) {
        case 0x2018 || 0x2019 || 0x201B || 0x2032:
          b.write("'");
        case 0x201C || 0x201D || 0x201F || 0x2033:
          b.write('"');
        case 0x2013:
          b.write('-');
        case 0x2014 || 0x2015:
          b.write(' — ');
        case 0x00A0 || 0x2007 || 0x202F || 0x2009 || 0x200A:
          b.write(' ');
        case 0x200B || 0x200C || 0x200D || 0x2060 || 0xFEFF || 0x00AD:
          break;
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static String _stripMarkup(String t) {
    var s = t;
    s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1]!);
    s = s.replaceAllMapped(RegExp(r'\*([^*\n]+)\*'), (m) => m[1]!);
    s = s.replaceAllMapped(RegExp(r'(?<!\w)_([^_\n]{1,80})_(?!\w)'), (m) => m[1]!);
    s = s.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => m[1]!);
    s = s.replaceAll(RegExp(r'\[\d{1,3}\]'), ' ');
    s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+'), '');
    return s;
  }

  static const _scaleWords = {
    'k': 'thousand', 'm': 'million', 'b': 'billion', 'bn': 'billion',
    'thousand': 'thousand', 'million': 'million', 'billion': 'billion',
    'trillion': 'trillion',
  };

  static String _currency(String t) => t.replaceAllMapped(_currencyRx, (m) {
        final sym = m[1]!;
        final amount = m[2]!;
        final scale = m[3] == null ? null : _scaleWords[m[3]!.toLowerCase()];
        final (major, minor) = switch (sym) {
          r'$' => ('dollar', 'cent'),
          '£' => ('pound', 'penny'),
          '€' => ('euro', 'cent'),
          _ => ('yen', 'sen'),
        };
        final parts = amount.split('.');
        final whole = int.tryParse(parts[0]);
        if (whole == null) return m[0]!;
        if (scale != null) {
          final num = parts.length > 1
              ? '${NumberWords.cardinal(whole)} point ${NumberWords.digits(parts[1])}'
              : NumberWords.cardinal(whole);
          return '$num $scale ${major}s';
        }
        final cents = parts.length > 1 ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) : null;
        final majorWords = '${NumberWords.cardinal(whole)} ${_plural(major, whole)}';
        if (cents != null && cents > 0) {
          final minorName = minor == 'penny' && cents != 1 ? 'pence' : _plural(minor, cents);
          return '$majorWords and ${NumberWords.cardinal(cents)} $minorName';
        }
        return majorWords;
      });

  static String _plural(String word, int n) {
    if (n == 1) return word;
    return word == 'penny' ? 'pence' : '${word}s';
  }

  static String _times(String t) => t.replaceAllMapped(_timeRx, (m) {
        final h = int.parse(m[1]!);
        final min = int.parse(m[2]!);
        if (h > 24 || min > 59) return m[0]!;
        final suffix = m[3] == null ? '' : ' ${m[3]!.toLowerCase()} m';
        final hour = NumberWords.cardinal(h == 0 && m[3] == null ? 0 : h);
        if (min == 0) return m[3] == null ? '$hour o\'clock' : '$hour$suffix';
        final minutes = min < 10 ? 'oh ${NumberWords.cardinal(min)}' : NumberWords.cardinal(min);
        return '$hour $minutes$suffix';
      });

  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  static String _isoDates(String t) => t.replaceAllMapped(_isoDate, (m) {
        final y = int.parse(m[1]!);
        final mo = int.parse(m[2]!);
        final d = int.parse(m[3]!);
        if (mo < 1 || mo > 12 || d < 1 || d > 31) return m[0]!;
        return '${_months[mo]} ${NumberWords.ordinal(d)}, ${NumberWords.year(y)}';
      });

  static String _temperatures(String t) => t.replaceAllMapped(_tempRx, (m) {
        final value = _spokenNumber(m[1]!);
        final scale = m[2]!.toLowerCase() == 'c' ? 'Celsius' : 'Fahrenheit';
        return '$value degrees $scale';
      });

  static const _unitNames = {
    'km': ('kilometer', 'kilometers'), 'cm': ('centimeter', 'centimeters'),
    'mm': ('millimeter', 'millimeters'), 'mg': ('milligram', 'milligrams'),
    'kg': ('kilogram', 'kilograms'), 'ml': ('milliliter', 'milliliters'),
    'lb': ('pound', 'pounds'), 'lbs': ('pound', 'pounds'),
    'oz': ('ounce', 'ounces'), 'mi': ('mile', 'miles'), 'ft': ('foot', 'feet'),
    'mph': ('mile per hour', 'miles per hour'),
    'kph': ('kilometer per hour', 'kilometers per hour'),
    'km/h': ('kilometer per hour', 'kilometers per hour'),
    'kb': ('kilobyte', 'kilobytes'), 'mb': ('megabyte', 'megabytes'),
    'gb': ('gigabyte', 'gigabytes'), 'tb': ('terabyte', 'terabytes'),
    'hz': ('hertz', 'hertz'), 'khz': ('kilohertz', 'kilohertz'),
    'mhz': ('megahertz', 'megahertz'), 'ghz': ('gigahertz', 'gigahertz'),
  };

  static String _units(String t) => t.replaceAllMapped(_unitRx, (m) {
        final names = _unitNames[m[2]!.toLowerCase()];
        if (names == null) return m[0]!;
        final raw = m[1]!;
        final one = raw == '1' || raw == '1.0';
        return '${_spokenNumber(raw)} ${one ? names.$1 : names.$2}';
      });

  static String _percent(String t) =>
      t.replaceAllMapped(_percentRx, (m) => '${_spokenNumber(m[1]!)} percent');

  static String _romanHeadings(String t) => t.replaceAllMapped(_romanHeading, (m) {
        final v = _roman(m[2]!);
        return v == null ? m[0]! : '${m[1]} ${NumberWords.cardinal(v)}';
      });

  static int? _roman(String s) {
    const values = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
    var total = 0;
    for (var i = 0; i < s.length; i++) {
      final v = values[s[i]];
      if (v == null) return null;
      final next = i + 1 < s.length ? values[s[i + 1]] ?? 0 : 0;
      total += v < next ? -v : v;
    }
    return total > 0 && total < 4000 ? total : null;
  }

  static final List<(RegExp, String)> _abbrevRules = [
    (RegExp(r'\bMrs\.'), 'Missus'),
    (RegExp(r'\bMr\.'), 'Mister'),
    (RegExp(r'\bMs\.'), 'Miss'),
    (RegExp(r'\bDr\.'), 'Doctor'),
    (RegExp(r'\bProf\.'), 'Professor'),
    (RegExp(r'\bJr\.'), 'Junior'),
    (RegExp(r'\bSr\.'), 'Senior'),
    (RegExp(r'\bSt\.(?=\s*\d)'), 'Street'),
    (RegExp(r'\bSt\.'), 'Saint'),
    (RegExp(r'\bMt\.'), 'Mount'),
    (RegExp(r'\bCapt\.', caseSensitive: false), 'Captain'),
    (RegExp(r'\bLt\.', caseSensitive: false), 'Lieutenant'),
    (RegExp(r'\bCol\.', caseSensitive: false), 'Colonel'),
    (RegExp(r'\bGen\.', caseSensitive: false), 'General'),
    (RegExp(r'\bSgt\.', caseSensitive: false), 'Sergeant'),
    (RegExp(r'\bCpl\.', caseSensitive: false), 'Corporal'),
    (RegExp(r'\bGov\.', caseSensitive: false), 'Governor'),
    (RegExp(r'\bSen\.', caseSensitive: false), 'Senator'),
    (RegExp(r'\bRep\.', caseSensitive: false), 'Representative'),
    (RegExp(r'\bRev\.', caseSensitive: false), 'Reverend'),
    (RegExp(r'\bDept\.', caseSensitive: false), 'Department'),
    (RegExp(r'\bCorp\.', caseSensitive: false), 'Corporation'),
    (RegExp(r'\bInc\.', caseSensitive: false), 'Incorporated'),
    (RegExp(r'\bLtd\.', caseSensitive: false), 'Limited'),
    (RegExp(r'\bNo\.(?=\s*\d)'), 'Number'),
    (RegExp(r'\bvs\.?(?=\s)', caseSensitive: false), 'versus'),
    (RegExp(r'\betc\.', caseSensitive: false), 'et cetera.'),
    (RegExp(r'\be\.g\.', caseSensitive: false), 'for example,'),
    (RegExp(r'\bi\.e\.', caseSensitive: false), 'that is,'),
    (RegExp(r'\bapprox\.', caseSensitive: false), 'approximately'),
    (RegExp(r'\ba\.m\.', caseSensitive: false), 'A M'),
    (RegExp(r'\bp\.m\.', caseSensitive: false), 'P M'),
  ];

  static String _abbreviations(String t) {
    var s = t;
    for (final (rx, replacement) in _abbrevRules) {
      s = s.replaceAll(rx, replacement);
    }
    return s;
  }

  static String _years(String t) {
    var s = t.replaceAllMapped(_monthYear, (m) {
      final y = int.parse(m[2]!);
      return '${m[1]} ${NumberWords.year(y)}';
    });
    s = s.replaceAllMapped(_yearAfterPreposition, (m) {
      return '${m[1]} ${NumberWords.year(int.parse(m[2]!))}';
    });
    return s;
  }

  static String _decimals(String t) => t.replaceAllMapped(_decimalRx, (m) {
        final whole = int.tryParse(m[1]!);
        if (whole == null) return m[0]!;
        return '${NumberWords.cardinal(whole)} point ${NumberWords.digits(m[2]!)}';
      });

  static String _integers(String t) => t.replaceAllMapped(_integerRx, (m) {
        final raw = m[0]!;
        if (raw.length > 1 && raw.startsWith('0')) return NumberWords.digits(raw);
        if (raw.length > 12) return NumberWords.digits(raw);
        final v = int.tryParse(raw);
        return v == null ? raw : NumberWords.cardinal(v);
      });

  /// "3.5" → "three point five"; "42" → "forty-two".
  static String _spokenNumber(String raw) {
    final negative = raw.startsWith('-');
    final body = negative ? raw.substring(1) : raw;
    final parts = body.split('.');
    final whole = int.tryParse(parts[0]) ?? 0;
    final words = parts.length > 1
        ? '${NumberWords.cardinal(whole)} point ${NumberWords.digits(parts[1])}'
        : NumberWords.cardinal(whole);
    return negative ? 'minus $words' : words;
  }

  // ── Acronyms ───────────────────────────────────────────────────────────

  /// Read as a word, never spelled out.
  static const _wordAcronyms = {
    'NASA', 'NATO', 'UNESCO', 'UNICEF', 'LASER', 'RADAR', 'SCUBA', 'AIDS',
    'OPEC', 'FIFA', 'OK', 'PIN', 'SIM', 'RAM', 'ROM', 'JPEG', 'GIF', 'WIFI',
    'LEGO', 'ASAP', 'SWAT', 'NAFTA', 'ISIS', 'COVID',
  };

  /// Always spelled out.
  static const _initialisms = {
    'FBI', 'CIA', 'NSA', 'USA', 'UK', 'UN', 'EU', 'TV', 'DVD', 'CD', 'PC',
    'GPS', 'DNA', 'RNA', 'AI', 'CEO', 'CFO', 'CTO', 'CPU', 'GPU', 'USB',
    'HTML', 'CSS', 'PDF', 'SMS', 'ID', 'VIP', 'HR', 'PR', 'IT', 'ER', 'ICU',
    'MRI', 'DIY', 'FAQ', 'ATM', 'BBC', 'CNN', 'NYC', 'LA', 'DC', 'USD',
    'EPUB', 'API', 'URL', 'HTTP', 'SQL', 'RPG', 'MMO', 'NPC', 'XP', 'HP',
    'MP', 'SSS', 'SS', 'GM', 'AC', 'DJ', 'MC', 'PS', 'RIP', 'TBH', 'LOL',
  };

  static String _acronyms(String t) {
    final letters = t.runes.where(_isLetterRune).length;
    if (letters == 0) return t;
    final upper = t.runes.where((r) => _isLetterRune(r) && _isUpperRune(r)).length;
    // Mostly-uppercase sentences are shouting or headings: read as words.
    if (letters >= 6 && upper / letters > 0.7) return t.toLowerCase();
    return t.replaceAllMapped(_acronymRx, (m) {
      final w = m[0]!;
      if (_wordAcronyms.contains(w)) return w;
      if (_initialisms.contains(w)) return _spell(w);
      if (RegExp(r'\d').hasMatch(w)) return w; // "R2D2", "B52" read fine as-is.
      if (w.length <= 3 && !RegExp('[AEIOU]').hasMatch(w)) return _spell(w);
      // Shouted word: lowercase for consistent pronunciation.
      return w.length >= 3 ? w.toLowerCase() : _spell(w);
    });
  }

  static String _spell(String w) => w.split('').join(' ');

  static bool _isLetterRune(int r) {
    final c = String.fromCharCode(r);
    return c.toLowerCase() != c.toUpperCase();
  }

  static bool _isUpperRune(int r) {
    final c = String.fromCharCode(r);
    return c == c.toUpperCase() && c != c.toLowerCase();
  }

  // ── Punctuation clean-up ───────────────────────────────────────────────

  static String _ellipsis(String t) {
    var s = t.replaceAll('…', '...');
    // Trailing ellipsis at the end of a sentence reads as a plain stop.
    s = s.replaceAll(RegExp(r'\.{2,}\s*$'), '.');
    s = s.replaceAll(RegExp(r'\.{2,}(?=["\x27)\]]*\s*$)'), '.');
    // Mid-sentence ellipsis becomes a short comma pause.
    s = s.replaceAll(RegExp(r'\s*\.{2,}\s*'), ', ');
    return s;
  }
}
