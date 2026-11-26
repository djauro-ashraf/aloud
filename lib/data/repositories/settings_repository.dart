import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sembast/sembast.dart';

import '../db/app_database.dart';

/// Stores the settings map (see `Prefs`) in the vault database.
final class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _key = 'app';

  Future<Map<String, Object?>> load() async {
    final v = await _db.settings.record(_key).get(_db.db);
    return v == null ? <String, Object?>{} : Map<String, Object?>.of(v);
  }

  Future<void> save(Map<String, Object?> map) => _db.settings.record(_key).put(_db.db, map);
}

/// Names of every secret the app keeps in the platform keystore.
abstract final class SecretKeys {
  static const pcToken = 'pc.token';
  static const deepl = 'translate.deepl';
  static const google = 'translate.google';
  static const azure = 'translate.azure';
  static const azureRegion = 'translate.azure.region';
  static const openAi = 'translate.openai';
  static const gemini = 'translate.gemini';
  static const libreUrl = 'translate.libre.url';
  static const libreKey = 'translate.libre.key';
}

/// API keys and tokens, kept in the Android Keystore (never in the database,
/// never in backups, never logged).
final class SecretsStore {
  SecretsStore(this.vaultId, [FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final String vaultId;
  final FlutterSecureStorage _storage;

  String _k(String key) => 'aloud.$vaultId.$key';

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: _k(key));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _k(key));
    } else {
      await _storage.write(key: _k(key), value: value);
    }
  }

  Future<bool> has(String key) async => (await read(key))?.isNotEmpty ?? false;
}
