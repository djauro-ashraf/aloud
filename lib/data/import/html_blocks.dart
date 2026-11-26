import 'package:aloud_core/aloud_core.dart';
import 'package:html/dom.dart' as dom;

/// Maps an `<img src>` to a stored image reference (or `null` to drop it).
typedef ImageResolver = String? Function(String src);

/// Converts an HTML/XHTML DOM into [ReaderBlock]s.
///
/// One converter serves EPUB chapters, saved web pages and local .html files,
/// so every source ends up in the same reader model.
final class HtmlBlocks {
  HtmlBlocks({this.resolveImage, this.skipChrome = false});

  final ImageResolver? resolveImage;

  /// Drop navigation/footers/sidebars (web pages).
  final bool skipChrome;

  static const _alwaysSkip = {
    'script', 'style', 'noscript', 'template', 'iframe', 'object', 'embed',
    'svg', 'canvas', 'form', 'button', 'select', 'input', 'textarea', 'head',
    'audio', 'video', 'map',
  };
  static const _chromeSkip = {'nav', 'header', 'footer', 'aside', 'menu'};
  static const _blocks = {
    'p', 'div', 'section', 'article', 'main', 'body', 'html', 'ul', 'ol', 'li',
    'blockquote', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'figure',
    'figcaption', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
    'header', 'footer', 'nav', 'aside', 'dl', 'dt', 'dd', 'details', 'summary',
    'address', 'center', 'fieldset', 'img', 'menu',
  };
  static const _italicTags = {'i', 'em', 'cite', 'dfn'};
  static const _boldTags = {'b', 'strong'};

  List<ReaderBlock> extract(dom.Node root) {
    final out = <ReaderBlock>[];
    _children(root, out, quote: false);
    return out;
  }

  // ── Walking ────────────────────────────────────────────────────────────

  void _children(dom.Node parent, List<ReaderBlock> out, {required bool quote}) {
    final run = <dom.Node>[];
    void flush() {
      if (run.isEmpty) return;
      _emitInline(run, out, kind: quote ? BlockKind.quote : BlockKind.paragraph);
      run.clear();
    }

    for (final n in parent.nodes) {
      if (n is dom.Element) {
        final tag = n.localName ?? '';
        if (_skip(n, tag)) continue;
        if (_blocks.contains(tag)) {
          flush();
          _block(n, tag, out, quote: quote);
        } else if (tag == 'br') {
          run.add(n);
        } else if (_containsBlock(n)) {
          // Inline wrapper (e.g. <a>/<span>) that holds blocks: descend.
          flush();
          _children(n, out, quote: quote);
        } else {
          run.add(n);
        }
      } else if (n is dom.Text) {
        run.add(n);
      }
    }
    flush();
  }

