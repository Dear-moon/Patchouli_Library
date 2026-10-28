import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';

import 'reader_modes_test.dart' as fixture;
import 'support/background_fixture.dart';
import 'support/reader_panels.dart';
import 'support/visual_review.dart';

Future<LibraryState> library(ReaderMode mode) async {
  SharedPreferences.setMockInitialValues({
    'readerChromeVisible': true,
    'readerChromeHintSeen': true,
    'reduceMotion': true,
  });
  final state = LibraryState(
    await SharedPreferences.getInstance(),
    backgrounds: EmptyReaderBackgrounds(),
  );
  await state.setReaderPreferences(ReaderPreferences(mode: mode));
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);

  test(
    'both-side paging defaults off and remains a shared interaction setting',
    () {
      expect(const ReaderPreferences().tapBothSidesNext, isFalse);
      expect(ReaderPreferences.fromJson({}).tapBothSidesNext, isFalse);
      final enabled = const ReaderPreferences().copyWith(
        tapBothSidesNext: true,
      );
      expect(
        ReaderPreferences.fromJson(enabled.toJson()).tapBothSidesNext,
        isTrue,
      );
      expect(enabled.copyWith(margin: 30).tapBothSidesNext, isTrue);
      expect(
        enabled.withLayoutOf(const ReaderPreferences()).tapBothSidesNext,
        isTrue,
      );
      expect(enabled.layoutKey, const ReaderPreferences().layoutKey);
      expect(
        () => ReaderPreferences.fromJson({'tapBothSidesNext': 'true'}),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'the dependent switch appears in place and retains the selected hand layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await library(ReaderMode.paged);
      addTearDown(state.dispose);
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(tapLayout: ReaderTapLayout.rightHand),
      );
      await state.setIndependentReaderStyle(fixture.book.id, true);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: fixture.app(state)),
      );
      await fixture.settleReader(tester);
      await openReaderPanel(tester, tab: '操作');
      const nextKey = ValueKey('reader-tap-both-sides-next');
      expect(find.byKey(nextKey), findsNothing);
      final parentRow = find
          .ancestor(of: find.text('分区点按翻页'), matching: find.byType(Row))
          .first;
      final parent = find.descendant(
        of: parentRow,
        matching: find.byType(AppGlassSwitch),
      );
      await tester.ensureVisible(parent);
      await tester.tap(parent);
      await fixture.settleReader(tester);
      expect(find.byKey(nextKey), findsOneWidget);
      await tester.ensureVisible(find.byKey(nextKey));
      await tester.pumpAndSettle();
      await captureReview(tester, key, 'reader-both-sides-option-off');
      await tester.tap(find.byKey(nextKey));
      await fixture.settleReader(tester);
      expect(state.readerPreferences.tapBothSidesNext, isTrue);
      expect(
        state.readerPreferencesFor(fixture.book.id).tapBothSidesNext,
        isTrue,
      );
      expect(
        state.readerPreferencesFor(fixture.book.id + 1).tapBothSidesNext,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('reader-tap-layout-rightHand')),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(nextKey));
      await tester.pumpAndSettle();
      await captureReview(tester, key, 'reader-both-sides-option-on');
      final restarted = LibraryState(await SharedPreferences.getInstance());
      addTearDown(restarted.dispose);
      expect(restarted.readerPreferences.tapBothSidesNext, isTrue);
      await tester.tap(find.byKey(nextKey));
      await fixture.settleReader(tester);
      expect(state.readerPreferences.tapLayout, ReaderTapLayout.rightHand);
      expect(
        find.byKey(const ValueKey('reader-tap-layout-rightHand')),
        findsOneWidget,
      );
      await tester.ensureVisible(parent);
      await tester.tap(parent);
      await fixture.settleReader(tester);
      expect(find.byKey(nextKey), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets(
      '${mode.name} advances from either edge while center still toggles controls',
      (tester) async {
        final state = await library(mode);
        addTearDown(state.dispose);
        await state.setReaderPreferences(
          state.readerPreferences.copyWith(
            tapBothSidesNext: true,
            tapLayout: ReaderTapLayout.rightHand,
            reflowOnChrome: false,
          ),
        );
        await tester.pumpWidget(fixture.app(state));
        await fixture.settleReader(tester);
        ReaderPagedController pager() => tester
            .widget<ReaderPagedView>(find.byType(ReaderPagedView))
            .controller;
        Future<void> tap(double x) async {
          final rect = tester.getRect(fixture.content());
          await tester.tapAt(
            Offset(rect.left + rect.width * x, rect.center.dy),
          );
          await fixture.settleReader(tester);
        }

        // A retained child value never enables the parent option by itself.
        await tap(.1);
        expect(pager().page, 0);
        await state.setReaderPreferences(
          state.readerPreferences.copyWith(tapPaging: true),
        );
        await fixture.settleReader(tester);
        await tap(.1);
        expect(pager().page, pager().pagesPerSpread);
        await tap(.9);
        expect(pager().page, 2 * pager().pagesPerSpread);
        final chrome = state.readerChromeVisible;
        await tap(.5);
        expect(state.readerChromeVisible, !chrome);
        expect(pager().page, 2 * pager().pagesPerSpread);
        // Swiping back is still available even though both tap zones advance.
        final rect = tester.getRect(fixture.content());
        final dx = mode == ReaderMode.vertical
            ? -rect.width * .7
            : rect.width * .7;
        await tester.dragFrom(rect.center - Offset(dx / 2, 0), Offset(dx, 0));
        await fixture.settleReader(tester);
        expect(pager().page, pager().pagesPerSpread);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('scroll mode advances one screen from either side', (
    tester,
  ) async {
    final state = await library(ReaderMode.scroll);
    addTearDown(state.dispose);
    await state.setReaderPreferences(
      state.readerPreferences.copyWith(tapPaging: true, tapBothSidesNext: true),
    );
    await tester.pumpWidget(fixture.app(state));
    await fixture.settleReader(tester);
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('reader-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final before = position().pixels;
    final rect = tester.getRect(fixture.content());
    await tester.tapAt(Offset(rect.left + rect.width * .1, rect.center.dy));
    await fixture.settleReader(tester);
    final afterLeft = position().pixels;
    expect(afterLeft, greaterThan(before));
    await tester.tapAt(Offset(rect.left + rect.width * .9, rect.center.dy));
    await fixture.settleReader(tester);
    expect(position().pixels, greaterThan(afterLeft));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
