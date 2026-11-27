import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/highlight.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../listen/backend_factory.dart';

/// Colours offered for the PDF highlight (the first is the long-standing default).
const _pdfColors = [0xFFE53935, 0xFFFB8C00, 0xFFFDD835, 0xFF43A047, 0xFF1E88E5, 0xFF8E24AA];

/// What is marked while listening, and what a tap does.
///
/// With [pdf] set, the controls for the highlight drawn over PDF pages are
/// included as well.
Future<void> showHighlightSheet(BuildContext context, {required bool pdf}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final mode = HighlightMode.parse(ref.pref(Prefs.highlightMode));
        final tap = TapToRead.parse(ref.pref(Prefs.tapToRead));
        final deviceVoice = VoiceResolver.engineOf(ref.watch(settingsProvider)) == EngineKind.system;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Highlight'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<HighlightMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: HighlightMode.auto, label: Text('Both')),
                      ButtonSegment(value: HighlightMode.sentence, label: Text('Sentence')),
                      ButtonSegment(value: HighlightMode.word, label: Text('Word')),
                      ButtonSegment(value: HighlightMode.off, label: Text('Off')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => ref.setPref(Prefs.highlightMode, v.first.name),
                  ),
                ),
                _VoiceNote(deviceVoice: deviceVoice, mode: mode),
                if (!pdf) ...[
                  const SectionLabel('Word style'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'soft', label: Text('Soft')),
                        ButtonSegment(value: 'strong', label: Text('Strong')),
                        ButtonSegment(value: 'underline', label: Text('Underline')),
                      ],
                      selected: {WordStyle.parse(ref.pref(Prefs.wordStyle)).name},
                      onSelectionChanged: (v) => ref.setPref(Prefs.wordStyle, v.first),
                    ),
                  ),
                ],
                const SectionLabel('Start reading from a sentence'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<TapToRead>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: TapToRead.doubleTap, label: Text('Double-tap')),
                      ButtonSegment(value: TapToRead.singleTap, label: Text('Tap')),
                      ButtonSegment(value: TapToRead.off, label: Text('Off')),
                    ],
                    selected: {tap},
                    onSelectionChanged: (v) => ref.setPref(Prefs.tapToRead, v.first.stored),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    switch (tap) {
                      TapToRead.doubleTap => 'Tap a sentence once to mark it, again to read from there.',
                      TapToRead.singleTap => 'A single tap starts reading from that sentence.',
                      TapToRead.off => 'Taps do nothing; use the player to move around.',
                    },
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
                if (pdf) ..._pdfControls(ref),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}

List<Widget> _pdfControls(WidgetRef ref) {
  final color = ref.pref(Prefs.pdfHighlightColor);
  return [
    const SectionLabel('PDF highlight colour'),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        children: [
          for (final c in _pdfColors)
            GestureDetector(
              onTap: () => ref.setPref(Prefs.pdfHighlightColor, c),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Color(c),
                child: color == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
              ),
            ),
        ],
      ),
    ),
    SliderTile(
      title: 'Word outline thickness',
      value: ref.pref(Prefs.pdfHighlightThickness),
      min: 1,
      max: 8,
      divisions: 14,
      label: ref.pref(Prefs.pdfHighlightThickness).toStringAsFixed(1),
      onChanged: (v) => ref.setPref(Prefs.pdfHighlightThickness, v),
    ),
    SliderTile(
      title: 'Side padding',
      value: ref.pref(Prefs.pdfHighlightPadH),
      min: 0,
      max: 12,
      divisions: 12,
      label: ref.pref(Prefs.pdfHighlightPadH).round().toString(),
      onChanged: (v) => ref.setPref(Prefs.pdfHighlightPadH, v),
    ),
    SliderTile(
      title: 'Top and bottom padding',
      value: ref.pref(Prefs.pdfHighlightPadV),
      min: 0,
      max: 12,
      divisions: 12,
      label: ref.pref(Prefs.pdfHighlightPadV).round().toString(),
      onChanged: (v) => ref.setPref(Prefs.pdfHighlightPadV, v),
    ),
    SliderTile(
      title: 'Move highlight up / down',
      value: ref.pref(Prefs.pdfHighlightOffsetY),
      min: -10,
      max: 10,
      divisions: 20,
      label: ref.pref(Prefs.pdfHighlightOffsetY).round().toString(),
      onChanged: (v) => ref.setPref(Prefs.pdfHighlightOffsetY, v),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            for (final p in [
              Prefs.pdfHighlightThickness,
              Prefs.pdfHighlightPadH,
              Prefs.pdfHighlightPadV,
              Prefs.pdfHighlightOffsetY,
            ]) {
              await ref.setPref(p, p.defaultValue);
            }
            await ref.setPref(Prefs.pdfHighlightColor, Prefs.pdfHighlightColor.defaultValue);
          },
          child: const Text('Reset PDF highlight'),
        ),
      ),
    ),
  ];
}

/// Says plainly what the current voice can highlight.
class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.deviceVoice, required this.mode});

  final bool deviceVoice;
  final HighlightMode mode;

  @override
  Widget build(BuildContext context) {
    final wantsWord = mode == HighlightMode.auto || mode == HighlightMode.word;
    final String text;
    if (mode == HighlightMode.off) {
      text = 'Nothing is marked while listening.';
    } else if (deviceVoice) {
      text = wantsWord
          ? 'The device voice reports every word, so the word being spoken is marked too.'
          : 'Marks the whole sentence being read.';
    } else {
      text = wantsWord
          ? 'Neural voices speak a whole sentence at a time, so they cannot say which word is being spoken. '
              'The sentence is marked instead. Switch to the device voice for word highlighting.'
          : 'Marks the whole sentence being read.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            wantsWord && !deviceVoice && mode != HighlightMode.off ? Icons.info_outline : Icons.check_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
