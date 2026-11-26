import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:aloud_core/aloud_core.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'import_exception.dart';
import 'text_importer.dart';

/// Progress callback: fraction 0‥1 and a short status line.
typedef ImportProgress = void Function(double fraction, String status);

/// Recognises text on rendered PDF pages (for scanned documents).
final class OcrService {
  OcrService({this.script = TextRecognitionScript.latin});

  final TextRecognitionScript script;

  Future<List<String>> recognizePage(PdfPage page, Directory tmp) async {
    // ~1800px on the long edge is the sweet spot for accuracy vs. speed.
    final scale = 1800 / (page.width > page.height ? page.width : page.height);
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) return const [];
    final recognizer = TextRecognizer(script: script);
    final file = File(p.join(tmp.path, 'ocr_${page.pageNumber}.png'));
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(image.pixels, image.width, image.height, ui.PixelFormat.bgra8888, completer.complete);
      final decoded = await completer.future;
      final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
      decoded.dispose();
      if (png == null) return const [];
      await file.writeAsBytes(png.buffer.asUint8List());
      final result = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return result.text.split(RegExp(r'\r?\n'));
    } finally {
      image.dispose();
      await recognizer.close();
      if (await file.exists()) await file.delete();
    }
  }
}

/// PDF → sections, with header/footer clean-up and optional OCR.
final class PdfImporter {
  PdfImporter({this._ocr});

  final OcrService? _ocr;

  /// Pages per section when the PDF has no chapter headings.
  static const pagesPerSection = 25;

  Future<ParsedBook> parse(
    String path, {
    required String fallbackTitle,
    required Directory tmp,
    ImportProgress? onProgress,
    bool Function()? isCancelled,
    PdfCleanupConfig cleanup = const PdfCleanupConfig(),
  }) async {
    final PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(path);
    } catch (e) {
      throw ImportException('Could not open this PDF (${e.toString().split('\n').first}).');
    }
    try {
      final total = doc.pages.length;
      if (total == 0) throw const ImportException('This PDF has no pages.');

      final pages = <List<String>>[];
      var empty = 0;
      for (var i = 0; i < total; i++) {
        if (isCancelled?.call() ?? false) throw const ImportException('Import cancelled.');
        final raw = await doc.pages[i].loadText();
        final text = raw?.fullText ?? '';
        if (text.trim().length < 10) empty++;
        pages.add(text.split(RegExp(r'\r?\n')));
        onProgress?.call((i + 1) / total * 0.4, 'Reading page ${i + 1} of $total');
      }

      final scanned = empty / total > 0.6;
      if (scanned) {
        final ocr = _ocr;
        if (ocr == null) {
          throw const ImportException('This PDF is a scan without a text layer. Enable OCR to read it.');
        }
        pages.clear();
        for (var i = 0; i < total; i++) {
          if (isCancelled?.call() ?? false) throw const ImportException('Import cancelled.');
          pages.add(await ocr.recognizePage(doc.pages[i], tmp));
          onProgress?.call(0.4 + (i + 1) / total * 0.5, 'Recognising text on page ${i + 1} of $total');
        }
      }

      onProgress?.call(0.92, 'Cleaning up');
      final cleaned = await Isolate.run(() => PdfCleanup.clean(pages, config: cleanup));
      if (cleaned.paragraphs.isEmpty) {
        throw const ImportException('No readable text was found in this PDF.');
      }

      final blocks = [
        for (final para in cleaned.paragraphs) BlockClassifier.classify(para.text).withPage(para.page),
      ];
      final sections = _sections(blocks, fallbackTitle, total);
      return ParsedBook(
        title: fallbackTitle,
        sections: sections,
        language: Languages.detect(cleaned.paragraphs.take(30).map((e) => e.text).join(' ')),
        pageCount: total,
      );
    } finally {
      await doc.dispose();
    }
  }

  static List<ReaderSection> _sections(List<ReaderBlock> blocks, String title, int pageCount) {
    final headings = blocks.where((b) => b.kind == BlockKind.heading && BlockClassifier.isChapterHeading(b.text)).length;
    if (headings >= 3) return ChapterSplitter.split(blocks, fallbackTitle: title);

    final out = <ReaderSection>[];
    for (var start = 0; start < pageCount; start += pagesPerSection) {
      final end = (start + pagesPerSection).clamp(0, pageCount);
      final slice = [
        for (final b in blocks)
          if ((b.page ?? 0) >= start && (b.page ?? 0) < end) b,
      ];
      if (slice.isEmpty) continue;
      out.add(ReaderSection(
        title: pageCount <= pagesPerSection ? title : 'Pages ${start + 1}–$end',
        blocks: slice,
      ));
    }
    return out;
  }
}
