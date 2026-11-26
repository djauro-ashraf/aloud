/// English number → spoken-words helpers.
///
/// Pure functions, no state. Used by the normaliser to make digits speakable
/// by engines that would otherwise read them inconsistently.
abstract final class NumberWords {
  static const _ones = [
    '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen',
  ];
  static const _tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty',
    'ninety',
  ];
  static const _scales = [
    (1000000000000, 'trillion'),
    (1000000000, 'billion'),
    (1000000, 'million'),
    (1000, 'thousand'),
  ];

  static const _ordinalIrregular = {
    'one': 'first',
    'two': 'second',
    'three': 'third',
    'five': 'fifth',
    'eight': 'eighth',
    'nine': 'ninth',
    'twelve': 'twelfth',
  };

  /// `1234` → `one thousand two hundred thirty-four`. Negative numbers are
  /// prefixed with "minus".
  static String cardinal(int n) {
    if (n == 0) return 'zero';
    if (n < 0) return 'minus ${cardinal(-n)}';
    final parts = <String>[];
    var rest = n;
    for (final (value, name) in _scales) {
      if (rest >= value) {
        parts.add('${_below1000(rest ~/ value)} $name');
        rest %= value;
      }
    }
    if (rest > 0) parts.add(_below1000(rest));
    return parts.join(' ');
  }

  /// `21` → `twenty-first`, `12` → `twelfth`.
  static String ordinal(int n) {
    final words = cardinal(n);
    final cut = words.lastIndexOf(RegExp(r'[ -]'));
    final head = cut < 0 ? '' : words.substring(0, cut + 1);
    final last = cut < 0 ? words : words.substring(cut + 1);
    final irregular = _ordinalIrregular[last];
    if (irregular != null) return '$head$irregular';
    if (last.endsWith('y')) {
      return '$head${last.substring(0, last.length - 1)}ieth';
    }
    return '$head${last}th';
  }

  /// Years read as pairs: `1999` → `nineteen ninety-nine`,
  /// `2005` → `two thousand five`, `1905` → `nineteen oh five`.
  static String year(int y) {
    if (y < 1000 || y > 2099) return cardinal(y);
    if (y >= 2000 && y <= 2009) {
      return y == 2000 ? 'two thousand' : 'two thousand ${_ones[y - 2000]}';
    }
    final hi = y ~/ 100;
    final lo = y % 100;
    if (lo == 0) return '${cardinal(hi)} hundred';
    final loWords = lo < 10 ? 'oh ${_ones[lo]}' : _below100(lo);
    return '${cardinal(hi)} $loWords';
  }

  /// `3.14` fractional part → `one four`.
  static String digits(String digits) => [
        for (final c in digits.split(''))
          c == '0' ? 'zero' : _ones[int.parse(c)],
      ].join(' ');

  static String _below100(int n) {
    if (n < 20) return _ones[n];
    final t = _tens[n ~/ 10];
    final o = n % 10;
    return o == 0 ? t : '$t-${_ones[o]}';
  }

  static String _below1000(int n) {
    if (n < 100) return _below100(n);
    final h = '${_ones[n ~/ 100]} hundred';
    final r = n % 100;
    return r == 0 ? h : '$h ${_below100(r)}';
  }
}
