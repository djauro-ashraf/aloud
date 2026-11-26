import 'dart:convert';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';

/// Result of parsing any source into the reader model.
final class ParsedBook {
  const ParsedBook({
    required this.title,
    required this.sections,
    this.author,
    this.language,
    this.images = const {},
    this.cover,
    this.pageCount = 0,
  });

  final String title;
  final String? author;
  final String? language;
  final List<ReaderSection> sections;

  /// Image resources keyed by the `imageRef` used in blocks.
  final Map<String, Uint8List> images;
  final Uint8List? cover;
  final int pageCount;
}

/// Decodes bytes of unknown text encoding.
abstract final class TextDecoder {
  static String decode(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      return utf8.decode(b.sublist(3), allowMalformed: true);
    }
    if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return _utf16(b, 2, littleEndian: true);
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16(b, 2, littleEndian: false);
    try {
      return utf8.decode(b);
    } on FormatException {
      // Legacy 8-bit text (Windows-1252 / Latin-1) is the common fallback.
      return latin1.decode(b);
    }
  }

  static String _utf16(Uint8List b, int offset, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = offset; i + 1 < b.length; i += 2) {
      units.add(littleEndian ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
    }
    return String.fromCharCodes(units);
  }
}

/// Plain-text → sections.
abstract final class TextImporter {
  static ParsedBook parse(Uint8List bytes, {required String fileName}) =>
      fromString(TextDecoder.decode(bytes), title: Names.titleFromFileName(fileName));

  static ParsedBook fromString(String text, {required String title}) {
    final paragraphs = Paragraphs.parse(text);
    final blocks = BlockClassifier.classifyAll(paragraphs);
    final sections = ChapterSplitter.split(blocks, fallbackTitle: title);
    final sample = paragraphs.take(40).join(' ');
    return ParsedBook(
      title: title,
      sections: sections.isEmpty ? [ReaderSection(title: title, blocks: const [])] : sections,
      language: Languages.detect(sample),
    );
  }
}
