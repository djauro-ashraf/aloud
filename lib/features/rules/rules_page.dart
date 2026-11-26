import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/ids.dart';
import 'rules_text.dart';

class RulesPage extends ConsumerWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesListProvider);
    final repo = ref.read(servicesProvider).rules;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening rules'),
        actions: [
          IconButton(
            tooltip: 'Try your rules',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => _showTester(context, ref),
          ),
          IconButton(
            tooltip: 'Template gallery',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/rules/templates'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                await Clipboard.setData(ClipboardData(text: await repo.exportJson()));
                if (context.mounted) context.snack('Rules copied to the clipboard.');
              } else {
                await _import(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Copy all rules (JSON)')),
              PopupMenuItem(value: 'import', child: Text('Import rules from JSON')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/rules/edit'),
        icon: const Icon(Icons.add),
        label: const Text('New rule'),
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Could not load rules', message: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.rule,
              title: 'No rules yet',
              message: 'Rules clean up what is spoken: skip author notes, fix pronunciations, add pauses…',
              action: FilledButton.icon(
                onPressed: () => context.push('/rules/templates'),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Browse templates'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = list[i];
              return Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline),
                ),
                confirmDismiss: (_) => confirm(context, title: 'Delete “${r.name}”?', confirmLabel: 'Delete', destructive: true),
                onDismissed: (_) => repo.delete(r.id),
                child: ListTile(
                  title: Text(r.name.isEmpty ? 'Untitled rule' : r.name),
                  subtitle: Text(RulesText.summary(r), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Switch(value: r.enabled, onChanged: (v) => repo.setEnabled(r.id, enabled: v)),
                  onTap: () => context.push('/rules/edit?id=${r.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final json = await promptText(
      context,
      title: 'Import rules',
      initial: clip.trim().startsWith('{') || clip.trim().startsWith('[') ? clip : '',
      hint: 'Paste rules JSON',
      confirmLabel: 'Import',
      maxLines: 6,
    );
    if (json == null) return;
    try {
      final n = await ref.read(servicesProvider).rules.importJson(json, newId: newId);
      if (context.mounted) context.snack(n == 0 ? 'No valid rules found.' : 'Imported $n rule${n == 1 ? '' : 's'}.');
    } on FormatException catch (e) {
      if (context.mounted) context.snack('That is not a rules file (${e.message}).');
    }
  }

  void _showTester(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const RuleTester(),
    );
  }
}

/// Paste any text and see exactly what would be spoken, sentence by sentence.
class RuleTester extends ConsumerStatefulWidget {
  const RuleTester({super.key, this.extraRule});

  /// An unsaved rule to include (used by the editor).
  final SpeechRule? extraRule;

  @override
  ConsumerState<RuleTester> createState() => _RuleTesterState();
}

class _RuleTesterState extends ConsumerState<RuleTester> {
  final _text = TextEditingController(
    text: "Author's Note: thanks for reading!\n\nDr. Smith paid \$4.50 at 3:45 PM on 2024-03-09. See www.example.com for 20% off.\n\n***\n\nThe FBI arrived at the 21st-floor office.",
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(settingsProvider);
    final extra = widget.extraRule;
    final rules = [
      for (final r in ref.watch(rulesListProvider).value ?? const <SpeechRule>[])
        if (r.id != extra?.id) r,
      ?extra,
    ];
    final engine = RuleEngine(
      rules,
      normalizer: NormalizerOptions(
        expandAbbreviations: Prefs.expandAbbreviations.read(prefs),
        spellAcronyms: Prefs.spellAcronyms.read(prefs),
      ),
      normalize: Prefs.normalizeText.read(prefs),
    );
    final rows = <Widget>[];
    for (final para in Paragraphs.parse(_text.text)) {
      final v = engine.checkParagraph(para);
      if (v.skip) {
        rows.add(_row(context, para, 'skipped (paragraph rule)', skipped: true));
        continue;
      }
      for (final s in SentenceSplitter.sentences(para)) {
        final p = engine.plan(s);
        final extras = [
          if (p.pauseBeforeMs > 0) 'pause ${p.pauseBeforeMs} ms before',
          if (p.pauseAfterMs > 0) 'pause ${p.pauseAfterMs} ms after',
          if (p.speedDelta != 0) 'speed ${p.speedDelta > 0 ? '+' : ''}${(p.speedDelta * 100).round()}%',
          if (p.flow != FlowDirective.none) 'flow: ${p.flow.name}',
        ].join(' · ');
        rows.add(_row(context, s, p.skip ? 'skipped' : p.fullSpeech, skipped: p.skip, extra: extras));
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _text,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Sample text'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: rows)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String original, String result, {required bool skipped, String extra = ''}) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(original, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(skipped ? Icons.volume_off_outlined : Icons.record_voice_over_outlined, size: 16, color: skipped ? t.colorScheme.outline : t.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result,
                  style: skipped ? t.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: t.colorScheme.outline) : t.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (extra.isNotEmpty) Text(extra, style: t.textTheme.labelSmall),
        ],
      ),
    );
  }
}
