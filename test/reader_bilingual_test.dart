import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_rich_content.dart';
import 'reader_modes_test.dart' show settleReader;
import 'support/background_fixture.dart';
import 'support/font_store_fixture.dart';
import 'support/epub_bilingual_fixture.dart';
import 'support/visual_review.dart';

class _Repository extends DemoNovelRepository {
  _Repository(this.book);
  final ImportedBook book;
  int reads = 0;
  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async {
    reads++;
    return book.bodies.first;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  ImportedBook fixture() =>
      parseLocalBook(LocalBookInput('双语.epub', bilingualEpubFixture()));

  test(
    'EPUB retains inherited language and multiplicative publisher opacity',
    () async {
      final content = await ReaderContent.parse(fixture().bodies.single);
      expect(content.languages, {'zh', 'ja', 'en'});
      expect(content.formats[0]!.language, 'zh');
      for (final index in [1, 3, 4]) {
        expect(content.formats[index]!.language, 'ja');
        expect(content.formats[index]!.opacity, closeTo(.4, .0001));
        expect(content.formats[index]!.slice(0, 3).opacity, .4);
      }
      final decoded = ReaderRichBody.decode(
        ReaderRichBody(content.paragraphs, formats: content.formats).encode(),
      );
      expect(decoded.formats[1]!.opacity, .4);
      final ink = content.formats[1]!.textStyle(
        const TextStyle(color: Color(0xFF30352F)),
      );
      expect(ink.color!.a, closeTo(.4, .001));
      final chinese = content.withHiddenLanguages({'ja', 'en'});
      expect(chinese.paragraphs, same(content.paragraphs));
      expect(chinese.order.toList(), [0, 2]);
      expect(chinese.layoutKey('base'), isNot(content.layoutKey('base')));
      for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
        final pages = (await paginateReader(
          content: content,
          size: const Size(320, 500),
          style: const TextStyle(fontSize: 20, color: Colors.black),
          preferences: ReaderPreferences(mode: mode),
          scaler: TextScaler.noScaling,
          current: () => true,
        ))!;
        if (mode == ReaderMode.vertical) {
          expect(
            pages.pages
                .expand((p) => p.glyphs)
                .where((g) => g.paragraph == 1)
                .every((g) => g.opacity == .4),
            true,
          );
        }
        final filtered = (await paginateReader(
          content: chinese,
          size: const Size(320, 500),
          style: const TextStyle(fontSize: 20),
          preferences: ReaderPreferences(mode: mode),
          scaler: TextScaler.noScaling,
          current: () => true,
        ))!;
        expect(
          filtered.pages
              .expand((p) => p.fragments)
              .every((f) => {0, 2}.contains(f.paragraph)),
          true,
        );
      }
    },
  );

