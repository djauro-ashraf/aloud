import 'package:sembast/sembast_io.dart';

/// Typed handles to the stores of one vault's database.
///
/// Sembast is a pure-Dart document store: no code generation, no native
/// libraries, reactive queries out of the box. Everything stored here is
/// small metadata; bulky content (sections, audio) lives in files.
final class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  final docs = stringMapStoreFactory.store('docs');
  final shelves = stringMapStoreFactory.store('shelves');
  final rules = stringMapStoreFactory.store('rules');
  final settings = stringMapStoreFactory.store('settings');
  final kv = StoreRef<String, Object?>('kv');

  static Future<AppDatabase> open(String path) async {
    final db = await databaseFactoryIo.openDatabase(path);
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();
}