  void _block(dom.Element el, String tag, List<ReaderBlock> out, {required bool quote}) {
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final text = _collapse(_plain(el));
        if (text.isNotEmpty) out.add(ReaderBlock.heading(text));
      case 'hr':
        out.add(const ReaderBlock(kind: BlockKind.sceneBreak, text: '* * *'));
      case 'img':
        _image(el, out);
      case 'blockquote':
        _children(el, out, quote: true);
      case 'pre':
        for (final line in _plain(el).split('\n')) {
          final t = _collapse(line);
          if (t.isNotEmpty) out.add(ReaderBlock.paragraph(t));
        }
      case 'tr':
        final cells = [
          for (final c in el.children)
            if (c.localName == 'td' || c.localName == 'th') _collapse(_plain(c)),
        ].where((c) => c.isNotEmpty).toList();
        if (cells.isNotEmpty) out.add(ReaderBlock.paragraph(cells.join(', ')));
      case 'p' || 'li' || 'dd' || 'dt' || 'figcaption' || 'summary' || 'td' || 'th':
        if (_containsBlock(el)) {
          _children(el, out, quote: quote);
        } else {
          _emitInline(el.nodes, out, kind: quote ? BlockKind.quote : BlockKind.paragraph);
        }
      default:
        _children(el, out, quote: quote);
    }
  }

  void _image(dom.Element el, List<ReaderBlock> out) {
    final src = el.attributes['src'] ?? el.attributes['data-src'] ?? el.attributes['xlink:href'];
    if (src == null || src.isEmpty || resolveImage == null) return;
    final ref = resolveImage!(src);
    if (ref != null) out.add(ReaderBlock(kind: BlockKind.image, imageRef: ref));
  }

  bool _skip(dom.Element el, String tag) {
    if (_alwaysSkip.contains(tag)) return true;
    if (skipChrome && _chromeSkip.contains(tag)) return true;
    if (el.attributes['hidden'] != null || el.attributes['aria-hidden'] == 'true') return true;
    final style = el.attributes['style'];
    if (style != null && RegExp(r'display\s*:\s*none', caseSensitive: false).hasMatch(style)) return true;
    return false;
  }

  bool _containsBlock(dom.Element el) {
    for (final c in el.children) {
      final t = c.localName ?? '';
      if (_blocks.contains(t) && t != 'img') return true;
      if (!_alwaysSkip.contains(t) && _containsBlock(c)) return true;
    }
    return false;
  }

  // ── Inline text ────────────────────────────────────────────────────────

  void _emitInline(Iterable<dom.Node> nodes, List<ReaderBlock> out, {required BlockKind kind}) {
    final acc = _Acc();
    for (final n in nodes) {
      _inline(n, acc, italic: false, bold: false);
    }
    // Inline images (e.g. <p><img/></p>) become their own blocks.
    for (final img in acc.images) {
      _image(img, out);
    }
    for (final line in acc.text.toString().split('\n')) {
      final t = _collapse(line);
      if (t.isEmpty) continue;
      final total = acc.total == 0 ? 1 : acc.total;
      final ctx = SentenceContext(
        italic: acc.italic / total > 0.9,
        bold: acc.bold / total > 0.9,
      );
      if (BlockClassifier.isSceneBreak(t)) {
        out.add(ReaderBlock(kind: BlockKind.sceneBreak, text: t));
      } else {
        out.add(ReaderBlock(kind: kind, text: t, context: ctx));
      }
    }
  }

  void _inline(dom.Node n, _Acc acc, {required bool italic, required bool bold}) {
    if (n is dom.Text) {
      final t = n.text;
      if (t.trim().isEmpty && acc.text.isEmpty) return;
      acc.text.write(t.replaceAll(RegExp(r'[\r\n\t]+'), ' '));
      final len = t.trim().length;
      acc.total += len;
      if (italic) acc.italic += len;
      if (bold) acc.bold += len;
    } else if (n is dom.Element) {
      final tag = n.localName ?? '';
      if (_alwaysSkip.contains(tag)) return;
      if (tag == 'br') {
        acc.text.write('\n');
        return;
      }
      if (tag == 'img') {
        acc.images.add(n);
        return;
      }
      if (tag == 'sup' && RegExp(r'^\[?\d+\]?$').hasMatch(n.text.trim())) return; // footnote marker
      final isItalic = italic || _italicTags.contains(tag) || _styleHas(n, 'italic');
      final isBold = bold || _boldTags.contains(tag) || _styleHas(n, 'bold');
      for (final c in n.nodes) {
        _inline(c, acc, italic: isItalic, bold: isBold);
      }
    }
  }

  static bool _styleHas(dom.Element el, String what) {
    final s = el.attributes['style'];
    return s != null && s.contains(what);
  }

  static String _plain(dom.Node n) {
    final b = StringBuffer();
    void walk(dom.Node x) {
      if (x is dom.Text) {
        b.write(x.text);
      } else if (x is dom.Element) {
        final t = x.localName ?? '';
        if (_alwaysSkip.contains(t)) return;
        if (t == 'br') b.write('\n');
        for (final c in x.nodes) {
          walk(c);
        }
      }
    }

    walk(n);
    return b.toString();
  }

  static String _collapse(String s) => s
      .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final class _Acc {
  final text = StringBuffer();
  final images = <dom.Element>[];
  int total = 0;
  int italic = 0;
  int bold = 0;
}
