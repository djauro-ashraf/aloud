import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/library/library_page.dart';
import '../features/listen/ui/voices_page.dart';
import '../features/reader/reader_page.dart';
import '../features/rules/rule_editor_page.dart';
import '../features/rules/rule_templates_page.dart';
import '../features/rules/rules_page.dart';
import '../features/settings/settings_page.dart';
import '../features/translate/translation_settings_page.dart';
import '../features/web_import/browser_page.dart';
import '../features/web_import/web_import_page.dart';

/// Navigator of the whole app; lets code outside the widget tree (share
/// handling) show dialogs.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryPage()),
      GoRoute(
        path: '/read/:id',
        builder: (_, state) => ReaderPage(docId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/voices', builder: (_, _) => const VoicesPage()),
      GoRoute(
        path: '/rules',
        builder: (_, _) => const RulesPage(),
        routes: [
          GoRoute(path: 'edit', builder: (_, state) => RuleEditorPage(ruleId: state.uri.queryParameters['id'])),
          GoRoute(path: 'templates', builder: (_, _) => const RuleTemplatesPage()),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(path: 'translation', builder: (_, _) => const TranslationSettingsPage()),
        ],
      ),
      GoRoute(
        path: '/web',
        builder: (_, state) => WebImportPage(
          shelfId: state.uri.queryParameters['shelf'],
          initialUrl: state.uri.queryParameters['url'],
        ),
      ),
      GoRoute(
        path: '/browser',
        builder: (_, state) => BrowserPage(
          url: state.uri.queryParameters['url'] ?? 'https://',
          shelfId: state.uri.queryParameters['shelf'],
          bookId: state.uri.queryParameters['book'],
        ),
      ),
    ],
  );
});
