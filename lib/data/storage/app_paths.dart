import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves every on-disk location the app uses for one vault.
///
/// A *vault* is an isolated data space (library, rules, settings, audio
/// cache). The app always has a `main` vault and, if the user enables the
/// decoy feature, a `guest` vault. Large shared downloads (voice models)
/// live outside the vault.
final class AppPaths {
  AppPaths({required this.supportDir, required this.vaultId})
      : root = Directory(p.join(supportDir.path, 'vaults', vaultId));

  /// Platform application-support directory.
  final Directory supportDir;
  final String vaultId;

  /// `<support>/vaults/<vaultId>`.
  final Directory root;

  File get dbFile => File(p.join(root.path, 'aloud.db'));
  Directory get libraryDir => Directory(p.join(root.path, 'library'));
  Directory get audioCacheDir => Directory(p.join(root.path, 'audio_cache'));
  Directory get tempDir => Directory(p.join(root.path, 'tmp'));

  /// Voice models are large and vault-independent.
  Directory get modelsDir => Directory(p.join(supportDir.path, 'models'));

  Directory docDir(String docId) => Directory(p.join(libraryDir.path, docId));
  Directory sectionsDir(String docId) => Directory(p.join(docDir(docId).path, 'sections'));
  Directory imagesDir(String docId) => Directory(p.join(docDir(docId).path, 'images'));
  Directory pagesDir(String docId) => Directory(p.join(docDir(docId).path, 'pages'));
  Directory translationsDir(String docId) => Directory(p.join(docDir(docId).path, 'translations'));
  File sectionFile(String docId, int i) => File(p.join(sectionsDir(docId).path, '$i.json'));
  File coverFile(String docId) => File(p.join(docDir(docId).path, 'cover.jpg'));
  File sourceFile(String docId, String name) => File(p.join(docDir(docId).path, name));

  /// Creates the vault's base directories.
  Future<void> ensure() async {
    for (final d in [root, libraryDir, audioCacheDir, tempDir, modelsDir]) {
      await d.create(recursive: true);
    }
  }
}
