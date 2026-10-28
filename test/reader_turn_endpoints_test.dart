import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_reflow.dart';
import 'package:wenku8_flutter/reader_vertical_text.dart';
import 'reader_modes_test.dart' show settleReader;
import 'support/visual_review.dart';

Future<({int old, int next})> taggedInk(
  WidgetTester tester,
  GlobalKey boundary,
) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = render.toImageSync();
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  var old = 0, next = 0;
  for (var y = 90; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      final r = data.getUint8(offset),
          g = data.getUint8(offset + 1),
          b = data.getUint8(offset + 2);
      if (r > 150 && g < 120 && b < 100) old++;
      if (b > 150 && r < 100 && g < 120) next++;
    }
  }
  image.dispose();
  return (old: old, next: next);
}

void main() {
  setUpAll(loadReviewFonts);
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    for (final forward in [true, false]) {
      for (final end in [false, true]) {
        testWidgets(
          '${mode.name} ${forward ? 'forward' : 'backward'} ${end ? 'outgoing clears before completion' : 'incoming waits outside the screen'}',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final controller = ReaderPagedController();
            final boundary = GlobalKey();
            const style = TextStyle(
              fontFamily: 'Roboto',
              fontSize: 19,
              height: 1.7,
            );
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  home: Material(
                    color: const Color(0xfff4f2eb),
                    child: ReaderPagedView(
                      content: ReaderContent(
                        List.generate(
                          100,
                          (i) =>
                              '第${i + 1}段：正文应当从屏幕外进入，也应当完整离开屏幕。边缘不能提前露出下一页，旧页不能停住后突然消失。',
                        ),
                      ),
                      preferences: ReaderPreferences(mode: mode),
                      style: style,
                      controller: controller,
                      title: '翻页首尾',
                      padding: forward
                          ? const EdgeInsets.fromLTRB(26, 56, 26, 40)
                          : const EdgeInsets.fromLTRB(43, 56, 17, 40),
                      onReady: () {},
                      onChanged: () {},
                      onUserScroll: () {},
                      onBoundary: (_) {},
                      pageBuilder: (leaf) {
                        final index = controller.debugPagination!.pages.indexOf(
                          leaf,
                        );
                        final ink = style.copyWith(
                          color: index == (forward ? 0 : 1)
                              ? const Color(0xffff2200)
                              : const Color(0xff0033ff),
                        );
                        return mode == ReaderMode.vertical
                            ? ReaderVerticalText(page: leaf, style: ink)
                            : Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final (i, f) in leaf.fragments.indexed)
                                    Positioned.fromRect(
                                      rect: f.rect,
                                      child: ReaderFragmentMotion(
                                        fragment: f,
                                        index: i,
                                        count: leaf.fragments.length,
                                        child: Text(f.text, style: ink),
                                      ),
                                    ),
                                ],
                              );
                      },
                    ),
                  ),
                ),
              ),
            );
            await settleReader(tester);
            if (!forward) {
              controller.seek(1 / (controller.pageCount - 1));
              await settleReader(tester);
              expect(controller.page, 1);
            }
            expect((await taggedInk(tester, boundary)).old, greaterThan(100));
            controller.pageBy(forward ? 1 : -1);
            await tester.pump();
            await tester.pump(Duration(milliseconds: end ? 612 : 2));
            await captureReview(
              tester,
              boundary,
              'endpoint-${mode.name}-${forward ? 'forward' : 'backward'}-${end ? 'end' : 'start'}',
            );
            final ink = await taggedInk(tester, boundary);
            if (end) {
              expect(
                ink.old,
                0,
                reason:
                    'The outgoing ink must leave the screen before the turn tree is removed.',
              );
            } else {
              expect(
                ink.next,
                0,
                reason:
                    'The incoming ink must start outside the screen, not inside the right/left margin.',
              );
              for (final milliseconds in [2, 4, 8]) {
                await tester.pump(Duration(milliseconds: milliseconds));
                expect((await taggedInk(tester, boundary)).next, 0);
              }
            }
            await tester.pumpAndSettle();
            expect(controller.page, forward ? 1 : 0);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
