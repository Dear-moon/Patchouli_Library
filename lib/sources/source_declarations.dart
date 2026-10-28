import '../catalog.dart';
import 'book_source.dart';

abstract final class SourceDeclarations {
  static final _sources = <String, BookSource>{};
  static void register(Iterable<BookSource> sources) {
    for (final source in sources) {
      _sources[source.key] = source;
    }
  }

  static BookSource? source(String? key) => _sources[key];
  static Map<String, dynamic> of(String? key) => Map<String, dynamic>.from(
    _sources[key]?.data['engine'] as Map? ?? const {},
  );
  static Map<String, dynamic> section(String? key, String name) =>
      Map<String, dynamic>.from(of(key)[name] as Map? ?? const {});
  static String platformKey(String? key) =>
      section(key, 'platform')['id'] as String? ?? key ?? 'local';
  static String platformName(String? key) =>
      section(key, 'platform')['name'] as String? ??
      _sources[key]?.name ??
      '本地书库';
  static String mark(String? key) =>
      section(key, 'platform')['mark'] as String? ?? 'JS';
  static String sessionKey(String key) =>
      section(key, 'session')['id'] as String? ?? key;
  static bool matches(Novel book, String field) {
    final pattern = section(book.sourceId, 'content')[field] as String?;
    return pattern != null &&
        book.bookUrl != null &&
        RegExp(pattern).hasMatch(book.bookUrl!);
  }

  static String? seriesUrl(Novel book) {
    final pattern =
        section(book.sourceId, 'content')['seriesUrlPattern'] as String?;
    if (pattern == null || book.bookUrl == null) return null;
    return RegExp(pattern).firstMatch(book.bookUrl!)?.group(1);
  }

  static bool isSeries(Novel book) => matches(book, 'seriesPattern');
  static bool isEpub(Novel book) => matches(book, 'epubPattern');
}
