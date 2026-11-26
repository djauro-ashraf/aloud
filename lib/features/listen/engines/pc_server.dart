import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aloud_core/aloud_core.dart';
import 'package:http/http.dart' as http;

import 'clip_backend.dart';
import 'speech_backend.dart';

/// A PC TTS server found on the local network.
final class PcServerInfo {
  const PcServerInfo({required this.url, required this.name, required this.version});

  final String url;
  final String name;
  final String version;
}

/// Result of a `/health` probe.
final class PcHealth {
  const PcHealth({required this.ok, this.message = '', this.version = '', this.serverName = ''});

  final bool ok;
  final String message;
  final String version;
  final String serverName;
}

/// Client for the Aloud/SmartReader PC TTS server: synthesises with big
/// neural voices on your computer and streams WAV back over Wi-Fi.
///
/// Protocol (unchanged from the previous app, so the existing server works):
///  * `GET  /health`  (Bearer token)
///  * `GET  /voices`  → `{voices: [{id, displayName, ready}]}`
///  * `POST /preview` `{voiceId, speakerId, text, noiseScale, noiseScaleW}` → WAV
///  * UDP broadcast `SMARTREADER_TTS_DISCOVER` to port 8766 → JSON reply
///    `{type: "SMARTREADER_TTS_SERVER", url, name, version}`
final class PcServerClient {
  PcServerClient({required this.baseUrl, this.token = '', http.Client? client}) : _client = client ?? http.Client();

  static const discoveryPort = 8766;
  static const _probe = 'SMARTREADER_TTS_DISCOVER';

  final String baseUrl;
  final String token;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> get _auth => {if (token.isNotEmpty) 'Authorization': 'Bearer $token'};

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<PcHealth> health() async {
    if (!isConfigured) return const PcHealth(ok: false, message: 'No server address set.');
    try {
      final res = await _client.get(_uri('/health'), headers: _auth).timeout(const Duration(seconds: 4));
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const PcHealth(ok: false, message: 'The server rejected the access token.');
      }
      if (res.statusCode != 200) return PcHealth(ok: false, message: 'Server answered HTTP ${res.statusCode}.');
      final j = jsonDecode(res.body);
      final m = j is Map ? j : const {};
      return PcHealth(
        ok: true,
        version: '${m['version'] ?? ''}',
        serverName: '${m['serverName'] ?? m['name'] ?? ''}',
      );
    } on TimeoutException {
      return const PcHealth(ok: false, message: 'The server did not answer. Is it running on the same Wi-Fi?');
    } on Exception catch (e) {
      return PcHealth(ok: false, message: 'Cannot reach the server ($e).');
    }
  }

  Future<List<VoiceInfo>> voices() async {
    final res = await _client.get(_uri('/voices'), headers: _auth).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw SpeechException('PC server /voices failed (HTTP ${res.statusCode}).');
    final j = jsonDecode(res.body) as Map;
    final list = (j['voices'] as List?) ?? const [];
    return [
      for (final v in list)
        if (v is Map && '${v['id']}'.isNotEmpty)
          VoiceInfo(
            engine: EngineKind.pc,
            id: '${v['id']}',
            name: '${v['displayName'] ?? v['id']}',
            detail: v['ready'] == false ? 'not ready' : 'ready',
          ),
    ];
  }

  /// Renders [text] and returns 16-bit PCM WAV bytes.
  Future<Uint8List> synthesize(
    String text,
    String voiceId, {
    int speakerId = 0,
    double noiseScale = 0.667,
    double noiseScaleW = 0.8,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _uri('/preview'),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'voiceId': voiceId,
              'speakerId': speakerId,
              'text': text,
              'noiseScale': noiseScale,
              'noiseScaleW': noiseScaleW,
            }),
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const SpeechException('The PC server took too long to render this sentence.');
    } on SocketException {
      throw const SpeechException('Lost connection to the PC server.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const SpeechException('The PC server rejected the access token.', retryable: false);
    }
    if (res.statusCode != 200) throw SpeechException('PC server error (HTTP ${res.statusCode}).');
    // The server may send 32-bit float WAV; Android players want 16-bit PCM.
    final pcm = WavCodec.toPcm16(res.bodyBytes);
    if (pcm == null) throw const SpeechException('The PC server returned audio in an unknown format.');
    return pcm;
  }

  /// Finds a server on the LAN with a UDP broadcast. `null` if none answers.
  static Future<PcServerInfo?> discover({Duration timeout = const Duration(milliseconds: 1500)}) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final probe = utf8.encode(_probe);
      socket.send(probe, InternetAddress('255.255.255.255'), discoveryPort);
      final completer = Completer<PcServerInfo?>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        try {
          final j = jsonDecode(utf8.decode(dg.data)) as Map;
          if (j['type'] != 'SMARTREADER_TTS_SERVER') return;
          final url = '${j['url'] ?? ''}';
          if (url.isEmpty || completer.isCompleted) return;
          completer.complete(PcServerInfo(
            url: url,
            name: '${j['name'] ?? dg.address.address}',
            version: '${j['version'] ?? '?'}',
          ));
        } catch (_) {
          // Ignore unrelated packets.
        }
      });
      final result = await completer.future.timeout(timeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  void close() => _client.close();
}

/// PC server as a [ClipSynthesizer].
final class PcSynthesizer implements ClipSynthesizer {
  PcSynthesizer(this._client, {required this.noise, required this.noiseW});

  final PcServerClient _client;
  final double Function() noise;
  final double Function() noiseW;

  @override
  String get extension => 'wav';

  @override
  Future<Uint8List> synthesize(String text, VoiceInfo voice) =>
      _client.synthesize(text, voice.id, noiseScale: noise(), noiseScaleW: noiseW());
}
