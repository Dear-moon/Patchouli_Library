import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_home_page.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

class _HomeStore extends SourceStore {
  _HomeStore(super.file);
  @override
  Future<void> flush() async {}
}

final _source = BookSource({
  'bookSourceName': 'Novelia',
  'bookSourceUrl': 'https://n.novelia.cc#sakura',
  'homeSections': [
    {'id': 'shelf', 'title': '我的收藏', 'operation': 'cloudShelf'},
    {'id': 'web', 'title': '网络小说 · 最多点击', 'url': 'web-clicks'},
    {'id': 'wenku', 'title': '文库小说 · 最新更新', 'url': 'wenku-update'},
  ],
});
Map<String, Object> _page(String section, int page) => {
  'items': List.generate(
    20,
    (i) => {
      'name': '$section $page-$i',
      'bookUrl': 'https://n.novelia.cc/novel/hameln/$section-$page-$i',
    },
  ),
  'hasMore': page < 2,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late SourceStore store;
  late SourceNovelRepository repository;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('source-home-test-');
    store = _HomeStore(File('${folder.path}/sources.json'));
    await store.saveSources([_source]);
    await store.select(_source.key, null);
    repository = SourceNovelRepository(
      store: store,
      legacy: const DemoNovelRepository(),
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SourcePlatform.channel, null);
    repository.dispose();
    store.dispose();
    await folder.delete(recursive: true);
  });

  test(
    'home declaration has independent sections and rejects duplicate identities',
    () {
      expect(_source.homeSections.length, 3);
      expect(_source.homeSections.first.requiresLogin, true);
      expect(repository.showsHome, true);
      expect(
        () => BookSource({
          ..._source.data,
          'homeSections': [
            {'id': 'x', 'title': 'One', 'url': 'one'},
            {'id': 'x', 'title': 'Two', 'url': 'two'},
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'cancelling an old section cannot cancel a replacement with the same source and id',
    () async {
      final pending = <Completer<Map<String, Object>>>[],
          ids = <String>[],
          cancelled = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            if (call.method == 'cancel') {
              cancelled.add(call.arguments as String);
              return null;
            }
            final args = call.arguments as Map;
            ids.add(args['requestId'] as String);
            final value = Completer<Map<String, Object>>();
            pending.add(value);
            return value.future;
          });
      final old = Object(),
          replacement = Object(),
          section = _source.homeSections[1];
      final first = repository.homePage(_source, section, owner: old);
      final failure = expectLater(first, throwsA(isA<SourceFailure>()));
      final second = repository.homePage(_source, section, owner: replacement);
      await Future<void>.delayed(Duration.zero);
      expect(pending.length, 2);
      repository.cancelHome(old);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, [ids.first]);
      pending.first.complete(_page('web', 1));
      pending.last.complete(_page('web', 1));
      await failure;
      expect((await second).items.length, 20);
    },
  );

  testWidgets(
    'source home limits previews and loads further pages only after See all',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final calls = <(String, int)>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            if (call.method == 'cancel') return null;
            if (call.method == 'accountStatus') {
              return {
                'status': 'none',
                'hasSession': false,
                'loginAvailable': true,
              };
            }
            final args = call.arguments as Map;
            expect(args['operation'], 'explore');
            final url = args['url'] as String;
            final page = args['page'] as int;
            calls.add((url, page));
            return _page(url, page);
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: SourceHomePage(
              sources: repository,
              source: _source,
              repository: repository,
              state: state,
              heading: const Text('HOME'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号与登录'), findsOneWidget);
      expect(calls.every((call) => call.$2 == 1), true);
      final scroll = find.byType(CustomScrollView);
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(calls.every((call) => call.$2 == 1), true);
      final web = find.byKey(const ValueKey('source-home-section-web'));
      expect(
        find
            .descendant(of: web, matching: find.byType(NovelRow))
            .evaluate()
            .length,
        10,
      );
      final more = find.byKey(const ValueKey('source-home-more-web'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: more,
          matching: find.byKey(const ValueKey('section-more-dot')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: more, matching: find.text('查看更多')),
        findsNothing,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-home-all-web')), findsNothing);
      expect(
        find.descendant(
          of: more,
          matching: find.byKey(const ValueKey('section-more-arrow')),
        ),
        findsOneWidget,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      final full = find.byKey(const ValueKey('source-home-all-web'));
      expect(full, findsOneWidget);
      await tester.drag(
        find.descendant(of: full, matching: find.byType(CustomScrollView)),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(calls, contains(('web-clicks', 2)));
      expect(store.selectedExplore, isNull);
      Navigator.of(tester.element(full)).pop();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: more,
          matching: find.byKey(const ValueKey('section-more-dot')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
