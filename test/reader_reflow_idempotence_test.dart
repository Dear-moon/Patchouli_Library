import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/personal_images.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/listening/controller.dart';
import 'package:wenku8_flutter/listening/store.dart';
import 'package:wenku8_flutter/listening/widgets.dart';

import 'reader_modes_test.dart' as fixture;
import 'support/reader_panels.dart';
import 'support/visual_review.dart';
import 'support/listening_fixture.dart';

class _EmptyBackgrounds extends ReaderBackgroundStore {
  @override
  Future<List<String>> list() async => [];
}

Future<LibraryState> library(ReaderMode mode) async {
  SharedPreferences.setMockInitialValues({
    'readerChromeVisible': true,
    'readerChromeHintSeen': true,
    'reduceMotion': true,
  });
  final state = LibraryState(
    await SharedPreferences.getInstance(),
    backgrounds: _EmptyBackgrounds(),
  );
  await state.setReaderPreferences(ReaderPreferences(mode: mode));
  return state;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.mewx.wenku8/reader_status'),
      (_) async => null,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.mewx.wenku8/reader_status'),
      null,
    );
  });

  test('reflow preference defaults on and validates its persisted value', () {
    expect(const ReaderPreferences().reflowOnChrome, isTrue);
    expect(ReaderPreferences.fromJson({}).reflowOnChrome, isTrue);
    final disabled = const ReaderPreferences().copyWith(reflowOnChrome: false);
    expect(
      ReaderPreferences.fromJson(disabled.toJson()).reflowOnChrome,
      isFalse,
    );
    expect(
      disabled.withLayoutOf(const ReaderPreferences()).reflowOnChrome,
      isFalse,
    );
    expect(
      () => ReaderPreferences.fromJson({'reflowOnChrome': 'false'}),
      throwsFormatException,
    );
  });

  testWidgets(
    'reflow switch is shared, saved and available in reader controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await library(ReaderMode.paged);
      addTearDown(state.dispose);
      await state.setIndependentReaderStyle(fixture.book.id, true);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: fixture.app(state)),
      );
      await fixture.settleReader(tester);
      await openReaderPanel(tester, tab: '操作');
      final toggle = find.byKey(const ValueKey('reader-reflow-on-chrome'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(find.text('控件显隐时正文重排'), findsOneWidget);
      await captureReview(tester, boundary, 'reader-reflow-switch');
      await tester.tap(toggle);
      await fixture.settleReader(tester);
      expect(state.readerPreferences.reflowOnChrome, isFalse);
      expect(
        state.readerPreferencesFor(fixture.book.id).reflowOnChrome,
        isFalse,
      );
      expect(
        state.readerPreferencesFor(fixture.book.id + 1).reflowOnChrome,
        isFalse,
      );
      final restarted = LibraryState(await SharedPreferences.getInstance());
      addTearDown(restarted.dispose);
      expect(restarted.readerPreferences.reflowOnChrome, isFalse);
      expect(
        restarted.readerPreferencesFor(fixture.book.id).reflowOnChrome,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets(
      '${mode.name} chrome reflow stays canonical with paused listening semantics',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = await library(mode);
        addTearDown(state.dispose);
        late ListeningController listening;
        // Command/storage queues must be born in the real async zone; awaiting
        // a queue created in FakeAsync from runAsync otherwise strands it.
        await tester.runAsync(() async {
          listening = ListeningController(
            repository: const DemoNovelRepository(),
            audio: FakeSpeechAudio(),
            store: ListeningStore(await SharedPreferences.getInstance()),
            outputFactory: (_) async => FakeListeningOutput(),
          );
          await listening.setFollow(false);
          await listening.start(fixture.book, chapter: 0, autoplay: false);
        });
        await tester.pumpWidget(
          ListeningScope(controller: listening, child: fixture.app(state)),
        );
        await fixture.settleReader(tester);
        final paged = find.byType(ReaderPagedView);
        final controller = tester.widget<ReaderPagedView>(paged).controller;
        controller.seek(.45);
        await fixture.settleReader(tester);
        Object signature() => {
          'page': controller.page,
          'size': controller.pageSize,
          'anchor': (controller.anchor!.paragraph, controller.anchor!.offset),
          'pages': [
            for (final page in controller.debugPagination!.pages)
              [
                for (final f in page.fragments)
                  (f.paragraph, f.start, f.end, f.text, f.rect),
              ],
          ],
        };
        final shown = signature();
        await tester.tapAt(const Offset(195, 422));
        // Listening enables double-tap gestures; let a real single tap settle.
        await tester.pump(const Duration(milliseconds: 350));
        await fixture.settleReader(tester);
        final hidden = signature();
        for (var round = 0; round < 8; round++) {
          await tester.tapAt(const Offset(195, 422));
          await tester.pump(const Duration(milliseconds: 350));
          await fixture.settleReader(tester);
          expect(signature(), round.isEven ? shown : hidden);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(listening.dispose);
      },
    );
  }

  for (final mode in ReaderMode.values) {
    for (final hideStatus in [false, true]) {
      testWidgets(
        '${mode.name} enabled reflow returns to each geometry, hidden status=$hideStatus',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = await library(mode);
          addTearDown(state.dispose);
          await state.setReaderPreferences(
            state.readerPreferences.copyWith(hideSystemStatus: hideStatus),
          );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(key: boundary, child: fixture.app(state)),
          );
          await fixture.settleReader(tester);
          final paged = find.byType(ReaderPagedView);
          if (mode.paginated) {
            tester.widget<ReaderPagedView>(paged).controller.seek(.45);
          } else {
            await tester.drag(
              find.byKey(const ValueKey('reader-scroll')),
              const Offset(0, -380),
            );
          }
          await fixture.settleReader(tester);
          Object signature() {
            if (mode.paginated) {
              final c = tester.widget<ReaderPagedView>(paged).controller;
              return {
                'page': c.page,
                'size': c.pageSize,
                'anchor': (c.anchor!.paragraph, c.anchor!.offset),
                'pages': [
                  for (final page in c.debugPagination!.pages)
                    [
                      for (final f in page.fragments)
                        (f.paragraph, f.start, f.end, f.text, f.rect),
                    ],
                ],
              };
            }
            final scroll = tester
                .widget<CustomScrollView>(
                  find.byKey(const ValueKey('reader-scroll')),
                )
                .controller!;
            return (scroll.offset, scroll.position.viewportDimension);
          }

          final visible = signature();
          await captureReview(
            tester,
            boundary,
            'reader-${mode.name}-reflow-shown-status-$hideStatus',
          );
          await tester.tapAt(const Offset(195, 422));
          await fixture.settleReader(tester);
          final hidden = signature();
          expect(
            hidden,
            mode.paginated ? isNot(equals(visible)) : equals(visible),
            reason:
                'Chrome reflow only changes paginated geometry; continuous '
                'scrolling keeps the same viewport and source position.',
          );
          await captureReview(
            tester,
            boundary,
            'reader-${mode.name}-reflow-hidden-status-$hideStatus',
          );
          for (var round = 0; round < 12; round++) {
            await tester.tapAt(const Offset(195, 422));
            await fixture.settleReader(tester);
            expect(
              signature(),
              round.isEven ? visible : hidden,
              reason: 'toggle $round changed a previously seen layout',
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets('${mode.name} reflow is independent of the viewport cache', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const original = EdgeInsets.fromLTRB(24, 40, 24, 32);
      final padding = ValueNotifier(original);
      addTearDown(padding.dispose);
      final controller = ReaderPagedController();
      final content = ReaderContent(fixture.paragraphs);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ValueListenableBuilder(
            valueListenable: padding,
            builder: (context, value, _) => ReaderPagedView(
              content: content,
              preferences: ReaderPreferences(mode: mode),
              style: const TextStyle(fontSize: 19, height: 1.72),
              controller: controller,
              title: '重排幂等',
              padding: value,
              reduceMotion: true,
              pageBuilder: (_) => const SizedBox.expand(),
              onReady: () {},
              onChanged: () {},
              onUserScroll: () {},
              onBoundary: (_) {},
            ),
          ),
        ),
      );
      await fixture.settleReader(tester);
      controller.seek(.45);
      await fixture.settleReader(tester);
      Object signature() => {
        'count': controller.pageCount,
        'pages': [
          for (final page in controller.debugPagination!.pages)
            [
              for (final f in page.fragments)
                (f.paragraph, f.start, f.end, f.text, f.rect),
            ],
        ],
      };
      final before = signature();
      for (var round = 0; round < 4; round++) {
        // A third geometry evicts A from the two-entry pagination cache.
        // Rebuilding A must not insert a new break at the latest page start.
        for (final next in [
          const EdgeInsets.fromLTRB(24, 108, 24, 110),
          const EdgeInsets.fromLTRB(24, 72, 24, 64),
          original,
        ]) {
          padding.value = next;
          await fixture.settleReader(tester);
          if (next.top == 108) {
            expect(controller.pageBy(round.isEven ? 1 : -1), isTrue);
            await fixture.settleReader(tester);
          }
        }
        expect(signature(), before, reason: 'round $round');
      }
      // Coalesced geometry changes must retain an exact source coordinate,
      // even when it lies inside a canonical page rather than at its start.
      const target = ReaderTextAnchor(7, 80);
      controller.reveal(target);
      await fixture.settleReader(tester);
      for (var round = 0; round < 4; round++) {
        for (final next in [
          const EdgeInsets.fromLTRB(24, 108, 24, 110),
          const EdgeInsets.fromLTRB(24, 72, 24, 64),
          original,
        ]) {
          padding.value = next;
          await tester.pump(const Duration(milliseconds: 1));
        }
      }
      await fixture.settleReader(tester);
      expect(signature(), before);
      expect(
        (controller.anchor!.paragraph, controller.anchor!.offset),
        (7, 80),
      );
      expect(
        controller.debugLeaf!.fragments.any(
          (f) => f.paragraph == 7 && f.start <= 80 && f.end > 80,
        ),
        isTrue,
      );
      controller.restore(
        const ReadingPosition(
          chapter: 0,
          chapterId: 1,
          paragraphIndex: 1,
          textOffset: 0,
          offset: 0,
          fraction: 0,
          fontSize: 19,
          width: 390,
          updatedAt: 1,
        ),
      );
      await fixture.settleReader(tester);
      expect(controller.pageBy(1), isTrue);
      await fixture.settleReader(tester);
      final afterTurn = (
        controller.anchor!.paragraph,
        controller.anchor!.offset,
      );
      for (final next in [
        const EdgeInsets.fromLTRB(24, 108, 24, 110),
        const EdgeInsets.fromLTRB(24, 72, 24, 64),
        original,
      ]) {
        padding.value = next;
        await fixture.settleReader(tester);
      }
      expect(
        (controller.anchor!.paragraph, controller.anchor!.offset),
        afterTurn,
        reason: 'An old restore must not override a newer page turn.',
      );
      expect(signature(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
