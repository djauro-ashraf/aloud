import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/core_providers.dart';
import '../../core/ui/widgets.dart';
import '../../data/import/article_extractor.dart';
import '../../data/import/import_exception.dart';
import '../../data/import/web_fetcher.dart';
import '../library/library_actions.dart';
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
    final result = await context.push<({String html, String url})>('/browser?url=${Uri.encodeComponent(uri?.toString() ?? 'https://')}');
    if (result == null || !mounted) return;
    try {
      final a = ref.read(webImportServiceProvider).fromHtml(result.html, Uri.parse(result.url));
      setState(() {
        _url.text = result.url;
        _article = a;
        _title.text = a.title;
        _chapters = 1;
        _error = null;
      });
    } on ImportException catch (e) {
      setState(() => _error = e.message);
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
                label: const Text('Browser view'),
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

/// In-app browser for pages that need JavaScript, logins or a captcha. Once
/// the page shows the text you want, "Use this page" hands its HTML back.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.url});

  final String url;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _web;
  int _progress = 0;
  String _title = '';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageFinished: (_) async {
          final t = await _web.getTitle();
          if (mounted) setState(() => _title = t ?? '');
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _use() async {
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
    if (mounted) context.pop((html: html, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'Browser' : _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _web.reload),
          FilledButton(onPressed: _use, child: const Text('Use this page')),
          const SizedBox(width: 12),
        ],
        bottom: _progress < 100 ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100)) : null,
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _web.canGoBack()) {
            await _web.goBack();
          } else if (context.mounted) {
            context.pop();
          }
        },
        child: WebViewWidget(controller: _web),
      ),
    );
  }
}
