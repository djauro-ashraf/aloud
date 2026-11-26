import 'dart:io';

import '../core/platform/native_bridge.dart';
import '../data/db/app_database.dart';
import '../data/import/import_service.dart';
import '../data/import/pdf_importer.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/rules_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/storage/app_paths.dart';
import '../data/storage/content_store.dart';
import '../features/listen/audio_handler.dart';
import '../features/listen/engines/audio_cache.dart';
import '../features/lock/vault_service.dart';

/// Everything that lives for the lifetime of one opened vault.
///
/// Constructed once per vault in [open] and handed to Riverpod as a single
/// override, so the rest of the app depends on providers, never on `main()`.
/// Closing the vault (lock / switch) disposes the whole provider scope.
final class AppServices {
  AppServices._({
    required this.vault,
    required this.paths,
    required this.db,
    required this.library,
    required this.rules,
    required this.settingsRepo,
    required this.secrets,
    required this.content,
    required this.importer,
    required this.audioCache,
    required this.bridge,
    required this.audioHandler,
    required this.initialSettings,
  });

  final VaultId vault;
  final AppPaths paths;
  final AppDatabase db;
  final LibraryRepository library;
  final RulesRepository rules;
  final SettingsRepository settingsRepo;
  final SecretsStore secrets;
  final ContentStore content;
  final ImportService importer;
  final AudioCache audioCache;
  final NativeBridge bridge;
  final AloudAudioHandler audioHandler;
  final Map<String, Object?> initialSettings;

  static Future<AppServices> open({
    required Directory supportDir,
    required VaultId vault,
    required NativeBridge bridge,
    required AloudAudioHandler audioHandler,
  }) async {
    final paths = AppPaths(supportDir: supportDir, vaultId: vault.folder);
    await paths.ensure();
    final db = await AppDatabase.open(paths.dbFile.path);
    final library = LibraryRepository(db, paths);
    final rules = RulesRepository(db);
    await rules.seedDefaultsIfNeeded();
    final settingsRepo = SettingsRepository(db);
    final content = ContentStore(paths);
    return AppServices._(
      vault: vault,
      paths: paths,
      db: db,
      library: library,
      rules: rules,
      settingsRepo: settingsRepo,
      secrets: SecretsStore(vault.folder),
      content: content,
      importer: ImportService(paths: paths, library: library, content: content, ocr: OcrService()),
      audioCache: AudioCache(paths.audioCacheDir),
      bridge: bridge,
      audioHandler: audioHandler,
      initialSettings: await settingsRepo.load(),
    );
  }

  Future<void> close() => db.close();
}
