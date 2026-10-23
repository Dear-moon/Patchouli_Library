import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/archive_shelf.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/novel_feed_controller.dart';
import 'package:wenku8_flutter/pages.dart';
import 'support/visual_review.dart';

class _Pending extends DemoNovelRepository {
  final requests = <Completer<NovelPage>>[];
  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) {
    final pending = Completer<NovelPage>();
    requests.add(pending);
    return pending.future;
  }
}

final _books = [
  for (var i = 0; i < 24; i++)
    Novel(
      id: 975000 + i,
      title: '书籍 ${i + 1}',
      author: '作者',
      genre: '轻小说',
      summary: '',
      colors: demoNovels.first.colors,
    ),
];

void main({
  Future<void> Function(WidgetTester tester, GlobalKey key, String name)?
  capture,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  for (final dark in [false, true]) {
    testWidgets(
      'pull refresh keeps the loaded shelf intact ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final state = await LibraryState.load();
        addTearDown(state.dispose);
        final repository = _Pending(), boundary = GlobalKey();
        final feed = NovelFeedController(repository);
        addTearDown(feed.dispose);
        final load = feed.loadInitial();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: novelTheme(dark ? Brightness.dark : Brightness.light),
              home: Scaffold(
                body: Atmosphere(
                  child: DiscoverPage(
                    books: const [],
                    feed: feed,
                    state: state,
                    repository: repository,
                    onSearch: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        // The book-wave skeleton intentionally keeps animating while pending.
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.byType(ArchiveShelfSkeleton), findsOneWidget);
        repository.requests.single.complete(
          NovelPage(items: _books, page: 1, totalPages: 1),
        );
        await load;
        await tester.pumpAndSettle();
        final shelfState = tester.state(find.byType(ArchiveFileCarousel));
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final scrollTop = scroll.position.pixels;

        await tester.timedDragFrom(
          tester.getBottomLeft(find.text('最近更新')) + const Offset(12, 8),
          Offset(0, scroll.position.viewportDimension * .8),
          const Duration(milliseconds: 600),
        );
        await tester.pump(const Duration(milliseconds: 700));
        // Native refresh waits for its snap animation before invoking the
        // callback. The integration binding advances real, not fake, time.
        for (var frame = 0; frame < 40 && !feed.refreshing; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          feed.refreshing,
          isTrue,
          reason:
              'viewport=${scroll.position.viewportDimension}, offset=${scroll.position.pixels}, requests=${repository.requests.length}',
        );
        expect(find.byType(ArchiveShelfSkeleton), findsNothing);
        expect(
          tester.state(find.byType(ArchiveFileCarousel)),
          same(shelfState),
        );
        final feedback = find.byKey(const ValueKey('feed-refresh-progress'));
        expect(feedback, findsOneWidget);
        expect(tester.getSize(feedback).height, lessThanOrEqualTo(8));
        expect(
          tester.getBottomLeft(feedback).dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('archive-file-carousel')))
                .dy,
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        expect(find.byType(LoadingSkeleton), findsNothing);
        await captureReview(
          tester,
          boundary,
          'discovery-refresh-${dark ? 'dark' : 'light'}-pending',
        );
        if (capture != null) {
          await capture(
            tester,
            boundary,
            'discovery-refresh-${dark ? 'dark' : 'light'}-pending',
          );
        }

        repository.requests.last.complete(
          NovelPage(
            items: [_books.last, ..._books.take(_books.length - 1)],
            page: 1,
            totalPages: 1,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          tester.state(find.byType(ArchiveFileCarousel)),
          same(shelfState),
        );
        expect(find.byType(ArchiveShelfSkeleton), findsNothing);
        expect(find.byType(BookRowSkeleton), findsNothing);
        await captureReview(
          tester,
          boundary,
          'discovery-refresh-${dark ? 'dark' : 'light'}-updated',
        );
        if (capture != null) {
          await capture(
            tester,
            boundary,
            'discovery-refresh-${dark ? 'dark' : 'light'}-updated',
          );
        }
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, scrollTop);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
