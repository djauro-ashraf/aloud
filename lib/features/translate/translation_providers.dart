import 'dart:async';
import 'dart:convert';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

import '../../data/repositories/settings_repository.dart';

/// A user-presentable translation failure.
final class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One way of translating text. Providers differ wildly in limits and
/// authentication; this interface hides that from the rest of the app.
abstract interface class TranslationProvider {
  String get id;
  String get label;

  /// Works without internet once models are downloaded.
  bool get offline;

  /// Largest number of texts and characters accepted per call.
  int get maxTexts;
  int get maxChars;

  /// [from] is a base language code or `auto`.
  Future<List<String>> translate(List<String> texts, {required String from, required String to});
}

/// Metadata for the settings screen (no instances, no network).
final class ProviderInfo {
  const ProviderInfo(this.id, this.label, this.blurb, {this.secrets = const [], this.offline = false});

  final String id;
  final String label;
  final String blurb;

  /// Secret keys the user must provide, with field labels.
  final List<(String key, String label)> secrets;
  final bool offline;
}

abstract final class TranslationProviders {
  static const infos = <ProviderInfo>[
    ProviderInfo('mlkit', 'On-device (ML Kit)', 'Free and private. Downloads ~30 MB per language once.', offline: true),
    ProviderInfo('mymemory', 'MyMemory', 'Free, no account. Slow and limited for long books.'),
    ProviderInfo('deepl', 'DeepL', 'High-quality. Free API key available.',
        secrets: [(SecretKeys.deepl, 'DeepL API key')]),
    ProviderInfo('google', 'Google Cloud Translation', 'Needs a Google Cloud API key.',
        secrets: [(SecretKeys.google, 'API key')]),
    ProviderInfo('azure', 'Microsoft Translator', 'Free tier available in Azure.',
        secrets: [(SecretKeys.azure, 'Subscription key'), (SecretKeys.azureRegion, 'Region (e.g. westeurope)')]),
    ProviderInfo('libre', 'LibreTranslate', 'Self-hosted or public instance.',
        secrets: [(SecretKeys.libreUrl, 'Server URL'), (SecretKeys.libreKey, 'API key (optional)')]),
    ProviderInfo('openai', 'OpenAI', 'Natural, context-aware literary translation.',
        secrets: [(SecretKeys.openAi, 'OpenAI API key')]),
    ProviderInfo('gemini', 'Google Gemini', 'Natural translation with a generous free tier.',
        secrets: [(SecretKeys.gemini, 'Gemini API key')]),
  ];

  static ProviderInfo info(String id) => infos.firstWhere((i) => i.id == id, orElse: () => infos.first);

