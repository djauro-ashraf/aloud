import 'dart:io';

import 'package:aloud_core/aloud_core.dart';
import 'package:sembast/sembast.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import '../storage/app_paths.dart';

/// Documents and shelves.
///
/// All mutations go through here so that files on disk and metadata in the
/// database can never drift apart (e.g. deleting a document removes its
/// folder too).
final class LibraryRepository {
  LibraryRepository(this._db, this._paths);

  final AppDatabase _db;
  final AppPaths _paths;

  // ── Documents ──────────────────────────────────────────────────────────

  Stream<List<Doc>> watchDocs() => _db.docs
      .query()
      .onSnapshots(_db.db)
      .map((snaps) => [for (final s in snaps) Doc.fromMap(s.value)]);

  Future<List<Doc>> allDocs() async {
    final snaps = await _db.docs.query().getSnapshots(_db.db);
    return [for (final s in snaps) Doc.fromMap(s.value)];
  }

  Future<Doc?> getDoc(String id) async {
    final v = await _db.docs.record(id).get(_db.db);
    return v == null ? null : Doc.fromMap(v);
  }

  Future<void> putDoc(Doc doc) => _db.docs.record(doc.id).put(_db.db, doc.toMap());

  /// Read-modify-write inside one transaction.
  Future<Doc?> updateDoc(String id, Doc Function(Doc) change) {
    return _db.db.transaction((txn) async {
      final v = await _db.docs.record(id).get(txn);
      if (v == null) return null;
      final next = change(Doc.fromMap(v));
      await _db.docs.record(id).put(txn, next.toMap());
      return next;
    });
  }

  /// Lightweight, frequent write used while listening.
  Future<void> savePosition(
    String id, {
    required ReadingPosition position,
    required double progress,
    bool completed = false,
    List<int>? sectionSentences,
  }) async {
    await _db.docs.record(id).update(_db.db, {
      'pos': position.toJson(),
      'progress': progress,
      'completed': completed,
      'openedAt': DateTime.now().millisecondsSinceEpoch,
      'sectionSentences': ?sectionSentences,
    });
  }

  Future<void> touch(String id) => _db.docs.record(id).update(_db.db, {
        'openedAt': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> moveDoc(String id, String? shelfId) => _db.docs.record(id).update(_db.db, {
        'shelfId': shelfId,
      });

  Future<void> resetProgress(String id) => _db.docs.record(id).update(_db.db, {
        'pos': ReadingPosition.start.toJson(),
        'progress': 0.0,
        'completed': false,
      });

  Future<void> deleteDoc(String id) async {
    await _db.docs.record(id).delete(_db.db);
    final dir = _paths.docDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Next document on the same shelf in natural title order, for
  /// "continue with the next book/chapter file" playback.
  Future<Doc?> nextAfter(Doc current) async {
    final siblings = [
      for (final d in await allDocs())
        if (d.shelfId == current.shelfId && d.kind.isSpeakable) d,
    ]..sort((a, b) => LibrarySorter.compare(LibrarySort.nameAz, a.sortKey, b.sortKey));
    final i = siblings.indexWhereId(current.id);
    return (i >= 0 && i + 1 < siblings.length) ? siblings[i + 1] : null;
  }

  // ── Shelves ────────────────────────────────────────────────────────────

  Stream<List<Shelf>> watchShelves() => _db.shelves
      .query()
      .onSnapshots(_db.db)
      .map((snaps) => [for (final s in snaps) Shelf.fromMap(s.value)]);

  Future<List<Shelf>> allShelves() async {
    final snaps = await _db.shelves.query().getSnapshots(_db.db);
    return [for (final s in snaps) Shelf.fromMap(s.value)];
  }

  Future<Shelf> createShelf(String name, {String? parentId, required String id}) async {
    final siblings = [
      for (final s in await allShelves())
        if (s.parentId == parentId) s.name,
    ];
    final shelf = Shelf(
      id: id,
      name: Names.unique(Names.sanitize(name, fallback: 'Shelf'), siblings),
      parentId: parentId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.shelves.record(id).put(_db.db, shelf.toMap());
    return shelf;
  }

  Future<void> renameShelf(String id, String name) =>
      _db.shelves.record(id).update(_db.db, {'name': Names.sanitize(name, fallback: 'Shelf')});

  /// Returns `false` if the move would create a cycle.
  Future<bool> moveShelf(String id, String? newParentId) async {
    final tree = ShelfTree([for (final s in await allShelves()) s.node]);
    if (!tree.canMove(id, newParentId)) return false;
    await _db.shelves.record(id).update(_db.db, {'parentId': newParentId});
    return true;
  }

  /// Deletes a shelf. Its documents and sub-shelves move up one level, unless
  /// [deleteContents] is true, in which case everything inside is removed.
  Future<void> deleteShelf(String id, {bool deleteContents = false}) async {
    final shelves = await allShelves();
    final tree = ShelfTree([for (final s in shelves) s.node]);
    final self = tree.node(id);
    if (self == null) return;
    final docs = await allDocs();

    if (deleteContents) {
      final doomed = {id, ...tree.descendantIds(id)};
      for (final d in docs.where((d) => doomed.contains(d.shelfId))) {
        await deleteDoc(d.id);
      }
      for (final sid in doomed) {
        await _db.shelves.record(sid).delete(_db.db);
      }
      return;
    }
    await _db.db.transaction((txn) async {
      for (final d in docs.where((d) => d.shelfId == id)) {
        await _db.docs.record(d.id).update(txn, {'shelfId': self.parentId});
      }
      for (final s in shelves.where((s) => s.parentId == id)) {
        await _db.shelves.record(s.id).update(txn, {'parentId': self.parentId});
      }
      await _db.shelves.record(id).delete(txn);
    });
  }

  // ── Maintenance ────────────────────────────────────────────────────────

  /// Total size in bytes of a document's folder.
  Future<int> folderSize(String id) async {
    final dir = _paths.docDir(id);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}

extension on List<Doc> {
  int indexWhereId(String id) => indexWhere((d) => d.id == id);
}
