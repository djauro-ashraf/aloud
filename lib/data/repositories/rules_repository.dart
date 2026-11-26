import 'dart:convert';

import 'package:aloud_core/aloud_core.dart';
import 'package:sembast/sembast.dart';

import '../db/app_database.dart';

/// Persists the user's listening rules.
final class RulesRepository {
  RulesRepository(this._db);

  final AppDatabase _db;

  static const _seededKey = 'rulesSeeded';

  Stream<List<SpeechRule>> watch() => _db.rules.query().onSnapshots(_db.db).map(_sorted);

  Future<List<SpeechRule>> all() async => _sorted(await _db.rules.query().getSnapshots(_db.db));

  List<SpeechRule> _sorted(List<RecordSnapshot<String, Map<String, Object?>>> snaps) {
    final list = [for (final s in snaps) SpeechRule.fromJson(s.value)];
    list.sort((a, b) {
      final p = a.priority.compareTo(b.priority);
      return p != 0 ? p : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<void> upsert(SpeechRule rule) => _db.rules.record(rule.id).put(_db.db, rule.toJson());

  Future<void> setEnabled(String id, {required bool enabled}) =>
      _db.rules.record(id).update(_db.db, {'enabled': enabled});

  Future<void> delete(String id) => _db.rules.record(id).delete(_db.db);

  /// Installs the default templates once per vault.
  Future<void> seedDefaultsIfNeeded() async {
    final seeded = await _db.kv.record(_seededKey).get(_db.db);
    if (seeded == true) return;
    await _db.db.transaction((txn) async {
      var prio = 0;
      for (final r in RuleTemplates.defaults()) {
        await _db.rules.record(r.id).put(txn, r.copyWith(priority: prio++).toJson());
      }
      await _db.kv.record(_seededKey).put(txn, true);
    });
  }

  /// Installs (or re-enables) a template rule.
  Future<void> installTemplate(RuleTemplate t) async {
    final existing = await _db.rules.record(t.rule.id).get(_db.db);
    if (existing != null) {
      await setEnabled(t.rule.id, enabled: true);
      return;
    }
    final count = await _db.rules.count(_db.db);
    await upsert(t.rule.copyWith(priority: count));
  }

  // ── Import / export ───────────────────────────────────────────────────

  Future<String> exportJson() async {
    final rules = await all();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'rules': [for (final r in rules) r.toJson()],
    });
  }

  /// Imports rules from [json]. Returns how many were added. Imported rules
  /// always get fresh ids so they can't overwrite existing ones.
  Future<int> importJson(String json, {required String Function() newId}) async {
    final decoded = jsonDecode(json);
    final list = decoded is Map ? decoded['rules'] : decoded;
    if (list is! List) throw const FormatException('Not a rules file');
    var added = 0;
    final base = await _db.rules.count(_db.db);
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.of(item.cast<String, Object?>());
      try {
        SpeechRule.fromJson({...map, 'id': 'probe'});
      } catch (_) {
        continue; // skip malformed entries instead of failing the whole import
      }
      map['id'] = newId();
      map['builtIn'] = false;
      map['priority'] = base + added;
      await _db.rules.record(map['id']! as String).put(_db.db, map);
      added++;
    }
    return added;
  }
}
