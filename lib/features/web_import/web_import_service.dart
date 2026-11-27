import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/core_providers.dart';
import '../../data/import/article_extractor.dart';
import '../../data/import/import_exception.dart';
import '../../data/import/web_fetcher.dart';
import '../../data/models/models.dart';

/// Fetches web pages / web-novel chapters and saves them to the library.
final class WebImportService {
  WebImportService(this._ref, [WebFetcher? fetcher]) : _fetcher = fetcher ?? WebFetcher();

  final Ref _ref;
  final WebFetcher _fetcher;

  Future<WebArticle> fetchArticle(Uri url) async {
    final html = await _fetcher.fetch(url);
    return fromHtml(html, url);
  }

  /// Extracts from HTML you already have (e.g. from the in-app browser).
  WebArticle fromHtml(String html, Uri url) {
    final article = ArticleExtractor.extract(html, url);
    if (article.wordCount < 20) {
      throw const ImportException(
        'Very little text was found on this page. If it loads content with JavaScript, '
        'open it in the browser view and import from there.',
      );
    }
    return article;
  }

  /// Follows "next chapter" links starting at [first], up to [count] pages.
  /// A failure after the first page ends the chain quietly with what was
  /// collected, so one broken link doesn't discard a whole batch.
  Future<List<WebArticle>> fetchChain(
    WebArticle first,
    int count, {
    void Function(int done, int total)? onProgress,
  }) async {
    final out = [first];
    final seen = {first.url.toString()};
    var next = first.nextUrl;
    onProgress?.call(1, count);
    while (out.length < count && next != null && seen.add(next.toString())) {
      if (next.host != first.url.host) break;
      await Future<void>.delayed(const Duration(milliseconds: 400)); // be polite to the site
      try {
        final a = await fetchArticle(next);
        out.add(a);
        next = a.nextUrl;
        onProgress?.call(out.length, count);
      } on ImportException {
        break;
      }
    }
    return out;
  }

  /// Saves [article] as the next chapter of [book], or as the first chapter
  /// of a new book when there is none (or it has been deleted meanwhile).
  /// Returns the book it now belongs to.
  Future<Doc> saveChapter(Doc? book, WebArticle article, {String? shelfId}) async {
    final importer = _ref.read(servicesProvider).importer;
    if (book != null) {
      final updated = await importer.appendArticles(book, [article]);
      if (updated != null) return updated;
    }
    return importer.importArticles([article], shelfId: shelfId);
  }

  /// Fetches up to [count] chapters after the last saved one and appends them.
  /// Returns the updated document, or `null` if there is nothing more.
  Future<Doc?> appendNext(Doc doc, {int count = 3}) async {
    final nextUrl = doc.nextUrl;
    if (nextUrl == null) return null;
    final services = _ref.read(servicesProvider);
    final first = await fetchArticle(Uri.parse(nextUrl));
    final chain = await fetchChain(first, count);
    return services.importer.appendArticles(doc, chain);
  }

  void dispose() => _fetcher.close();
}

final webImportServiceProvider = Provider<WebImportService>((ref) {
  final s = WebImportService(ref);
  ref.onDispose(s.dispose);
  return s;
});
