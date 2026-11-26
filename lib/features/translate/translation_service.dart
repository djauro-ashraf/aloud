import 'dart:convert';
import 'dart:io';

import 'package:aloud_core/aloud_core.dart';
import 'package:path/path.dart' as p;

import '../../core/prefs.dart';
import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/storage/app_paths.dart';
import '../listen/engines/sherpa_models.dart' show CancelToken;
import 'translation_providers.dart';

/// Translates a whole section, remembering results on disk so a chapter is
/// translated (and paid for) only once.
final class TranslationService {
  TranslationService({
    required this._paths,
    required this._secrets,
    required this._prefs,
  });

  final AppPaths _paths;
  final SecretsStore _secrets;
  final Map<String, Object?> Function() _prefs;

  String get providerId => Prefs.translateProvider.read(_prefs());
  String get targetLanguage => Prefs.translateTarget.read(_prefs());

  File _cacheFile(String docId, int section, String provider, String to) =>
      File(p.join(_paths.translationsDir(docId).path, '${to}_${provider}_$section.json'));

  Future<bool> isCached(Doc doc, int section) =>
      _cacheFile(doc.id, section, providerId, targetLanguage).exists();

  /// Returns [section] with every text block translated.
  ///
  /// Images and scene breaks are left alone. Failed batches fall back to the
  /// original text rather than aborting, but a total failure (bad key,
  /// offline) throws [TranslationException].
  Future<ReaderSection> translate(
    Doc doc,
    int sectionIndex,
    ReaderSection section, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    final to = targetLanguage;
    final provider = providerId;
    final cache = _cacheFile(doc.id, sectionIndex, provider, to);

    final speakable = [
      for (var i = 0; i < section.blocks.length; i++)
        if (section.blocks[i].isSpeakable && section.blocks[i].kind != BlockKind.sceneBreak) i,
    ];
    final texts = [for (final i in speakable) section.blocks[i].text];

    List<String>? translated;
    if (await cache.exists()) {
      try {
        final raw = (jsonDecode(await cache.readAsString()) as List).cast<String>();
        if (raw.length == texts.length) translated = raw;
      } catch (_) {
        // Corrupt cache entry: translate again.
      }
    }

    if (translated == null) {
      final from = doc.language ?? Languages.detect(texts.take(20).join(' ')) ?? 'auto';
      if (from == to) return section;
      final impl = await TranslationProviders.create(provider, _secrets);
      final plan = BatchPlan.build(texts, maxTexts: impl.maxTexts, maxChars: impl.maxChars);
      final results = <String, String>{};
      var done = 0;
      for (final batch in plan.batches) {
        if (cancel?.isCancelled ?? false) throw const TranslationException('Cancelled');
        final out = await impl.translate([for (final it in batch) it.text], from: from, to: to);
        for (var i = 0; i < batch.length && i < out.length; i++) {
          results[BatchPlan.key(batch[i])] = out[i];
        }
        done++;
        onProgress?.call(done / plan.batches.length);
      }
      translated = plan.assemble(results);
      await cache.parent.create(recursive: true);
      await cache.writeAsString(jsonEncode(translated));
    }

    final blocks = [...section.blocks];
    for (var k = 0; k < speakable.length; k++) {
      final i = speakable[k];
      blocks[i] = blocks[i].withText(translated[k]);
    }
    return ReaderSection(title: section.title, blocks: blocks);
  }

  Future<void> clearCache(String docId) async {
    final d = _paths.translationsDir(docId);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
