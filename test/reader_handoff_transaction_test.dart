import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'reader_modes_test.dart' show settleReader;

void main() {
  testWidgets('touching a moving boundary does not commit an unfinished sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ReaderPagedController();
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPagedView(
          content: ReaderContent(['Current chapter']),
          chapterKey: 1,
          title: 'Current',
          controller: controller,
          preferences: const ReaderPreferences(
            mode: ReaderMode.paged,
            pageEffect: ReaderPageEffect.slide,
          ),
          style: const TextStyle(fontSize: 19),
          padding: const EdgeInsets.all(26),
          pageBuilder: (_) => const ColoredBox(color: Colors.blue),
          previousChapter: ReaderPagedChapter(
            key: 0,
            content: ReaderContent(['Previous']),
            title: 'Previous',
            pageBuilder: (_) => const ColoredBox(color: Colors.red),
          ),
          onChapterTurned: (_) => commits++,
          onReady: () {},
          onChanged: () {},
          onUserScroll: () {},
          onBoundary: (_) {},
        ),
      ),
    );
    await settleReader(tester);
    final gesture = await tester.startGesture(const Offset(80, 400));
    await gesture.moveBy(const Offset(230, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pager.page!, inExclusiveRange(0, .5));
    final interrupt = await tester.startGesture(const Offset(290, 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      commits,
      0,
      reason:
          'A pointer hold ends a scroll activity but does not finish its chapter turn.',
    );
    await interrupt.moveBy(const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await interrupt.up();
    await settleReader(tester);
    expect(commits, 0);
    expect(pager.page, closeTo(1, .001));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    testWidgets(
      '${mode.name} keeps the landed sheet while its neighbour cache changes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ReaderPagedController(), capture = GlobalKey();
        final contents = [
          for (var i = 0; i < 3; i++) ReaderContent(['Chapter $i.']),
        ];
        const colors = [Colors.red, Colors.blue, Colors.green];
        var current = 0, next = 1;
        ReaderPagedChapter adjacent(int index) => ReaderPagedChapter(
          key: index,
          content: contents[index],
          title: 'Chapter $index',
          pageBuilder: (_) => ColoredBox(color: colors[index]),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: StatefulBuilder(
                builder: (context, update) => ReaderPagedView(
                  content: contents[current],
                  chapterKey: current,
                  title: 'Chapter $current',
                  controller: controller,
                  preferences: ReaderPreferences(
                    mode: mode,
                    pageEffect: ReaderPageEffect.slide,
                  ),
                  style: const TextStyle(fontSize: 19, height: 1.7),
                  padding: const EdgeInsets.all(26),
                  pageBuilder: (_) => ColoredBox(color: colors[current]),
                  previousChapter: current == 0 ? null : adjacent(0),
                  nextChapter: adjacent(next),
                  onChapterTurned: (_) {
                    update(() => next = 2);
                  },
                  onReady: () {},
                  onChanged: () {},
                  onUserScroll: () {},
                  onBoundary: (_) {},
                ),
              ),
            ),
          ),
        );
        await settleReader(tester);
        expect(controller.adjacentReady(1), isTrue);
        expect(controller.pageBy(1), isTrue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 301));
        await tester.pump(const Duration(milliseconds: 1));
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        if (boundary.debugNeedsPaint) {
          tester.binding.rootPipelineOwner.flushPaint();
        }
        final image = boundary.toImageSync();
        var blue = false;
        await tester.runAsync(() async {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final pixel = (400 * image.width + 195) * 4;
          blue = bytes.getUint8(pixel + 2) == Colors.blue.toARGB32() & 255;
          image.dispose();
        });
        expect(
          blue,
          isTrue,
          reason:
              'The landed chapter must own its sheet until the new chapter is published; a mutable prefetch slot cannot erase it.',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'offscreen pagination waits for reflow and reuses both control geometries',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReaderPagedController();
      final contents = [
        for (var i = 0; i < 3; i++)
          ReaderContent(
            List.generate(60, (p) => '第$i章第$p段。${'重排时不能同时计算相邻章节。' * 5}'),
          ),
      ];
      var inset = 26.0;
      late StateSetter update;
      ReaderPagedChapter adjacent(int i) => ReaderPagedChapter(
        key: i,
        content: contents[i],
        title: 'Chapter $i',
        pageBuilder: (_) => const SizedBox.expand(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return ReaderPagedView(
                content: contents[1],
                chapterKey: 1,
                title: 'Chapter 1',
                controller: controller,
                preferences: const ReaderPreferences(
                  mode: ReaderMode.paged,
                  pageEffect: ReaderPageEffect.slide,
                ),
                style: const TextStyle(fontSize: 19, height: 1.7),
                padding: EdgeInsets.fromLTRB(26, inset, 26, inset),
                pageBuilder: (_) => const SizedBox.expand(),
                previousChapter: adjacent(0),
                nextChapter: adjacent(2),
                onReady: () {},
                onChanged: () {},
                onUserScroll: () {},
                onBoundary: (_) {},
                onChapterTurned: (_) {},
              );
            },
          ),
        ),
      );
      await settleReader(tester);
      final starts = controller.debugAdjacentLayoutStarts;
      expect(starts, 2);
      update(() => inset = 110);
      for (var f = 0; f < 10; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        controller.debugAdjacentLayoutStarts,
        starts,
        reason:
            'The visible reflow has priority over new offscreen pagination.',
      );
      await settleReader(tester);
      expect(controller.debugAdjacentLayoutStarts, starts + 2);
      update(() => inset = 26);
      await settleReader(tester);
      expect(
        controller.debugAdjacentLayoutStarts,
        starts + 2,
        reason: 'Reopening a known controls geometry must reuse pagination.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
