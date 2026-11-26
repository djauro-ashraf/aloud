import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../data/repositories/settings_repository.dart';
import 'translation_providers.dart';

/// Choose the target language and provider, and store API keys securely.
class TranslationSettingsPage extends ConsumerStatefulWidget {
  const TranslationSettingsPage({super.key});

  @override
  ConsumerState<TranslationSettingsPage> createState() => _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends ConsumerState<TranslationSettingsPage> {
  final _controllers = <String, TextEditingController>{};
  bool _downloading = false;

  TextEditingController _controllerFor(String key) {
    return _controllers.putIfAbsent(key, () {
      final c = TextEditingController();
      ref.read(servicesProvider).secrets.read(key).then((v) {
        if (mounted && v != null) c.text = v;
      });
      return c;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _downloadModel(String lang) async {
    setState(() => _downloading = true);
    try {
      final ok = await MlKitProvider.download(lang);
      if (mounted) context.snack(ok ? 'Model for ${Languages.nameOf(lang)} is ready.' : 'Download failed.');
    } on Exception catch (e) {
      if (mounted) context.snack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.pref(Prefs.translateTarget);
    final providerId = ref.pref(Prefs.translateProvider);
    final info = TranslationProviders.info(providerId);
    final secrets = ref.read(servicesProvider).secrets;

    return Scaffold(
      appBar: AppBar(title: const Text('Translation')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionLabel('Translate into'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: Languages.all.any((l) => l.code == target) ? target : 'en',
              items: [for (final l in Languages.all) DropdownMenuItem(value: l.code, child: Text(l.name))],
              onChanged: (v) => ref.setPref(Prefs.translateTarget, v ?? 'en'),
            ),
          ),
          const SectionLabel('Provider'),
          for (final p in TranslationProviders.infos)
            ListTile(
              selected: p.id == providerId,
              leading: Icon(p.id == providerId ? Icons.check_circle : Icons.radio_button_unchecked),
              title: Text(p.label),
              subtitle: Text(p.blurb),
              onTap: () => ref.setPref(Prefs.translateProvider, p.id),
            ),
          if (info.secrets.isNotEmpty) ...[
            const SectionLabel('Credentials'),
            for (final (key, label) in info.secrets)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _controllerFor(key),
                  obscureText: key != SecretKeys.libreUrl && key != SecretKeys.azureRegion,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: 'Stored in the Android Keystore on this device only.',
                  ),
                  onChanged: (v) => secrets.write(key, v.trim()),
                ),
              ),
          ],
          if (info.id == 'mlkit') ...[
            const SectionLabel('On-device models'),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: Text('Download ${Languages.nameOf(target)}'),
              subtitle: const Text('Source-language models download automatically when first needed.'),
              trailing: _downloading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton.tonal(onPressed: () => _downloadModel(target), child: const Text('Download')),
            ),
          ],
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Translations are saved per chapter, so a chapter is translated only once. '
              'Cloud providers receive the text you translate.',
            ),
          ),
        ],
      ),
    );
  }
}
