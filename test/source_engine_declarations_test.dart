import 'dart:io';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/book_platform.dart';
import 'package:wenku8_flutter/sources/source_declarations.dart';

void main() {
  test(
    'declared book IDs survive normalized records, collisions and restart',
    () async {
      final folder = await Directory.systemTemp.createTemp('declared-book-id-');
      final file = File('${folder.path}/index.json');
      final store = SourceStore(file);
      SourceStore? restarted;
      try {
        BookSource rules(String key) => BookSource({
          'bookSourceName': key,
          'bookSourceUrl': key,
          'engine': {
            'version': 1,
            'identity': {'bookIdPattern': r'^catalog:(\d+)$'},
          },
        });
        final source = rules('https://numeric.example');
        final other = rules('https://other-numeric.example');
        await store.saveSources([source, other]);
        final record = {'name': 'Fixture', 'bookUrl': 'catalog:42'};
        expect(store.remember(source, record).id, 42);
        expect(store.remember(source, record).id, 42);
        expect(() => store.remember(other, record), throwsFormatException);
        expect(
          () => store.remember(source, {
            'name': 'Wrong',
            'bookUrl': 'unexpected',
          }),
          throwsFormatException,
        );
        await store.flush();
        restarted = SourceStore(file);
        await restarted.load();
        expect(restarted.remember(source, record).id, 42);
      } finally {
        restarted?.dispose();
        store.dispose();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'declared volume ancestry returns the complete series without merging volume identities',
    () async {
      final folder = await Directory.systemTemp.createTemp('declared-series-');
      final store = SourceStore(File('${folder.path}/index.json'));
      final repository = SourceNovelRepository(store: store);
      try {
        final source = BookSource({
          'bookSourceName': 'Series fixture',
          'bookSourceUrl': 'https://books.example#translated',
          'engine': {
            'version': 1,
            'content': {
              'seriesPattern': r'^https://books\.example/series/[^?]+$',
              'epubPattern': r'[?]volume=',
              'seriesUrlPattern':
                  r'^(https://books\.example/series/[^?]+)\?.*volume=',
            },
          },
        });
        await store.saveSources([source]);
        final series = store.remember(source, {
          'name': 'Complete series',
          'bookUrl': 'https://books.example/series/one',
        });
        await store.rememberChapters(series.id, [
          {'name': 'Volume one', 'url': '${series.bookUrl}?volume=one.epub'},
          {'name': 'Volume two', 'url': '${series.bookUrl}?volume=two.epub'},
        ]);
        final full = store.book(series.id)!;
        final one = repository.sourceVolumeTarget(full, 0)!;
        final two = repository.sourceVolumeTarget(full, 1)!;
        expect(one.id, isNot(two.id));
        expect(SourceDeclarations.seriesUrl(one), series.bookUrl);
        expect(SourceDeclarations.seriesUrl(series), isNull);
        expect(repository.sourceSeriesTarget(one)!.id, series.id);
        expect(repository.sourceSeriesTarget(two)!.chapters, hasLength(2));
        expect(repository.sourceSeriesTarget(one)!.title, 'Complete series');
        expect(store.book(one.id)!.bookUrl, contains('volume=one.epub'));
        await store.flush();
      } finally {
        repository.dispose();
        store.dispose();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'platform and shared account identity come entirely from imported declarations',
    () {
      final rules = [
        for (final variant in ['a', 'b'])
          BookSource({
            'bookSourceName': 'Variant $variant',
            'bookSourceUrl': 'https://books.example#$variant',
            'engine': {
              'version': 1,
              'platform': {
                'id': 'sample',
                'name': 'Sample Library',
                'mark': 'SL',
              },
              'session': {
                'id': 'sample-session',
                'members': [
                  'https://books.example#a',
                  'https://books.example#b',
                ],
              },
            },
          }),
      ];
      final platforms = bookPlatforms(rules, includeWenku: true);
      expect(platforms.length, 1);
      expect(platforms.single.name, 'Sample Library');
      expect(platforms.single.mark, 'SL');
      expect(bookPlatformKey(rules.last.key), 'sample');
      expect(SourceDeclarations.sessionKey(rules.last.key), 'sample-session');
      expect(bookPlatforms([], includeWenku: true), isEmpty);
    },
  );
  test(
    'numeric chapter identity is declared without a provider-specific branch',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'declared-identity-',
      );
      final store = SourceStore(File('${folder.path}/index.json'));
      try {
        final source = BookSource({
          'bookSourceName': 'Numeric fixture',
          'bookSourceUrl': 'https://numeric.example',
          'engine': {
            'version': 1,
            'identity': {'chapterIdPattern': r'/([0-9]+)$'},
          },
        });
        await store.saveSources([source]);
        final book = store.remember(source, {
          'name': 'Fixture',
          'bookUrl': 'https://numeric.example/book',
        });
        final rows = await store.rememberChapters(book.id, [
          {'name': 'Chapter', 'url': 'https://numeric.example/chapter/42'},
        ]);
        expect(rows.single.id, 42);
        await store.flush();
      } finally {
        store.dispose();
        await folder.delete(recursive: true);
      }
    },
  );
  test('unsupported engine declarations fail before import', () {
    expect(
      () => BookSource({
        'bookSourceName': 'Unsupported',
        'bookSourceUrl': 'https://other.example',
        'engine': {'version': 2},
      }),
      throwsFormatException,
    );
  });
}
