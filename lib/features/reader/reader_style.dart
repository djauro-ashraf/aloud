import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/theme/app_theme.dart';

/// Resolved typography and colours of the reading surface.
final class ReaderStyle {
  const ReaderStyle({
    required this.palette,
    required this.body,
    required this.heading,
    required this.margin,
    required this.justify,
  });

  final ReaderPalette palette;
  final TextStyle body;
  final TextStyle heading;
  final double margin;
  final bool justify;

  static const _families = {'serif': 'serif', 'sans': 'sans-serif', 'mono': 'monospace'};

  static ReaderStyle of(WidgetRef ref, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = ReaderPalette.resolve(ref.pref(Prefs.readerTheme), scheme);
    final scale = ref.pref(Prefs.fontScale);
    final height = ref.pref(Prefs.lineHeight);
    final family = _families[ref.pref(Prefs.fontFamily)] ?? 'serif';
    final body = TextStyle(
      fontFamily: family,
      fontSize: 18 * scale,
      height: height,
      color: palette.text,
    );
    return ReaderStyle(
      palette: palette,
      body: body,
      heading: body.copyWith(fontSize: 18 * scale * 1.35, fontWeight: FontWeight.w700, height: 1.3),
      margin: ref.pref(Prefs.pageMargin),
      justify: ref.pref(Prefs.justify),
    );
  }
}
