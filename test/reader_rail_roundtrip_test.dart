import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_status.dart';
import 'reader_modes_test.dart' show settleReader;
import 'support/visual_review.dart';

final _book = Novel(
  id: 987653,
  title: 'Repeated rail handoff',
  author: 'Regression',
  genre: '',
  summary: '',
  colors: const [Colors.black, Colors.grey],
  chapters: [
    for (var c = 0; c < 3; c++)
      NovelChapter(
        'Chapter $c',
        List.generate(
          [12, 40, 3][c],
          (i) => '第$c章，第$i段：${'连续来回翻动，正文与章名必须始终处于当前纸面。' * 4}',
        ).join('\n\n'),
        id: c + 1,
      ),
  ],
);

void main() {
  setUpAll(loadReviewFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          ReaderStatusFooter.events,
          MockStreamHandler.inline(
            onListen: (_, events) => events.success({
              'time': DateTime(2026, 10, 23, 0, 7).millisecondsSinceEpoch,
              'battery': 98,
              'charging': false,
            }),
          ),
        );
  });
  for (final effect in [
    ReaderPageEffect.slide,
    ReaderPageEffect.cover,
    ReaderPageEffect.staggered,
    ReaderPageEffect.paper,
  ]) {
    testWidgets(
      '${effect.name} four fast chapter reversals retain their rail after handoff',
      (tester) async {
        tester.view.physicalSize = const Size(1216, 2640);
        tester.view.devicePixelRatio = 3.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'readerChromeHintSeen': true});
        final state = await LibraryState.load();
        addTearDown(state.dispose);
        await state.setReaderPreferences(
          ReaderPreferences(
            mode: ReaderMode.paged,
            pageEffect: effect,
            hideSystemStatus: true,
          ),
        );
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              home: ReaderPage(
                novel: _book,
                state: state,
                repository: const DemoNovelRepository(),
                initialChapter: 1,
              ),
            ),
          ),
        );
        await settleReader(tester);
        ReaderPagedController controller() => tester
            .widget<ReaderPagedView>(find.byType(ReaderPagedView))
            .controller;
        Future<void> stroke(bool back, int gap) async {
          final gesture = await tester.startGesture(
            Offset(back ? 72 : 286, 371),
          );
          for (var step = 0; step < 5; step++) {
            await gesture.moveBy(Offset(back ? 43 : -43, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          if (gap > 0) {
            await tester.pump(Duration(milliseconds: gap));
          }
        }

        for (final gap in [0, 64, 160]) {
          controller().seek(0);
          await settleReader(tester);
          for (var pair = 0; pair < 4; pair++) {
            await stroke(true, 700);
            await settleReader(tester);
            await stroke(false, 700);
            await settleReader(tester);
          }
          for (var turn = 0; turn < 4; turn++) {
            await stroke(turn.isEven, gap);
          }
          await settleReader(tester);
          final view = tester.widget<PageView>(find.byType(PageView));
          expect(controller().ready, isTrue, reason: 'gap $gap');
          expect(
            view.controller!.page,
            closeTo((controller().page + 1).toDouble(), .001),
            reason:
                'gap $gap must land on the current chapter, not an empty edge',
          );
          final frame = find.byKey(
            ValueKey('reader-page-frame-${controller().page}'),
          );
          expect(tester.getTopLeft(frame).dx, closeTo(0, .01));
          expect(tester.takeException(), isNull);
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          if (boundary.debugNeedsPaint) {
            tester.binding.rootPipelineOwner.flushPaint();
          }
          final image = boundary.toImageSync(pixelRatio: .5);
          var ink = 0;
          await tester.runAsync(() async {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            for (
              var p = image.width * 80 * 4;
              p < bytes.lengthInBytes;
              p += 4
            ) {
              if (bytes.getUint8(p) < 120 &&
                  bytes.getUint8(p + 1) < 120 &&
                  bytes.getUint8(p + 2) < 120) {
                ink++;
              }
            }
            image.dispose();
          });
          expect(
            ink,
            greaterThan(20),
            reason:
                '${effect.name} gap $gap must actually paint the retained body',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    for (final rapid in [false, true]) {
      testWidgets(
        '${mode.name} ${rapid ? 'interrupted' : 'settled'} round trips retain a visible sheet',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'readerChromeHintSeen': true,
          });
          final state = await LibraryState.load();
          addTearDown(state.dispose);
          await state.setReaderPreferences(
            ReaderPreferences(mode: mode, pageEffect: ReaderPageEffect.slide),
          );
          final capture = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: ReaderPage(
                  novel: _book,
                  state: state,
                  repository: const DemoNovelRepository(),
                  initialChapter: 1,
                ),
              ),
            ),
          );
          await settleReader(tester);
          ReaderPagedView pages() =>
              tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
          final sign = mode == ReaderMode.vertical ? 1.0 : -1.0;
          void checkSheet(String phase) {
            final controller = pages().controller;
            final view = tester.widget<PageView>(find.byType(PageView));
            final expected = controller.page ~/ controller.pagesPerSpread + 1;
            expect(
              view.controller!.page,
              closeTo(expected.toDouble(), .001),
              reason: phase,
            );
            final frame = find.byKey(
              ValueKey('reader-page-frame-${expected - 1}'),
            );
            expect(frame, findsOneWidget, reason: phase);
            expect(tester.getTopLeft(frame).dx, closeTo(0, .01), reason: phase);
            expect(controller.ready, isTrue, reason: phase);
            expect(tester.takeException(), isNull, reason: phase);
          }

          for (var round = 0; round < 20; round++) {
            pages().controller.seek(0);
            await settleReader(tester);
            final before = pages().title;
            await tester.timedDragFrom(
              const Offset(100, 400),
              Offset(-sign * 190, 0),
              const Duration(milliseconds: 90),
            );
            if (rapid) {
              await tester.pump(const Duration(milliseconds: 16));
            } else {
              await settleReader(tester);
              expect(pages().title, isNot(before));
              checkSheet('backward $round');
            }
            await tester.timedDragFrom(
              const Offset(290, 400),
              Offset(sign * 190, 0),
              const Duration(milliseconds: 90),
            );
            await settleReader(tester);
            if (round % 3 == 0) {
              await tester.tapAt(const Offset(195, 400));
              await tester.pump(const Duration(milliseconds: 32));
              await tester.tapAt(const Offset(195, 400));
              await settleReader(tester);
            }
            await captureReview(
              tester,
              capture,
              'rail-${mode.name}-${rapid ? 'rapid' : 'settled'}-$round',
            );
            checkSheet('round $round');
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            if (boundary.debugNeedsPaint) {
              tester.binding.rootPipelineOwner.flushPaint();
            }
            final image = boundary.toImageSync(pixelRatio: .5);
            var ink = 0;
            await tester.runAsync(() async {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              for (var p = 0; p < bytes.lengthInBytes; p += 4) {
                if (bytes.getUint8(p) < 120 &&
                    bytes.getUint8(p + 1) < 120 &&
                    bytes.getUint8(p + 2) < 120) {
                  ink++;
                }
              }
              image.dispose();
            });
            expect(
              ink,
              greaterThan(20),
              reason:
                  'round $round must paint real ink, not just retain offscreen widgets.',
            );
            if (!rapid) expect(pages().title, before);
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
