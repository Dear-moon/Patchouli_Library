import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:wenku8_flutter/reader_turn_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/reader_book_layout.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_vertical_text.dart';

import 'reader_modes_test.dart' as fixture;
import 'support/visual_review.dart';

void main({
  Future<void> Function(WidgetTester, GlobalKey, String)? capture,
  bool native = false,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!native) setUpAll(loadReviewFonts);

  test('wide pages share a gutter; narrow and short windows stay single', () {
    final wide = ReaderBookLayout.resolve(
      viewport: const Size(972, 620),
      margin: 26,
    );
    expect(wide.count, 2);
    expect(wide.pages.first.width, wide.pages.last.width);
    expect(wide.pages.last.left - wide.pages.first.right, 52);
    expect(wide.spine!.center.dx, 486);
    for (final size in [const Size(378, 620), const Size(748, 180)]) {
      final narrow = ReaderBookLayout.resolve(viewport: size, margin: 26);
      expect(narrow.count, 1);
      expect(narrow.pageSize, size);
    }
    expect(
      ReaderBookLayout.resolve(
        viewport: const Size(668, 620),
        margin: 26,
      ).count,
      2,
    );
  });

  test('book leaves avoid an off-centre hinge and tabletop fold', () {
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(456, 0, 24, 900),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureFlat,
    );
    final book = ReaderBookLayout.resolve(
      viewport: const Size(972, 620),
      margin: 26,
      features: const [hinge],
      origin: const Offset(26, 100),
    );
    expect(book.count, 2);
    expect(book.pages.first.right, 404);
    expect(book.pages.last.left, 480);
    expect(book.pages.first.width, book.pages.last.width);
    expect(book.spine, isNull);
    const table = DisplayFeature(
      bounds: Rect.fromLTWH(0, 390, 1024, 20),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureHalfOpened,
    );
    final tabletop = ReaderBookLayout.resolve(
      viewport: const Size(972, 680),
      margin: 26,
      features: const [table],
      origin: const Offset(26, 100),
    );
    expect(tabletop.pages.every((rect) => rect.top >= 322), true);
    expect(tabletop.pages.every((rect) => rect.bottom <= 680), true);
  });

  test(
    'a flat crease never restricts a compact inner screen to half a page',
    () {
      for (final width in [600.0, 668.0, 972.0]) {
        for (final state in [
          DisplayFeatureState.postureFlat,
          DisplayFeatureState.unknown,
        ]) {
          final normal = ReaderBookLayout.resolve(
            viewport: Size(width, 800),
            margin: 26,
          );
          final folded = ReaderBookLayout.resolve(
            viewport: Size(width, 800),
            margin: 26,
            features: [
              DisplayFeature(
                bounds: Rect.fromLTWH(width / 2, 0, 0, 900),
                type: DisplayFeatureType.fold,
                state: state,
              ),
            ],
          );
          expect(folded.pages, normal.pages);
        }
      }
      final halfOpen = ReaderBookLayout.resolve(
        viewport: const Size(600, 800),
        margin: 26,
        features: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(300, 0, 0, 900),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      );
      expect(halfOpen.pageSize.width, lessThan(300));
    },
  );

  ReaderPagedController controller(WidgetTester tester) =>
      tester.widget<ReaderPagedView>(find.byType(ReaderPagedView)).controller;

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    if (capture == null) {
      await captureReview(tester, key, name);
    } else {
      await capture(tester, key, name);
    }
    expect(tester.takeException(), isNull);
  }

  void window(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    tester.view.viewPadding = tester.view.padding;
  }

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets('${mode.name} fills an unfolded compact display', (
      tester,
    ) async {
      window(tester, const Size(650, 800));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final state = await fixture.library(mode);
      addTearDown(state.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: fixture.app(
            state,
            features: const [
              DisplayFeature(
                bounds: Rect.fromLTWH(325, 0, 0, 800),
                type: DisplayFeatureType.fold,
                state: DisplayFeatureState.postureFlat,
              ),
            ],
          ),
        ),
      );
      await fixture.settleReader(tester);
      final paged = controller(tester);
      expect(paged.pagesPerSpread, 1);
      expect(paged.pageSize!.width, greaterThan(550));
      await shot(tester, boundary, 'book-${mode.name}-compact-flat-fold');
      expect(paged.pageBy(1), true);
      await fixture.settleReader(tester);
      expect(paged.page, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${mode.name} opens as a book and turns a complete spread', (
      tester,
    ) async {
      window(tester, const Size(1024, 800));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final state = await fixture.library(mode);
      await state.setReduceMotion(false);
      addTearDown(state.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: fixture.app(state)),
      );
      await fixture.settleReader(tester);
      final paged = controller(tester);
      expect(paged.pagesPerSpread, 2);
      expect(paged.visiblePages, [0, 1]);
      expect(paged.pageSize!.width, lessThan(500));
      expect(find.textContaining('1–2/'), findsOneWidget);
      final layout = paged.debugBookLayout!;
      expect(layout.pages.first.overlaps(layout.pages.last), false);
      if (mode == ReaderMode.vertical) {
        final pages = find.byType(ReaderVerticalText).hitTestable();
        final visible = tester.widgetList<ReaderVerticalText>(pages).toList();
        expect(visible, hasLength(2));
        final first = visible.first;
        final second = visible.last;
        expect(
          tester.getCenter(find.byWidget(first)).dx,
          greaterThan(tester.getCenter(find.byWidget(second)).dx),
        );
      }
      await shot(tester, boundary, 'book-${mode.name}');
      final generation = paged.debugLayoutGeneration;
      expect(paged.pageBy(1), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.byWidgetPredicate(
          (w) => w is ReaderTurnScope && w.enabled && w.outgoing,
        ),
        findsNWidgets(paged.pagesPerSpread),
      );
      await shot(tester, boundary, 'book-${mode.name}-turning');
      await tester.pumpAndSettle();
      expect(paged.visiblePages, [2, 3]);
      expect(paged.debugLayoutGeneration, generation);
      paged.seek(1);
      await fixture.settleReader(tester);
      expect(paged.page, paged.pageCount - 1);
      expect(paged.visiblePages.last, paged.pageCount - 1);
      expect(paged.fraction, 1);
      expect(
        paged.pageBy(1),
        true,
        reason: 'The next chapter follows the same page-turn path.',
      );
      await fixture.settleReader(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(state.positionFor(fixture.book.id)!.chapter, 1);
      paged.seek(1);
      await fixture.settleReader(tester);
      expect(
        paged.pageBy(1),
        false,
        reason: 'Only the final chapter is the book boundary.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '${mode.name} folds/restores with archive motion and an anchor',
      (tester) async {
        window(tester, const Size(1024, 800));
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final state = await fixture.library(mode);
        await state.setReduceMotion(false);
        addTearDown(state.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: fixture.app(state)),
        );
        await fixture.settleReader(tester);
        final paged = controller(tester);
        paged.pageBy(1);
        await fixture.settleReader(tester);
        for (final width in [430.0, 1024.0]) {
          final anchor = paged.anchor!;
          final generation = paged.debugLayoutGeneration;
          window(tester, Size(width, 800));
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 1));
            if (paged.ready && paged.debugLayoutGeneration > generation) break;
          }
          await tester.pump();
          expect(paged.pagesPerSpread, width == 430 ? 1 : 2);
          expect(paged.debugLayoutGeneration, generation + 1);
          expect(
            find.byKey(const ValueKey('reader-book-incoming')),
            findsOneWidget,
          );
          expect(find.byType(ReaderSkeleton), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          await shot(tester, boundary, 'book-${mode.name}-resize-$width');
          expect(
            paged.debugLeaf!.fragments.any(
              (fragment) =>
                  fragment.paragraph == anchor.paragraph &&
                  fragment.start <= anchor.offset &&
                  anchor.offset < fragment.end,
            ),
            true,
          );
          await tester.pumpAndSettle();
          expect(
            paged.debugLeaf!.fragments.any(
              (fragment) =>
                  fragment.paragraph == anchor.paragraph &&
                  fragment.start <= anchor.offset &&
                  anchor.offset < fragment.end,
            ),
            true,
            reason:
                'The resize must retain its anchor after callbacks settle, '
                'not only during the transition ($width).',
          );
          expect(tester.binding.transientCallbackCount, 0);
        }
        final generation = paged.debugLayoutGeneration;
        final anchor = paged.anchor!;
        final shownStart = paged.debugFirstVisibleAnchor!;
        await tester.tapAt(const Offset(512, 320));
        await fixture.settleReader(tester);
        expect(paged.pagesPerSpread, 2);
        expect(paged.debugLayoutGeneration, generation + 1);
        expect(
          (paged.anchor!.paragraph, paged.anchor!.offset),
          (anchor.paragraph, anchor.offset),
        );
        expect(
          find.byKey(const ValueKey('reader-book-incoming')),
          findsNothing,
        );
        await shot(tester, boundary, 'book-${mode.name}-hidden-chrome');
        expect(
          paged.visiblePages
              .expand((index) => paged.debugPagination!.pages[index].fragments)
              .any(
                (fragment) =>
                    fragment.paragraph == anchor.paragraph &&
                    fragment.start <= anchor.offset &&
                    anchor.offset < fragment.end,
              ),
          isTrue,
        );
        await tester.tapAt(const Offset(512, 320));
        await fixture.settleReader(tester);
        expect(
          (
            paged.debugFirstVisibleAnchor!.paragraph,
            paged.debugFirstVisibleAnchor!.offset,
          ),
          (shownStart.paragraph, shownStart.offset),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
