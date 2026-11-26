import 'dart:async';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/core_providers.dart';
import '../../../core/prefs.dart';
import '../../../core/ui/widgets.dart';
import '../engines/edge_tts.dart';
import '../engines/speech_backend.dart';
import 'voices_offline_pc.dart';

const sampleSentence = 'Listening should feel effortless. The quick brown fox jumps over the lazy dog.';

/// Speaks [sample] with [voice], reporting failures in a snackbar.
Future<void> previewVoice(BuildContext context, WidgetRef ref, VoiceInfo voice) async {
  try {
    await ref.read(backendFactoryProvider).preview(voice, sampleSentence);
  } on SpeechException catch (e) {
    if (context.mounted) context.snack(e.message);
  } on Object catch (e) {
    if (context.mounted) context.snack('Could not play the preview: $e');
  }
}

class VoicesPage extends ConsumerWidget {
  const VoicesPage({super.key});

  static const _blurbs = {
    EngineKind.system: 'Your phone’s built-in voices. Instant and fully offline.',
    EngineKind.edge: 'Very natural neural voices. Needs internet; audio is cached so re-listening is free.',
    EngineKind.sherpa: 'Natural neural voices that run on your phone. Download once, then use offline.',
    EngineKind.pc: 'Highest quality: voices rendered on your own computer over Wi-Fi.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = EngineKind.values.asNameMap()[ref.pref(Prefs.engine)] ?? EngineKind.system;
    return PopScope(
      onPopInvokedWithResult: (_, _) => unawaited(ref.read(backendFactoryProvider).stopPreview()),
      child: Scaffold(
        appBar: AppBar(title: const Text('Voice & engine')),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<EngineKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: EngineKind.system, label: Text('Device'), icon: Icon(Icons.smartphone)),
                  ButtonSegment(value: EngineKind.edge, label: Text('Edge'), icon: Icon(Icons.cloud_outlined)),
                  ButtonSegment(value: EngineKind.sherpa, label: Text('Offline'), icon: Icon(Icons.download_done)),
                  ButtonSegment(value: EngineKind.pc, label: Text('PC'), icon: Icon(Icons.computer)),
                ],
                selected: {engine},
                onSelectionChanged: (v) => ref.setPref(Prefs.engine, v.first.name),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(_blurbs[engine]!, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (engine != EngineKind.system)
              SwitchListTile(
                title: const Text('Fall back to the device voice'),
                subtitle: const Text('Keep listening if the connection or model fails'),
                value: ref.pref(Prefs.fallbackToSystem),
                onChanged: (v) => ref.setPref(Prefs.fallbackToSystem, v),
              ),
            const Divider(height: 1),
            switch (engine) {
              EngineKind.system => const _DeviceVoices(),
              EngineKind.edge => const _EdgeVoices(),
              EngineKind.sherpa => const OfflineVoices(),
              EngineKind.pc => const PcServerSection(),
            },
          ],
        ),
      ),
    );
  }
}

// ── Device ────────────────────────────────────────────────────────────────

class _DeviceVoices extends ConsumerStatefulWidget {
  const _DeviceVoices();

  @override
  ConsumerState<_DeviceVoices> createState() => _DeviceVoicesState();
}

class _DeviceVoicesState extends ConsumerState<_DeviceVoices> {
  late final Future<List<VoiceInfo>> _voices = ref.read(backendFactoryProvider).system.listVoices();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final chosen = ref.pref(Prefs.systemVoice);
    return FutureBuilder<List<VoiceInfo>>(
      future: _voices,
      builder: (context, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
        final all = snap.data!;
        final q = _filter.toLowerCase();
        final list = [
          for (final v in all)
            if (q.isEmpty || v.name.toLowerCase().contains(q) || v.locale.toLowerCase().contains(q)) v,
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter voices (e.g. en-GB)'),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            ListTile(
              selected: chosen.isEmpty,
              leading: Icon(chosen.isEmpty ? Icons.check_circle : Icons.radio_button_unchecked),
              title: const Text('Automatic'),
              subtitle: const Text('Pick a voice that matches the text’s language'),
              onTap: () => ref.setPref(Prefs.systemVoice, ''),
            ),
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No voices were reported by the system. Install a text-to-speech engine in Android settings.'),
              ),
            for (final v in list)
              ListTile(
                selected: chosen == v.id,
                leading: Icon(chosen == v.id ? Icons.check_circle : Icons.radio_button_unchecked),
                title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${v.locale} · ${v.detail}'),
                trailing: IconButton(
                  icon: const Icon(Icons.play_circle_outline),
                  tooltip: 'Preview',
                  onPressed: () => previewVoice(context, ref, v),
                ),
                onTap: () => ref.setPref(Prefs.systemVoice, v.id),
              ),
          ],
        );
      },
    );
  }
}

// ── Edge ──────────────────────────────────────────────────────────────────

class _EdgeVoices extends ConsumerStatefulWidget {
  const _EdgeVoices();

  @override
  ConsumerState<_EdgeVoices> createState() => _EdgeVoicesState();
}

class _EdgeVoicesState extends ConsumerState<_EdgeVoices> {
  List<VoiceInfo> _voices = EdgeCatalog.voices;
  bool _loading = false;
  String _filter = '';

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final live = await ref.read(backendFactoryProvider).edge.fetchVoices();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (live != null && live.isNotEmpty) {
        _voices = live;
      } else {
        context.snack('Could not load the full list. Showing the built-in voices.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chosen = ref.pref(Prefs.edgeVoice);
    final q = _filter.toLowerCase();
    final list = [
      for (final v in _voices)
        if (q.isEmpty || v.name.toLowerCase().contains(q) || v.locale.toLowerCase().contains(q) || (v.gender?.toLowerCase() == q)) v,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter (e.g. en-GB, Female)'),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 8),
              _loading
                  ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.cloud_download_outlined), tooltip: 'Load all voices', onPressed: _refresh),
            ],
          ),
        ),
        for (final v in list)
          ListTile(
            selected: chosen == v.id,
            leading: Icon(chosen == v.id ? Icons.check_circle : Icons.radio_button_unchecked),
            title: Text(v.name),
            subtitle: Text('${v.locale}${v.gender == null ? '' : ' · ${v.gender}'}'),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Preview',
              onPressed: () => previewVoice(context, ref, v),
            ),
            onTap: () => ref.setPref(Prefs.edgeVoice, v.id),
          ),
      ],
    );
  }
}
