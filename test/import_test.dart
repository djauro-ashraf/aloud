import 'dart:convert';
import 'dart:typed_data';

import 'package:aloud/data/import/article_extractor.dart';
import 'package:aloud/data/import/epub_importer.dart';
import 'package:aloud/data/import/import_exception.dart';
import 'package:aloud/data/import/text_importer.dart';
import 'package:aloud_core/aloud_core.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List buildEpub({bool nav3 = false}) {
  final a = Archive();
  void add(String name, String text) {
    final b = utf8.encode(text);
    a.add(ArchiveFile(name, b.length, b));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
  add('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="${nav3 ? '3.0' : '2.0'}">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>The Test Book</dc:title><dc:creator>Ann Author</dc:creator><dc:language>en-GB</dc:language>
    <meta name="cover" content="cov"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cov" href="img/cover.png" media-type="image/png"/>
    <item id="pic" href="img/pic%201.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''');
  add('OEBPS/toc.ncx', '''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
 <navPoint id="a"><navLabel><text>The Beginning</text></navLabel><content src="ch1.xhtml"/></navPoint>
 <navPoint id="b"><navLabel><text>The End</text></navLabel><content src="text/ch2.xhtml#top"/></navPoint>
</navMap></ncx>''');
  add('OEBPS/ch1.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"><body>
<h1>Chapter One</h1>
<p>It was a dark night. <i>Very</i> dark indeed.</p>
<p><i>This whole paragraph is a thought.</i></p>
<hr/>
<p>Next scene starts here.<br/>Second line.</p>
</body></html>''');
  add('OEBPS/text/ch2.xhtml', '''<html xmlns="http://www.w3.org/1999/xhtml"><body>
<div><p>Final chapter text.<sup>1</sup></p><img src="../img/pic%201.png"/></div>
<blockquote><p>A quoted line.</p></blockquote>
</body></html>''');
  add('OEBPS/img/cover.png', 'PNGCOVER');
  add('OEBPS/img/pic 1.png', 'PNGPIC');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  group('EpubImporter', () {
    test('metadata, toc titles, cover', () {
      final book = EpubImporter.parse(buildEpub(), fallbackTitle: 'x');
      expect(book.title, 'The Test Book');
      expect(book.author, 'Ann Author');
      expect(book.language, 'en');
      expect(book.sections.map((s) => s.title).toList(), ['The Beginning', 'The End']);
      expect(book.cover, isNotNull);
    });

    test('blocks: headings, italics, scene breaks, line breaks, quotes, footnotes', () {
      final book = EpubImporter.parse(buildEpub(), fallbackTitle: 'x');
      final b = book.sections[0].blocks;
      expect(b[0].kind, BlockKind.heading);
      expect(b[0].text, 'Chapter One');
      expect(b[1].text, 'It was a dark night. Very dark indeed.');
      expect(b[1].context.italic, isFalse);
      expect(b[2].context.italic, isTrue);
      expect(b[3].kind, BlockKind.sceneBreak);
      expect(b[4].text, 'Next scene starts here.');
      expect(b[5].text, 'Second line.');

      final c = book.sections[1].blocks;
      expect(c[0].text, 'Final chapter text.'); // <sup>1</sup> footnote marker dropped
      expect(c[1].kind, BlockKind.image);
      expect(c.last.kind, BlockKind.quote);
    });

    test('images are resolved relative to the chapter and url-decoded', () {
      final book = EpubImporter.parse(buildEpub(), fallbackTitle: 'x');
      expect(book.images.length, 1);
      final ref = book.sections[1].blocks[1].imageRef!;
      expect(book.images.containsKey(ref), isTrue);
      expect(utf8.decode(book.images[ref]!), 'PNGPIC');
    });

    test('garbage is rejected with a friendly error', () {
      expect(
        () => EpubImporter.parse(Uint8List.fromList([1, 2, 3, 4]), fallbackTitle: 'x'),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('TextImporter', () {
    test('detects chapters and language', () {
      final text = [
        for (var i = 1; i <= 4; i++) ...['Chapter $i', 'Some text for chapter $i. And more of it.'],
      ].join('\n\n');
      final book = TextImporter.fromString(text, title: 'Novel');
      expect(book.sections.length, 4);
      expect(book.sections.first.title, 'Chapter 1');
    });
    test('decodes utf8, utf8 with BOM, utf16 and latin1', () {
      expect(TextDecoder.decode(Uint8List.fromList(utf8.encode('héllo'))), 'héllo');
      expect(TextDecoder.decode(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('ok')])), 'ok');
      expect(TextDecoder.decode(Uint8List.fromList([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])), 'hi');
      expect(TextDecoder.decode(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9])), 'café');
    });
  });

  group('ArticleExtractor', () {
    final para = 'He walked slowly through the quiet forest, thinking about everything that had happened. ' * 3;
    final page = '''
<html lang="en"><head><title>Chapter 7: The Gate | Great Novels</title>
<link rel="next" href="/novel/ch8"/></head>
<body>
<nav><a href="/">Home</a></nav>
<div class="sidebar"><p>Popular novels you may like and other advertising nonsense here.</p></div>
<div id="chapter-content">
  <h1>Chapter 7: The Gate</h1>
  <p>$para</p>
  <p>$para</p>
  <p>Support us on Patreon at patreon.com/xyz</p>
  <p>Next Chapter</p>
</div>
<div class="comments"><p>Great chapter!!! Cannot wait for the next one, author-sama.</p></div>
<script>var x = 1;</script>
</body></html>''';

    test('finds the story, drops chrome, title and next link', () {
      final a = ArticleExtractor.extract(page, Uri.parse('https://example.com/novel/ch7'));
      expect(a.title, 'Chapter 7: The Gate');
      expect(a.nextUrl.toString(), 'https://example.com/novel/ch8');
      final text = a.blocks.map((b) => b.text).join('\n');
      expect(text.contains('quiet forest'), isTrue);
      expect(text.contains('Popular novels'), isFalse);
      expect(text.contains('Great chapter'), isFalse);
      expect(text.contains('var x'), isFalse);
      expect(a.blocks.first.kind, BlockKind.heading);
      expect(a.blocks.where((b) => b.text == 'Next Chapter'), isEmpty);
    });

    test('text-density fallback and anchor-based next link', () {
      final html = '''<html><head><title>Post</title></head><body>
<div class="wrap"><p>${'Sentence one is here and it goes on for a while. ' * 6}</p><p>${'Another long paragraph follows with more words. ' * 6}</p></div>
<div><a href="page2.html">Next Chapter »</a></div></body></html>''';
      final a = ArticleExtractor.extract(html, Uri.parse('https://x.org/a/page1.html'));
      expect(a.blocks.length >= 2, isTrue);
      expect(a.nextUrl.toString(), 'https://x.org/a/page2.html');
    });
  });
}
