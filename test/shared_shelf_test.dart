import 'support/source_declaration_fixtures.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/bookshelf_scope.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/cloud_platform_shelf.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

Novel book(int id, String? source) => Novel(
  id: id,
  title: 'Fixture $id',
  author: '',
  genre: '',
  summary: '',
  colors: const [Colors.grey, Colors.black],
  sourceId: source,
  bookUrl: source == null ? null : 'https://n.novelia.cc/novel/hameln/$id',
);

class _CloudFixtureStore extends SourceStore {
  _CloudFixtureStore(this.fixture)
    : super(File('${Directory.systemTemp.path}/unwritten-cloud-fixture.json'));
  final BookSource fixture;
  @override
  List<BookSource> get sources => [fixture];
  @override
  List<BookSource> get enabled => [fixture];
  @override
  BookSource? source(String? key) => key == fixture.key ? fixture : null;
  @override
  Future<void> load() async {}
  @override
  Future<void> flush() async {}
}

void main() {
  test(
    'series grouping preserves each volume reading record across restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final one = book(0x40000011, 'https://books.example');
      final two = book(0x40000012, 'https://books.example');
      final series = book(0x40000013, 'https://books.example');
      final other = book(0x40000014, 'https://other.example');
      for (final item in [one, two, other]) {
        await state.setShelfMembership(item.id, true, novel: item);
      }
      await state.setChapter(one.id, 2);
      await state.setChapter(two.id, 5);
      final firstAdded = state.addedAt(one.id);
      await state.groupShelfSeries(series, [one.id, two.id]);
      expect(state.shelf.toSet(), {series.id, other.id});
      expect(state.addedAt(series.id), firstAdded);
      expect(state.cachedNovel(one.id)!.title, one.title);
      expect(state.cachedNovel(two.id)!.title, two.title);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('chapter_${one.id}'), 2);
      expect(preferences.getInt('chapter_${two.id}'), 5);
      final restarted = await LibraryState.load();
      addTearDown(restarted.dispose);
      expect(restarted.shelf.toSet(), {series.id, other.id});
      expect(restarted.cachedNovel(one.id)!.title, one.title);
    },
  );
  test(
    'a removed volume is not resurrected by delayed series grouping',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final one = book(0x40000021, 'https://books.example');
      await state.setShelfMembership(one.id, true, novel: one);
      await state.setShelfMembership(one.id, false);
      await state.groupShelfSeries(book(0x40000022, one.sourceId), [one.id]);
      expect(state.shelf, isEmpty);
    },
  );
  setUp(registerSourceFixtures);
  TestWidgetsFlutterBinding.ensureInitialized();
  test('platform and cloud location survive restart and backup', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await LibraryState.load();
    addTearDown(state.dispose);
    await state.setShelfView(platform: 'novelia', location: 'cloud');
    final backup = await state.createBackup();
    final restarted = await LibraryState.load();
    addTearDown(restarted.dispose);
    expect(restarted.shelfPlatform, 'novelia');
    expect(restarted.shelfLocation, 'cloud');
    await state.setShelfView(platform: 'all', location: 'local');
    await state.restoreBackup(backup, importPreferences: true);
    expect(state.shelfPlatform, 'novelia');
    expect(state.shelfLocation, 'cloud');
  });

  test(
    'local platform filter groups Novelia variants without losing membership',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final books = [
        book(11, null),
        book(0x40000001, 'https://n.novelia.cc#sakura'),
        book(0x40000002, 'https://n.novelia.cc#gpt'),
        book(0x40000003, 'https://www.lightnovel.fun'),
      ];
      for (final item in books) {
        await state.setShelfMembership(item.id, true, novel: item);
      }
      final before = state.shelf.toSet();
      await state.setShelfView(platform: 'novelia');
      expect(bookshelfIds(state, null), {books[1].id, books[2].id});
      await state.setShelfView(platform: 'qingguo');
      expect(bookshelfIds(state, null), {books[3].id});
      expect(state.shelf.toSet(), before);
    },
  );

  test(
    'external cloud entries do not enter link-only reading discovery',
    () async {
      final store = _CloudFixtureStore(
        BookSource({
          'engine': engineFixture('https://n.novelia.cc#sakura'),
          'bookSourceUrl': 'https://n.novelia.cc#sakura',
          'bookSourceName': 'Novelia',
          'linkOnly': true,
          'bookUrlPattern': r'^https://n\.novelia\.cc/novel/',
        }),
      );
      addTearDown(store.dispose);
      final repo = SourceNovelRepository(store: store);
      addTearDown(repo.dispose);
      store.remember(store.fixture, {
        'name': 'Web fixture',
        'bookUrl': 'https://n.novelia.cc/novel/hameln/1',
      });
      store.remember(store.fixture, {
        'name': 'External fixture',
        'bookUrl': 'https://n.novelia.cc/wenku/2',
      });
      final page = await repo.browse();
      expect(page.items.map((b) => b.title), ['Web fixture']);
      expect(store.books.length, 2);
    },
  );

  for (final needsVerification in [false, true]) {
    testWidgets(
      'cloud shelf restores $needsVerification without adding local favorites',
      (tester) async {
        SharedPreferences.setMockInitialValues({'reduceMotion': true});
        final state = await LibraryState.load();
        addTearDown(state.dispose);
        await state.setShelfView(platform: 'novelia', location: 'cloud');
        final store = _CloudFixtureStore(
          BookSource({
            'engine': engineFixture('https://n.novelia.cc#sakura'),
            'bookSourceUrl': 'https://n.novelia.cc#sakura',
            'bookSourceName': 'Novelia · Sakura',
            'cloudShelf': true,
            if (needsVerification)
              'ruleAccount': {
                'verify': {'js': 'getAccount'},
              },
          }),
        );
        addTearDown(store.dispose);
        final repo = SourceNovelRepository(store: store);
        addTearDown(repo.dispose);
        final methods = <String>[];
        var verified = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
              methods.add(call.method);
              if (call.method == 'accountStatus') {
                return {
                  'status': needsVerification
                      ? (verified ? 'verified' : 'signedOut')
                      : 'saved',
                  'hasSession': true,
                  'loginAvailable': true,
                  'capabilities': {'verify': needsVerification},
                  if (verified)
                    'checkedAt': DateTime.now().millisecondsSinceEpoch,
                };
              }
              if (call.method == 'run') {
                final operation = (call.arguments as Map)['operation'];
                if (operation == 'accountVerify') {
                  expect(needsVerification, true);
                  verified = true;
                  return true;
                }
                expect(operation, 'cloudShelf');
                expect(verified, needsVerification);
                return {
                  'items': [
                    {
                      'name': 'Cloud fixture',
                      'bookUrl': 'https://n.novelia.cc/novel/hameln/1',
                    },
                  ],
                  'hasMore': false,
                };
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SourcePlatform.channel, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light),
            home: Scaffold(
              body: CloudPlatformShelf(
                repository: repo,
                state: state,
                header: const SizedBox.shrink(),
                showHeader: false,
                offline: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cloud fixture'), findsWidgets);
        expect(state.shelf, isEmpty);
        expect(
          methods.where((m) => m == 'run').length,
          needsVerification ? 2 : 1,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
