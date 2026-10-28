import 'package:wenku8_flutter/sources/source_declarations.dart';
import 'package:flutter/material.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/sources/source_discovery_filters.dart';
import 'package:wenku8_flutter/sources/source_epub_progress.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/local_image_layout.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/sources/source_image_locator.dart';
import 'package:wenku8_flutter/sources/book_source.dart';
import 'package:wenku8_flutter/sources/source_epub.dart';
import 'package:wenku8_flutter/sources/source_platform.dart';

Uint8List fixture() {
  final zip = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  );
  add(
    'OPS/book.opf',
    '<package version="2.0"><metadata><title>Fixture</title></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>',
  );
  add(
    'OPS/one.xhtml',
    '<html><body><h1>First</h1><p>First body with <ruby>字<rt>じ</rt></ruby>.</p><p><img src="image.png" width="1362" height="1920"/></p></body></html>',
  );
  add(
    'OPS/two.xhtml',
    '<html><body><h1>Second</h1><p>Second body.</p></body></html>',
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  zip.addFile(ArchiveFile('OPS/image.png', png.length, png));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url =
      'https://books.example/wenku/0123456789abcdef01234567?volume=Volume%201.epub';
  final source = BookSource({
    'bookSourceName': 'Novelia',
    'bookSourceUrl': 'https://books.example#sakura',
  });
  final book = Novel(
    id: 0x40000001,
    title: 'Volume',
    author: 'Author',
    genre: '',
    summary: '',
    colors: const [],
    chapters: const [],
    sourceId: source.key,
    bookUrl: url,
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SourcePlatform.channel, null),
  );
  test(
    'EPUB streams chapters and illustrations without embedding image bytes',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'novelia-file-parser-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final original = await File(
        '${folder.path}/volume.epub',
      ).writeAsBytes(fixture());
      final key = sha256.convert(utf8.encode('${source.key}\n$url')).toString();
      final input = (
        path: original.path,
        directory: folder.path,
        url: url,
        bookId: book.id,
        key: key,
        progress: null,
      );
      final parsed = await parseSourceEpubFile(input);
      expect(parsed.map((row) => row['name']), ['First', 'Second']);
      expect(parsed.every((row) => !row.containsKey('body')), true);
      final body = await File(
        '${folder.path}/${parsed.first['bodyFile']}',
      ).readAsString();
      expect(body, contains('source-image:'));
      expect(body, contains('reader-rich-v1:'));
      expect(body, isNot(contains('data:image')));
      expect(body, isNot(contains('wenku-local:')));
      final content = await ReaderContent.parse(body);
      expect(content.illustrations, hasLength(1));
      final image = content.paragraphs.singleWhere(
        (paragraph) => paragraph.startsWith('<!--image-->'),
      );
      expect(readerIllustrationUrl(image), content.illustrations.single);
      expect(LocalImageLayout.fromParagraph(image).width, '1362');
      expect(LocalImageLayout.fromParagraph(image).height, '1920');
      expect(parsed.first['url'], contains('volume=Volume%201.epub#epub='));
      expect(
        (await parseSourceEpubFile(input)).map((row) => row['url']),
        parsed.map((row) => row['url']),
      );
      expect(
        folder.listSync().where((file) => file.path.endsWith('.png')),
        isNotEmpty,
      );
    },
  );
  test(
    'cached EPUB dimensions are recognized without accepting trailing text',
    () {
      final key = 'a' * 64;
      final locator = sourceImageLocator(
        book.id,
        'source-epub://$key/cover.jpeg',
      )!;
      final marker = '<!--image-->$locator<!--image-->';
      expect(
        readerIllustrationUrl('$marker<!--epub-image:w=1362;h=1920-->'),
        locator,
      );
      expect(readerIllustrationUrl('${marker}prose'), isNull);
      expect(
        readerIllustrationUrl('$marker<!--epub-image:w=javascript:bad-->'),
        isNull,
      );
      expect(
        readerIllustrationUrl(
          '<!--image-->${sourceImageLocator(book.id, 'https://images.example.test/cover.jpeg')}<!--image--><!--epub-image:w=1362;h=1920-->',
        ),
        isNull,
      );
    },
  );
  testWidgets(
    'declared filters preserve the server query and grading selection',
    (tester) async {
      SourceExplore? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showJellySheet<SourceExplore>(
                    context: context,
                    builder: (_) => const SourceDiscoveryFilters(
                      current: 'catalog?query=old&level=1',
                      config: {
                        'path': 'catalog',
                        'title': 'Fixture filters',
                        'queryKey': 'query',
                        'choices': [
                          {
                            'key': 'level',
                            'label': 'Level',
                            'options': {
                              '0': 'All',
                              '1': 'Grade one',
                              '2': 'Grade two',
                            },
                          },
                        ],
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'Author & Title');
      await tester.tap(find.text('Grade two'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(Uri.parse(result!.url).queryParameters, {
        'query': 'Author & Title',
        'level': '2',
      });
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'volume detection distinguishes a series, a selected volume and web novels',
    () {
      SourceDeclarations.register([
        BookSource({
          ...source.data,
          'engine': {
            'version': 1,
            'content': {
              'epubPattern': r'\?volume=',
              'seriesPattern': r'/catalog/[^?]+$',
            },
          },
        }),
      ]);
      expect(SourceDeclarations.isEpub(book), true);
      expect(SourceDeclarations.isSeries(book), false);
    },
  );
  testWidgets('EPUB loading shows download percentage and parsing progress', (
    tester,
  ) async {
    final progress = ValueNotifier(
      const EpubLoadProgress(
        EpubLoadStage.downloading,
        received: 1024 * 1024,
        total: 4 * 1024 * 1024,
      ),
    );
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourceEpubProgressPanel(progress: progress)),
      ),
    );
    expect(find.text('正在下载 EPUB'), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
    progress.value = const EpubLoadProgress(EpubLoadStage.parsing, chapters: 4);
    await tester.pump();
    expect(find.text('已处理 4 章'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    progress.value = const EpubLoadProgress(EpubLoadStage.ready, chapters: 8);
    await tester.pump();
    expect(find.text('共 8 章'), findsOneWidget);
  });
  test(
    'concurrent readers and a restarted cache reuse one downloaded volume',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'novelia-epub-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SourcePlatform.channel, (call) async {
            expect(call.method, 'run');
            expect((call.arguments as Map)['operation'], 'epub');
            calls++;
            final args = call.arguments as Map;
            final bytes = fixture();
            SourcePlatform.reportDownloadProgress({
              'id': args['requestId'],
              'received': 0,
              'total': bytes.length,
            });
            final file = await File(
              '${folder.path}/download-$calls.epub',
            ).writeAsBytes(bytes);
            SourcePlatform.reportDownloadProgress({
              'id': args['requestId'],
              'received': bytes.length,
              'total': bytes.length,
            });
            return {'path': file.path};
          });
      final cache = SourceEpubCache(directory: folder);
      final result = await Future.wait([
        cache.load(source, book, SourcePlatform()),
        cache.load(source, book, SourcePlatform()),
      ]);
      expect(calls, 1);
      expect(result.first.length, 2);
      expect(result.first.every((row) => !row.containsKey('body')), true);
      expect(
        await cache.content(
          source,
          book,
          SourcePlatform(),
          result.first.first['url'] as String,
        ),
        contains('First body'),
      );
      expect(cache.progressFor(book.id).value.stage, EpubLoadStage.ready);
      final metadataSize = utf8.encode(jsonEncode(result.first)).length;
      expect(metadataSize, lessThan(2000));
      await SourceEpubCache(
        directory: folder,
      ).load(source, book, SourcePlatform());
      expect(calls, 1);
      final other = BookSource({
        ...source.data,
        'bookSourceUrl': 'https://books.example#jp',
      });
      await SourceEpubCache(
        directory: folder,
      ).load(other, book, SourcePlatform());
      expect(calls, 2);
      final key = sha256.convert(utf8.encode('${source.key}\n$url')).toString();
      await File(
        '${folder.path}/$key/${result.first.first['bodyFile']}',
      ).delete();
      await expectLater(
        cache.content(
          source,
          book,
          SourcePlatform(),
          result.first.first['url'] as String,
        ),
        throwsA(isA<SourceFailure>()),
      );
      await cache.load(source, book, SourcePlatform());
      expect(calls, 3);
    },
  );
}
