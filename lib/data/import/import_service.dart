import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:path/path.dart' as p;

import '../../core/util/ids.dart';
import '../models/models.dart';
import '../repositories/library_repository.dart';
import '../storage/app_paths.dart';
import '../storage/content_store.dart';
import 'article_extractor.dart';
import 'comic_importer.dart';
import 'epub_importer.dart';
import 'import_exception.dart';
import 'pdf_importer.dart';
import 'text_importer.dart';

/// Turns files, pasted text and web articles into library documents.
///
/// Every import is all-or-nothing: if parsing fails halfway, the half-written
/// document folder is removed so the library never contains broken items.
final class ImportService {
  ImportService({
    required this._paths,
    required this._library,
    required this._content,
    this._ocr,
  });

  final AppPaths _paths;
  final LibraryRepository _library;
  final ContentStore _content;
  final OcrService? _ocr;

  static const supportedExtensions = ['txt', 'md', 'text', 'epub', 'pdf', 'cbz', 'zip', 'html', 'htm'];

  static bool isSupported(String fileName) =>
      supportedExtensions.contains(p.extension(fileName).toLowerCase().replaceFirst('.', ''));

  // ── Files ──────────────────────────────────────────────────────────────

  Future<Doc> importFile(
    String sourcePath, {
    String? shelfId,
    String? displayName,
    ImportProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final name = displayName ?? p.basename(sourcePath);
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!supportedExtensions.contains(ext)) {
      throw ImportException('".$ext" files are not supported yet.');
    }
    final src = File(sourcePath);
    if (!await src.exists()) throw const ImportException('The file could not be found.');
    final size = await src.length();
    final title = Names.titleFromFileName(name);
    final id = newId();
    final dir = _paths.docDir(id);
    await dir.create(recursive: true);

    try {
      onProgress?.call(0.02, 'Opening $name');
      switch (ext) {
        case 'epub':
          final bytes = await src.readAsBytes();
          onProgress?.call(0.1, 'Parsing chapters');
          final book = await Isolate.run(() => EpubImporter.parse(bytes, fallbackTitle: title));
          await src.copy(_paths.sourceFile(id, 'source.epub').path);
          return await _store(id, book, DocKind.epub, shelfId, size, 'source.epub');
        case 'pdf':
          final copy = await src.copy(_paths.sourceFile(id, 'source.pdf').path);
          final book = await PdfImporter(ocr: _ocr).parse(
            copy.path,
            fallbackTitle: title,
            tmp: _paths.tempDir,
            onProgress: onProgress,
            isCancelled: isCancelled,
          );
          return await _store(id, book, DocKind.pdf, shelfId, size, 'source.pdf');
        case 'cbz' || 'zip':
          onProgress?.call(0.1, 'Extracting pages');
          final count = await ComicImporter.extract(sourcePath, _paths.pagesDir(id).path);
          final first = ComicImporter.pages(_paths.pagesDir(id)).first;
          await first.copy(_paths.coverFile(id).path);
          final doc = Doc(
            id: id,
            title: title,
            kind: DocKind.comic,
            addedAt: DateTime.now().millisecondsSinceEpoch,
            shelfId: shelfId,
            sizeBytes: size,
            pageCount: count,
            hasCover: true,
          );
          await _library.putDoc(doc);
          return doc;
        case 'html' || 'htm':
          final text = TextDecoder.decode(await src.readAsBytes());
          final article = ArticleExtractor.extract(text, Uri.parse('file:///${Uri.encodeComponent(name)}'));
          if (article.blocks.isEmpty) throw const ImportException('No readable text found in this page.');
          final book = ParsedBook(
            title: article.title,
            language: article.language,
            sections: [ReaderSection(title: article.title, blocks: article.blocks)],
          );
          return await _store(id, book, DocKind.web, shelfId, size, null);
        default:
          final bytes = await src.readAsBytes();
          final book = await Isolate.run(() => TextImporter.parse(bytes, fileName: name));
          if (book.sections.every((s) => s.blocks.isEmpty)) throw const ImportException('This file is empty.');
          return await _store(id, book, DocKind.text, shelfId, size, null);
      }
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  // ── Pasted text ────────────────────────────────────────────────────────

  Future<Doc> importText(String title, String text, {String? shelfId}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw const ImportException('There is no text to save.');
    final book = TextImporter.fromString(clean, title: Names.title(title, fallback: 'Pasted text'));
    final id = newId();
    try {
      return await _store(id, book, DocKind.text, shelfId, clean.length, null);
    } catch (_) {
      await _deleteDir(id);
      rethrow;
    }
  }

  // ── Web ────────────────────────────────────────────────────────────────

  /// Saves web chapters as ONE document (one section per chapter), so a web
  /// novel behaves like a book: continuous listening, table of contents,
  /// a single library entry.
  Future<Doc> importArticles(List<WebArticle> articles, {String? shelfId, String? title}) async {
    if (articles.isEmpty) throw const ImportException('Nothing to save.');
    final first = articles.first;
    final book = ParsedBook(
      title: Names.title(title ?? first.siteName ?? first.title),
      language: first.language,
      sections: [for (final a in articles) ReaderSection(title: a.title, blocks: a.blocks)],
    );
    final id = newId();
    try {
      final doc = await _store(id, book, DocKind.web, shelfId, 0, null);
      return await _library.updateDoc(
            id,
            (d) => d.copyWith(sourceUrl: articles.last.url.toString(), nextUrl: articles.last.nextUrl?.toString()),
          ) ??
          doc;
    } catch (_) {
      await _deleteDir(id);
      rethrow;
    }
  }

  /// Appends further chapters to a saved web document.
  Future<Doc?> appendArticles(Doc doc, List<WebArticle> articles) async {
    if (articles.isEmpty) return doc;
    final count = await _content.append(doc.id, [
      for (final a in articles) ReaderSection(title: a.title, blocks: a.blocks),
    ]);
    return _library.updateDoc(
      doc.id,
      (d) => d.copyWith(
        sectionCount: count,
        sourceUrl: articles.last.url.toString(),
        nextUrl: articles.last.nextUrl?.toString(),
        clearNextUrl: articles.last.nextUrl == null,
      ),
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<Doc> _store(
    String id,
    ParsedBook book,
    DocKind kind,
    String? shelfId,
    int size,
    String? sourceFile,
  ) async {
    final sections = book.sections.where((s) => s.blocks.isNotEmpty).toList();
    if (sections.isEmpty) throw const ImportException('No readable text was found.');

    for (final e in book.images.entries) {
      final f = _content.image(id, e.key);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(e.value);
    }
    final Uint8List? cover = book.cover;
    if (cover != null) await _paths.coverFile(id).writeAsBytes(cover);

    await _content.writeAll(id, sections);
    final doc = Doc(
      id: id,
      title: book.title,
      author: book.author,
      kind: kind,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      shelfId: shelfId,
      sizeBytes: size,
      sectionCount: sections.length,
      pageCount: book.pageCount,
      language: book.language,
      sourceFile: sourceFile,
      hasCover: cover != null,
    );
    await _library.putDoc(doc);
    return doc;
  }

  Future<void> _deleteDir(String id) async {
    final d = _paths.docDir(id);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
