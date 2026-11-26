import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/util/format.dart';
import 'reader_sheets.dart';
import 'reading_controller.dart';

/// Transport controls under the text: seek bar, play/pause, skips, speed,
/// sleep timer and the settings sheet.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(readingProvider);
    final ctrl = ref.read(readingProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final speed = ref.pref(Prefs.speed);
    final length = s.index?.length ?? 0;
    final busy = s.loading || s.translating;

    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(
                value: s.cursor,
                length: length,
                onSeek: (i) => ctrl.seekToSentence(i),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => showListenSheet(context),
                    child: Text(Fmt.speed(speed)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    tooltip: 'Previous paragraph',
                    onPressed: ctrl.previousParagraph,
                  ),
                  IconButton(
                    icon: const Icon(Icons.replay),
                    tooltip: 'Previous sentence',
                    onPressed: ctrl.previousSentence,
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: busy
                        ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
                        : IconButton.filled(
                            iconSize: 36,
                            icon: Icon(s.isPlaying ? Icons.pause : Icons.play_arrow),
                            tooltip: s.isPlaying ? 'Pause' : 'Play',
                            onPressed: ctrl.toggle,
                          ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    tooltip: 'Next sentence',
                    onPressed: ctrl.nextSentence,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Next paragraph',
                    onPressed: ctrl.nextParagraph,
                  ),
                  IconButton(
                    icon: Badge(
                      isLabelVisible: s.sleepEnd != null || s.sleepAtChapterEnd,
                      smallSize: 8,
                      child: const Icon(Icons.bedtime_outlined),
                    ),
                    tooltip: 'Sleep timer & settings',
                    onPressed: () => showListenSheet(context),
                  ),
                ],
              ),
              if (s.sectionCount > 1)
                Text(
                  '${s.sectionTitle.isEmpty ? 'Section' : s.sectionTitle}  ·  ${s.section + 1}/${s.sectionCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seek slider over the sentences of the current section.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.value, required this.length, required this.onSeek});

  final int value;
  final int length;
  final void Function(int sentence) onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final max0 = max(1, widget.length - 1).toDouble();
    final v = (_drag ?? widget.value.toDouble()).clamp(0.0, max0);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
      child: Slider(
        value: v,
        min: 0,
        max: max0,
        onChanged: widget.length <= 1 ? null : (x) => setState(() => _drag = x),
        onChangeEnd: (x) {
          setState(() => _drag = null);
          widget.onSeek(x.round());
        },
      ),
    );
  }
}
