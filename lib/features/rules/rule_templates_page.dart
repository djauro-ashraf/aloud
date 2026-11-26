import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import 'rules_text.dart';

/// Ready-made rules grouped by purpose. Adding one never creates duplicates:
/// templates have stable ids, so re-adding just re-enables it.
class RuleTemplatesPage extends ConsumerWidget {
  const RuleTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = {
      for (final r in ref.watch(rulesListProvider).value ?? const <SpeechRule>[])
        if (r.enabled) r.id,
    };
    final repo = ref.read(servicesProvider).rules;
    final categories = <String, List<RuleTemplate>>{};
    for (final t in RuleTemplates.all) {
      (categories[t.category] ??= []).add(t);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Template gallery')),
      body: ListView(
        children: [
          for (final entry in categories.entries) ...[
            SectionLabel(entry.key),
            for (final t in entry.value)
              ListTile(
                title: Text(t.title),
                subtitle: Text('${t.description}\n${RulesText.summary(t.rule)}'),
                isThreeLine: true,
                trailing: installed.contains(t.rule.id)
                    ? const Chip(label: Text('Added'), avatar: Icon(Icons.check, size: 16))
                    : FilledButton.tonal(
                        onPressed: () async {
                          await repo.installTemplate(t);
                          if (context.mounted) context.snack('Added “${t.title}”');
                        },
                        child: const Text('Add'),
                      ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
