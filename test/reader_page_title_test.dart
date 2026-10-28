import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'reader_modes_test.dart' as fixture;
import 'support/visual_review.dart';

String shownTitle(WidgetTester tester) => tester
    .widget<AppText>(find.byKey(const ValueKey('reader-chapter-title')))
    .data;

final book = Novel(
  id: 987620,
  title: '页眉章节归属',
  author: '',
  genre: '',
  summary: '',
  colors: const [Colors.black, Colors.grey],
  chapters: [
    NovelChapter('原始资源标题', fixture.paragraphs.join('\n\n'), id: 1),
    const NovelChapter('插图单页', '这页属于未列入目录的插图页，不能显示上一章标题。', id: 2),
    const NovelChapter('下一章资源', '下一章正文。', id: 3),
  ],
  navigation: const BookNavigation([
    BookNavigationEntry('第一章', BookReadingTarget(1)),
    BookNavigationEntry('第一章内第二节', BookReadingTarget(1, paragraph: 5)),
    BookNavigationEntry('第二章', BookReadingTarget(3)),
  ]),
);

void main() {
  setUpAll(loadReviewFonts);
  test('reading labels resolve the source anchor within the same resource', () {
    expect(book.readingTitleFor(1), '插图单页');
    expect(book.readingTitleFor(0, paragraph: 4, offset: 100), '第一章');
    expect(book.readingTitleFor(0, paragraph: 5), '第一章内第二节');
  });
  testWidgets('a title correction updates the paper without repagination', (
    tester,
  ) async {
    final title = ValueNotifier('旧标题');
    addTearDown(title.dispose);
    final controller = ReaderPagedController();
    final content = ReaderContent(fixture.paragraphs);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: title,
          builder: (context, value, _) => ReaderPagedView(
            content: content,
            controller: controller,
            chapterKey: 'same-chapter',
            title: value,
            style: const TextStyle(fontSize: 19, height: 1.72),
            preferences: const ReaderPreferences(mode: ReaderMode.paged),
            padding: const EdgeInsets.all(24),
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
    final generation = controller.debugLayoutGeneration;
    title.value = '修正后的本章标题';
    await tester.pump();
    expect(shownTitle(tester), '修正后的本章标题');
    expect(controller.debugLayoutGeneration, generation);
  });

  testWidgets(
    'an unlisted reading resource never borrows another chapter title',
    (tester) async {
      final state = await fixture.library(ReaderMode.paged);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 1,
          ),
        ),
      );
      await fixture.settleReader(tester);
      expect(shownTitle(tester), '插图单页');
    },
  );

  testWidgets('pages inside one EPUB resource use their own directory anchor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await fixture.library(ReaderMode.paged);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: ReaderPage(
          novel: book,
          state: state,
          repository: const DemoNovelRepository(),
          initialChapter: 0,
        ),
      ),
    );
    await fixture.settleReader(tester);
    expect(shownTitle(tester), '第一章');
    final controller = tester
        .widget<ReaderPagedView>(find.byType(ReaderPagedView))
        .controller;
    controller.seek(1);
    await fixture.settleReader(tester);
    expect(
      controller.debugFirstVisibleAnchor!.paragraph,
      greaterThanOrEqualTo(5),
    );
    expect(shownTitle(tester), '第一章内第二节');
    controller.seek(0);
    await fixture.settleReader(tester);
    expect(shownTitle(tester), '第一章');
  });

  testWidgets(
    'prefetched titles remain with their own chapters on round trips',
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
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            initialChapter: 1,
          ),
        ),
      );
      await fixture.settleReader(tester);
      ReaderPagedController controller() => tester
          .widget<ReaderPagedView>(find.byType(ReaderPagedView))
          .controller;
      for (var round = 0; round < 4; round++) {
        expect(shownTitle(tester), '插图单页');
        expect(controller().adjacentReady(1), isTrue);
        expect(controller().pageBy(1), isTrue);
        await fixture.settleReader(tester);
        expect(shownTitle(tester), '第二章');
        expect(controller().pageBy(-1), isTrue);
        await fixture.settleReader(tester);
        expect(shownTitle(tester), '插图单页');
        expect(controller().pageBy(-1), isTrue);
        await fixture.settleReader(tester);
        expect(shownTitle(tester), '第一章内第二节');
        expect(controller().pageBy(1), isTrue);
        await fixture.settleReader(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
