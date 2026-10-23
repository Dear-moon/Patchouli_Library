import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_reflow.dart';
import 'reader_modes_test.dart' as fixture;
import 'support/visual_review.dart';

void main() {
  setUpAll(loadReviewFonts);

  test(
    'line bands preserve all source ranges and exact shaped height',
    () async {
      final content = ReaderContent(fixture.paragraphs);
      final pagination = (await paginateReader(
        content: content,
        size: const Size(338, 540),
        style: const TextStyle(fontSize: 19, height: 1.72),
        preferences: const ReaderPreferences(mode: ReaderMode.paged),
        scaler: TextScaler.noScaling,
        current: () => true,
      ))!;
      for (final page in pagination.pages) {
        for (final fragment in page.fragments) {
          final lines = fragment.lines.toList();
          expect(lines.length, fragment.lineCount);
          expect(lines.first.start, fragment.start);
          expect(lines.last.end, fragment.end);
          expect(lines.first.top, 0);
          expect(
            lines.last.top + lines.last.height,
            closeTo(fragment.rect.height, .001),
          );
          expect(
            [
              for (final line in lines)
                content.paragraphs[fragment.paragraph].substring(
                  line.start,
                  line.end,
                ),
            ].join(),
            fragment.text,
          );
          for (var i = 1; i < lines.length; i++) {
            expect(lines[i].start, lines[i - 1].end);
            expect(
              lines[i].top,
              closeTo(lines[i - 1].top + lines[i - 1].height, .001),
            );
          }
        }
      }
    },
  );

  testWidgets(
    'real horizontal prose reflows by line without reshaping every frame',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = await fixture.library(ReaderMode.paged);
      addTearDown(state.dispose);
      await state.setReduceMotion(false);
      await state.setReaderPreferences(
        state.readerPreferences.copyWith(
          chapterEntrance: false,
          pageEffect: ReaderPageEffect.slide,
        ),
      );
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: capture, child: fixture.app(state)),
      );
      await fixture.settleReader(tester);
      final controller = tester
          .widget<ReaderPagedView>(find.byType(ReaderPagedView))
          .controller;
      controller.seek(.4);
      await fixture.settleReader(tester);
      final before = controller.debugLeaf!;
      final generation = controller.debugLayoutGeneration;
      await captureReview(tester, capture, 'line-before');
      await tester.tapAt(const Offset(195, 422));
      for (
        var i = 0;
        i < 100 && controller.debugLayoutGeneration == generation;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      for (var i = 0; i < 100 && !controller.ready; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump();
      final measured = controller.debugParagraphMeasurements;
      await captureReview(tester, capture, 'line-start');
      await tester.pump(const Duration(milliseconds: 80));
      final renderers = tester.allRenderObjects
          .whereType<RenderReaderLineMotion>()
          .toList();
      expect(renderers, isNotEmpty);
      final paragraph = renderers.firstWhere((r) => r.debugLineCount > 2);
      expect(
        paragraph.debugLineProgress(0),
        lessThan(paragraph.debugLineProgress(paragraph.debugLineCount - 1)),
      );
      expect(
        paragraph.debugLineDisplacement(0),
        isNot(paragraph.debugLineDisplacement(paragraph.debugLineCount - 1)),
      );
      await captureReview(tester, capture, 'line-middle');
      await tester.pump(const Duration(milliseconds: 80));
      expect(controller.debugParagraphMeasurements, measured);
      expect(controller.debugLayoutGeneration, generation + 1);
      await fixture.settleReader(tester);
      await captureReview(tester, capture, 'line-complete');
      expect(
        tester.allRenderObjects.whereType<RenderReaderLineMotion>(),
        isEmpty,
      );
      // Repeated and interrupted toggles return to the canonical page, including
      // paragraphs that were partially shown on the previous geometry.
      await tester.tapAt(const Offset(195, 422));
      await fixture.settleReader(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tapAt(const Offset(195, 422));
        await tester.pump(const Duration(milliseconds: 35));
        await tester.tapAt(const Offset(195, 422));
        await fixture.settleReader(tester);
      }
      expect(
        controller.debugLeaf!.fragments.map(
          (f) => (f.paragraph, f.start, f.end, f.text, f.rect),
        ),
        before.fragments.map(
          (f) => (f.paragraph, f.start, f.end, f.text, f.rect),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
