import 'support/source_declaration_fixtures.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart' as rendering;
import 'package:wenku8_flutter/book_collection_layout.dart';
import 'package:wenku8_flutter/novel_feed_controller.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_store.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/archive_carousel.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';

class _PreviewRepository extends DemoNovelRepository {
  final calls = <int>[];
  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) async {
    calls.add(page);
    return NovelPage(
      items: _previewBooks(page * 20, 20),
      page: page,
      totalPages: 3,
    );
  }
}

List<Novel> _previewBooks(int start, int count) => List.generate(
  count,
  (i) => Novel(
    id: 95000 + start + i,
    title: 'Preview ${start + i}',
    author: 'Author',
    genre: '',
    summary: '',
    colors: const [Colors.grey, Colors.black],
  ),
);

class _MenuStore extends SourceStore {
  _MenuStore()
    : super(File('${Directory.systemTemp.path}/unwritten-platform-menu.json')) {
    selectedSource = 'https://n.novelia.cc#sakura';
  }
  final fixtures = [
    for (final variant in ['Sakura', 'GPT', '有道', '日文原文'].indexed)
      BookSource({
        'bookSourceName': 'Novelia · ${variant.$2}',
        'engine': engineFixture('https://n.novelia.cc#sakura'),
        'bookSourceUrl':
            'https://n.novelia.cc#${['sakura', 'gpt', 'youdao', 'jp'][variant.$1]}',
      }),
  ];
  @override
  List<BookSource> get sources => fixtures;
  @override
  List<BookSource> get enabled => fixtures;
  @override
  BookSource? source(String? key) =>
      fixtures.where((source) => source.key == key).firstOrNull;
  @override
  Future<void> load() async {}
}

Future<(int, int, List<int>)> _sectionFrame(
  WidgetTester tester,
  String stage,
) async => (await tester.runAsync(() async {
  final boundary = tester.renderObject<rendering.RenderRepaintBoundary>(
    find.byKey(const ValueKey('section-capture')),
  );
  final image = await boundary.toImage();
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final folder = Platform.environment['PATCHOULI_UI_CAPTURE'];
  if (folder != null) {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File.fromUri(
      Directory(folder).uri.resolve('$stage.png'),
    ).writeAsBytes(png.buffer.asUint8List());
  }
  final result = (image.width, image.height, rgba.buffer.asUint8List());
  image.dispose();
  return result;
}))!;

