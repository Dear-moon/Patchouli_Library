import 'support/source_declaration_fixtures.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/novel_feed_controller.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

void main() {
  setUp(registerSourceFixtures);
  TestWidgetsFlutterBinding.ensureInitialized();
  late SourceStore store;
  late SourceNovelRepository repository;
  late Directory directory;
  final calls = <String>[];
  late Future<dynamic> Function(Map arguments) response;
  BookSource source(String id) => BookSource({
    'bookSourceName': id,
    'engine': engineFixture(
      id.startsWith('https:') ? id : 'https://$id.example.invalid',
    ),
    'bookSourceUrl': id.startsWith('https:')
        ? id
        : 'https://$id.example.invalid',
    'searchUrl': '/search?key={{key}}',
  });
  Map<String, dynamic> result(Map args) {
    final definition = args['source'] as Map;
    return {
      'items': [
        {
          'name': '${args['key']} ${definition['bookSourceName']}',
          'bookUrl': '${definition['bookSourceUrl']}/novel/${args['key']}',
        },
      ],
      'hasMore': false,
    };
  }

  setUp(() async {
    calls.clear();
    directory = await Directory.systemTemp.createTemp('platform-search-');
    store = SourceStore(File('${directory.path}/index.json'));
    await store.saveSources([
      for (final id in ['slow', 'fast', 'other']) source(id),
    ]);
    store.selectedSource = store.sources.first.key;
    repository = SourceNovelRepository(store: store);
    response = (args) async => result(args);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
          if (call.method != 'run') return null;
          final args = Map<String, dynamic>.from(call.arguments as Map);
          calls.add((args['source'] as Map)['bookSourceName'] as String);
          return response(args);
        });
  });
  tearDown(() async {
    repository.dispose();
    await store.flush();
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SourcePlatform.channel, null);
    await directory.delete(recursive: true);
  });
  test('default search calls only the currently selected platform', () async {
    final page = await repository.searchProgressPage('Novel');
    expect(calls, ['slow']);
    expect(page.items.single.title, 'Novel slow');
  });
  test(
    'fast platforms publish results while a slow platform is pending',
    () async {
      final slow = Completer<dynamic>();
      final visible = Completer<void>();
      response = (args) async =>
          (args['source'] as Map)['bookSourceName'] == 'slow'
          ? await slow.future
          : result(args);
      final feed = NovelFeedController(repository, search: true)
        ..allPlatforms = true;
      addTearDown(feed.dispose);
      feed.addListener(() {
        if (feed.items.length == 2 && feed.loading && !visible.isCompleted) {
          visible.complete();
        }
      });
      final search = feed.searchFor('Novel');
      await visible.future.timeout(const Duration(seconds: 10));
      expect(feed.items.map((book) => book.title), [
        'Novel fast',
        'Novel other',
      ]);
      expect(feed.platformSearchProgress!.completed, 2);
      slow.completeError(
        PlatformException(code: 'source', message: 'HTTP 503'),
      );
      await search;
      expect(feed.items, hasLength(2));
      expect(feed.loading, false);
      expect(feed.error, isNull);
      expect(feed.searchNotice, contains('slow'));
      expect(calls.where((name) => name == 'slow'), hasLength(1));
    },
  );
  test('a blocked worker does not delay the next queued platform', () async {
    await store.saveSources([
      for (var i = 0; i < 6; i++) source('queued$i'),
    ], replace: false);
    final slow = Completer<dynamic>(), allFast = Completer<void>();
    response = (args) async =>
        (args['source'] as Map)['bookSourceName'] == 'slow'
        ? await slow.future
        : result(args);
    final search = repository.searchProgressPage(
      'Novel',
      allPlatforms: true,
      onProgress: (value) {
        if (value.completed == 8 && !allFast.isCompleted) allFast.complete();
      },
    );
    await allFast.future.timeout(const Duration(seconds: 10));
    expect(calls, contains('queued5'));
    slow.complete({'items': <dynamic>[], 'hasMore': false});
    expect((await search).items, hasLength(8));
  });
  test('late results cannot cross a query change', () async {
    final old = Completer<dynamic>(), started = Completer<void>();
    response = (args) async {
      if (args['key'] == 'Old') {
        if (!started.isCompleted) started.complete();
        return await old.future;
      }
      return result(args);
    };
    final feed = NovelFeedController(repository, search: true);
    addTearDown(feed.dispose);
    final previous = feed.searchFor('Old');
    await started.future.timeout(const Duration(seconds: 10));
    await feed.searchFor('New');
    old.complete({
      'items': [
        {'name': 'Old stale', 'bookUrl': 'https://slow.example.invalid/old'},
      ],
      'hasMore': false,
    });
    await previous;
    expect(feed.items.single.title, 'New slow');
    expect(feed.error, isNull);
  });
  test(
    'all-platform search includes one selected Novelia translation',
    () async {
      await store.saveSources([
        source('https://n.novelia.cc#sakura'),
        source('https://n.novelia.cc#gpt'),
        source('https://n.novelia.cc#jp'),
      ], replace: false);
      store.selectedSource = 'https://n.novelia.cc#gpt';
      await repository.searchProgressPage('Novel', allPlatforms: true);
      expect(calls.where((name) => name.startsWith('https://n.novelia.cc#')), [
        'https://n.novelia.cc#gpt',
      ]);
    },
  );
}
