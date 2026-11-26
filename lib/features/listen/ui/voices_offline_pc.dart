import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/core_providers.dart';
import '../../../core/prefs.dart';
import '../../../core/ui/widgets.dart';
import '../../../data/repositories/settings_repository.dart';
import '../engines/pc_server.dart';
import '../engines/sherpa_models.dart';
import '../engines/speech_backend.dart';
import 'voices_page.dart';

// ── Offline (Sherpa) ──────────────────────────────────────────────────────

class OfflineVoices extends ConsumerStatefulWidget {
  const OfflineVoices({super.key});

  @override
  ConsumerState<OfflineVoices> createState() => _OfflineVoicesState();
}

class _OfflineVoicesState extends ConsumerState<OfflineVoices> {
  final _progress = <String, double>{};
  final _status = <String, String>{};
  final _tokens = <String, CancelToken>{};

  Future<void> _install(SherpaVoice v) async {
    final models = ref.read(backendFactoryProvider).models;
    final token = CancelToken();
    setState(() {
      _progress[v.modelFolder] = 0;
      _tokens[v.modelFolder] = token;
    });
    try {
      await models.install(
        v,
        cancel: token,
        onProgress: (f, status) {
          if (mounted) {
            setState(() {
              _progress[v.modelFolder] = f;
              _status[v.modelFolder] = status;
            });
          }
        },
      );
      if (mounted) {
        await ref.setPref(Prefs.sherpaVoice, v.id);
        if (mounted) context.snack('${v.name} is ready.');
      }
    } on SpeechException catch (e) {
      if (mounted && !token.isCancelled) context.snack(e.message);
    } on Object catch (e) {
      if (mounted) context.snack('Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _progress.remove(v.modelFolder);
          _tokens.remove(v.modelFolder);
        });
      }
    }
  }

  Future<void> _remove(SherpaVoice v) async {
    final ok = await confirm(
      context,
      title: 'Remove ${v.family == SherpaFamily.kokoro ? 'the Kokoro voice pack' : v.name}?',
      message: 'You can download it again later.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(backendFactoryProvider).models.uninstall(v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.read(backendFactoryProvider).models;
    final chosen = ref.pref(Prefs.sherpaVoice);
    Widget group(String title, String blurb, Iterable<SherpaVoice> voices) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(blurb, style: Theme.of(context).textTheme.bodySmall),
            ),
            for (final v in voices) _tile(models, v, chosen),
          ],
        );
    final kokoro = SherpaCatalog.all.where((v) => v.family == SherpaFamily.kokoro);
    final piper = SherpaCatalog.all.where((v) => v.family == SherpaFamily.piper);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('Kokoro — most natural', 'One ~350 MB download unlocks all 11 voices. Best on a recent phone.', kokoro),
        group('Piper — lighter', 'Smaller downloads; the “compact” ones are only ~6 MB.', piper),
        const SectionLabel('Performance'),
        SliderTile(
          title: 'CPU threads',
          value: ref.pref(Prefs.sherpaThreads).toDouble(),
          min: 1,
          max: 6,
          divisions: 5,
          label: '${ref.pref(Prefs.sherpaThreads)}',
          onChanged: (v) => ref.setPref(Prefs.sherpaThreads, v.round()),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tile(SherpaModelManager models, SherpaVoice v, String chosen) {
    final installed = models.isInstalled(v);
    final busy = _progress.containsKey(v.modelFolder);
    final selected = chosen == v.id;
    final progress = _progress[v.modelFolder];
    final voice = VoiceInfo(engine: EngineKind.sherpa, id: v.id, name: v.name, locale: 'en');
    return ListTile(
      selected: selected && installed,
      leading: Icon(selected && installed ? Icons.check_circle : Icons.radio_button_unchecked),
      title: Text(v.name),
      subtitle: busy
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: (progress ?? 0) <= 0 ? null : progress),
                  const SizedBox(height: 2),
                  Text(_status[v.modelFolder] ?? '', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            )
          : Text('${v.accent} · ${installed ? 'installed' : v.sizeLabel}'),
      trailing: busy
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => _tokens[v.modelFolder]?.cancel(),
            )
          : installed
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Preview',
                    onPressed: () => previewVoice(context, ref, voice),
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: () => _remove(v)),
                ])
              : IconButton(icon: const Icon(Icons.download), tooltip: 'Download', onPressed: () => _install(v)),
      onTap: installed ? () => ref.setPref(Prefs.sherpaVoice, v.id) : (busy ? null : () => _install(v)),
    );
  }
}

// ── PC server ─────────────────────────────────────────────────────────────

class PcServerSection extends ConsumerStatefulWidget {
  const PcServerSection({super.key});

  @override
  ConsumerState<PcServerSection> createState() => _PcServerSectionState();
}

class _PcServerSectionState extends ConsumerState<PcServerSection> {
  late final _url = TextEditingController(text: ref.read(settingsProvider)[Prefs.pcUrl.key] as String? ?? '');
  final _token = TextEditingController();
  String _status = '';
  bool _ok = false;
  bool _busy = false;
  List<VoiceInfo> _voices = const [];

  @override
  void initState() {
    super.initState();
    ref.read(servicesProvider).secrets.read(SecretKeys.pcToken).then((t) {
      if (mounted && t != null) _token.text = t;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.setPref(Prefs.pcUrl, _url.text.trim());
    await ref.read(servicesProvider).secrets.write(SecretKeys.pcToken, _token.text.trim());
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _status = 'Looking for a server on this Wi-Fi…';
    });
    final found = await PcServerClient.discover();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found != null) {
        _url.text = found.url;
        _status = 'Found “${found.name}” (v${found.version}). Enter its token if it needs one, then test.';
      } else {
        _status = 'No server answered. Is it running on the same Wi-Fi?';
      }
    });
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _busy = true;
      _status = 'Testing…';
    });
    final client = PcServerClient(baseUrl: _url.text.trim(), token: _token.text.trim());
    try {
      final h = await client.health();
      var voices = const <VoiceInfo>[];
      if (h.ok) voices = await client.voices();
      if (!mounted) return;
      setState(() {
        _ok = h.ok;
        _voices = voices;
        _status = h.ok ? 'Connected${h.serverName.isEmpty ? '' : ' to ${h.serverName}'}. ${voices.length} voices available.' : h.message;
      });
    } on SpeechException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = ref.pref(Prefs.pcVoice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Server address', hintText: 'http://192.168.1.20:8765'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Access token (if required)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(onPressed: _busy ? null : _discover, icon: const Icon(Icons.wifi_find), label: const Text('Find')),
                  const SizedBox(width: 12),
                  FilledButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.link), label: const Text('Connect')),
                ],
              ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(_ok ? Icons.check_circle : Icons.info_outline, size: 18, color: _ok ? Colors.green : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        for (final v in _voices)
          ListTile(
            selected: chosen == v.id,
            leading: Icon(chosen == v.id ? Icons.check_circle : Icons.radio_button_unchecked),
            title: Text(v.name),
            subtitle: Text(v.detail),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Preview',
              onPressed: () => previewVoice(context, ref, v),
            ),
            onTap: () => ref.setPref(Prefs.pcVoice, v.id),
          ),
        if (_voices.isEmpty && chosen.isNotEmpty)
          ListTile(leading: const Icon(Icons.check_circle), title: Text(chosen), subtitle: const Text('Selected voice')),
      ],
    );
  }
}
