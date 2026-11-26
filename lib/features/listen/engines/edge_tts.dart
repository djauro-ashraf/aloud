import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:crypto/crypto.dart';

import 'clip_backend.dart';
import 'speech_backend.dart';

/// Client for Microsoft Edge's online neural voices (the same service the
/// browser's "Read aloud" uses).
///
/// Protocol notes (all behaviour mirrors the previous Android app):
///  * a WebSocket carries one JSON config frame, one SSML frame, then
///    streams MP3 chunks until a `turn.end` text frame;
///  * every connection needs a time-based `Sec-MS-GEC` token, so a wrong
///    device clock makes the handshake fail — we recalibrate from the
///    server's `Date` header and retry once;
///  * binary frames start with a 2-byte header length followed by the header
///    text; only the bytes after it are audio.
final class EdgeTtsClient {
  static const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const _chromium = '143.0.3650.75';
  static const _major = '143';
  static const _host = 'speech.platform.bing.com';
  static const _winEpochSeconds = 11644473600;
  static const _origin = 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/$_major.0.0.0 Safari/537.36 Edg/$_major.0.0.0';

  final _rng = Random.secure();
  int _skewSeconds = 0;

  /// `Sec-MS-GEC`: SHA-256 of the 5-minute-rounded Windows file time + token.
  String _gec() {
    final unix = DateTime.now().millisecondsSinceEpoch ~/ 1000 + _skewSeconds;
    var ticks = unix + _winEpochSeconds;
    ticks -= ticks % 300;
    final fileTime = ticks * 10000000; // 100-ns intervals
    return sha256.convert(utf8.encode('$fileTime$_token')).toString().toUpperCase();
  }

  String _hex32() => List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  Map<String, String> get _headers => {
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': _origin,
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent': _ua,
        'Cookie': 'muid=${_hex32().toUpperCase()};',
      };

  /// Synthesises [text] with [voice]; returns MP3 bytes.
  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    int ratePercent = 0,
    int pitchHz = 0,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _once(text, voice, ratePercent, pitchHz);
      } on WebSocketException catch (e) {
        last = e;
        // Most handshake rejections are clock skew; fix it and retry.
        await _calibrateClock();
      } on TimeoutException catch (e) {
        last = e;
      } on SocketException catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      } on HandshakeException catch (e) {
        last = e;
      }
    }
    throw SpeechException('Edge voice unavailable (${_describe(last)}). Check your connection.');
  }

  String _describe(Object? e) {
    if (e is SocketException) return 'no connection';
    if (e is TimeoutException) return 'timed out';
    if (e is WebSocketException) return 'handshake refused';
    return '$e';
  }

  Future<Uint8List> _once(String text, String voice, int rate, int pitch) async {
    final url = 'wss://$_host/consumer/speech/synthesize/readaloud/edge/v1'
        '?TrustedClientToken=$_token&Sec-MS-GEC=${_gec()}&Sec-MS-GEC-Version=1-$_chromium'
        '&ConnectionId=${_hex32()}';
    final ws = await WebSocket.connect(url, headers: _headers).timeout(const Duration(seconds: 10));
    final audio = BytesBuilder(copy: false);
    final done = Completer<void>();

    final sub = ws.listen(
      (dynamic data) {
        if (data is String) {
          if (data.contains('Path:turn.end') && !done.isCompleted) done.complete();
        } else if (data is List<int>) {
          final bytes = data is Uint8List ? data : Uint8List.fromList(data);
          if (bytes.length < 2) return;
          final headerLen = (bytes[0] << 8) | bytes[1];
          if (bytes.length <= 2 + headerLen) return;
          final header = latin1.decode(bytes.sublist(2, 2 + headerLen), allowInvalid: true);
          if (header.contains('Path:audio')) audio.add(bytes.sublist(2 + headerLen));
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) {
          audio.length > 0
              ? done.complete()
              : done.completeError(const SpeechException('The Edge voice service closed the connection.'));
        }
      },
      cancelOnError: true,
    );

    try {
      final stamp = '${DateTime.now().toUtc().toIso8601String().split('.').first}.000Z';
      ws.add('X-Timestamp:$stamp\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false",'
          '"wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n');
      final ssml = SsmlBuilder.build(text: text, voice: voice, ratePercent: rate, pitchHz: pitch);
      ws.add('X-RequestId:${_hex32()}\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:$stamp\r\n'
          'Path:ssml\r\n\r\n$ssml');
      final timeout = Duration(seconds: (8 + text.length / 40).clamp(8, 30).round());
      await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
      unawaited(ws.close().catchError((Object _) => null));
    }
    if (audio.length == 0) throw const SpeechException('The Edge voice returned no audio.');
    return audio.takeBytes();
  }

  /// Reads the server's clock from an HTTPS `Date` header.
  Future<void> _calibrateClock() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.headUrl(Uri.https(_host, '/'));
      final res = await req.close();
      final date = res.headers.value(HttpHeaders.dateHeader);
      if (date != null) {
        final server = HttpDate.parse(date);
        _skewSeconds = server.difference(DateTime.now().toUtc()).inSeconds;
      }
      await res.drain<void>();
    } catch (_) {
      // Keep the previous skew.
    } finally {
      client.close(force: true);
    }
  }

  /// Live voice list from the service; `null` if offline.
  Future<List<VoiceInfo>?> fetchVoices() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https(_host, '/consumer/speech/synthesize/readaloud/voices/list', {
        'trustedclienttoken': _token,
        'Sec-MS-GEC': _gec(),
        'Sec-MS-GEC-Version': '1-$_chromium',
      });
      final req = await client.getUrl(uri);
      _headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await utf8.decodeStream(res);
      final list = jsonDecode(body) as List<Object?>;
      return [
        for (final v in list)
          if (v is Map)
            VoiceInfo(
              engine: EngineKind.edge,
              id: '${v['ShortName']}',
              name: _friendly('${v['ShortName']}'),
              locale: '${v['Locale']}',
              gender: v['Gender'] as String?,
            ),
      ]..sort((a, b) => a.locale.compareTo(b.locale));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _friendly(String shortName) {
    // en-US-AriaNeural → Aria
    final parts = shortName.split('-');
    return parts.length >= 3 ? parts.sublist(2).join('-').replaceAll('Neural', '') : shortName;
  }
}

