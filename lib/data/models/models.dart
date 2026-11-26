import 'package:aloud_core/aloud_core.dart';

/// What kind of content a library item holds.
enum DocKind {
  /// Plain text pasted or imported from a .txt file.
  text('Text'),
  epub('EPUB'),
  pdf('PDF'),

  /// Saved web page / web-novel chapter(s).
  web('Web'),

  /// Image-based comic (CBZ). Read visually, not spoken.
  comic('Comic');

  const DocKind(this.label);
  final String label;

  /// Whether the item has speakable text.
  bool get isSpeakable => this != comic;
}

/// A library item (book, article, PDF, comic…).
final class Doc {
  const Doc({
    required this.id,
    required this.title,
    required this.kind,
    required this.addedAt,
    this.author,
    this.shelfId,
    this.openedAt,
    this.sizeBytes = 0,
    this.sectionCount = 0,
    this.pageCount = 0,
    this.position = ReadingPosition.start,
    this.progress = 0,
    this.completed = false,
    this.sourceUrl,
    this.nextUrl,
    this.language,
    this.sourceFile,
    this.hasCover = false,
    this.sectionSentences = const [],
  });

  final String id;
  final String title;
  final DocKind kind;
  final int addedAt;
  final String? author;

  /// Null = library root.
  final String? shelfId;
  final int? openedAt;
  final int sizeBytes;
  final int sectionCount;

  /// PDF / comic page count.
  final int pageCount;
  final ReadingPosition position;

  /// 0‥1.
  final double progress;
  final bool completed;
  final String? sourceUrl;

  /// Link to the chapter after the last saved one (web novels).
  final String? nextUrl;

  /// BCP-47 base code of the text, when known.
  final String? language;

  /// File name of the original inside the document folder.
  final String? sourceFile;
  final bool hasCover;

  /// Sentence count per section (filled lazily as sections are opened) so
  /// progress can be computed without re-parsing every chapter.
  final List<int> sectionSentences;

  bool get started => openedAt != null && (position.section > 0 || position.sentence > 0 || progress > 0);

  SortKey get sortKey => SortKey(title: title, addedAt: addedAt, openedAt: openedAt, sizeBytes: sizeBytes);

  Doc copyWith({
    String? title,
    String? author,
    Object? shelfId = _keep,
    int? openedAt,
    int? sizeBytes,
    int? sectionCount,
    int? pageCount,
    ReadingPosition? position,
    double? progress,
    bool? completed,
    String? sourceUrl,
    String? nextUrl,
    bool clearNextUrl = false,
    String? language,
    bool? hasCover,
    List<int>? sectionSentences,
  }) =>
      Doc(
        id: id,
        kind: kind,
        addedAt: addedAt,
        sourceFile: sourceFile,
        title: title ?? this.title,
        author: author ?? this.author,
        shelfId: identical(shelfId, _keep) ? this.shelfId : shelfId as String?,
        openedAt: openedAt ?? this.openedAt,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        sectionCount: sectionCount ?? this.sectionCount,
        pageCount: pageCount ?? this.pageCount,
        position: position ?? this.position,
        progress: progress ?? this.progress,
        completed: completed ?? this.completed,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        nextUrl: clearNextUrl ? null : (nextUrl ?? this.nextUrl),
        language: language ?? this.language,
        hasCover: hasCover ?? this.hasCover,
        sectionSentences: sectionSentences ?? this.sectionSentences,
      );

  static const _keep = Object();

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'addedAt': addedAt,
        if (author != null) 'author': author,
        if (shelfId != null) 'shelfId': shelfId,
        if (openedAt != null) 'openedAt': openedAt,
        'sizeBytes': sizeBytes,
        'sectionCount': sectionCount,
        'pageCount': pageCount,
        'pos': position.toJson(),
        'progress': progress,
        'completed': completed,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (nextUrl != null) 'nextUrl': nextUrl,
        if (language != null) 'language': language,
        if (sourceFile != null) 'sourceFile': sourceFile,
        'hasCover': hasCover,
        'sectionSentences': sectionSentences,
      };

  static Doc fromMap(Map<String, Object?> m) => Doc(
        id: m['id']! as String,
        title: (m['title'] as String?) ?? 'Untitled',
        kind: DocKind.values.asNameMap()[m['kind']] ?? DocKind.text,
        addedAt: ((m['addedAt'] as num?) ?? 0).toInt(),
        author: m['author'] as String?,
        shelfId: m['shelfId'] as String?,
        openedAt: (m['openedAt'] as num?)?.toInt(),
        sizeBytes: ((m['sizeBytes'] as num?) ?? 0).toInt(),
        sectionCount: ((m['sectionCount'] as num?) ?? 0).toInt(),
        pageCount: ((m['pageCount'] as num?) ?? 0).toInt(),
        position: ReadingPosition.fromJson((m['pos'] as Map?)?.cast<String, Object?>()),
        progress: ((m['progress'] as num?) ?? 0).toDouble(),
        completed: (m['completed'] as bool?) ?? false,
        sourceUrl: m['sourceUrl'] as String?,
        nextUrl: m['nextUrl'] as String?,
        language: m['language'] as String?,
        sourceFile: m['sourceFile'] as String?,
        hasCover: (m['hasCover'] as bool?) ?? false,
        sectionSentences: [
          for (final n in (m['sectionSentences'] as List<Object?>? ?? const [])) (n! as num).toInt(),
        ],
      );
}

/// A user-created folder. Shelves nest via [parentId].
final class Shelf {
  const Shelf({required this.id, required this.name, this.parentId, this.createdAt = 0});

  final String id;
  final String name;
  final String? parentId;
  final int createdAt;

  ShelfNode get node => ShelfNode(id, parentId, name);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        if (parentId != null) 'parentId': parentId,
        'createdAt': createdAt,
      };

  static Shelf fromMap(Map<String, Object?> m) => Shelf(
        id: m['id']! as String,
        name: (m['name'] as String?) ?? 'Shelf',
        parentId: m['parentId'] as String?,
        createdAt: ((m['createdAt'] as num?) ?? 0).toInt(),
      );
}
