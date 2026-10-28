import 'support/source_declaration_fixtures.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_rich_content.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';
import 'package:wenku8_flutter/sources/source_repository.dart';
import 'package:wenku8_flutter/sources/source_store.dart';

Future<Uint8List> _font(String name) =>
    File('android/app/src/test/resources/source-fonts/$name').readAsBytes();

class _PairedFontPlatform extends SourcePlatform {
  _PairedFontPlatform(this.bytes);
  final Uint8List bytes;
  @override
  Future<dynamic> run(
    BookSource source,
    String operation, {
    String? url,
    String key = '',
    int page = 1,
    Map<String, dynamic>? book,
    Map<String, dynamic>? chapter,
    String? requestId,
    bool background = false,
    void Function(int received, int? total)? onDownloadProgress,
  }) async => {
    'text':
        'A\uE001B\n\n<!--image-->https://images.example.test/a.png<!--image-->',
    'font': bytes,
  };
}

class _FontCachePaths extends PathProviderPlatform {
  _FontCachePaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  setUp(registerSourceFixtures);
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fontCache;
  late PathProviderPlatform previousPaths;
  setUpAll(() async {
    fontCache = await Directory.systemTemp.createTemp('decoded-chapter-fonts-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FontCachePaths(fontCache.path);
  });
  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    await fontCache.delete(recursive: true);
  });
  for (final name in [
    'source.ttf',
    'source.woff2',
    'source-hmtx.woff2',
    'source-untransformed.woff2',
  ]) {
    test(
      'paired font survives persisted content and native typography: $name',
      () async {
        final original = ReaderRichBody(
          ['A\uE001B', '繁體內容'],
          sourceFont: base64Encode(await _font(name)),
          revision: 'source-lightnovel-font-v1',
        );
        final restored = ReaderRichBody.decode(original.encode());
        expect(restored.sourceFont, original.sourceFont);
        expect(restored.paragraphs, original.paragraphs);
        final content = await ReaderContent.parse(original.encode());
        expect(content.hasSourceFont, true);
        final digest = sha256.convert(await _font(name));
        final cached = File('${fontCache.path}/chapter-fonts-v1/$digest.ttf');
        expect(await cached.exists(), true);
        expect((await cached.readAsBytes()).take(4), [0, 1, 0, 0]);
        final family = content.sourceFontFamily!;
        final paragraph = content.formats[0]!;
        expect(paragraph.textStyle(const TextStyle()).fontFamily, family);
        expect(paragraph.slice(0, 1).fontFamily, family);
        expect(paragraph.withReferences([]).fontFamily, family);
        expect(paragraph.withBreaks(before: true).fontFamily, family);
        expect(content.layoutKey('fixture'), contains(family));
        expect(content.localized(const Locale('zh', 'CN')), same(content));
        expect(
          await content.localizedAsync(const Locale('zh', 'TW')),
          same(content),
        );
        expect(content.paragraphs, original.paragraphs);
      },
    );
  }

  for (final escaped in [false, true]) {
    testWidgets(
      'cached LightNovelShelf introduction renders plain paragraphs: escaped=$escaped',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final state = await LibraryState.load();
        addTearDown(state.dispose);
        await state.setReduceMotion(true);
        const markup =
            '<div><p>First &amp; second</p><p>Next paragraph</p></div>';
        final novel = Novel.fromSnapshot({
          ...demoNovels.first.toSnapshot(),
          'sourceId': 'https://www.lightnovel.app',
          'summary': escaped ? htmlEscape.convert(markup) : markup,
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: novelTheme(Brightness.light),
            home: DetailPage(
              novel: novel,
              state: state,
              repository: const DemoNovelRepository(),
              fromCache: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('First & second\n\nNext paragraph'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('First & second\n\nNext paragraph'), findsOneWidget);
        expect(find.textContaining('<p>'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test('different chapter fonts never share a registered family', () async {
    Future<ReaderContent> load(String name) async => ReaderContent.parse(
      ReaderRichBody([
        'AB',
      ], sourceFont: base64Encode(await _font(name))).encode(),
    );
    final first = await load('source.ttf');
    final second = await load('source.woff2');
    expect(first.sourceFontFamily, isNot(second.sourceFontFamily));
    expect((await load('source.ttf')).sourceFontFamily, first.sourceFontFamily);
  });

  test(
    'native source content binds the returned font before caching',
    () async {
      final root = await Directory.systemTemp.createTemp('source-font-body-');
      addTearDown(() => root.delete(recursive: true));
      final store = SourceStore(File('${root.path}/index.json'));
      addTearDown(store.dispose);
      final source = BookSource({
        'bookSourceUrl': 'https://www.lightnovel.app',
        'engine': engineFixture('https://www.lightnovel.app'),
        'bookSourceName': 'Shelf',
        'enabled': true,
      });
      await store.saveSources([source]);
      final book = store.remember(source, {
        'name': 'Fixture',
        'bookUrl': '${source.key}/book/8',
      });
      final chapters = await store.rememberChapters(book.id, [
        {'name': 'First', 'url': '${source.key}/read/8/1'},
      ]);
      final bytes = await _font('source.woff2');
      final repository = SourceNovelRepository(
        store: store,
        legacy: const DemoNovelRepository(),
        platform: _PairedFontPlatform(bytes),
      );
      addTearDown(repository.dispose);
      final saved = ReaderRichBody.decode(
        await repository.chapterContent(book.id, chapters.single),
      );
      expect(saved.sourceFont, base64Encode(bytes));
      expect(saved.revision, 'source-embedded-font-v1');
      expect(saved.paragraphs.first, 'A\uE001B');
      expect(saved.paragraphs.last, contains('source-image://${book.id}'));
    },
  );
}
