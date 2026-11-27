import 'dart:async';
import 'dart:convert';

import 'package:aloud_core/aloud_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/core_providers.dart';
import '../../core/prefs.dart';
import '../../core/ui/widgets.dart';
import '../../data/import/article_extractor.dart';
import '../../data/import/import_exception.dart';
import '../../data/models/models.dart';
import 'saved_urls.dart';
import 'web_import_service.dart';

/// What the browser hands back when it closes.
sealed class BrowserResult {
  const BrowserResult();
}

/// "Review before saving": the page as it is now, to look over on the import screen.
final class BrowserPageChosen extends BrowserResult {
  const BrowserPageChosen({required this.html, required this.url});

  final String html;
  final String url;
}

/// Chapters were saved from inside the browser.
final class BrowserSaved extends BrowserResult {
  const BrowserSaved({required this.book, required this.chapters});

  final Doc book;

  /// Chapters added during this visit.
  final int chapters;
}

/// In-app browser for pages that need JavaScript, a login or a captcha, built
/// for saving a run of chapters without leaving the page:
///
/// open a chapter → **Save** → **Next** → **Save** → …
///
/// Every Save reads the page as it is shown and adds it as the next chapter of
/// one book (the first Save creates it), so a whole novel ends up as a single
/// library entry. Pass [bookId] to keep filling an existing web book.
class BrowserPage extends ConsumerStatefulWidget {
  const BrowserPage({super.key, required this.url, this.shelfId, this.bookId});

  final String url;
  final String? shelfId;
  final String? bookId;

  @override
  ConsumerState<BrowserPage> createState() => _BrowserPageState();
}

enum _Menu { review, rename, newBook, autoNext }

class _BrowserPageState extends ConsumerState<BrowserPage> {
  late final WebViewController _web;
  final _saved = SavedUrls();

  /// The book chapters are being added to; null until the first Save.
  Doc? _book;

  /// Chapters added to [_book] during this visit.
  int _added = 0;

  /// The "next chapter" link found when [_nextFor] was saved.
  Uri? _next;
  String? _nextFor;

  bool _busy = false;
  int _progress = 0;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (_) async {
          final t = await _web.getTitle();
          if (mounted) setState(() => _title = t ?? '');
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
    unawaited(_continueBook());
  }

  /// When opened from a book, new chapters join it instead of starting another.
  Future<void> _continueBook() async {
    final id = widget.bookId;
    if (id == null) return;
    final book = await ref.read(servicesProvider).library.getDoc(id);
    if (book == null || !mounted) return;
    final last = book.sourceUrl == null ? null : Uri.tryParse(book.sourceUrl!);
    setState(() {
      _book = book;
      if (last != null) _saved.add(last);
    });
  }

  /// The page as shown right now, including anything scripts have added.
  Future<({String html, String url})> _snapshot() async {
    final raw = await _web.runJavaScriptReturningResult('document.documentElement.outerHTML');
    final url = await _web.currentUrl() ?? widget.url;
    var html = raw is String ? raw : '$raw';
    // Android returns the string JSON-encoded.
    if (html.startsWith('"')) {
      try {
        html = jsonDecode(html) as String;
      } on FormatException {
        // Keep the raw value.
      }
    }
    return (html: html, url: url);
  }

  // ── Saving ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final page = await _snapshot();
      final url = Uri.parse(page.url);
      if (_saved.contains(url)) {
        _say('Already saved — open the next chapter.', withNext: true);
        return;
      }
      final service = ref.read(webImportServiceProvider);
      final article = service.fromHtml(page.html, url);
      final book = await service.saveChapter(_book, article, shelfId: widget.shelfId);
      if (!mounted) return;