  /// Builds the provider, reading its keys from the keystore.
  static Future<TranslationProvider> create(String id, SecretsStore secrets, {http.Client? client}) async {
    final c = client ?? http.Client();
    Future<String> need(String key, String what) async {
      final v = await secrets.read(key);
      if (v == null || v.trim().isEmpty) throw TranslationException('Add your $what in Settings → Translation.');
      return v.trim();
    }

    switch (id) {
      case 'mlkit':
        return MlKitProvider();
      case 'mymemory':
        return MyMemoryProvider(c);
      case 'deepl':
        return DeepLProvider(c, await need(SecretKeys.deepl, 'DeepL key'));
      case 'google':
        return GoogleProvider(c, await need(SecretKeys.google, 'Google API key'));
      case 'azure':
        return AzureProvider(
          c,
          await need(SecretKeys.azure, 'Azure key'),
          (await secrets.read(SecretKeys.azureRegion))?.trim() ?? '',
        );
      case 'libre':
        return LibreProvider(c, await need(SecretKeys.libreUrl, 'LibreTranslate server URL'),
            (await secrets.read(SecretKeys.libreKey))?.trim());
      case 'openai':
        return OpenAiProvider(c, await need(SecretKeys.openAi, 'OpenAI key'));
      case 'gemini':
        return GeminiProvider(c, await need(SecretKeys.gemini, 'Gemini key'));
      default:
        throw TranslationException('Unknown translation provider "$id".');
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

Map<String, String> _json([Map<String, String> extra = const {}]) =>
    {'Content-Type': 'application/json; charset=utf-8', ...extra};

Object? _decode(http.Response r, String who) {
  if (r.statusCode == 401 || r.statusCode == 403) {
    throw TranslationException('$who rejected the API key (HTTP ${r.statusCode}).');
  }
  if (r.statusCode == 429) throw TranslationException('$who rate limit reached. Try again in a minute.');
  if (r.statusCode >= 400) throw TranslationException('$who error (HTTP ${r.statusCode}).');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

String _unescape(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

Future<http.Response> _send(Future<http.Response> Function() call, String who) async {
  try {
    return await call().timeout(const Duration(seconds: 45));
  } on TimeoutException {
    throw TranslationException('$who did not answer in time.');
  } on Exception {
    throw TranslationException('Could not reach $who. Check your connection.');
  }
}

// ── Offline ───────────────────────────────────────────────────────────────

/// Google ML Kit on-device translation.
final class MlKitProvider implements TranslationProvider {
  @override
  String get id => 'mlkit';
  @override
  String get label => 'On-device';
  @override
  bool get offline => true;
  @override
  int get maxTexts => 40;
  @override
  int get maxChars => 4000;

  static final _models = OnDeviceTranslatorModelManager();

  static Future<bool> isDownloaded(String lang) => _models.isModelDownloaded(lang);

  static Future<bool> download(String lang) => _models.downloadModel(lang, isWifiRequired: false);

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final src = BCP47Code.fromRawValue(from);
    final dst = BCP47Code.fromRawValue(to);
    if (src == null || dst == null) {
      throw TranslationException('On-device translation does not support "${src == null ? from : to}".');
    }
    for (final l in [from, to]) {
      if (!await isDownloaded(l)) {
        final ok = await download(l);
        if (!ok) throw TranslationException('Could not download the on-device model for "$l".');
      }
    }
    final translator = OnDeviceTranslator(sourceLanguage: src, targetLanguage: dst);
    try {
      return [for (final t in texts) await translator.translateText(t)];
    } finally {
      await translator.close();
    }
  }
}

// ── Classic APIs ──────────────────────────────────────────────────────────

final class MyMemoryProvider implements TranslationProvider {
  MyMemoryProvider(this._c);
  final http.Client _c;
  @override
  String get id => 'mymemory';
  @override
  String get label => 'MyMemory';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 1;
  @override
  int get maxChars => 450;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final src = from == 'auto' ? 'en' : from;
    final out = <String>[];
    for (final t in texts) {
      final uri = Uri.https('api.mymemory.translated.net', '/get', {'q': t, 'langpair': '$src|$to'});
      final j = _decode(await _send(() => _c.get(uri), 'MyMemory'), 'MyMemory') as Map;
      final text = (j['responseData'] as Map?)?['translatedText'] as String?;
      if (text == null || text.contains('MYMEMORY WARNING')) {
        throw const TranslationException('MyMemory daily limit reached. Try another provider or tomorrow.');
      }
      out.add(_unescape(text));
    }
    return out;
  }
}

final class GoogleProvider implements TranslationProvider {
  GoogleProvider(this._c, this._key);
  final http.Client _c;
  final String _key;
  @override
  String get id => 'google';
  @override
  String get label => 'Google';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 100;
  @override
  int get maxChars => 25000;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final res = await _send(
      () => _c.post(
        Uri.https('translation.googleapis.com', '/language/translate/v2', {'key': _key}),
        headers: _json(),
        body: jsonEncode({'q': texts, 'target': to, if (from != 'auto') 'source': from, 'format': 'text'}),
      ),
      'Google Translate',
    );
    final j = _decode(res, 'Google Translate') as Map;
    final list = ((j['data'] as Map)['translations'] as List).cast<Map<Object?, Object?>>();
    return [for (final t in list) _unescape('${t['translatedText']}')];
  }
}

final class DeepLProvider implements TranslationProvider {
  DeepLProvider(this._c, this._key);
  final http.Client _c;
  final String _key;
  @override
  String get id => 'deepl';
  @override
  String get label => 'DeepL';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 40;
  @override
  int get maxChars => 20000;

  static String _code(String c, {required bool target}) {
    final u = c.toUpperCase();
    if (!target) return u;
    return switch (u) { 'EN' => 'EN-US', 'PT' => 'PT-BR', _ => u };
  }

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final host = _key.endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
    final res = await _send(
      () => _c.post(
        Uri.https(host, '/v2/translate'),
        headers: _json({'Authorization': 'DeepL-Auth-Key $_key'}),
        body: jsonEncode({
          'text': texts,
          'target_lang': _code(to, target: true),
          if (from != 'auto') 'source_lang': _code(from, target: false),
        }),
      ),
      'DeepL',
    );
    final j = _decode(res, 'DeepL') as Map;
    return [for (final t in (j['translations'] as List).cast<Map<Object?, Object?>>()) '${t['text']}'];
  }
}

final class AzureProvider implements TranslationProvider {
  AzureProvider(this._c, this._key, this._region);
  final http.Client _c;
  final String _key;
  final String _region;
  @override
  String get id => 'azure';
  @override
  String get label => 'Microsoft';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 100;
  @override
  int get maxChars => 40000;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final res = await _send(
      () => _c.post(
        Uri.https('api.cognitive.microsofttranslator.com', '/translate', {
          'api-version': '3.0',
          'to': to,
          if (from != 'auto') 'from': from,
        }),
        headers: _json({
          'Ocp-Apim-Subscription-Key': _key,
          if (_region.isNotEmpty) 'Ocp-Apim-Subscription-Region': _region,
        }),
        body: jsonEncode([for (final t in texts) {'Text': t}]),
      ),
      'Microsoft Translator',
    );
    final j = _decode(res, 'Microsoft Translator') as List;
    return [
      for (final item in j.cast<Map<Object?, Object?>>())
        '${((item['translations'] as List).first as Map)['text']}',
    ];
  }
}

