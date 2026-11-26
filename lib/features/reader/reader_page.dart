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
import '../web_import/web_import_service.dart';
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
    // Keep the PDF page in step with the spoken sentence.
    ref.listen<int?>(readingProvider.select((s) => s.cursorBlock), (_, block) {
      final s = ref.read(readingProvider);
      if (block == null || doc?.kind != DocKind.pdf || !_pageMode || !s.isPlaying) return;
      final page = s.content?.blocks[block].page;
      if (page != null && _pdf.isReady && _pdf.pageNumber != page + 1) {
        unawaited(_pdf.goToPage(pageNumber: page + 1));
      }
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
    final showPages = isPdf && _pageMode;

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
          if (!showPages)
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
              if (doc.sourceUrl != null) const PopupMenuItem(value: 'open', child: Text('Open original page')),
            ],
          ),
        ],
      ),
      body: showPages ? _pdfPages(doc) : const TextReaderView(bottomPadding: 40),
      floatingActionButton: showPages
          ? FloatingActionButton.extended(
              onPressed: () => _readFromPage(doc),
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Read from this page'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _fetching ? const LinearProgressIndicator() : const PlayerBar(),
    );
  }

  Widget _pdfPages(Doc doc) {
    final path = ref.read(servicesProvider).paths.sourceFile(doc.id, 'source.pdf').path;
    return PdfViewer.file(
      path,
      controller: _pdf,
      initialPageNumber: 1,
      params: const PdfViewerParams(),
    );
  }

  /// Starts listening at the first sentence on the visible PDF page.
  Future<void> _readFromPage(Doc doc) async {
    final page = (_pdf.pageNumber ?? 1) - 1;
    final ctrl = ref.read(readingProvider.notifier);
    var s = ref.read(readingProvider);
    // Without chapter headings the sections are fixed page ranges.
    const perSection = 25;
    final guess = page ~/ perSection;
    if (s.content?.blocks.any((b) => b.page == page) != true && guess < s.sectionCount && guess != s.section) {
      await ctrl.goToSection(guess);
      s = ref.read(readingProvider);
    }
    final i = s.index?.firstSentenceOnPage(s.content!, page);
    if (i == null) {
      if (mounted) context.snack('No readable text on this page.');
      return;
    }
    await ctrl.seekToSentence(i, play: true);
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
