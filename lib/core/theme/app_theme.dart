import 'package:material_ui/material_ui.dart';

/// Builds the app's Material 3 themes from one accent colour.
abstract final class AppTheme {
  static ThemeData build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeMode mode(String name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// Accent colours offered in settings.
  static const accents = <int>[
    0xFF2F6F6A,
    0xFF3F5AA6,
    0xFF7A4FA3,
    0xFFB5475A,
    0xFFC0702B,
    0xFF4F7B2D,
    0xFF5B5F66,
  ];
}

/// Palettes for the reading surface (independent of the app theme).
final class ReaderPalette {
  const ReaderPalette({
    required this.name,
    required this.background,
    required this.text,
    required this.highlight,
    required this.dim,
  });

  final String name;
  final Color background;
  final Color text;

  /// Background of the sentence being read.
  final Color highlight;

  /// Secondary text (chapter labels, hints).
  final Color dim;

  static const paper = ReaderPalette(
    name: 'Paper',
    background: Color(0xFFFAF7F0),
    text: Color(0xFF222222),
    highlight: Color(0x55F2C94C),
    dim: Color(0xFF7A7468),
  );
  static const sepia = ReaderPalette(
    name: 'Sepia',
    background: Color(0xFFF1E6D0),
    text: Color(0xFF4A3B27),
    highlight: Color(0x66D9A441),
    dim: Color(0xFF8A7556),
  );
  static const night = ReaderPalette(
    name: 'Night',
    background: Color(0xFF16181C),
    text: Color(0xFFD7D9DE),
    highlight: Color(0x554F8CFF),
    dim: Color(0xFF8B909A),
  );
  static const black = ReaderPalette(
    name: 'Black',
    background: Color(0xFF000000),
    text: Color(0xFFBFC2C8),
    highlight: Color(0x663E7BEB),
    dim: Color(0xFF777B83),
  );

  static const all = {'paper': paper, 'sepia': sepia, 'night': night, 'black': black};

  /// `app` follows the surrounding Material theme.
  static ReaderPalette resolve(String name, ColorScheme scheme) {
    final fixed = all[name];
    if (fixed != null) return fixed;
    return ReaderPalette(
      name: 'App',
      background: scheme.surface,
      text: scheme.onSurface,
      highlight: scheme.primary.withValues(alpha: 0.28),
      dim: scheme.onSurfaceVariant,
    );
  }
}
