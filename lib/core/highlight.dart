import 'prefs.dart';

/// What the reader marks while a sentence is being read.
enum HighlightMode {
  /// The sentence, plus the current word when the voice reports one.
  auto,

  /// The sentence only.
  sentence,

  /// The current word only (the sentence when the voice cannot report words).
  word,

  off;

  static HighlightMode parse(String value) =>
      values.firstWhere((m) => m.name == value, orElse: () => auto);

  /// Whether the sentence is marked, given whether a word position is known.
  /// In [word] mode the sentence takes over when there is no word to mark, so
  /// something is always visible.
  bool showsSentence({required bool hasWord}) => switch (this) {
        auto || sentence => true,
        word => !hasWord,
        off => false,
      };

  /// Whether a word is marked.
  bool showsWord({required bool hasWord}) => hasWord && (this == auto || this == word);
}

/// How the current word is drawn in text view.
enum WordStyle {
  soft,
  strong,
  underline;

  static WordStyle parse(String value) =>
      values.firstWhere((m) => m.name == value, orElse: () => soft);
}

/// What a tap on a sentence does.
enum TapToRead {
  /// Tap once to mark the sentence, tap again to read from it (the default:
  /// hard to trigger by accident while scrolling).
  doubleTap,

  /// A single tap reads from that sentence.
  singleTap,

  off;

  static TapToRead parse(String value) => switch (value) {
        'single' => singleTap,
        'off' => off,
        _ => doubleTap,
      };

  String get stored => switch (this) {
        doubleTap => 'double',
        singleTap => 'single',
        off => 'off',
      };
}

/// How the highlight is painted over a PDF page.
final class PdfHighlightStyle {
  const PdfHighlightStyle({
    required this.color,
    required this.thickness,
    required this.padH,
    required this.padV,
    required this.offsetY,
  });

  factory PdfHighlightStyle.from(Map<String, Object?> prefs) => PdfHighlightStyle(
        color: Prefs.pdfHighlightColor.read(prefs),
        thickness: Prefs.pdfHighlightThickness.read(prefs),
        padH: Prefs.pdfHighlightPadH.read(prefs),
        padV: Prefs.pdfHighlightPadV.read(prefs),
        offsetY: Prefs.pdfHighlightOffsetY.read(prefs),
      );

  /// ARGB colour value.
  final int color;

  /// Stroke width of the word outline, in logical pixels.
  final double thickness;

  /// Extra room around each highlighted line, in logical pixels.
  final double padH;
  final double padV;

  /// Vertical nudge for PDFs whose text boxes sit slightly off, in logical pixels.
  final double offsetY;

  @override
  bool operator ==(Object other) =>
      other is PdfHighlightStyle &&
      other.color == color &&
      other.thickness == thickness &&
      other.padH == padH &&
      other.padV == padV &&
      other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(color, thickness, padH, padV, offsetY);
}
