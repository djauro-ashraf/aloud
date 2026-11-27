import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import '../../data/import/article_extractor.dart';
import '../../data/import/import_exception.dart';
import '../../data/import/web_fetcher.dart';
import '../library/library_actions.dart';
import 'browser_page.dart';
import 'web_import_service.dart';

/// Paste a link → see what will be saved → save one page or a run of chapters.
class WebImportPage extends ConsumerStatefulWidget {
  const WebImportPage({super.key, this.shelfId, this.initialUrl});

  final String? shelfId;
  final String? initialUrl;

  @override
  ConsumerState<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends ConsumerState<WebImportPage> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  final _title = TextEditingController();
  WebArticle? _article;
  bool _busy = false;
  String _status = '';
  String? _error;
  double _chapters = 1;

  @override
  void initState() {
    super.initState();
    if ((widget.initialUrl ?? '').isNotEmpty) unawaited(Future<void>.microtask(_fetch));
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => _url.text = t);
  }

  Future<void> _fetch() async {
    final uri = WebFetcher.parseUrl(_url.text);
    if (uri == null) {
      setState(() => _error = 'That doesn’t look like a web address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _article = null;
      _status = 'Fetching…';
    });
    try {
      final a = await ref.read(webImportServiceProvider).fetchArticle(uri);
      if (!mounted) return;
      setState(() {
        _article = a;
        _title.text = a.title;
        _chapters = 1;
      });
    } on ImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBrowser() async {
    final uri = WebFetcher.parseUrl(_url.text);
    final query = {
      'url': uri?.toString() ?? 'https://',
      if (widget.shelfId != null) 'shelf': widget.shelfId!,
    };
    final result = await context.push<BrowserResult>(Uri(path: '/browser', queryParameters: query).toString());
    if (result == null || !mounted) return;
    switch (result) {
      case BrowserSaved(:final book, :final chapters):
        // The chapters are already in the library; there is nothing left to do here.
        context.snack('Saved $chapters ${chapters == 1 ? 'chapter' : 'chapters'} to “${book.title}”');
        context.pop();
      case BrowserPageChosen(:final html, :final url):
        try {
          final a = ref.read(webImportServiceProvider).fromHtml(html, Uri.parse(url));
          setState(() {
            _url.text = url;
            _article = a;
            _title.text = a.title;
            _chapters = 1;
            _error = null;
          });
        } on ImportException catch (e) {
          setState(() => _error = e.message);
        }
    }
  }

  Future<void> _save({required bool listen}) async {
    final first = _article;
    if (first == null) return;
    setState(() {
      _busy = true;
      _status = 'Saving…';
    });
    try {
      final service = ref.read(webImportServiceProvider);
      final count = _chapters.round();
      final chain = count > 1
          ? await service.fetchChain(first, count, onProgress: (done, total) {
              if (mounted) setState(() => _status = 'Fetching chapter $done of $total…');
            })
          : [first];
      final doc = await ref.read(servicesProvider).importer.importArticles(
            chain,
            shelfId: widget.shelfId,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          );
      if (!mounted) return;
      context.snack(chain.length == 1 ? 'Saved “${doc.title}”' : 'Saved ${chain.length} chapters');
      context.pop();
      openDoc(context, ref, doc, listen: listen);
    } on ImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Add from the web')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _fetch(),
            decoration: InputDecoration(
              labelText: 'Page or chapter link',
              hintText: 'https://…',
              suffixIcon: IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste', onPressed: _paste),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _fetch,
                icon: const Icon(Icons.download),
                label: const Text('Fetch'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openBrowser,
                icon: const Icon(Icons.public),
                label: const Text('Browse & save'),
              ),
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(children: [const LinearProgressIndicator(), const SizedBox(height: 8), Text(_status)]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                color: scheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(14), child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
              ),
            ),
          if (a != null && !_busy) ...[
            const SizedBox(height: 20),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.wordCount} words${a.siteName == null ? '' : ' · ${a.siteName}'}', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Text(
                      a.blocks.where((b) => b.isSpeakable).take(3).map((b) => b.text).join('\n\n'),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (a.nextUrl != null) ...[
              const SizedBox(height: 8),
              SliderTile(
                title: 'Chapters to add (follows “next”)',
                value: _chapters,
                min: 1,
                max: 50,
                divisions: 49,
                label: _chapters.round() == 1 ? 'just this page' : '${_chapters.round()} chapters',
                onChanged: (v) => setState(() => _chapters = v),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No “next chapter” link found on this page.'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: FilledButton.icon(onPressed: () => _save(listen: true), icon: const Icon(Icons.headphones), label: const Text('Save & listen'))),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: () => _save(listen: false), child: const Text('Save')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
