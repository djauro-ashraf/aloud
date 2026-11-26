import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Persisted lock configuration (kept outside any vault database because it
/// must be readable before a vault is opened).
final class VaultConfig {
  const VaultConfig({this.locked = false, this.salt = '', this.hash = '', this.decoy = false});

  /// A passphrase is required at launch.
  final bool locked;
  final String salt;
  final String hash;

  /// Any wrong passphrase opens an empty, separate "guest" library instead of
  /// an error, so an onlooker can't tell a private library exists.
  final bool decoy;

  Map<String, Object?> toJson() => {'locked': locked, 'salt': salt, 'hash': hash, 'decoy': decoy};

  static VaultConfig fromJson(Map<String, Object?> j) => VaultConfig(
        locked: (j['locked'] as bool?) ?? false,
        salt: (j['salt'] as String?) ?? '',
        hash: (j['hash'] as String?) ?? '',
        decoy: (j['decoy'] as bool?) ?? false,
      );
}

/// Which data space to open.
enum VaultId {
  main,
  guest;

  String get folder => name;
}

/// Passphrase lock with an optional decoy library.
///
/// Passphrases are never stored: only a salted, iterated SHA-256 digest
/// (100 000 rounds, computed off the UI isolate). This protects against
/// casual snooping and shoulder-surfing; it does not encrypt files on disk.
final class VaultService {
  VaultService(this._file);

  final File _file;
  static const _rounds = 100000;

  Future<VaultConfig> load() async {
    try {
      if (!await _file.exists()) return const VaultConfig();
      return VaultConfig.fromJson((jsonDecode(await _file.readAsString()) as Map).cast<String, Object?>());
    } catch (_) {
      return const VaultConfig();
    }
  }

  Future<void> _save(VaultConfig c) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(c.toJson()));
  }

  static String _newSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  static Future<String> _digest(String passphrase, String salt) =>
      Isolate.run(() {
        var d = sha256.convert(utf8.encode('$salt:$passphrase')).bytes;
        for (var i = 0; i < _rounds; i++) {
          d = sha256.convert([...d, ...utf8.encode(salt)]).bytes;
        }
        return base64Url.encode(d);
      });

  Future<void> enable(String passphrase, {required bool decoy}) async {
    final salt = _newSalt();
    await _save(VaultConfig(locked: true, salt: salt, hash: await _digest(passphrase, salt), decoy: decoy));
  }

  Future<void> disable() => _save(const VaultConfig());

  Future<void> setDecoy(bool decoy) async {
    final c = await load();
    await _save(VaultConfig(locked: c.locked, salt: c.salt, hash: c.hash, decoy: decoy));
  }

  /// `main` for the right passphrase; `guest` for a wrong one when decoy mode
  /// is on; `null` for a wrong one otherwise.
  Future<VaultId?> unlock(String passphrase) async {
    final c = await load();
    if (!c.locked) return VaultId.main;
    final ok = await _digest(passphrase, c.salt) == c.hash;
    if (ok) return VaultId.main;
    return c.decoy ? VaultId.guest : null;
  }

  Future<bool> verify(String passphrase) async {
    final c = await load();
    return c.locked && await _digest(passphrase, c.salt) == c.hash;
  }
}
