import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../data/models/models.dart';
import '../comics/comic_reader_view.dart';
import '../web_import/browser_page.dart';
import '../web_import/web_import_service.dart';
import 'highlight_sheet.dart';
import 'pdf_reader_view.dart';
import 'player_bar.dart';
import 'reader_sheets.dart';
import 'reading_controller.dart';
import 'text_reader_view.dart';

/// Reader for one document. Picks the right view for the document kind.
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.docId});

  final String docId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _pdf = PdfViewerController();
  bool _pageMode = true;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(() => ref.read(readingProvider.notifier).open(widget.docId)));
    ref.listenManual<bool>(
      settingsProvider.select((m) => Prefs.keepScreenOn.read(m)),
      (_, keepOn) => unawaited(keepOn ? WakelockPlus.enable() : WakelockPlus.disable()),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(docProvider(widget.docId));
    final ctrl = ref.read(readingProvider.notifier);

    ref.listen<String?>(readingProvider.select((s) => s.notice), (_, n) {
      if (n == null) return;
      context.snack(n);
      ctrl.clearNotice();
    });
    ref.listen<String?>(readingProvider.select((s) => s.error), (_, e) {
      if (e == null) return;
      context.snack(
        e,
        action: SnackBarAction(label: 'Voices', onPressed: () => context.push('/voices')),
      );
      ctrl.clearError();
    });
    // Playback was closed from the notification / mini-player: leave the reader.
    ref.listen<bool>(readingProvider.select((s) => s.doc == null && !s.loading), (prev, closed) {
      if (prev == false && closed && context.canPop()) context.pop();
    });
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.error_outline, title: 'This item no longer exists'),
      );
    }
    if (doc.kind == DocKind.comic) return ComicReaderView(doc: doc);

    final s = ref.watch(readingProvider);
    final isPdf = doc.kind == DocKind.pdf;
    // Translated speech no longer matches the printed page, so show the text.
    final showPages = isPdf && _pageMode && !s.translated;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            if (s.sectionTitle.isNotEmpty && s.sectionCount > 1)
              Text(s.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (isPdf)
            IconButton(
              tooltip: _pageMode ? 'Text view' : 'Page view',
              icon: Icon(_pageMode ? Icons.subject : Icons.picture_as_pdf_outlined),
              onPressed: () => setState(() => _pageMode = !_pageMode),
            ),
          if (s.sectionCount > 1)
            IconButton(
              tooltip: 'Chapters',
              icon: const Icon(Icons.list),
              onPressed: () => showChaptersSheet(context),
            ),
          if (showPages)
            IconButton(
              tooltip: 'Highlight & tapping',
              icon: const Icon(Icons.highlight),
              onPressed: () => showHighlightSheet(context, pdf: true),
            )
          else
            IconButton(
              tooltip: 'Appearance',
              icon: const Icon(Icons.text_fields),
              onPressed: () => showAppearanceSheet(context),
            ),
          IconButton(
            tooltip: s.translated ? 'Show original' : 'Translate',
            icon: s.translating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.translate, color: s.translated ? Theme.of(context).colorScheme.primary : null),
            onPressed: () => ctrl.setTranslated(!s.translated),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(v, doc),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'voices', child: Text('Voice & engine')),
              const PopupMenuItem(value: 'rules', child: Text('Listening rules')),
              const PopupMenuItem(value: 'translation', child: Text('Translation settings')),
              if (doc.kind == DocKind.web && doc.nextUrl != null)
                const PopupMenuItem(value: 'more', child: Text('Fetch more chapters')),
              if (doc.kind == DocKind.web && (doc.nextUrl ?? doc.sourceUrl) != null)
                const PopupMenuItem(value: 'browse', child: Text('Browse & add chapters')),
              if (doc.sourceUrl != null) const PopupMenuItem(value: 'open', child: Text('Open original page')),
            ],
          ),
        ],
      ),
      body: showPages ? PdfReaderView(doc: doc, controller: _pdf) : const TextReaderView(bottomPadding: 40),
      bottomNavigationBar: _fetching ? const LinearProgressIndicator() : const PlayerBar(),
    );
  }

  Future<void> _onMenu(String v, Doc doc) async {
    switch (v) {
      case 'voices':
        unawaited(context.push('/voices'));
      case 'rules':
        unawaited(context.push('/rules'));
      case 'translation':
        unawaited(context.push('/settings/translation'));
      case 'open':
        final u = Uri.tryParse(doc.sourceUrl ?? '');
        if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
      case 'browse':
        // Opens the site at the next chapter; whatever is saved there joins this book.
        final start = doc.nextUrl ?? doc.sourceUrl!;
        await context.push<BrowserResult>(
          Uri(path: '/browser', queryParameters: {'url': start, 'book': doc.id}).toString(),
        );
        if (mounted) await ref.read(readingProvider.notifier).reloadDocMeta();
      case 'more':
        setState(() => _fetching = true);
        try {
          await ref.read(webImportServiceProvider).appendNext(doc, count: 5);
          await ref.read(readingProvider.notifier).reloadDocMeta();
          if (mounted) context.snack('Chapters added.');
        } on Object catch (e) {
          if (mounted) context.snack('$e');
        } finally {
          if (mounted) setState(() => _fetching = false);
        }
    }
  }
}
