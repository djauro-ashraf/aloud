import 'package:aloud_core/aloud_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'html_blocks.dart';

/// A readable article pulled out of a web page.
final class WebArticle {
  const WebArticle({
    required this.title,
    required this.blocks,
    required this.url,
    this.nextUrl,
    this.prevUrl,
    this.siteName,
    this.language,
  });

  final String title;
  final List<ReaderBlock> blocks;
  final Uri url;
  final Uri? nextUrl;
  final Uri? prevUrl;
  final String? siteName;
  final String? language;

  int get wordCount => blocks.fold(0, (s, b) => s + (b.isSpeakable ? b.text.split(' ').length : 0));
}

/// "Reader mode" for the web: finds the main text of a page, removes site
/// chrome, and locates next/previous chapter links (web novels).
///
/// Strategy, in order: well-known novel-site containers → semantic
/// `<article>` → text-density scoring. This is intentionally a heuristic, not
/// a per-site scraper, so it keeps working when sites change their markup.
abstract final class ArticleExtractor {
  static const _knownSelectors = [
    '#chapter-content', '.chapter-content', '#chr-content', '.chr-c', '#chp_raw',
    '.chp_raw', '.reading-content', '.text-left', '.entry-content', '.post-content',
    '.fr-view', '#content', '.article-content', '.story-content', '[itemprop=articleBody]',
    'article', 'main',
  ];

  static final _noiseClass = RegExp(
    r'comment|share|social|sidebar|related|advert|\bads?\b|banner|popup|cookie|breadcrumb|newsletter|subscribe|navigation|navbar|menu|toolbar|pagination|widget|modal|overlay|donat|patreon',
    caseSensitive: false,
  );
  static final _contentClass = RegExp(r'article|content|chapter|post|entry|story|novel|text|reading|body', caseSensitive: false);
  static final _nextText = RegExp(r'^\s*(?:next(?:\s+chapter|\s+page)?|chapter\s+next|›|»|→|>|下一章|下一页|다음)\s*[»›>→]?\s*$', caseSensitive: false);
  static final _prevText = RegExp(r'^\s*(?:prev(?:ious)?(?:\s+chapter|\s+page)?|‹|«|←|<|上一章|上一页|이전)\s*$', caseSensitive: false);

  static WebArticle extract(String htmlSource, Uri url) {
    final doc = html.parse(htmlSource);
    final title = _title(doc);
    final next = _link(doc, url, next: true);
    final prev = _link(doc, url, next: false);

    _prune(doc);
    final container = _pickContainer(doc);
    final blocks = HtmlBlocks(skipChrome: true).extract(container);

    // Normalise through the web polisher: headings carry a "# " marker there.
    final marked = [
      for (final b in blocks)
        if (b.isSpeakable) b.kind == BlockKind.heading ? '# ${b.text}' : b.text,
    ];
    final polished = WebTextPolisher.polish(marked, title: title);
    final out = [
      for (final p in polished)
        if (p.startsWith('# ')) ReaderBlock.heading(p.substring(2)) else BlockClassifier.classify(p),
    ];

    final lang = doc.documentElement?.attributes['lang']?.split(RegExp('[-_]')).first.toLowerCase();
    return WebArticle(
      title: title,
      blocks: out,
      url: url,
      nextUrl: next,
      prevUrl: prev,
      siteName: _meta(doc, 'og:site_name'),
      language: lang ?? Languages.detect(polished.take(30).join(' ')),
    );
  }

  // ── Title ──────────────────────────────────────────────────────────────

  static String _title(dom.Document doc) {
    final og = _meta(doc, 'og:title');
    var t = og ?? doc.querySelector('h1')?.text ?? doc.querySelector('title')?.text ?? 'Untitled';
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // "Chapter 5 - My Novel | SiteName" → keep the first meaningful part.
    final parts = t.split(RegExp(r'\s[|–—]\s'));
    if (parts.length > 1 && parts.first.trim().length >= 4) t = parts.first.trim();
    return Names.title(t);
  }

  static String? _meta(dom.Document doc, String property) {
    for (final m in doc.querySelectorAll('meta')) {
      if (m.attributes['property'] == property || m.attributes['name'] == property) {
        final c = m.attributes['content']?.trim();
        if (c != null && c.isNotEmpty) return c;
      }
    }
    return null;
  }

  // ── Container selection ────────────────────────────────────────────────

  static void _prune(dom.Document doc) {
    for (final tag in ['script', 'style', 'noscript', 'iframe', 'form', 'svg', 'nav', 'footer', 'aside', 'button']) {
      for (final e in doc.querySelectorAll(tag).toList()) {
        e.remove();
      }
    }
    for (final e in doc.querySelectorAll('[class],[id]').toList()) {
      final sig = '${e.className} ${e.id}';
      if (_noiseClass.hasMatch(sig) && !_contentClass.hasMatch(sig)) e.remove();
    }
  }

  static dom.Element _pickContainer(dom.Document doc) {
    for (final sel in _knownSelectors) {
      final el = doc.querySelector(sel);
      if (el != null && _textLength(el) > 400) return el;
    }
    // Text-density scoring: reward long paragraphs, credit parents.
    final scores = <dom.Element, double>{};
    for (final p in doc.querySelectorAll('p')) {
      final len = p.text.trim().length;
      if (len < 40) continue;
      final score = 1 + len / 100 + ','.allMatches(p.text).length * 0.3;
      final parent = p.parent;
      if (parent != null) {
        scores[parent] = (scores[parent] ?? 0) + score;
        final grand = parent.parent;
        if (grand != null) scores[grand] = (scores[grand] ?? 0) + score / 2;
      }
    }
    if (scores.isNotEmpty) {
      return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    // Text pasted into <div>/<br> without paragraphs: fall back to the body.
    return doc.body ?? doc.documentElement!;
  }

  static int _textLength(dom.Element e) => e.text.trim().length;

  // ── Chapter links ──────────────────────────────────────────────────────

  static Uri? _link(dom.Document doc, Uri base, {required bool next}) {
    final rel = next ? 'next' : 'prev';
    for (final l in doc.querySelectorAll('link[rel],a[rel]')) {
      if ((l.attributes['rel'] ?? '').split(' ').contains(rel)) {
        final u = _resolve(base, l.attributes['href']);
        if (u != null) return u;
      }
    }
    final id = next ? RegExp(r'next', caseSensitive: false) : RegExp(r'prev', caseSensitive: false);
    final textRx = next ? _nextText : _prevText;
    for (final a in doc.querySelectorAll('a[href]')) {
      final label = a.text.trim();
      final sig = '${a.id} ${a.className}';
      final byText = label.length <= 24 && textRx.hasMatch(label);
      final byId = id.hasMatch(sig) && label.length <= 24;
      if (byText || byId) {
        final u = _resolve(base, a.attributes['href']);
        if (u != null && u != base) return u;
      }
    }
    return null;
  }

  static Uri? _resolve(Uri base, String? href) {
    if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) return null;
    try {
      final u = base.resolve(href);
      return (u.scheme == 'http' || u.scheme == 'https') ? u : null;
    } catch (_) {
      return null;
    }
  }
}
