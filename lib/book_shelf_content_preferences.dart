import 'dart:convert';

/// Ordering of the featured region, independent of the collection below it.
enum BookShelfContentSort { original, recentRead, recentAdded, title }

/// Dynamic queries remain selected when the current source has no matches.
/// Their absence is not deletion of a named organization category.
String? shelfContentDynamicCategoryLabel(String category) {
  final (prefix, label) = category.startsWith('_author:')
      ? ('_author:', '作者')
      : category.startsWith('_tag:')
      ? ('_tag:', '标签')
      : ('', '');
  if (prefix.isEmpty) return null;
  try {
    final name = Uri.decodeComponent(category.substring(prefix.length)).trim();
    return name.isEmpty ? null : '$label · $name';
  } on FormatException {
    return null;
  }
}

/// A page owns its featured-region selection without changing book membership.
/// Missing legacy records follow the collection and retain its original layout.
class BookShelfContentPreferences {
  const BookShelfContentPreferences.defaults()
    : followCollection = true,
      category = '_all',
      readingFilter = 'all',
      sort = BookShelfContentSort.recentRead,
      source = 'all';

  const BookShelfContentPreferences({
    this.followCollection = true,
    this.category = '_all',
    this.readingFilter = 'all',
    this.sort = BookShelfContentSort.recentRead,
    this.source = 'all',
  });

  static const readingFilters = {
    'all',
    'recent',
    'unread',
    'reading',
    'finished',
  };
  static const sources = {'all', 'local', 'cached', 'online', 'history'};

  final bool followCollection;
  final String category;
  final String readingFilter;
  final BookShelfContentSort sort;
  final String source;

  BookShelfContentPreferences copyWith({
    bool? followCollection,
    String? category,
    String? readingFilter,
    BookShelfContentSort? sort,
    String? source,
  }) => BookShelfContentPreferences(
    followCollection: followCollection ?? this.followCollection,
    category: category ?? this.category,
    readingFilter: readingFilter ?? this.readingFilter,
    sort: sort ?? this.sort,
    source: source ?? this.source,
  );

  Map<String, Object> toJson() => {
    'followCollection': followCollection,
    'category': category,
    'readingFilter': readingFilter,
    'sort': sort.name,
    'source': source,
  };

  String get record => jsonEncode(toJson());

  static BookShelfContentPreferences? tryParse(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (value is! Map ||
        value['followCollection'] is! bool ||
        value['category'] is! String ||
        (value['category'] as String).isEmpty ||
        (value['category'] as String).length > 512 ||
        !readingFilters.contains(value['readingFilter']) ||
        !sources.contains(value['source'])) {
      return null;
    }
    final sortName = value['sort'];
    final sort = BookShelfContentSort.values
        .where((item) => item.name == sortName)
        .firstOrNull;
    if (sort == null) return null;
    return BookShelfContentPreferences(
      followCollection: value['followCollection'] as bool,
      category: value['category'] as String,
      readingFilter: value['readingFilter'] as String,
      sort: sort,
      source: value['source'] as String,
    );
  }

  static BookShelfContentPreferences parseOrDefault(Object? value) =>
      tryParse(value) ?? const BookShelfContentPreferences.defaults();

  @override
  bool operator ==(Object other) =>
      other is BookShelfContentPreferences &&
      followCollection == other.followCollection &&
      category == other.category &&
      readingFilter == other.readingFilter &&
      sort == other.sort &&
      source == other.source;

  @override
  int get hashCode =>
      Object.hash(followCollection, category, readingFilter, sort, source);
}
