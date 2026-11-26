import 'dart:typed_data';

/// Parsed WAV header.
final class WavInfo {
  const WavInfo({
    required this.format,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  /// 1 = PCM integer, 3 = IEEE float.
  final int format;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get bytesPerFrame => channels * (bitsPerSample ~/ 8);
  int get frames => bytesPerFrame == 0 ? 0 : dataLength ~/ bytesPerFrame;
  int get durationMs => sampleRate == 0 ? 0 : (frames * 1000) ~/ sampleRate;
}

/// Minimal WAV reader/writer.
///
/// Android media players are happiest with 16-bit PCM, but Sherpa and the PC
/// server produce 32-bit float audio. [toPcm16] normalises both.
abstract final class WavCodec {
  static WavInfo? parse(Uint8List b) {
    if (b.length < 44) return null;
    final d = ByteData.sublistView(b);
    if (_tag(b, 0) != 'RIFF' || _tag(b, 8) != 'WAVE') return null;
    var pos = 12;
    int? format, channels, rate, bits;
    while (pos + 8 <= b.length) {
      final id = _tag(b, pos);
      var size = d.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= b.length) {
        format = d.getUint16(body, Endian.little);
        channels = d.getUint16(body + 2, Endian.little);
        rate = d.getUint32(body + 4, Endian.little);
        bits = d.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26 && body + 26 <= b.length) {
          // WAVE_FORMAT_EXTENSIBLE: real format is the first 2 bytes of the sub-format GUID.
          format = d.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        // Streaming encoders write 0 or 0xFFFFFFFF; trust the file length.
        if (size == 0 || size == 0xFFFFFFFF || body + size > b.length) size = b.length - body;
        if (format == null || channels == null || rate == null || bits == null) return null;
        return WavInfo(
          format: format,
          channels: channels,
          sampleRate: rate,
          bitsPerSample: bits,
          dataOffset: body,
          dataLength: size,
        );
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }

  /// Converts any supported WAV (8/16/24/32-bit PCM or 32-bit float) to
  /// 16-bit PCM. Returns the input untouched if it already is 16-bit PCM.
  /// Returns `null` if the input is not a supported WAV.
  static Uint8List? toPcm16(Uint8List wav) {
    final info = parse(wav);
    if (info == null) return null;
    if (info.format == 1 && info.bitsPerSample == 16) return wav;
    final src = ByteData.sublistView(wav, info.dataOffset, info.dataOffset + info.dataLength);
    final bytes = info.bitsPerSample ~/ 8;
    final count = info.dataLength ~/ bytes;
    final out = Int16List(count);
    for (var i = 0; i < count; i++) {
      final o = i * bytes;
      double v;
      if (info.format == 3 && info.bitsPerSample == 32) {
        v = src.getFloat32(o, Endian.little);
      } else if (info.format == 3 && info.bitsPerSample == 64) {
        v = src.getFloat64(o, Endian.little);
      } else if (info.bitsPerSample == 8) {
        v = (src.getUint8(o) - 128) / 128;
      } else if (info.bitsPerSample == 24) {
        var s = src.getUint8(o) | (src.getUint8(o + 1) << 8) | (src.getUint8(o + 2) << 16);
        if (s & 0x800000 != 0) s -= 0x1000000;
        v = s / 8388608;
      } else if (info.bitsPerSample == 32) {
        v = src.getInt32(o, Endian.little) / 2147483648;
      } else if (info.bitsPerSample == 16) {
        v = src.getInt16(o, Endian.little) / 32768;
      } else {
        return null;
      }
      out[i] = _clip(v);
    }
    return encodePcm16(out, info.sampleRate, channels: info.channels);
  }

  /// Float samples in −1‥1 → 16-bit PCM WAV.
  static Uint8List encodeFloat(Float32List samples, int sampleRate, {int channels = 1}) {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcm[i] = _clip(samples[i]);
    }
    return encodePcm16(pcm, sampleRate, channels: channels);
  }

  static Uint8List encodePcm16(Int16List samples, int sampleRate, {int channels = 1}) {
    final dataLen = samples.length * 2;
    final out = Uint8List(44 + dataLen);
    final d = ByteData.sublistView(out);
    void tag(int o, String s) {
      for (var i = 0; i < 4; i++) {
        out[o + i] = s.codeUnitAt(i);
      }
    }

    tag(0, 'RIFF');
    d.setUint32(4, 36 + dataLen, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, channels, Endian.little);
    d.setUint32(24, sampleRate, Endian.little);
    d.setUint32(28, sampleRate * channels * 2, Endian.little);
    d.setUint16(32, channels * 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    d.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      d.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return out;
  }

  /// A silent 16-bit mono WAV of [ms] milliseconds.
  static Uint8List silence(int ms, {int sampleRate = 24000}) =>
      encodePcm16(Int16List((sampleRate * ms) ~/ 1000), sampleRate);

  static int durationMs(Uint8List wav) => parse(wav)?.durationMs ?? 0;

  static int _clip(double v) {
    final s = (v * 32767).round();
    return s > 32767 ? 32767 : (s < -32768 ? -32768 : s);
  }

  static String _tag(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));
}
