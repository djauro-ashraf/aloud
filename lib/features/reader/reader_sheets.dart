import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/format.dart';
import 'highlight_sheet.dart';
import 'reading_controller.dart';

// ── Chapters ──────────────────────────────────────────────────────────────

Future<void> showChaptersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(readingProvider);
          final count = s.sectionCount;
          return ListView.builder(
            controller: scroll,
            itemCount: count,
            itemBuilder: (_, i) {
              final title = i < s.toc.length && s.toc[i].isNotEmpty ? s.toc[i] : 'Section ${i + 1}';
              final current = i == s.section;
              return ListTile(
                selected: current,
                leading: current ? const Icon(Icons.graphic_eq) : Text('${i + 1}'),
                title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(readingProvider.notifier).goToSection(i);
                },
              );
            },
          );
        },
      ),
    ),
  );
}

// ── Appearance ────────────────────────────────────────────────────────────

Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final theme = ref.pref(Prefs.readerTheme);
        final family = ref.pref(Prefs.fontFamily);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Theme'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('App'),
                        selected: theme == 'app',
                        onSelected: (_) => ref.setPref(Prefs.readerTheme, 'app'),
                      ),
                      for (final e in ReaderPalette.all.entries)
                        ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: e.value.background, radius: 9),
                          label: Text(e.value.name),
                          selected: theme == e.key,
                          onSelected: (_) => ref.setPref(Prefs.readerTheme, e.key),
                        ),
                    ],
                  ),
                ),
                const SectionLabel('Font'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'serif', label: Text('Serif')),
                      ButtonSegment(value: 'sans', label: Text('Sans')),
                      ButtonSegment(value: 'mono', label: Text('Mono')),
                    ],
                    selected: {family},
                    onSelectionChanged: (v) => ref.setPref(Prefs.fontFamily, v.first),
                  ),
                ),
                SliderTile(
                  title: 'Text size',
                  value: ref.pref(Prefs.fontScale),
                  min: 0.7,
                  max: 2.0,
                  divisions: 26,
                  label: '${(ref.pref(Prefs.fontScale) * 100).round()}%',
                  onChanged: (v) => ref.setPref(Prefs.fontScale, v),
                ),
                SliderTile(
                  title: 'Line spacing',
                  value: ref.pref(Prefs.lineHeight),
                  min: 1.2,
                  max: 2.2,
                  divisions: 10,
                  onChanged: (v) => ref.setPref(Prefs.lineHeight, v),
                ),
                SliderTile(
                  title: 'Side margins',
                  value: ref.pref(Prefs.pageMargin),
                  min: 8,
                  max: 48,
                  divisions: 10,
                  label: '${ref.pref(Prefs.pageMargin).round()}',
                  onChanged: (v) => ref.setPref(Prefs.pageMargin, v),
                ),
                SwitchListTile(
                  title: const Text('Justify text'),
                  value: ref.pref(Prefs.justify),
                  onChanged: (v) => ref.setPref(Prefs.justify, v),
                ),
                SwitchListTile(
                  title: const Text('Follow the spoken sentence'),
                  subtitle: const Text('Scroll automatically while listening'),
                  value: ref.pref(Prefs.autoScroll),
                  onChanged: (v) => ref.setPref(Prefs.autoScroll, v),
                ),
                SwitchListTile(
                  title: const Text('Keep screen on'),
                  value: ref.pref(Prefs.keepScreenOn),
                  onChanged: (v) => ref.setPref(Prefs.keepScreenOn, v),
                ),
                ListTile(
                  title: const Text('Highlight & tapping'),
                  subtitle: const Text('What is marked while listening, and how to start from a sentence'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showHighlightSheet(ctx, pdf: false),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// ── Listening (speed, sleep, pacing) ──────────────────────────────────────

Future<void> showListenSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final speed = ref.pref(Prefs.speed);
        final s = ref.watch(readingProvider);
        final ctrl = ref.read(readingProvider.notifier);
        final sleepEnd = s.sleepEnd;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Speed'),
                SliderTile(
                  title: 'Reading speed',
                  value: speed,
                  min: 0.5,
                  max: 3.0,
                  divisions: 50,
                  label: Fmt.speed(speed),
                  onChanged: (v) => ctrl.setSpeed((v * 20).round() / 20),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final v in const [0.8, 1.0, 1.25, 1.5, 1.75, 2.0])
                        ChoiceChip(
                          label: Text(Fmt.speed(v)),
                          selected: (speed - v).abs() < 0.01,
                          onSelected: (_) => ctrl.setSpeed(v),
                        ),
                    ],
                  ),
                ),
                const SectionLabel('Sleep timer'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final m in const [15, 30, 45, 60, 90])
                        ChoiceChip(
                          label: Text('$m min'),
                          selected: false,
                          onSelected: (_) => ctrl.setSleepTimer(Duration(minutes: m)),
                        ),
                      ChoiceChip(
                        label: const Text('End of chapter'),
                        selected: s.sleepAtChapterEnd,
                        onSelected: (v) => ctrl.setSleepAtChapterEnd(v),
                      ),
                      if (sleepEnd != null || s.sleepAtChapterEnd)
                        ActionChip(
                          avatar: const Icon(Icons.close, size: 16),
                          label: const Text('Turn off'),
                          onPressed: () => ctrl.setSleepTimer(null),
                        ),
                    ],
                  ),
                ),
                if (sleepEnd != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('Pauses at ${TimeOfDay.fromDateTime(sleepEnd).format(ctx)}'),
                  ),
                const SectionLabel('Pacing'),
                SliderTile(
                  title: 'Pause between paragraphs',
                  value: ref.pref(Prefs.paragraphPauseMs).toDouble(),
                  min: 0,
                  max: 1500,
                  divisions: 15,
                  label: '${ref.pref(Prefs.paragraphPauseMs)} ms',
                  onChanged: (v) => ref.setPref(Prefs.paragraphPauseMs, v.round()),
                ),
                SliderTile(
                  title: 'Pause between sentences',
                  value: ref.pref(Prefs.sentencePauseMs).toDouble(),
                  min: 0,
                  max: 600,
                  divisions: 12,
                  label: '${ref.pref(Prefs.sentencePauseMs)} ms',
                  onChanged: (v) => ref.setPref(Prefs.sentencePauseMs, v.round()),
                ),
                const SectionLabel('Continue automatically'),
                SwitchListTile(
                  title: const Text('Next chapter'),
                  value: ref.pref(Prefs.autoNextSection),
                  onChanged: (v) => ref.setPref(Prefs.autoNextSection, v),
                ),
                SwitchListTile(
                  title: const Text('Next book on the shelf'),
                  subtitle: const Text('When a book ends, start the next one alphabetically'),
                  value: ref.pref(Prefs.autoNextDocument),
                  onChanged: (v) => ref.setPref(Prefs.autoNextDocument, v),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.offline_pin_outlined),
                  title: const Text('Prepare this chapter for offline'),
                  subtitle: s.prepareProgress == null
                      ? const Text('Generate the audio now and keep it on this device')
                      : LinearProgressIndicator(value: s.prepareProgress),
                  trailing: s.prepareProgress == null
                      ? null
                      : IconButton(icon: const Icon(Icons.close), onPressed: ctrl.cancelPrepare),
                  onTap: s.prepareProgress == null ? ctrl.prepareChapterOffline : null,
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Voice & engine'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/voices');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.rule),
                  title: const Text('Listening rules'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/rules');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
}
