import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/util/format.dart';
import '../lock/lock_settings.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Future<int> _cacheSize = ref.read(servicesProvider).audioCache.sizeBytes();

  @override
  Widget build(BuildContext context) {
    final mode = ref.pref(Prefs.themeMode);
    final accent = ref.pref(Prefs.accent);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SectionLabel('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {mode},
              onSelectionChanged: (v) => ref.setPref(Prefs.themeMode, v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Wrap(
              spacing: 12,
              children: [
                for (final c in AppTheme.accents)
                  InkResponse(
                    onTap: () => ref.setPref(Prefs.accent, c),
                    child: CircleAvatar(
                      backgroundColor: Color(c),
                      radius: 18,
                      child: accent == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ],
            ),
          ),
          const SectionLabel('Listening'),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice & engine'),
            subtitle: Text(_engineLabel(ref.pref(Prefs.engine))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/voices'),
          ),
          ListTile(
            leading: const Icon(Icons.rule),
            title: const Text('Listening rules'),
            subtitle: const Text('Skip notes, fix pronunciations, add pauses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/rules'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('Smart text clean-up'),
            subtitle: const Text('Read numbers, dates, money and symbols naturally'),
            value: ref.pref(Prefs.normalizeText),
            onChanged: (v) => ref.setPref(Prefs.normalizeText, v),
          ),
          if (ref.pref(Prefs.normalizeText)) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Expand abbreviations'),
              subtitle: const Text('Mr. → Mister, e.g. → for example'),
              value: ref.pref(Prefs.expandAbbreviations),
              onChanged: (v) => ref.setPref(Prefs.expandAbbreviations, v),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Spell out initialisms'),
              subtitle: const Text('FBI → F B I; shouted words are read normally'),
              value: ref.pref(Prefs.spellAcronyms),
              onChanged: (v) => ref.setPref(Prefs.spellAcronyms, v),
            ),
          ],
          SliderTile(
            title: 'Prepare ahead',
            value: ref.pref(Prefs.prefetch).toDouble(),
            min: 0,
            max: 8,
            divisions: 8,
            label: '${ref.pref(Prefs.prefetch)} sentences',
            onChanged: (v) => ref.setPref(Prefs.prefetch, v.round()),
          ),
          const SectionLabel('Translation'),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('Translation'),
            subtitle: const Text('Provider, language and API keys'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/translation'),
          ),
          const SectionLabel('Storage'),
          FutureBuilder<int>(
            future: _cacheSize,
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Audio cache'),
              subtitle: Text(snap.hasData ? '${Fmt.bytes(snap.data!)} of generated speech' : 'Calculating…'),
              trailing: TextButton(
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Clear audio cache?',
                    message: 'Speech is generated again when needed. Your books are not affected.',
                    confirmLabel: 'Clear',
                  );
                  if (!ok) return;
                  await ref.read(servicesProvider).audioCache.clear();
                  setState(() => _cacheSize = Future.value(0));
                },
                child: const Text('Clear'),
              ),
            ),
          ),
          SliderTile(
            title: 'Cache limit',
            value: ref.pref(Prefs.cacheLimitMb).toDouble(),
            min: 100,
            max: 4000,
            divisions: 39,
            label: Fmt.bytes(ref.pref(Prefs.cacheLimitMb) * 1024 * 1024),
            onChanged: (v) => ref.setPref(Prefs.cacheLimitMb, (v / 100).round() * 100),
          ),
          const SectionLabel('Privacy'),
          const LockSettingsSection(),
          const SectionLabel('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Aloud'),
            subtitle: Text('Version 0.1.0 · listen to anything'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _engineLabel(String name) => switch (name) {
        'edge' => 'Edge neural (online)',
        'sherpa' => 'Offline neural',
        'pc' => 'PC server',
        _ => 'Device voice',
      };
}
