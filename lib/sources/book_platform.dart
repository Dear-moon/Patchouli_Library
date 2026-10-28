import 'book_source.dart';
import 'source_declarations.dart';

const wenkuPlatformKey = 'builtin:wenku8';
String bookPlatformKey(String? source) =>
    SourceDeclarations.platformKey(source);

class BookPlatform {
  BookPlatform(this.key, this.name, this.mark, this.sources);
  final String key, name, mark;
  final List<BookSource> sources;
  bool get isWenku => false;
  String get code => '$mark / READING ARCHIVE';
}

List<BookPlatform> bookPlatforms(
  Iterable<BookSource> sources, {
  required bool includeWenku,
}) {
  SourceDeclarations.register(sources);
  final platforms = <String, BookPlatform>{};
  for (final source in sources) {
    final key = bookPlatformKey(source.key);
    (platforms[key] ??= BookPlatform(
      key,
      SourceDeclarations.platformName(source.key),
      SourceDeclarations.mark(source.key),
      [],
    )).sources.add(source);
  }
  return platforms.values.toList();
}
