import 'package:aloud_core/aloud_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs.dart';
import '../data/models/models.dart';
import '../features/listen/backend_factory.dart';
import '../features/translate/translation_service.dart';
import 'services.dart';

/// The opened vault's services. Overridden in `AloudRoot` once a vault is open.
final servicesProvider = Provider<AppServices>((ref) {
  throw StateError('servicesProvider must be overridden with an opened vault.');
});

/// Asks the app root to lock (close this vault and show the lock screen).
/// Overridden by `AloudRoot`.
final lockCallbackProvider = Provider<VoidCallback>((ref) => () {});

// ── Settings ──────────────────────────────────────────────────────────────

/// All user settings as one map; read through typed [Pref] keys.
final settingsProvider = NotifierProvider<SettingsNotifier, Map<String, Object?>>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<Map<String, Object?>> {
  @override
  Map<String, Object?> build() => ref.read(servicesProvider).initialSettings;

  Future<void> set<T>(Pref<T> pref, T value) async {
    state = {...state, pref.key: value};
    await ref.read(servicesProvider).settingsRepo.save(state);
  }
}

extension PrefWatch on WidgetRef {
  /// Watches one setting; rebuilds only when *that* value changes.
  T pref<T>(Pref<T> p) => watch(settingsProvider.select((m) => p.read(m)));

  Future<void> setPref<T>(Pref<T> p, T value) => read(settingsProvider.notifier).set(p, value);
}

extension PrefRead on Ref {
  T prefValue<T>(Pref<T> p) => p.read(read(settingsProvider));
}

// ── Data streams ──────────────────────────────────────────────────────────

final docsProvider = StreamProvider<List<Doc>>((ref) => ref.watch(servicesProvider).library.watchDocs());

final shelvesProvider = StreamProvider<List<Shelf>>((ref) => ref.watch(servicesProvider).library.watchShelves());

final rulesListProvider = StreamProvider<List<SpeechRule>>((ref) => ref.watch(servicesProvider).rules.watch());

/// A single document, live.
final docProvider = Provider.family<Doc?, String>((ref, id) {
  final docs = ref.watch(docsProvider).value ?? const <Doc>[];
  for (final d in docs) {
    if (d.id == id) return d;
  }
  return null;
});

// ── Services ──────────────────────────────────────────────────────────────

/// Fires with a human-readable reason whenever listening falls back to the
/// device voice. The reading controller surfaces it in the UI.
final fallbackNoticeProvider = NotifierProvider<FallbackNotice, String?>(FallbackNotice.new);

class FallbackNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String reason) => state = reason;
  void clear() => state = null;
}

final backendFactoryProvider = Provider<BackendFactory>((ref) {
  final s = ref.watch(servicesProvider);
  final factory = BackendFactory(
    paths: s.paths,
    cache: s.audioCache,
    bridge: s.bridge,
    secrets: s.secrets,
    prefs: () => ref.read(settingsProvider),
    onFallback: (reason) => ref.read(fallbackNoticeProvider.notifier).show(reason),
  );
  ref.onDispose(factory.dispose);
  return factory;
});

final translationServiceProvider = Provider<TranslationService>((ref) {
  final s = ref.watch(servicesProvider);
  return TranslationService(paths: s.paths, secrets: s.secrets, prefs: () => ref.read(settingsProvider));
});
