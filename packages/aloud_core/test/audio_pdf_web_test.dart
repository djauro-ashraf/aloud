import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:test/test.dart';

void main() {
  group('WavCodec', () {
    test('encode → parse', () {
      final wav = WavCodec.encodePcm16(Int16List.fromList([0, 1000, -1000, 32767]), 16000);
      final info = WavCodec.parse(wav)!;
      expect(info.sampleRate, 16000);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
      expect(info.frames, 4);
    });
    test('float32 wav converts to pcm16', () {
      // Hand-build a float32 WAV with 3 samples.
      final data = ByteData(12)
        ..setFloat32(0, 0.0, Endian.little)
        ..setFloat32(4, 0.5, Endian.little)
        ..setFloat32(8, -1.0, Endian.little);
      final out = Uint8List(44 + 12);
      final d = ByteData.sublistView(out);
      void tag(int o, String s) {
        for (var i = 0; i < 4; i++) {
          out[o + i] = s.codeUnitAt(i);
        }
      }
      tag(0, 'RIFF');
      d.setUint32(4, 36 + 12, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      d.setUint32(16, 16, Endian.little);
      d.setUint16(20, 3, Endian.little);
      d.setUint16(22, 1, Endian.little);
      d.setUint32(24, 22050, Endian.little);
      d.setUint32(28, 22050 * 4, Endian.little);
      d.setUint16(32, 4, Endian.little);
      d.setUint16(34, 32, Endian.little);
      tag(36, 'data');
      d.setUint32(40, 12, Endian.little);
      out.setRange(44, 56, data.buffer.asUint8List());

      final pcm = WavCodec.toPcm16(out)!;
      final info = WavCodec.parse(pcm)!;
      expect(info.format, 1);
      expect(info.bitsPerSample, 16);
      expect(info.sampleRate, 22050);
      final s = ByteData.sublistView(pcm, info.dataOffset);
      expect(s.getInt16(0, Endian.little), 0);
      expect(s.getInt16(2, Endian.little), closeTo(16384, 2));
      expect(s.getInt16(4, Endian.little), -32767);
    });
    test('garbage is rejected, silence has duration', () {
      expect(WavCodec.parse(Uint8List(10)), isNull);
      expect(WavCodec.toPcm16(Uint8List(100)), isNull);
      expect(WavCodec.durationMs(WavCodec.silence(500)), 500);
    });
    test('float encode clips', () {
      final wav = WavCodec.encodeFloat(Float32List.fromList([2.0, -2.0]), 8000);
      final s = ByteData.sublistView(wav, 44);
      expect(s.getInt16(0, Endian.little), 32767);
      expect(s.getInt16(2, Endian.little), -32768);
    });
  });

  group('PdfCleanup', () {
    const words = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot'];
    List<List<String>> book() => [
          for (var p = 1; p <= 6; p++)
            [
              'MY GREAT BOOK',
              '',
              'This is the first line of the ${words[p - 1]} page and it keeps going on and on',
              'until it wraps around to a second line with a ${words[p - 1]} hyphen-',
              'ated word that should be joined. A new sentence follows here for ${words[p - 1]}',
              'and ends the ${words[p - 1]} paragraph.',
              '',
              '$p',
            ],
        ];

    test('removes repeated headers and page numbers', () {
      final r = PdfCleanup.clean(book());
      final all = r.paragraphs.map((p) => p.text).join(' ');
      expect(all.contains('MY GREAT BOOK'), isFalse);
      expect(r.removed.where((x) => x.reason == 'page number').length, 6);
      expect(r.removed.where((x) => x.reason == 'repeated header/footer').length, 6);
    });
    test('joins hyphenation and wrapped lines', () {
      final r = PdfCleanup.clean(book());
      expect(r.paragraphs.first.text.contains('hyphenated word'), isTrue);
      expect(r.paragraphs.first.page, 0);
    });
    test('short documents keep their edges but lose bare page numbers', () {
      final r = PdfCleanup.clean([
        ['Title', 'Some text here.', '1'],
      ]);
      expect(r.paragraphs.map((p) => p.text).join(' '), 'Title Some text here.');
    });
    test('paragraph continues across a page break', () {
      final r = PdfCleanup.clean([
        ['This sentence is long enough to look like a full wrapped line of text and', 'continues'],
        ['onto the next page.'],
      ]);
      expect(r.paragraphs.length, 1);
      expect(r.paragraphs.first.text.endsWith('next page.'), isTrue);
    });
    test('custom patterns', () {
      final r = PdfCleanup.clean([
        ['Downloaded from x.com', 'Real text.'],
      ], config: PdfCleanupConfig(extraRemove: [RegExp('^Downloaded from')]));
      expect(r.paragraphs.single.text, 'Real text.');
    });
  });

  group('WebTextPolisher', () {
    test('drops site chrome, keeps story', () {
      final out = WebTextPolisher.polish([
        'Share',
        'Chapter 5: The Door',
        'He opened the door.',
        'Next Chapter',
        'Translator: Bob',
        'Read the latest chapters at NovelFull.com',
        '© 2024 Somebody. All rights reserved.',
        'She smiled.',
      ]);
      expect(out, ['Chapter 5: The Door', 'He opened the door.', 'She smiled.']);
    });
    test('drops duplicate leading title but keeps one heading', () {
      final out = WebTextPolisher.polish(['# Chapter 5: The Door', 'Chapter 5: The Door', 'Body.'],
          title: 'Chapter 5: The Door');
      expect(out, ['# Chapter 5: The Door', 'Body.']);
    });
    test('heading and scene break helpers', () {
      expect(WebTextPolisher.isHeading('# Hello'), isTrue);
      expect(WebTextPolisher.isSceneBreak('* * *'), isTrue);
      expect(WebTextPolisher.stripHeadingMarker('## Hi'), 'Hi');
    });
  });
}
