import 'dart:convert';

/// Featured shelf limits never limit the collection or remove books from it.
class BookShelfPreferences {
  const BookShelfPreferences.defaults()
    : minimumBooks = 1,
      maximumBooks = 10,
      repeatFill = true;

  factory BookShelfPreferences({
    int minimumBooks = 1,
    int maximumBooks = 10,
    bool repeatFill = true,
  }) {
    if (!_validCount(minimumBooks) || !_validCount(maximumBooks)) {
      throw const FormatException('立体书架数量须为 1–100 本');
    }
    return BookShelfPreferences._(minimumBooks, maximumBooks, repeatFill);
  }

  const BookShelfPreferences._(
    this.minimumBooks,
    this.maximumBooks,
    this.repeatFill,
  );

  static const maximum = 100;
  final int minimumBooks;
  final int maximumBooks;
  final bool repeatFill;

  int featuredCount(int available) =>
      available < minimumBooks ? 0 : available.clamp(0, maximumBooks);

  BookShelfPreferences copyWith({
    int? minimumBooks,
    int? maximumBooks,
    bool? repeatFill,
  }) => BookShelfPreferences(
    minimumBooks: minimumBooks ?? this.minimumBooks,
    maximumBooks: maximumBooks ?? this.maximumBooks,
    repeatFill: repeatFill ?? this.repeatFill,
  );

  Map<String, Object> toJson() => {
    'minimumBooks': minimumBooks,
    'maximumBooks': maximumBooks,
    'repeatFill': repeatFill,
  };

  String get record => jsonEncode(toJson());

  static bool _validCount(Object? value) =>
      value is int && value >= 1 && value <= maximum;

  static BookShelfPreferences? tryParse(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (value is! Map ||
        !_validCount(value['minimumBooks']) ||
        !_validCount(value['maximumBooks']) ||
        value.containsKey('repeatFill') && value['repeatFill'] is! bool) {
      return null;
    }
    return BookShelfPreferences._(
      value['minimumBooks'] as int,
      value['maximumBooks'] as int,
      value['repeatFill'] as bool? ?? true,
    );
  }

  static BookShelfPreferences parseOrDefault(Object? value) =>
      tryParse(value) ?? const BookShelfPreferences.defaults();

  @override
  bool operator ==(Object other) =>
      other is BookShelfPreferences &&
      minimumBooks == other.minimumBooks &&
      maximumBooks == other.maximumBooks &&
      repeatFill == other.repeatFill;

  @override
  int get hashCode => Object.hash(minimumBooks, maximumBooks, repeatFill);
}
