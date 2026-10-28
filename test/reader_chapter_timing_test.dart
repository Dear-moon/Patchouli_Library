import 'package:flutter/material.dart';
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
  id: 987652,
  title: 'Same gesture, same turn',
  author: 'Regression',
  genre: '',
  summary: '',
  colors: const [Colors.grey, Colors.black],
  chapters: [
    for (var c = 0; c < 2; c++)
      NovelChapter(
        c == 0 ? 'Before' : 'After',
        List.generate(
          40,
          (i) => '第$c章，第$i段。${'书页与章名应同时跟随手势，章节切换不能重新启动动画。' * 4}',
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
            onListen: (_, events) {
              events.success({
                'time': DateTime(2026, 10, 22, 10, 35).millisecondsSinceEpoch,
                'battery': 56,
                'charging': true,
              });
            },
          ),
        );
  });
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    for (final speed in ReaderPageSpeed.values) {
      for (final forward in [true, false]) {
        testWidgets(
          '${mode.name}/${speed.name}/${forward ? 'next' : 'previous'} chapter swipe follows and settles like an ordinary page',
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
              ReaderPreferences(
                mode: mode,
                pageEffect: ReaderPageEffect.slide,
                pageSpeed: speed,
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
                    initialChapter: forward ? 0 : 1,
                  ),
                ),
              ),
            );
            await settleReader(tester);
            ReaderPagedController controller() => tester
                .widget<ReaderPagedView>(find.byType(ReaderPagedView))
                .controller;
            double sourceX(int spread) => tester
                .getTopLeft(
                  find.byKey(ValueKey('reader-page-frame-$spread')).first,
                )
                .dx;
            final sign =
                (mode == ReaderMode.vertical ? 1.0 : -1.0) * (forward ? 1 : -1);
            final name =
                '${mode.name}-${speed.name}-${forward ? 'next' : 'previous'}';
            Future<(double, double, List<double>)> stroke(
              int spread, {
              bool chapter = false,
            }) async {
              final gesture = await tester.startGesture(const Offset(195, 400));
              await gesture.moveBy(Offset(sign * 60, 0));
              await tester.pump(const Duration(milliseconds: 16));
              await gesture.moveBy(Offset(sign * 60, 0));
              await tester.pump(const Duration(milliseconds: 16));
              final moved = sourceX(spread);
              final incoming = find.byKey(
                ValueKey('reader-page-frame-${spread + (forward ? 1 : -1)}'),
              );
              final source = find.byKey(ValueKey('reader-page-frame-$spread'));
              final rect = tester.getRect(source.first);
              final nextRect = tester.getRect(incoming.first);
              expect(
                rect.intersect(nextRect).width,
                lessThan(.05),
                reason: 'Adjacent sheets cannot share a visible strip.',
              );
              final status = find.descendant(
                of: source.first,
                matching: find.byType(ReaderStatusFooter),
              );
              final title = find.descendant(
                of: source.first,
                matching: find.text(forward ? 'Before' : 'After'),
              );
              expect(status, findsOneWidget);
              final inset = tester
                  .widget<ReaderPagedView>(find.byType(ReaderPagedView))
                  .padding
                  .left;
              expect(
                tester.getTopLeft(title).dx,
                closeTo(rect.left + inset, .1),
              );
              await tester.pump(const Duration(milliseconds: 96));
              final held = sourceX(spread);
              await captureReview(
                tester,
                capture,
                'timing-$name-${chapter ? 'chapter' : 'page'}-held',
              );
              await gesture.up();
              final samples = <double>[];
              for (var i = 0; i < 36; i++) {
                await tester.pump(const Duration(milliseconds: 16));
                final source = find.byKey(
                  ValueKey('reader-page-frame-$spread'),
                );
                samples.add(
                  source.evaluate().isEmpty
                      ? sign * 390
                      : tester.getTopLeft(source.first).dx,
                );
                if (chapter && i == 4) {
                  await captureReview(
                    tester,
                    capture,
                    'timing-$name-chapter-release',
                  );
                }
              }
              await settleReader(tester);
              return (moved, held, samples);
            }

            if (!forward) {
              controller().seek(1);
              await settleReader(tester);
            }
            final normalSpread =
                controller().page ~/ controller().pagesPerSpread;
            final ordinary = await stroke(normalSpread);
            controller().seek(forward ? 1 : 0);
            await settleReader(tester);
            final last = controller().page ~/ controller().pagesPerSpread;
            expect(controller().adjacentReady(forward ? 1 : -1), isTrue);
            final boundary = await stroke(last, chapter: true);
            debugPrint(
              '$name: ordinary=${ordinary.$1},${ordinary.$2}; chapter=${boundary.$1},${boundary.$2}',
            );
            expect(
              boundary.$1,
              closeTo(ordinary.$1, .1),
              reason:
                  'The chapter edge must already be under the finger, not waiting to start a full animation.',
            );
            expect(
              boundary.$2,
              closeTo(boundary.$1, .1),
              reason: 'Holding still cannot advance a chapter transition.',
            );
            for (var i = 0; i < ordinary.$3.length; i++) {
              expect(
                boundary.$3[i],
                closeTo(ordinary.$3[i], .5),
                reason: 'Release frame $i must use the same settling clock.',
              );
            }
            expect(
              tester
                  .widget<ReaderPagedView>(find.byType(ReaderPagedView))
                  .title,
              forward ? 'After' : 'Before',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    for (final speed in ReaderPageSpeed.values) {
      testWidgets(
        '${mode.name}/${speed.name} tapped chapter and page use the same duration',
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
            ReaderPreferences(
              mode: mode,
              pageEffect: ReaderPageEffect.slide,
              pageSpeed: speed,
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: ReaderPage(
                novel: _book,
                state: state,
                repository: const DemoNovelRepository(),
                initialChapter: 0,
              ),
            ),
          );
          await settleReader(tester);
          ReaderPagedView pages() =>
              tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
          final quarter = Duration(
            microseconds:
                speed.durationFor(ReaderPageEffect.slide).inMicroseconds ~/ 4,
          );
          Future<List<double>> turn(bool chapter) async {
            pages().controller.seek(chapter ? 1 : 0);
            await settleReader(tester);
            final position = tester
                .widget<PageView>(find.byType(PageView))
                .controller!
                .position;
            final start = position.pixels;
            expect(pages().controller.pageBy(1), isTrue);
            await tester.pump();
            final samples = <double>[];
            for (var i = 0; i < 3; i++) {
              await tester.pump(quarter);
              samples.add(
                (position.pixels - start) / position.viewportDimension,
              );
              expect(
                find.byKey(const ValueKey('reader-chapter-outgoing')),
                findsNothing,
              );
            }
            await tester.pump(quarter + const Duration(milliseconds: 1));
            await tester.pump(const Duration(milliseconds: 16));
            expect(pages().title, chapter ? 'After' : 'Before');
            await settleReader(tester);
            return samples;
          }

          final ordinary = await turn(false), chapter = await turn(true);
          for (var i = 0; i < ordinary.length; i++) {
            expect(chapter[i], closeTo(ordinary[i], .0001));
            expect(chapter[i], closeTo((i + 1) / 4, .001));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '${mode.name} an unfinished or reversed boundary stroke never commits the adjacent chapter',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'readerChromeHintSeen': true});
        final state = await LibraryState.load();
        addTearDown(state.dispose);
        await state.setReaderPreferences(
          ReaderPreferences(mode: mode, pageEffect: ReaderPageEffect.slide),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderPage(
              novel: _book,
              state: state,
              repository: const DemoNovelRepository(),
              initialChapter: 0,
            ),
          ),
        );
        await settleReader(tester);
        ReaderPagedView pages() =>
            tester.widget<ReaderPagedView>(find.byType(ReaderPagedView));
        pages().controller.seek(1);
        await settleReader(tester);
        final last = pages().controller.page;
        final sign = mode == ReaderMode.vertical ? 1.0 : -1.0;
        for (final reverse in [false, true]) {
          final gesture = await tester.startGesture(const Offset(195, 400));
          await gesture.moveBy(Offset(sign * 60, 0));
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.moveBy(Offset(sign * (reverse ? 90 : 20), 0));
          await tester.pump(const Duration(milliseconds: 96));
          expect(pages().title, 'Before');
          if (reverse) {
            await gesture.moveBy(Offset(-sign * 90, 0));
            await tester.pump(const Duration(milliseconds: 96));
          }
          await gesture.up();
          await settleReader(tester);
          expect(pages().title, 'Before');
          expect(pages().controller.page, last);
          expect(pages().controller.ready, isTrue);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
