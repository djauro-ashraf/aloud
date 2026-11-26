/// A user-presentable import failure (unsupported format, empty file, …).
final class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
