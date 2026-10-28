import 'support/source_declaration_fixtures.dart';
import 'package:wenku8_flutter/sources/source_declarations.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/my_page.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/platform_account_page.dart';
import 'package:wenku8_flutter/sources/source_account.dart';
import 'package:wenku8_flutter/sources/source_host_bridge.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

class _AccountStore extends SourceStore {
  _AccountStore(this.fixtures)
    : super(
        File('${Directory.systemTemp.path}/unwritten-account-fixture.json'),
      ) {
    selectedSource = fixtures.first.key;
    SourceDeclarations.register(fixtures);
  }
  final List<BookSource> fixtures;
  @override
  List<BookSource> get sources => fixtures;
  @override
  List<BookSource> get enabled => fixtures;
  @override
  BookSource? source(String? key) =>
      fixtures.where((source) => source.key == key).firstOrNull;
  @override
  Future<void> load() async {}
  void choose(String key) {
    selectedSource = key;
    notifyListeners();
  }
}

BookSource _source(String url) => BookSource({
  'bookSourceUrl': url,
  'engine': engineFixture(url),
  'bookSourceName': url,
  'ruleAccount': {
    'verify': {'js': 'getAccount'},
  },
});

void main() {
  setUp(registerSourceFixtures);
  TestWidgetsFlutterBinding.ensureInitialized();
  const ls = 'https://www.lightnovel.app';
  const lk = 'https://www.lightnovel.fun';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SourcePlatform.channel, null);
  });
  Map<String, dynamic> status(String key) => {
    'status': 'verified',
    'hasSession': true,
    'loginAvailable': true,
    'checkedAt': DateTime.now().millisecondsSinceEpoch,
    'capabilities': {'verify': true, 'checkIn': true},
    'profile': {
      'displayName': key == ls ? 'Shelf reader' : 'LK reader',
      'avatarUrl': '',
    },
  };

  test(
    'safe profile fields and saved credentials remain visible on network errors',
    () {
      final value = SourceAccountStatus.fromMap({
        'status': 'error',
        'validationError': '书源轻书架连接协商失败（HTTP 403）',
        'hasSession': true,
        'profile': {'displayName': 'Reader', 'avatarUrl': ''},
      });
      expect(value.hasSession, true);
      expect(value.displayName, 'Reader');
      expect(value.label, '暂时无法验证登录');
      expect(value.explanation, contains('登录信息仍保留'));
      expect(value.explanation, contains('HTTP 403'));
    },
  );

  test(
    'Novelia account verification coalesces and invalidates across variants',
    () async {
      final sakura = _source('https://n.novelia.cc#sakura');
      final jp = _source('https://n.novelia.cc#jp');
      final store = _AccountStore([sakura, jp]);
      final repository = SourceNovelRepository(
        store: store,
        legacy: const DemoNovelRepository(),
      );
      addTearDown(repository.dispose);
      addTearDown(store.dispose);
      var verified = false, checks = 0, reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            if (call.method == 'accountStatus') {
              reads++;
              return {
                ...status(sakura.key),
                'status': verified ? 'verified' : 'saved',
              };
            }
            expect(call.method, 'run');
            expect((call.arguments as Map)['operation'], 'accountVerify');
            checks++;
            verified = true;
            return true;
          });
      final result = await Future.wait([
        repository.ensureAccount(sakura),
        repository.ensureAccount(jp),
      ]);
      expect(checks, 1);
      expect(result.every((value) => value.status == 'verified'), true);
      final before = reads;
      repository.refreshAccount(jp.key);
      await repository.accountStatus(sakura);
      expect(reads, before + 1);
    },
  );

  for (final legacySelected in [false, true]) {
    test(
      'all saved accounts restore without an account page, including Wenku selection $legacySelected',
      () async {
        final store = _AccountStore([_source(ls), _source(lk)]);
        if (legacySelected) {
          store.selectedSource = SourceNovelRepository.legacyKey;
        }
        final repository = SourceNovelRepository(
          store: store,
          legacy: const DemoNovelRepository(),
        );
        final library = await LibraryState.load();
        addTearDown(repository.dispose);
        addTearDown(store.dispose);
        addTearDown(library.dispose);
        final bridge = SourceHostBridge(library, repository: repository);
        addTearDown(bridge.dispose);
        final verified = <String>{};
        final checks = <String>[];
        final priorities = <bool>[];
        var pauses = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
              if (call.method == 'accountStatus') {
                final key = (call.arguments as Map)['bookSourceUrl'] as String;
                return {
                  ...status(key),
                  'status': verified.contains(key) ? 'verified' : 'saved',
                };
              }
              if (call.method == 'pauseConnections') {
                pauses++;
                return null;
              }
              expect(call.method, 'run');
              final args = call.arguments as Map;
              expect(args['operation'], 'accountVerify');
              final key = (args['source'] as Map)['bookSourceUrl'] as String;
              checks.add(key);
              priorities.add(args['background'] == true);
              verified.add(key);
              return true;
            });
        bridge.attach();
        await Future<void>.delayed(Duration.zero);
        expect(checks, [ls, lk]);
        expect(priorities, [legacySelected, true]);
        bridge.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(Duration.zero);
        expect(pauses, 1);
        verified.remove(lk);
        repository.refreshAccount(lk);
        store.choose(lk);
        await Future<void>.delayed(Duration.zero);
        expect(checks, [ls, lk, lk]);
        bridge.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(checks, [ls, lk, lk]);
        verified.remove(lk);
        repository.refreshAccount(lk);
        bridge.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(checks, [ls, lk, lk, lk]);
        await repository.ensureAccount(store.fixtures.last, force: true);
        expect(checks, [ls, lk, lk, lk, lk]);
        expect(priorities.skip(2), everyElement(false));
        expect(
          (await repository.accountStatus(store.fixtures.last)).status,
          'verified',
        );
      },
    );
  }

  testWidgets(
    'My identity follows discovery selection without borrowing another platform account',
    (tester) async {
      final store = _AccountStore([_source(ls), _source(lk)]);
      final repository = SourceNovelRepository(
        store: store,
        legacy: const DemoNovelRepository(),
      );
      final library = await LibraryState.load();
      addTearDown(repository.dispose);
      addTearDown(store.dispose);
      addTearDown(library.dispose);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            expect(call.method, 'accountStatus');
            return status((call.arguments as Map)['bookSourceUrl'] as String);
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: MyPage(state: library, repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shelf reader'), findsOneWidget);
      expect(find.text('轻书架 · 已登录'), findsOneWidget);
      store.choose(lk);
      await tester.pumpAndSettle();
      expect(find.text('LK reader'), findsOneWidget);
      expect(find.text('Shelf reader'), findsNothing);
      expect(find.text('轻之国度 · 已登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'account page expands the selected platform and puts others in the shared dropdown',
    (tester) async {
      final store = _AccountStore([_source(ls), _source(lk)]);
      final repository = SourceNovelRepository(
        store: store,
        legacy: const DemoNovelRepository(),
      );
      final library = await LibraryState.load();
      addTearDown(repository.dispose);
      addTearDown(store.dispose);
      addTearDown(library.dispose);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            expect(call.method, 'accountStatus');
            return status((call.arguments as Map)['bookSourceUrl'] as String);
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: PlatformAccountPage(state: library, repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('platform-account-lightnovel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('platform-account-qingguo')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('other-platform-accounts')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('other-account-qingguo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('other-account-builtin:wenku8')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('other-account-lightnovel')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
