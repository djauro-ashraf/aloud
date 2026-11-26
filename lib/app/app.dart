import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../core/platform/file_picking.dart';
import '../core/prefs.dart';
import '../core/theme/app_theme.dart';
import '../data/import/import_service.dart';
import '../data/import/web_fetcher.dart';
import '../features/library/import_flow.dart';
import '../features/library/library_actions.dart';
import 'core_providers.dart';
import 'router.dart';

/// The running application (a vault is open and providers are available).
class AloudApp extends ConsumerWidget {
  const AloudApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final seed = Color(ref.pref(Prefs.accent));
    return MaterialApp.router(
      title: 'Aloud',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.build(seed, Brightness.light),
      darkTheme: AppTheme.build(seed, Brightness.dark),
      themeMode: AppTheme.mode(ref.pref(Prefs.themeMode)),
      builder: (context, child) => _StartupTasks(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// One-time startup work that needs providers and a navigator: notification
/// permission and handling things shared to the app by other apps.
class _StartupTasks extends ConsumerStatefulWidget {
  const _StartupTasks({required this.child});

  final Widget child;

  @override
  ConsumerState<_StartupTasks> createState() => _StartupTasksState();
}

class _StartupTasksState extends ConsumerState<_StartupTasks> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(servicesProvider).bridge;
    _sub = bridge.sharedItemsAvailable.listen((_) => unawaited(_consumeShares()));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _askNotifications();
      await _consumeShares();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Android 13+ hides the media notification unless permitted. Ask once.
  Future<void> _askNotifications() async {
    if (Prefs.askedNotifications.read(ref.read(settingsProvider))) return;
    await ref.read(settingsProvider.notifier).set(Prefs.askedNotifications, true);
    try {
      await Permission.notification.request();
    } on Object {
      // Not available on this platform; playback still works.
    }
  }

  Future<void> _consumeShares() async {
    final items = await ref.read(servicesProvider).bridge.takeSharedItems();
    if (items.isEmpty) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final router = GoRouter.of(ctx);

    final files = <PickedFile>[
      for (final i in items)
        if (!i.isText && i.path != null && ImportService.isSupported(i.name ?? i.path!))
          PickedFile(path: i.path!, name: i.name ?? p.basename(i.path!)),
    ];
    final texts = [for (final i in items) if (i.isText) i.text!.trim()];

    if (files.isNotEmpty) {
      await importFiles(ctx, ref, files, shelfId: ref.read(currentShelfProvider));
      return;
    }
    for (final t in texts) {
      final url = WebFetcher.parseUrl(t.split(RegExp(r'\s+')).firstWhere((w) => w.contains('.'), orElse: () => ''));
      if (url != null && t.split(RegExp(r'\s+')).length <= 3) {
        unawaited(router.push('/web?url=${Uri.encodeComponent(url.toString())}'));
        return;
      }
      if (t.length > 40) {
        final doc = await ref.read(servicesProvider).importer.importText(
              t.split('\n').first.trim().length > 60 ? 'Shared text' : t.split('\n').first.trim(),
              t,
              shelfId: ref.read(currentShelfProvider),
            );
        if (ctx.mounted) openDoc(ctx, ref, doc, listen: true);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
