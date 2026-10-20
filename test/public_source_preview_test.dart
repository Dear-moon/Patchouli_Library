import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/legacy_cover.dart';
import 'package:wenku8_flutter/legacy_transport.dart';
import 'package:wenku8_flutter/legacy_wenku_repository.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';
import 'package:wenku8_flutter/online_component.dart';
import 'package:wenku8_flutter/wenku_account.dart';
import 'package:wenku8_flutter/wenku_reviews.dart';

import 'local_books_test.dart' show epubFixture;
import 'support/offline_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const remote = LegacyWenkuRepository();
  final unavailable = isA<OnlineComponentUnavailable>();

  test(
    'source preview fails online requests explicitly, without demo results',
    () async {
      final book = offlineFixtureBook(71);
      for (final request in <Future<Object?> Function()>[
        remote.list,
        () => remote.search('sample'),
        () => remote.find(book.id),
        () => remote.detail(book),
        () => remote.chapters(book.id),
        () => remote.chapterContent(book.id, book.chapters.first),
        () => remote.publicationLibraries(),
        () => remote.browsePublication(1),
        () => remote.tagPage('sample'),
        () => LegacyCover.bytes(71),
        () => LegacyTransport.illustration('https://example.test/image.png'),
      ]) {
        await expectLater(request(), throwsA(unavailable));
      }
    },
  );

  test(
    'account facade never pretends to authenticate or persist a session',
    () async {
      final account = WenkuAccount();
      addTearDown(account.dispose);
      await account.initialize();
      for (final action in <Future<Object?> Function()>[
        () => account.login('fixture-user', 'fixture-password'),
        account.refreshProfile,
        account.signIn,
        account.refreshCloud,
        () => account.addCloud(71),
        () => account.removeCloud(71),
        () => account.recommend(71),
        () => account.postReview(
          bookId: 71,
          title: 'fixture',
          content: 'fixture',
        ),
      ]) {
        await expectLater(action(), throwsA(unavailable));
        expect(account.authenticated, isFalse);
        expect(account.profile, isNull);
        expect(account.error, OnlineComponentUnavailable.message);
      }
      final reviews = WenkuReviewFeed(id: 71);
      addTearDown(reviews.dispose);
      await reviews.load();
      expect(reviews.loading, isFalse);
      expect(reviews.items, isEmpty);
      expect(reviews.error, OnlineComponentUnavailable.message);
    },
  );

  test('existing cached chapters and local TXT/EPUB remain readable', () async {
    final root = await Directory.systemTemp.createTemp('source-preview-');
    addTearDown(() => root.delete(recursive: true));
    final cache = OfflineCacheStore(Directory('${root.path}/cache'));
    final local = LocalBookStore(Directory('${root.path}/books'));
    await local.load();
    await cache.load();
    final repository = OfflineNovelRepository(
      remote: remote,
      cache: cache,
      local: local,
    );
    addTearDown(() {
      repository.dispose();
      local.dispose();
      cache.dispose();
    });
    final book = offlineFixtureBook(71);
    final epoch = cache.epochFor(book.id);
    await cache.saveBook(book, epoch: epoch);
    await cache.saveChapter(
      book.id,
      book.chapters.first.id,
      '已缓存的正文。',
      epoch: epoch,
    );
    expect(
      await repository.chapterContent(book.id, book.chapters.first),
      '已缓存的正文。',
    );

    const text = '第一章\n本地 TXT 正文。';
    final txt = await local.import(
      LocalBookInput(
        'sample.txt',
        Uint8List.fromList(utf8.encode(text)),
        text: text,
      ),
    );
    final epub = await local.import(
      LocalBookInput('sample.epub', epubFixture()),
    );
    for (final original in [txt, epub]) {
      final resolved = await repository.find(original.id);
      expect(resolved!.id, original.id);
      expect(await repository.chapters(original.id), isNotEmpty);
      expect(
        await repository.chapterContent(original.id, original.chapters.first),
        isNotEmpty,
      );
    }
  });
}