  test(
    'book language choices persist independently of typography and backup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      await state.setHiddenReaderLanguages(100, {'ja'});
      expect(state.independentReaderStyle(100), false);
      expect(state.hiddenReaderLanguagesFor(101), isEmpty);
      await state.setIndependentReaderStyle(100, true);
      await state.setIndependentReaderStyle(100, false);
      expect(state.hiddenReaderLanguagesFor(100), {'ja'});
      final backup = await state.createBackup();
      final loaded = await LibraryState.load();
      addTearDown(loaded.dispose);
      expect(loaded.hiddenReaderLanguagesFor(100), {'ja'});
      await loaded.setHiddenReaderLanguages(100, {});
      await loaded.restoreBackup(backup, importPreferences: true);
      expect(loaded.hiddenReaderLanguagesFor(100), {'ja'});
    },
  );

  test(
    'existing EPUB gains language metadata without changing body coordinates or chapter IDs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bilingual-migration-',
      );
      addTearDown(() => root.delete(recursive: true));
      final initial = LocalBookStore(Directory('${root.path}/books'));
      await initial.load();
      final book = await initial.import(
        LocalBookInput('旧双语.epub', bilingualEpubFixture()),
      );
      initial.dispose();
      final folder = Directory('${root.path}/books/${book.id}');
      final metadata = File('${folder.path}/book.json');
      final record =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      (record['source'] as Map).remove('publisherLanguages');
      await metadata.writeAsString(jsonEncode(record));
      final bodyFile = File('${folder.path}/c${book.chapters.first.id}.txt');
      final original = ReaderRichBody.decode(await bodyFile.readAsString());
      await bodyFile.writeAsString(
        ReaderRichBody(
          original.paragraphs,
          revision: original.revision,
        ).encode(),
      );
      final loaded = LocalBookStore(Directory('${root.path}/books'));
      addTearDown(loaded.dispose);
      await loaded.load();
      final upgraded = await loaded.ensureNavigation(book.id);
      final after = ReaderRichBody.decode(await bodyFile.readAsString());
      expect(
        upgraded.chapters.map((c) => c.id),
        book.chapters.map((c) => c.id),
      );
      expect(after.paragraphs, original.paragraphs);
      expect(after.formats[1]!.language, 'ja');
      expect(after.formats[1]!.opacity, .4);
      expect(after.revision, original.revision);
    },
  );

  test(
    'only-language mode applies to languages first encountered in a later chapter and survives backup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      await state.setHiddenReaderLanguages(100, {'ja'}, onlyLanguage: 'zh');
      final backup = await state.createBackup();
      final restored = await LibraryState.load();
      addTearDown(restored.dispose);
      expect(restored.onlyReaderLanguageFor(100), 'zh');
      final later = ReaderContent(
        const ['中文', 'English', '日本語', '未标记的插图说明'],
        formats: {
          0: const ReaderRichParagraph(language: 'zh'),
          1: const ReaderRichParagraph(language: 'en'),
          2: const ReaderRichParagraph(language: 'ja'),
        },
      );
      expect(
        later
            .withHiddenLanguages(
              restored.hiddenReaderLanguagesFor(100),
              onlyLanguage: restored.onlyReaderLanguageFor(100),
            )
            .order
            .toList(),
        [0, 3],
      );
      await restored.setHiddenReaderLanguages(100, {});
      expect(restored.onlyReaderLanguageFor(100), isNull);
      await restored.restoreBackup(backup, importPreferences: true);
      expect(restored.onlyReaderLanguageFor(100), 'zh');
    },
  );

  for (final mode in ReaderMode.values) {
    testWidgets(
      'actual ${mode.name} reader toggles languages without refetching or losing original text',
      (tester) async {
        tester.view.physicalSize = const Size(412, 892);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'reduceMotion': true,
          'readerChromeVisible': true,
          'readerChromeHintSeen': true,
        });
        final state = LibraryState(
          await SharedPreferences.getInstance(),
          backgrounds: EmptyReaderBackgrounds(),
          fonts: InstalledSerifFixture(),
        );
        addTearDown(state.dispose);
        await state.setReaderPreferences(ReaderPreferences(mode: mode));
        final repo = _Repository(fixture());
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: novelTheme(
                mode == ReaderMode.vertical
                    ? Brightness.dark
                    : Brightness.light,
              ),
              home: ReaderPage(
                novel: repo.book.novel,
                state: state,
                repository: repo,
                initialChapter: 0,
              ),
            ),
          ),
        );
        await settleReader(tester);
        await captureReview(tester, boundary, 'bilingual-${mode.name}-both');
        await tester.tap(find.byKey(const ValueKey('reader-settings-entry')));
        await tester.pumpAndSettle();
        final chinese = find.byKey(const ValueKey('reader-language-only-zh'));
        await tester.ensureVisible(chinese);
        await captureReview(
          tester,
          boundary,
          'bilingual-${mode.name}-language-options',
        );
        await tester.tap(chinese);
        await tester.pumpAndSettle();
        expect(state.hiddenReaderLanguagesFor(repo.book.novel.id), {
          'ja',
          'en',
        });
        await tester.binding.handlePopRoute();
        await settleReader(tester);
        if (mode == ReaderMode.scroll) {
          expect(find.byKey(const ValueKey('paragraph-1')), findsNothing);
        } else {
          final content = tester
              .widget<ReaderPagedView>(find.byType(ReaderPagedView))
              .content;
          expect(
            content.order.every((i) => content.formats[i]?.language != 'ja'),
            true,
          );
          expect(content.paragraphs, contains('これは日本語の段落です。'));
        }
        expect(repo.reads, 1);
        expect(tester.takeException(), isNull);
        await captureReview(
          tester,
          boundary,
          'bilingual-${mode.name}-hidden-ja',
        );
        await tester.tap(find.byKey(const ValueKey('reader-settings-entry')));
        await tester.pumpAndSettle();
        // Selecting the current language again must not hide it.
        await tester.ensureVisible(chinese);
        await tester.tap(chinese);
        await tester.pumpAndSettle();
        expect(state.hiddenReaderLanguagesFor(repo.book.novel.id), {
          'ja',
          'en',
        });
        final japanese = find.byKey(const ValueKey('reader-language-only-ja'));
        await tester.ensureVisible(japanese);
        await tester.tap(japanese);
        await tester.pumpAndSettle();
        expect(state.hiddenReaderLanguagesFor(repo.book.novel.id), {
          'zh',
          'en',
        });
        final all = find.byKey(const ValueKey('reader-language-all'));
        await tester.ensureVisible(all);
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(state.hiddenReaderLanguagesFor(repo.book.novel.id), isEmpty);
        await tester.binding.handlePopRoute();
        await settleReader(tester);
        if (mode == ReaderMode.scroll) {
          expect(find.byKey(const ValueKey('paragraph-1')), findsOneWidget);
        } else {
          expect(
            tester
                .widget<ReaderPagedView>(find.byType(ReaderPagedView))
                .content
                .languageFilter,
            isEmpty,
          );
        }
        expect(repo.reads, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'local continue button uses a compact section number without the chapter name',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reduceMotion': true});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      final book = fixture().novel;
      await state.setChapter(book.id, 0);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: DetailPage(
            novel: book,
            state: state,
            repository: const DemoNovelRepository(),
            fromCache: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<GlassPillButton>(
        find.byKey(const ValueKey('detail-read-button')),
      );
      expect(button.label, '继续阅读 · 第1节');
      expect(button.label, isNot(contains(book.title)));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final key in ['BILINGUAL_EPUB', 'REFERENCE_EPUB']) {
    final path = Platform.environment[key];
    test('user supplied $key imports with semantic navigation', () async {
      final imported = parseLocalBook(
        LocalBookInput(
          File(path!).uri.pathSegments.last,
          await File(path).readAsBytes(),
        ),
      );
      expect(imported.novel.chapters, isNotEmpty);
      expect(imported.novel.navigation?.entries, isNotEmpty);
      final bodies = [
        for (final body in imported.bodies) ReaderRichBody.decode(body),
      ];
      final formats = bodies.expand((b) => b.formats.values).toList();
      if (key == 'BILINGUAL_EPUB') {
        final japanese = formats.where((f) => f.language == 'ja').toList();
        expect(japanese.length, greaterThan(10000));
        expect(japanese.every((f) => f.opacity == .4), true);
        expect(formats.any((f) => f.language == 'zh'), true);
      }
      debugPrint(
        jsonEncode({
          'fixture': key,
          'chapters': imported.novel.chapters.length,
          'directory': imported.novel.directory.length,
          'paragraphs': bodies.fold<int>(0, (n, b) => n + b.paragraphs.length),
          'languageCounts': {
            for (final code
                in formats
                    .map((f) => f.language)
                    .where((s) => s.isNotEmpty)
                    .toSet())
              code: formats.where((f) => f.language == code).length,
          },
          'dimParagraphs': formats.where((f) => f.opacity < 1).length,
        }),
      );
    }, skip: path == null);
  }
}