void main() {
  setUp(registerSourceFixtures);
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final reduced in [false, true]) {
    testWidgets(
      'section morph keeps a gap, has no overlay, and retracts, reduced $reduced',
      (tester) async {
        var opens = 0;
        const linkKey = ValueKey('section-more-control');
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                  child: RepaintBoundary(
                    key: const ValueKey('section-capture'),
                    child: ColoredBox(
                      color: Colors.white,
                      child: SizedBox(
                        width: 180,
                        child: ArchiveSection(
                          title: '最近更新',
                          code: '01 / A LONG ARCHIVE INDEX',
                          moreKey: linkKey,
                          onMore: () {
                            opens++;
                            Navigator.of(
                              tester.element(find.byKey(linkKey)),
                            ).push(
                              softRoute<void>(
                                const Scaffold(
                                  key: ValueKey('section-more-page'),
                                  body: Text('More'),
                                ),
                                reduceMotion: reduced,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final link = find.byKey(linkKey);
        final rect = tester.getRect(link);
        final morph = find.byKey(const ValueKey('section-more-morph'));
        dynamic painter() => tester
            .widget<CustomPaint>(
              find.byKey(
                const ValueKey('section-more-morph'),
                skipOffstage: false,
              ),
            )
            .painter;
        double progress() => painter().progress as double;
        Future<void> frame(String stage) async {
          final (width, height, pixels) = await _sectionFrame(
            tester,
            '$stage-$reduced',
          );
          final capture = tester.getRect(
            find.byKey(const ValueKey('section-capture')),
          );
          final paint = tester.getRect(morph).shift(-capture.topLeft);
          int red(int x, int y) => pixels[(y * width + x) * 4];
          var left = width;
          for (var y = paint.top.ceil(); y < paint.bottom.floor(); y++) {
            for (var x = paint.left.ceil(); x < paint.right.floor(); x++) {
              if (red(x, y) < 100 && x < left) left = x;
            }
          }
          expect(left, lessThan(width));
          var ruleEnd = paint.left.ceil();
          for (var x = paint.left.ceil(); x < left - 2; x++) {
            if (red(x, paint.center.dy.floor()) < 245 ||
                red(x, paint.center.dy.ceil()) < 245) {
              ruleEnd = x;
            }
          }
          expect(left - ruleEnd - 1, greaterThanOrEqualTo(6), reason: stage);
          final background =
              rect.center - capture.topLeft + const Offset(0, 14);
          expect(
            red(background.dx.round(), background.dy.round()),
            greaterThanOrEqualTo(250),
            reason: stage,
          );
          expect(height, greaterThan(44));
        }

        expect(progress(), 0);
        await frame('dot');
        final gesture = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 70));
        await frame('pressed');
        await gesture.up();
        await tester.pump();
        expect(opens, 0);
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 90));
          expect(painter().shaftProgress, inExclusiveRange(0, 1));
          expect(painter().headProgress, 0);
          await frame('shaft-early');
          final early = painter().shaftProgress as double;
          await tester.pump(const Duration(milliseconds: 150));
          expect(painter().shaftProgress, greaterThan(early));
          expect(painter().headProgress, 0);
          await frame('shaft-long');
          await tester.pump(const Duration(milliseconds: 90));
          expect(painter().shaftProgress, 1);
          expect(painter().headProgress, inExclusiveRange(0, 1));
          await frame('head-growing');
        }
        await tester.pumpAndSettle();
        expect(progress(), 1);
        expect(tester.getRect(link), rect);
        expect(find.text('查看更多'), findsNothing);
        await frame('arrow');
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 90));
          expect(progress(), inExclusiveRange(0, 1));
          await frame('reverse');
        }
        await tester.pumpAndSettle();
        expect(progress(), 0);
        await frame('returned-dot');
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(opens, 0);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(opens, 1);
        final morePage = find.byKey(const ValueKey('section-more-page'));
        expect(morePage, findsOneWidget);
        expect(progress(), 1);
        final moreContext = tester.element(morePage);
        final exitDuration = ModalRoute.of(
          moreContext,
        )!.reverseTransitionDuration;
        Navigator.of(moreContext).pop();
        await tester.pump();
        if (!reduced) {
          expect(progress(), 1);
          await tester.pump(exitDuration);
          await tester.pump();
          expect(progress(), 1);
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 90));
          expect(progress(), inExclusiveRange(0, 1));
          await frame('after-return-retract');
        }
        await tester.pumpAndSettle();
        expect(progress(), 0);
        await frame('after-return-dot');
        expect(find.byKey(const ValueKey('section-more-dot')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'discovery caps its preview and continues loading only in the full list',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final repository = _PreviewRepository();
      final feed = NovelFeedController(repository, initialItems: 20);
      addTearDown(feed.dispose);
      await feed.loadInitial();
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: DiscoverPage(
              books: const [],
              feed: feed,
              state: state,
              repository: repository,
              onSearch: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookCollectionSliver>(find.byType(BookCollectionSliver))
            .itemCount,
        10,
      );
      final home = find.byKey(const PageStorageKey('discover'));
      await tester.drag(home, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(repository.calls, [1]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('discover-see-all-footer')),
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('discover-see-all-footer'))),
      );
      await tester.pumpAndSettle();
      final full = find.byKey(const ValueKey('all-discovery-books'));
      expect(full, findsOneWidget);
      final scrolling = find.descendant(
        of: full,
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(scrolling, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(repository.calls, contains(2));
      Navigator.of(tester.element(full)).pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookCollectionSliver>(find.byType(BookCollectionSliver))
            .itemCount,
        10,
      );
    },
  );

  testWidgets(
    'shelf preview offers both full list entries without losing sort or books',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      await state.setShelfView(layout: 'list');
      final books = _previewBooks(0, 30);
      for (final book in books) {
        await state.setShelfMembership(book.id, true, novel: book);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: ShelfPage(
              books: books,
              state: state,
              repository: const DemoNovelRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<BookCollectionView>(
        find.byType(BookCollectionView),
      );
      expect(view.itemCount - view.leadingCount - view.trailingCount, 10);
      expect(
        find.byKey(const ValueKey('shelf-see-all-header')),
        findsOneWidget,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('shelf-see-all-header'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shelf-see-all-header')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-shelf-books')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shelf-see-all-header')),
          matching: find.byKey(const ValueKey('section-more-arrow')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('shelf-see-all-header')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-shelf-books')), findsOneWidget);
      expect(tester.widget<ShelfPage>(find.byType(ShelfPage)).fullList, true);
      final full = tester.widget<BookCollectionView>(
        find.byType(BookCollectionView),
      );
      expect(full.itemCount - full.leadingCount - full.trailingCount, 30);
      expect(state.shelf.length, 30);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('all-shelf-books'))),
      ).pop();
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byType(ShelfPage),
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(scroll, const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shelf-see-all-footer')),
        findsOneWidget,
      );
    },
  );

  for (final quiet in [false, true]) {
    testWidgets(
      'Novelia submenu animates entry and return with reduced motion $quiet',
      (tester) async {
        final store = _MenuStore();
        addTearDown(store.dispose);
        final repository = SourceNovelRepository(
          store: store,
          legacy: const DemoNovelRepository(),
        );
        addTearDown(repository.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 64,
                  child: DiscoveryPlatformHeader(
                    repository: repository,
                    reduceMotion: quiet,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(
            find.byKey(const ValueKey('discovery-platform-picker')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('discovery-platform-novelia')),
        );
        await tester.pump();
        final switcher = tester.widget<AnimatedSwitcher>(
          find.byKey(const ValueKey('platform-menu-transition')),
        );
        expect(switcher.duration, quiet ? Duration.zero : NovelMotion.enter);
        final child = find.byKey(const ValueKey('platform-menu-novelia'));
        if (!quiet) {
          final fade = find
              .ancestor(of: child, matching: find.byType(FadeTransition))
              .first;
          expect(
            tester.widget<FadeTransition>(fade).opacity.value,
            lessThan(1),
          );
          await tester.pump(const Duration(milliseconds: 120));
          expect(
            tester.widget<FadeTransition>(fade).opacity.value,
            greaterThan(0),
          );
          expect(
            tester.widget<FadeTransition>(fade).opacity.value,
            lessThan(1),
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('platform-menu-back')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('platform-menu-root')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        Navigator.of(
          tester.element(find.byKey(const ValueKey('platform-menu-root'))),
        ).pop();
        await tester.pumpAndSettle();
      },
    );
  }

  test('shelf view choice survives a backup roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final state = await LibraryState.load();
    addTearDown(state.dispose);
    await state.setShelfView(layout: 'list');
    final backup = await state.createBackup();
    await state.setShelfView(layout: 'shelf');
    await state.restoreBackup(backup, importPreferences: true);
    expect(state.shelfLayout, 'list');
  });
  testWidgets(
    'shelf preview shows up to 10 books and retains the full management list',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final books = [
        for (var i = 1; i <= 12; i++)
          Novel(
            id: 9000 + i,
            title: '书架作品 $i',
            author: '作者',
            genre: '',
            summary: '',
            colors: const [Colors.grey, Colors.black],
            chapters: const [],
          ),
      ];
      for (final book in books) {
        await state.setShelfMembership(book.id, true, novel: book);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: ShelfPage(
              books: books,
              state: state,
              repository: const DemoNovelRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ArchiveFileCarousel>(find.byType(ArchiveFileCarousel))
            .books
            .length,
        10,
      );
      expect(find.text('全部书籍'), findsNWidgets(2));
      final view = find.byKey(const ValueKey('shelf-view'));
      await tester.tap(view);
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅列表'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveFileCarousel), findsNothing);
      expect(state.shelfLayout, 'list');
      final restored = await LibraryState.load();
      expect(restored.shelfLayout, 'list');
      restored.dispose();
      await state.setShelfView(layout: 'shelf');
      for (final book in books.take(3)) {
        await state.setShelfMembership(book.id, false);
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ArchiveFileCarousel>(find.byType(ArchiveFileCarousel))
            .books
            .length,
        9,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