final class LibreProvider implements TranslationProvider {
  LibreProvider(this._c, this._url, this._key);
  final http.Client _c;
  final String _url;
  final String? _key;
  @override
  String get id => 'libre';
  @override
  String get label => 'LibreTranslate';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 20;
  @override
  int get maxChars => 5000;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final base = _url.replaceAll(RegExp(r'/+$'), '');
    final res = await _send(
      () => _c.post(
        Uri.parse('$base/translate'),
        headers: _json(),
        body: jsonEncode({
          'q': texts,
          'source': from,
          'target': to,
          'format': 'text',
          if (_key != null && _key.isNotEmpty) 'api_key': _key,
        }),
      ),
      'LibreTranslate',
    );
    final j = _decode(res, 'LibreTranslate') as Map;
    final t = j['translatedText'];
    return t is List ? [for (final x in t) '$x'] : ['$t'];
  }
}

// ── LLM providers ─────────────────────────────────────────────────────────

String _llmPrompt(List<String> texts, String from, String to) =>
    'Translate each string in the JSON array below from ${from == 'auto' ? 'its source language' : from} '
    'into the language with code "$to". Keep names, tone and punctuation natural for audiobook narration. '
    'Respond with ONLY a JSON array of exactly ${texts.length} strings, in the same order, no commentary.\n\n'
    '${jsonEncode(texts)}';

List<String> _parseLlmArray(String raw, int expected) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '').replaceAll(RegExp(r'\s*```$'), '');
  final start = s.indexOf('[');
  final end = s.lastIndexOf(']');
  if (start < 0 || end <= start) throw const TranslationException('The AI answered in an unexpected format.');
  final list = jsonDecode(s.substring(start, end + 1)) as List;
  if (list.length != expected) {
    throw const TranslationException('The AI returned a different number of paragraphs than requested.');
  }
  return [for (final x in list) '$x'];
}

final class OpenAiProvider implements TranslationProvider {
  OpenAiProvider(this._c, this._key, {this.model = 'gpt-4o-mini'});
  final http.Client _c;
  final String _key;
  final String model;
  @override
  String get id => 'openai';
  @override
  String get label => 'OpenAI';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 20;
  @override
  int get maxChars => 5000;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final res = await _send(
      () => _c.post(
        Uri.https('api.openai.com', '/v1/chat/completions'),
        headers: _json({'Authorization': 'Bearer $_key'}),
        body: jsonEncode({
          'model': model,
          'temperature': 0.2,
          'messages': [
            {'role': 'user', 'content': _llmPrompt(texts, from, to)},
          ],
        }),
      ),
      'OpenAI',
    );
    final j = _decode(res, 'OpenAI') as Map;
    final content = (((j['choices'] as List).first as Map)['message'] as Map)['content'] as String;
    return _parseLlmArray(content, texts.length);
  }
}

final class GeminiProvider implements TranslationProvider {
  GeminiProvider(this._c, this._key, {this.model = 'gemini-2.0-flash'});
  final http.Client _c;
  final String _key;
  final String model;
  @override
  String get id => 'gemini';
  @override
  String get label => 'Gemini';
  @override
  bool get offline => false;
  @override
  int get maxTexts => 20;
  @override
  int get maxChars => 5000;

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    final res = await _send(
      () => _c.post(
        Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent', {'key': _key}),
        headers: _json(),
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': _llmPrompt(texts, from, to)},
              ],
            },
          ],
          'generationConfig': {'temperature': 0.2},
        }),
      ),
      'Gemini',
    );
    final j = _decode(res, 'Gemini') as Map;
    final parts = ((((j['candidates'] as List).first as Map)['content'] as Map)['parts'] as List);
    return _parseLlmArray((parts.first as Map)['text'] as String, texts.length);
  }
}
