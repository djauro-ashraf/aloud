import 'dart:convert';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'html_blocks.dart';
import 'import_exception.dart';
import 'text_importer.dart';

/// EPUB 2/3 → sections. Pure Dart: safe to run inside `Isolate.run`.
abstract final class EpubImporter {
  static ParsedBook parse(Uint8List bytes, {required String fallbackTitle}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ImportException('This file is not a valid EPUB (zip is damaged).');
    }
    final files = <String, ArchiveFile>{
      for (final f in archive)
        if (f.isFile) _decode(f.name): f,
    };

    String? read(String path) {
      final f = files[path] ?? files[_decode(path)];
      final b = f?.readBytes();
      return b == null ? null : utf8.decode(b, allowMalformed: true);
    }

    final container = read('META-INF/container.xml');
    if (container == null) throw const ImportException('EPUB is missing META-INF/container.xml.');
    final opfPath = _all(XmlDocument.parse(container), 'rootfile')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .firstOrNull;
    if (opfPath == null) throw const ImportException('EPUB has no package document.');
    final opfText = read(opfPath);
    if (opfText == null) throw const ImportException('EPUB package document is missing.');
    final opf = XmlDocument.parse(opfText);

    String resolve(String from, String href) {
      final clean = Uri.decodeFull(href.split('#').first.split('?').first);
      if (clean.startsWith('/')) return clean.substring(1);
      final dir = p.posix.dirname(from);
      return p.posix.normalize(dir == '.' ? clean : p.posix.join(dir, clean));
    }

    // Metadata
    String? meta(String local) => _all(opf, local).map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).firstOrNull;
    final title = meta('title') ?? fallbackTitle;
    final author = meta('creator');
    final lang = meta('language');

    // Manifest
    final manifest = <String, _Item>{};
    for (final it in _all(opf, 'item')) {
      final id = it.getAttribute('id');
      final href = it.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = _Item(
        path: resolve(opfPath, href),
        type: it.getAttribute('media-type') ?? '',
        props: it.getAttribute('properties') ?? '',
      );
    }

    // Spine
    final spineEl = _all(opf, 'spine').firstOrNull;
    final spine = <String>[];
    for (final ref in _all(opf, 'itemref')) {
      final id = ref.getAttribute('idref');
      if (id == null || ref.getAttribute('linear') == 'no') continue;
      final item = manifest[id];
      if (item != null && item.isDocument) spine.add(item.path);
    }
    if (spine.isEmpty) throw const ImportException('EPUB has no readable chapters.');

    // Table of contents → titles per file
    final tocTitles = _readToc(opf, spineEl, manifest, read, resolve);

    // Cover
    Uint8List? cover;
    final coverId = _all(opf, 'meta')
        .where((m) => m.getAttribute('name') == 'cover')
        .map((m) => m.getAttribute('content'))
        .firstOrNull;
    final coverItem = manifest.values.where((i) => i.props.contains('cover-image')).firstOrNull ??
        (coverId == null ? null : manifest[coverId]);
    if (coverItem != null) cover = (files[coverItem.path] ?? files[_decode(coverItem.path)])?.readBytes();

    // Chapters
    final images = <String, Uint8List>{};
    final imageRefs = <String, String>{};
    final sections = <ReaderSection>[];
    for (final path in spine) {
      final text = read(path);
      if (text == null) continue;
      final doc = html.parse(text);
      final root = doc.body ?? doc.documentElement;
      if (root == null) continue;
      final blocks = HtmlBlocks(resolveImage: (src) {
        if (src.startsWith('data:')) return null;
        final full = resolve(path, src);
        final existing = imageRefs[full];
        if (existing != null) return existing;
        final data = (files[full] ?? files[_decode(full)])?.readBytes();
        if (data == null) return null;
        final ref = 'images/${imageRefs.length}_${p.posix.basename(full)}';
        imageRefs[full] = ref;
        images[ref] = data;
        return ref;
      }).extract(root);
      if (blocks.isEmpty) continue;

      final firstHeading = blocks.where((b) => b.kind == BlockKind.heading).firstOrNull?.text;
      sections.add(ReaderSection(
        title: tocTitles[path] ?? firstHeading ?? 'Section ${sections.length + 1}',
        blocks: blocks,
      ));
    }
    if (sections.every((s) => s.blocks.every((b) => !b.isSpeakable))) {
      throw const ImportException('No readable text found (the EPUB may be image-only or DRM-protected).');
    }

    final sample = [
      for (final s in sections.take(3))
        for (final b in s.blocks.take(20))
          if (b.isSpeakable) b.text,
    ].join(' ');
    return ParsedBook(
      title: title,
      author: author,
      language: lang?.split(RegExp('[-_]')).first.toLowerCase() ?? Languages.detect(sample),
      sections: sections,
      images: images,
      cover: cover,
    );
  }

  // ── TOC ────────────────────────────────────────────────────────────────

  static Map<String, String> _readToc(
    XmlDocument opf,
    XmlElement? spine,
    Map<String, _Item> manifest,
    String? Function(String) read,
    String Function(String, String) resolve,
  ) {
    final out = <String, String>{};

    void add(String from, String src, String label) {
      final path = resolve(from, src);
      final t = label.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) out.putIfAbsent(path, () => t);
    }

    // EPUB 3 navigation document.
    final nav = manifest.values.where((i) => i.props.split(' ').contains('nav')).firstOrNull;
    if (nav != null) {
      final text = read(nav.path);
      if (text != null) {
        final doc = html.parse(text);
        final navEl = doc.querySelectorAll('nav').where((n) {
          final t = n.attributes['epub:type'] ?? n.attributes['type'] ?? '';
          return t.contains('toc');
        }).firstOrNull ?? doc.querySelector('nav');
        for (final a in navEl?.querySelectorAll('a') ?? const <dom.Element>[]) {
          final href = a.attributes['href'];
          if (href != null) add(nav.path, href, a.text);
        }
      }
    }
    if (out.isNotEmpty) return out;

    // EPUB 2 NCX.
    final ncxId = spine?.getAttribute('toc');
    final ncx = (ncxId == null ? null : manifest[ncxId]) ??
        manifest.values.where((i) => i.type == 'application/x-dtbncx+xml').firstOrNull;
    if (ncx != null) {
      final text = read(ncx.path);
      if (text != null) {
        for (final point in _all(XmlDocument.parse(text), 'navPoint')) {
          final label = _all(point, 'text').firstOrNull?.innerText ?? '';
          final src = _all(point, 'content').firstOrNull?.getAttribute('src');
          if (src != null) add(ncx.path, src, label);
        }
      }
    }
    return out;
  }

  static Iterable<XmlElement> _all(XmlNode node, String local) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static String _decode(String s) {
    try {
      return Uri.decodeFull(s);
    } catch (_) {
      return s;
    }
  }
}

final class _Item {
  const _Item({required this.path, required this.type, required this.props});

  final String path;
  final String type;
  final String props;

  bool get isDocument => type == 'application/xhtml+xml' || type == 'text/html' || type == 'application/x-dtbook+xml';
}