      _saved.add(url);
      setState(() {
        _added = _book == null || book.id != _book!.id ? 1 : _added + 1;
        _book = book;
        _next = article.nextUrl;
        _nextFor = page.url;
      });
      final chapters = book.sectionCount;
      _say(
        'Saved “${article.title}” — $chapters ${chapters == 1 ? 'chapter' : 'chapters'} in “${book.title}”',
        withNext: article.nextUrl != null,
      );
      if (article.nextUrl != null && Prefs.browserAutoNext.read(ref.read(settingsProvider))) {
        await _web.loadRequest(article.nextUrl!);
      }
    } on ImportException catch (e) {
      if (mounted) context.snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message, {required bool withNext}) {
    if (!mounted) return;
    context.snack(message, action: withNext ? SnackBarAction(label: 'Next', onPressed: _goNext) : null);
  }

  /// Opens the chapter after this one: the link found when this page was
  /// saved, or else the one on the page as it is now.
  Future<void> _goNext() async {
    if (_busy) return;
    final current = await _web.currentUrl();
    var next = current != null && current == _nextFor ? _next : null;
    if (next == null) {
      final page = await _snapshot();
      next = ArticleExtractor.extract(page.html, Uri.parse(page.url)).nextUrl;
    }
    if (!mounted) return;
    if (next == null) {
      context.snack('No “next chapter” link found here. Use the site’s own link, then tap Save.');
      return;
    }
    await _web.loadRequest(next);
  }

  // ── Leaving ────────────────────────────────────────────────────────────

  void _finish() {
    final book = _book;
    context.pop<BrowserResult>(book != null && _added > 0 ? BrowserSaved(book: book, chapters: _added) : null);
  }

  Future<void> _review() async {
    final page = await _snapshot();
    if (mounted) context.pop<BrowserResult>(BrowserPageChosen(html: page.html, url: page.url));
  }

  Future<void> _rename() async {
    final book = _book;
    if (book == null) return;
    final name = await promptText(context, title: 'Rename book', initial: book.title);
    if (name == null) return;
    final updated = await ref.read(servicesProvider).library.updateDoc(book.id, (d) => d.copyWith(title: Names.title(name)));
    if (updated != null && mounted) setState(() => _book = updated);
  }

  Future<void> _onMenu(_Menu item) async {
    switch (item) {
      case _Menu.review:
        await _review();
      case _Menu.rename:
        await _rename();
      case _Menu.newBook:
        setState(() {
          _book = null;
          _added = 0;
          _saved.clear();
        });
        if (mounted) context.snack('The next Save starts a new book.');
      case _Menu.autoNext:
        final on = Prefs.browserAutoNext.read(ref.read(settingsProvider));
        await ref.setPref(Prefs.browserAutoNext, !on);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final autoNext = ref.pref(Prefs.browserAutoNext);
    final book = _book;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'Browser' : _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _web.reload),
          if (_added > 0) TextButton(onPressed: _finish, child: Text('Done ($_added)')),
          PopupMenuButton<_Menu>(
            onSelected: _onMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: _Menu.review, child: Text('Review this page before saving')),
              if (book != null) const PopupMenuItem(value: _Menu.rename, child: Text('Rename book')),
              if (book != null) const PopupMenuItem(value: _Menu.newBook, child: Text('Start a new book')),
              CheckedPopupMenuItem(
                value: _Menu.autoNext,
                checked: autoNext,
                child: const Text('Open the next chapter after saving'),
              ),
            ],
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100))
            : null,
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _web.canGoBack()) {
            await _web.goBack();
          } else if (mounted) {
            _finish();
          }
        },
        child: WebViewWidget(controller: _web),
      ),
      bottomNavigationBar: _SaveBar(
        book: book,
        added: _added,
        busy: _busy,
        onSave: _save,
        onNext: _goNext,
      ),
    );
  }
}

/// The two actions that make up the loop, and where the pages are going.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.book, required this.added, required this.busy, required this.onSave, required this.onNext});

  final Doc? book;
  final int added;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = book == null
        ? 'Open a chapter, then tap Save'
        : '“${book!.title}” · ${book!.sectionCount} ${book!.sectionCount == 1 ? 'chapter' : 'chapters'}';
    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : onSave,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
