import 'dart:convert';

import 'package:http/http.dart' as http;

import 'import_exception.dart';

/// Downloads a web page as text, handling encodings and common failures.
final class WebFetcher {
  WebFetcher([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0.0.0 Mobile Safari/537.36';

  /// Normalises user input: adds a scheme, trims, validates.
  static Uri? parseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty || s.contains(' ')) return null;
    if (!RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false).hasMatch(s)) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty || !u.host.contains('.')) {
      return null;
    }
    return u;
  }

  Future<String> fetch(Uri url) async {
    final http.Response res;
    try {
      res = await _client.get(url, headers: {
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 25));
    } on Exception catch (e) {
      throw ImportException('Could not reach ${url.host}: ${_short(e)}');
    }
    if (res.statusCode == 403 || res.statusCode == 503) {
      throw ImportException(
        '${url.host} blocked the request (HTTP ${res.statusCode}). '
        'Try "Open in browser view" and import from there.',
      );
    }
    if (res.statusCode >= 400) {
      throw ImportException('The server answered HTTP ${res.statusCode}.');
    }
    return decode(res);
  }

  static String decode(http.Response res) {
    final bytes = res.bodyBytes;
    final header = res.headers['content-type'] ?? '';
    var charset = RegExp(r'charset=([\w\-]+)', caseSensitive: false).firstMatch(header)?.group(1)?.toLowerCase();
    if (charset == null) {
      final head = latin1.decode(bytes.take(2048).toList(), allowInvalid: true);
      charset = RegExp(r'''charset\s*=\s*["']?([\w\-]+)''', caseSensitive: false)
          .firstMatch(head)
          ?.group(1)
          ?.toLowerCase();
    }
    if (charset == 'iso-8859-1' || charset == 'latin1' || charset == 'windows-1252') {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void close() => _client.close();
}