/// Built-in voice list, used when the live list can't be fetched.
abstract final class EdgeCatalog {
  static VoiceInfo _v(String id, String gender) => VoiceInfo(
        engine: EngineKind.edge,
        id: id,
        name: EdgeTtsClient._friendly(id),
        locale: id.split('-').take(2).join('-'),
        gender: gender,
      );

  static final List<VoiceInfo> voices = [
    _v('en-US-AriaNeural', 'Female'), _v('en-US-JennyNeural', 'Female'),
    _v('en-US-AvaNeural', 'Female'), _v('en-US-EmmaNeural', 'Female'),
    _v('en-US-MichelleNeural', 'Female'), _v('en-US-AndrewNeural', 'Male'),
    _v('en-US-BrianNeural', 'Male'), _v('en-US-GuyNeural', 'Male'),
    _v('en-US-ChristopherNeural', 'Male'), _v('en-US-EricNeural', 'Male'),
    _v('en-US-RogerNeural', 'Male'), _v('en-US-SteffanNeural', 'Male'),
    _v('en-GB-SoniaNeural', 'Female'), _v('en-GB-LibbyNeural', 'Female'),
    _v('en-GB-RyanNeural', 'Male'), _v('en-GB-ThomasNeural', 'Male'),
    _v('en-AU-NatashaNeural', 'Female'), _v('en-AU-WilliamNeural', 'Male'),
    _v('en-IN-NeerjaNeural', 'Female'), _v('en-IN-PrabhatNeural', 'Male'),
    _v('es-ES-ElviraNeural', 'Female'), _v('es-ES-AlvaroNeural', 'Male'),
    _v('es-MX-DaliaNeural', 'Female'), _v('es-MX-JorgeNeural', 'Male'),
    _v('fr-FR-DeniseNeural', 'Female'), _v('fr-FR-HenriNeural', 'Male'),
    _v('de-DE-KatjaNeural', 'Female'), _v('de-DE-ConradNeural', 'Male'),
    _v('it-IT-ElsaNeural', 'Female'), _v('it-IT-DiegoNeural', 'Male'),
    _v('pt-BR-FranciscaNeural', 'Female'), _v('pt-BR-AntonioNeural', 'Male'),
    _v('pt-PT-RaquelNeural', 'Female'), _v('ru-RU-SvetlanaNeural', 'Female'),
    _v('ru-RU-DmitryNeural', 'Male'), _v('ja-JP-NanamiNeural', 'Female'),
    _v('ja-JP-KeitaNeural', 'Male'), _v('ko-KR-SunHiNeural', 'Female'),
    _v('ko-KR-InJoonNeural', 'Male'), _v('zh-CN-XiaoxiaoNeural', 'Female'),
    _v('zh-CN-YunxiNeural', 'Male'), _v('zh-CN-YunjianNeural', 'Male'),
    _v('zh-TW-HsiaoChenNeural', 'Female'), _v('ar-SA-ZariyahNeural', 'Female'),
    _v('hi-IN-SwaraNeural', 'Female'), _v('hi-IN-MadhurNeural', 'Male'),
    _v('tr-TR-EmelNeural', 'Female'), _v('nl-NL-ColetteNeural', 'Female'),
    _v('pl-PL-ZofiaNeural', 'Female'), _v('id-ID-GadisNeural', 'Female'),
    _v('vi-VN-HoaiMyNeural', 'Female'), _v('th-TH-PremwadeeNeural', 'Female'),
    _v('uk-UA-PolinaNeural', 'Female'),
  ];

  /// A sensible voice for a language code (`es`, `ja`, …), if one exists.
  static VoiceInfo? defaultFor(String language) {
    final l = language.split(RegExp('[-_]')).first.toLowerCase();
    return voices.where((v) => v.language == l).firstOrNull;
  }

  static VoiceInfo? byId(String id) => voices.where((v) => v.id == id).firstOrNull;
}

/// Edge as a [ClipSynthesizer].
final class EdgeSynthesizer implements ClipSynthesizer {
  EdgeSynthesizer(this._client);

  final EdgeTtsClient _client;

  @override
  String get extension => 'mp3';

  @override
  Future<Uint8List> synthesize(String text, VoiceInfo voice) =>
      _client.synthesize(text: text, voice: voice.id);
}
