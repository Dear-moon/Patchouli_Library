import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/local_import_options.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/local_book_media.dart';

Uint8List illustratedEpub({bool namedImages = false, bool imagesOnly = false}) {
  final zip = Archive();
  void text(String path, String content) {
    final bytes = utf8.encode(content);
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final pages = [
    'lead',
    if (!imagesOnly) 'one',
    'middle',
    if (!imagesOnly) 'two',
    'tail',
  ];
  text(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  );
  text(
    'OPS/book.opf',
    '''<package version="2.0"><metadata><title>原书插图顺序</title></metadata><manifest>
<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
${pages.map((p) => '<item id="$p" href="$p.xhtml" media-type="application/xhtml+xml"/>').join()}
</manifest><spine toc="toc">${pages.map((p) => '<itemref idref="$p"/>').join()}</spine></package>''',
  );
  text(
    'OPS/toc.ncx',
    '<ncx><navMap>${pages.where((p) => namedImages || p == 'one' || p == 'two').map((p) => '<navPoint><navLabel><text>${switch (p) {
      'one' => '原书第一章',
      'two' => '原书第二章',
      _ => '原书插图 $p',
    }}</text></navLabel><content src="$p.xhtml"/></navPoint>').join()}</navMap></ncx>',
  );
  for (final page in pages) {
    final isText = page == 'one' || page == 'two';
    text(
      'OPS/$page.xhtml',
      '<html><body>${isText ? '<h1>${page == 'one' ? '原书第一章' : '原书第二章'}</h1><p>$page 完整正文，不应丢失。</p>' : '<p><img src="$page.png"/></p>'}</body></html>',
    );
    if (!isText) {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      zip.addFile(ArchiveFile('OPS/$page.png', png.length, png));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  for (final inline in [false, true]) {
    test(
      'removing and reimporting keeps EPUB directory, inline=$inline',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'epub-reimport-layout-',
        );
        addTearDown(() => root.delete(recursive: true));
        final original = LocalBookInput('原书.epub', illustratedEpub());
        final store = LocalBookStore(root);
        addTearDown(store.dispose);
        await store.load();
        final book = await store.import(
          original,
          requireMatchingOptions: !inline,
        );
        final before = await store.chapterContent(book.id, book.chapters[1]);
        await store.remove(book.id);
        final restarted = LocalBookStore(root);
        addTearDown(restarted.dispose);
        await restarted.load();
        final reimported = await restarted.import(original);
        expect(
          reimported.chapters.map((c) => c.title),
          book.chapters.map((c) => c.title),
        );
        expect(
          await restarted.chapterContent(book.id, reimported.chapters[1]),
          before,
        );
        expect(restarted.importOptionsFor(book.id).inlineEpubImages, inline);
      },
    );
    test('record-only EPUB layout survives restart, inline=$inline', () async {
      final root = await Directory.systemTemp.createTemp(
        'epub-pending-layout-',
      );
      addTearDown(() => root.delete(recursive: true));
      final original = LocalBookInput('原书.epub', illustratedEpub());
      final id = parseLocalBook(original).novel.id;
      final store = LocalBookStore(root);
      addTearDown(store.dispose);
      await store.load();
      await store.rememberEpubLayouts({id: inline});
      final restarted = LocalBookStore(root);
      addTearDown(restarted.dispose);
      await restarted.load();
      await expectLater(
        restarted.rememberEpubLayouts({id: !inline}),
        throwsFormatException,
      );
      final book = await restarted.import(original);
      expect(book.chapters, hasLength(inline ? 2 : 5));
      expect(restarted.importOptionsFor(id).inlineEpubImages, inline);
    });
  }
  test(
    'sync keeps the source directory version instead of moving old bookmarks',
    () async {
      final root = await Directory.systemTemp.createTemp('epub-sync-layout-');
      addTearDown(() => root.delete(recursive: true));
      final original = LocalBookInput('原书.epub', illustratedEpub());
      Future<LocalBookStore> store(String name) async {
        final value = LocalBookStore(Directory('${root.path}/$name'));
        addTearDown(value.dispose);
        await value.load();
        return value;
      }

      final old = await store('old');
      final oldBook = await old.import(original, requireMatchingOptions: true);
      expect(oldBook.chapters, hasLength(5));
      expect(old.importOptionsFor(oldBook.id).isDefault, true);
      final next = await store('new');
      final nextBook = await next.import(original);
      expect(nextBook.chapters, hasLength(2));
      final saved = next.importOptionsFor(nextBook.id).toJson();
      expect(saved['version'], 2);
      final restored = LocalImportOptions.fromJson(saved);
      expect(restored.inlineEpubImages, true);
      final target = await store('target');
      final copied = await target.import(
        original,
        requireMatchingOptions: true,
        optionsById: {nextBook.id: restored},
      );
      expect(
        copied.chapters.map((c) => c.title),
        nextBook.chapters.map((c) => c.title),
      );
      expect(
        await target.chapterContent(copied.id, copied.chapters.first),
        await next.chapterContent(nextBook.id, nextBook.chapters.first),
      );
      await expectLater(
        next.import(original, requireMatchingOptions: true),
        throwsFormatException,
      );
      expect(next.book(nextBook.id)!.chapters, hasLength(2));
      expect(old.book(oldBook.id)!.chapters, hasLength(5));
    },
  );
  test(
    'existing image-sizing upgrades keep their old chapter IDs and boundaries',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'epub-old-boundaries-',
      );
      addTearDown(() => root.delete(recursive: true));
      final original = illustratedEpub();
      final parsed = parseLocalBook(LocalBookInput('旧书.epub', original));
      final id = parsed.novel.id;
      final directory = await Directory(
        '${root.path}/$id',
      ).create(recursive: true);
      await File('${directory.path}/original').writeAsBytes(original);
      final chapters = [
        for (var i = 1; i <= 5; i++) NovelChapter('旧目录 $i', '', id: i),
      ];
      final bodies = [
        '<!--image-->wenku-local://$id/img-0.png<!--image-->',
        'one 完整正文，不应丢失。',
        '<!--image-->wenku-local://$id/img-1.png<!--image-->',
        'two 完整正文，不应丢失。',
        '<!--image-->wenku-local://$id/img-2.png<!--image-->',
      ];
      for (var i = 0; i < bodies.length; i++) {
        await File('${directory.path}/c${i + 1}.txt').writeAsString(bodies[i]);
      }
      await File('${directory.path}/book.json').writeAsString(
        jsonEncode({
          'version': 1,
          'novel': parsed.novel.withChapters(chapters).toSnapshot(),
          'source': {'name': '旧书.epub', 'digest': parsed.digest, 'parser': 2},
          'chapters': [
            for (final c in chapters) {'id': c.id, 'title': c.title},
          ],
        }),
      );
      final store = LocalBookStore(root);
      addTearDown(store.dispose);
      await store.load();
      final first = await store.chapterContent(
        id,
        store.book(id)!.chapters.first,
      );
      expect(first, contains('wenku-local://$id/img-0.png'));
      expect(store.book(id)!.chapters.map((c) => c.id), [1, 2, 3, 4, 5]);
      expect(
        await store.chapterContent(id, store.book(id)!.chapters[1]),
        bodies[1],
      );
      final saved = jsonDecode(
        await File('${directory.path}/book.json').readAsString(),
      );
      expect(
        saved['source']['imageSizing'],
        1,
        reason:
            'The sizing-only migration must succeed without rebuilding the directory.',
      );
    },
  );
  test(
    'unlisted image-only spine pages remain inline without invented chapters',
    () {
      final parsed = parseLocalBook(
        LocalBookInput('原书.epub', illustratedEpub()),
      );
      expect(parsed.novel.chapters.map((c) => c.title), ['原书第一章', '原书第二章']);
      expect(parsed.bodies.first, startsWith('<!--image-->'));
      expect(parsed.bodies.first, contains('one 完整正文，不应丢失。'));
      expect(parsed.bodies.last, contains('two 完整正文，不应丢失。'));
      final body = parsed.bodies.join('\n\n');
      expect(
        RegExp(r'<!--image-->wenku-local:').allMatches(body),
        hasLength(3),
      );
      expect(body.indexOf('/img-0.png'), lessThan(body.indexOf('one 完整正文')));
      expect(body.indexOf('/img-1.png'), greaterThan(body.indexOf('one 完整正文')));
      expect(body.indexOf('/img-1.png'), lessThan(body.indexOf('two 完整正文')));
      expect(body.indexOf('/img-2.png'), greaterThan(body.indexOf('two 完整正文')));
      expect(parsed.images, hasLength(3));
    },
  );
  test(
    'illustration chapters explicitly listed by the original remain separate',
    () {
      final parsed = parseLocalBook(
        LocalBookInput('原书.epub', illustratedEpub(namedImages: true)),
      );
      expect(parsed.novel.chapters, hasLength(5));
      expect(parsed.novel.chapters[2].title, '原书插图 middle');
      expect(parsed.bodies[2], contains('<!--image-->'));
    },
  );
  test(
    'an all-illustration book stays readable without numbered fake chapters',
    () {
      final parsed = parseLocalBook(
        LocalBookInput('原书.epub', illustratedEpub(imagesOnly: true)),
      );
      expect(parsed.novel.chapters.single.title, '插图');
      expect(
        RegExp(r'<!--image-->wenku-local:').allMatches(parsed.bodies.single),
        hasLength(3),
      );
    },
  );
  test(
    'file-backed import and restart preserve the same text and image ordering',
    () async {
      final root = await Directory.systemTemp.createTemp('epub-inline-pages-');
      addTearDown(() => root.delete(recursive: true));
      final original = illustratedEpub();
      final file = await File('${root.path}/原书.epub').writeAsBytes(original);
      final store = LocalBookStore(Directory('${root.path}/library'));
      addTearDown(store.dispose);
      await store.load();
      final book = await store.importFile('原书.epub', file.path);
      final first = await store.chapterContent(book.id, book.chapters.first);
      expect(book.chapters, hasLength(2));
      final restarted = LocalBookStore(store.directory);
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(restarted.book(book.id)!.chapters, hasLength(2));
      expect(
        await restarted.chapterContent(book.id, book.chapters.first),
        first,
      );
      expect(
        await File('${root.path}/library/${book.id}/media.json').exists(),
        true,
      );
      expect(
        await File('${root.path}/library/${book.id}/img-2.png').exists(),
        false,
      );
      final before = LocalBookMedia.root;
      LocalBookMedia.root = store.directory;
      try {
        expect(
          await LocalBookMedia.load('wenku-local://${book.id}/img-2.png'),
          isNotEmpty,
        );
      } finally {
        LocalBookMedia.root = before;
      }
      expect(await file.readAsBytes(), original);
    },
  );
}
