/// Navigation addresses the reading order; it does not define or renumber it.
/// Several spine resources (colour plates, for example) can share one TOC entry.
class BookReadingTarget {
  const BookReadingTarget(
    this.chapterId, {
    this.paragraph = 0,
    this.offset = 0,
  });
  final int chapterId, paragraph, offset;
  Map<String, int> toJson() => {
    'chapter': chapterId,
    'paragraph': paragraph,
    'offset': offset,
  };
  factory BookReadingTarget.fromJson(Map value) {
    if (value['chapter'] is! int ||
        value['chapter'] <= 0 ||
        value['paragraph'] is! int ||
        value['paragraph'] < 0 ||
        value['offset'] is! int ||
        value['offset'] < 0) {
      throw const FormatException('原书导航位置有误');
    }
    return BookReadingTarget(
      value['chapter'],
      paragraph: value['paragraph'],
      offset: value['offset'],
    );
  }
  BookReadingTarget inChapter(int id) =>
      BookReadingTarget(id, paragraph: paragraph, offset: offset);
}

class BookNavigationEntry {
  const BookNavigationEntry(this.title, this.target, {this.depth = 0});
  final String title;
  final BookReadingTarget target;
  final int depth;
  Map<String, Object> toJson() => {
    'title': title,
    'target': target.toJson(),
    if (depth > 0) 'depth': depth,
  };
}

class BookNavigation {
  const BookNavigation(this.entries, {this.targets = const {}});
  final List<BookNavigationEntry> entries;
  final Map<String, BookReadingTarget> targets;
  Map<String, Object> toJson() => {
    'version': 1,
    'entries': entries.map((e) => e.toJson()).toList(),
    'targets': {for (final e in targets.entries) e.key: e.value.toJson()},
  };
  factory BookNavigation.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['entries'] is! List ||
        raw['entries'].length > 10000 ||
        raw['targets'] is! Map ||
        raw['targets'].length > 50000) {
      throw const FormatException('原书导航数据有误');
    }
    final entries = <BookNavigationEntry>[];
    for (final e in raw['entries']) {
      if (e is! Map ||
          e['title'] is! String ||
          e['title'].isEmpty ||
          e['title'].length > 2048 ||
          e['target'] is! Map ||
          (e['depth'] ?? 0) is! int ||
          (e['depth'] ?? 0) < 0 ||
          (e['depth'] ?? 0) > 32) {
        throw const FormatException('原书目录条目有误');
      }
      entries.add(
        BookNavigationEntry(
          e['title'],
          BookReadingTarget.fromJson(e['target']),
          depth: e['depth'] ?? 0,
        ),
      );
    }
    return BookNavigation(
      List.unmodifiable(entries),
      targets: Map.unmodifiable({
        for (final e in (raw['targets'] as Map).entries)
          if (e.key is String && e.key.length <= 4096 && e.value is Map)
            e.key as String: BookReadingTarget.fromJson(e.value),
      }),
    );
  }
}
