import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../catalog.dart';
import '../local_books.dart';
import 'book_source.dart';
import 'source_image_locator.dart';
import 'source_platform.dart';

enum EpubLoadStage { preparing, downloading, checking, parsing, ready, failed }

class EpubLoadProgress {
  const EpubLoadProgress(
    this.stage, {
    this.received = 0,
    this.total,
    this.chapters = 0,
  });
  final EpubLoadStage stage;
  final int received, chapters;
  final int? total;
  double? get fraction =>
      stage == EpubLoadStage.downloading && total != null && total! > 0
      ? (received / total!).clamp(0.0, 1.0)
      : stage == EpubLoadStage.ready
      ? 1
      : null;
}

Future<List<Map<String, dynamic>>> parseSourceEpubFile(
  ({
    String path,
    String directory,
    String url,
    int bookId,
    String key,
    SendPort? progress,
  })
  input,
) async {
  input.progress?.send({'stage': 'checking'});
  final parsed = await parseLocalEpubFile(
    input.path,
    id: input.bookId,
    outputDirectory: input.directory,
    imageUrl: (name) => sourceImageLocator(
      input.bookId,
      Uri(scheme: 'source-epub', host: input.key, path: '/$name').toString(),
    )!,
    onArchiveReady: () => input.progress?.send({'stage': 'parsing'}),
    onChapter: (count) =>
        input.progress?.send({'stage': 'parsing', 'chapters': count}),
  );
  return [
    for (var i = 0; i < parsed.novel.chapters.length; i++)
      {
        'name': parsed.novel.chapters[i].title,
        'url': Uri.parse(input.url)
            .replace(fragment: 'epub=${Uri.encodeComponent(parsed.origins[i])}')
            .toString(),
        'bodyFile': 'c${parsed.novel.chapters[i].id}.txt',
      },
  ];
}

class SourceEpubCache {
  SourceEpubCache({this.directory});
  final Directory? directory;
  final _pending = <String, Future<List<Map<String, dynamic>>>>{};
  final _created = <String, DateTime>{};
  final _progress = <int, ValueNotifier<EpubLoadProgress>>{};

  ValueListenable<EpubLoadProgress> progressFor(int id) =>
      _progress.putIfAbsent(
        id,
        () => ValueNotifier(const EpubLoadProgress(EpubLoadStage.preparing)),
      );
  void _report(int id, EpubLoadProgress progress) {
    progressFor(id);
    _progress[id]!.value = progress;
  }

  String _key(BookSource source, Novel book) =>
      sha256.convert(utf8.encode('${source.key}\n${book.bookUrl}')).toString();
  Future<Directory> _root() async =>
      directory ??
      // Preserve the existing on-device cache namespace during migration.
      Directory('${(await getTemporaryDirectory()).path}/novelia-epub-v2');

  Future<List<Map<String, dynamic>>> load(
    BookSource source,
    Novel book,
    SourcePlatform platform,
  ) {
    final key = _key(source, book);
    final created = _created[key];
    if (created != null &&
        DateTime.now().difference(created) >= const Duration(hours: 6)) {
      _pending.remove(key);
      _created.remove(key);
    }
    _created.putIfAbsent(key, DateTime.now);
    return _pending.putIfAbsent(key, () async {
      Directory? staging;
      ReceivePort? receiver;
      try {
        _report(book.id, const EpubLoadProgress(EpubLoadStage.preparing));
        final root = await _root();
        await root.create(recursive: true);
        final folder = Directory('${root.path}/$key');
        final index = File('${folder.path}/index.json');
        if (await index.exists() &&
            DateTime.now().difference(await index.lastModified()) <
                const Duration(hours: 6)) {
          _created[key] = await index.lastModified();
          final value = jsonDecode(await index.readAsString()) as Map;
          final rows = (value['rows'] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          _report(
            book.id,
            EpubLoadProgress(EpubLoadStage.ready, chapters: rows.length),
          );
          return rows;
        }
        staging = await root.createTemp('.$key-');
        final download =
            await platform.run(
                  source,
                  'epub',
                  book: {'bookUrl': book.bookUrl},
                  onDownloadProgress: (received, total) => _report(
                    book.id,
                    EpubLoadProgress(
                      EpubLoadStage.downloading,
                      received: received,
                      total: total,
                    ),
                  ),
                )
                as Map;
        final original = await File(
          download['path'] as String,
        ).rename('${staging.path}/volume.epub');
        receiver = ReceivePort();
        receiver.listen((raw) {
          final data = raw as Map;
          _report(
            book.id,
            EpubLoadProgress(
              data['stage'] == 'checking'
                  ? EpubLoadStage.checking
                  : EpubLoadStage.parsing,
              chapters: data['chapters'] as int? ?? 0,
            ),
          );
        });
        _report(book.id, const EpubLoadProgress(EpubLoadStage.checking));
        final rows = await compute(parseSourceEpubFile, (
          path: original.path,
          directory: staging.path,
          url: book.bookUrl!,
          bookId: book.id,
          key: key,
          progress: receiver.sendPort,
        ));
        receiver.close();
        receiver = null;
        var size = 0;
        await for (final file in staging.list()) {
          if (file is File) size += await file.length();
        }
        await File(
          '${staging.path}/index.json',
        ).writeAsString(jsonEncode({'rows': rows, 'size': size}), flush: true);
        if (await folder.exists()) await folder.delete(recursive: true);
        await staging.rename(folder.path);
        staging = null;
        _created[key] = DateTime.now();
        await _prune(root, key);
        _report(
          book.id,
          EpubLoadProgress(EpubLoadStage.ready, chapters: rows.length),
        );
        return rows;
      } catch (_) {
        _pending.remove(key);
        _created.remove(key);
        _report(book.id, const EpubLoadProgress(EpubLoadStage.failed));
        rethrow;
      } finally {
        receiver?.close();
        if (staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
        while (_pending.length > 2) {
          final oldest = _pending.keys.first;
          _pending.remove(oldest);
          _created.remove(oldest);
        }
      }
    });
  }

  Future<String> content(
    BookSource source,
    Novel book,
    SourcePlatform platform,
    String url,
  ) async {
    final rows = await load(source, book, platform);
    final name =
        rows.singleWhere((row) => row['url'] == url)['bodyFile'] as String;
    final file = File('${(await _root()).path}/${_key(source, book)}/$name');
    if (!await file.exists()) {
      await _invalidate(source, book);
      throw const SourceFailure('卷册缓存已被系统清理，请重试加载');
    }
    return file.readAsString();
  }

  Future<Uint8List> image(BookSource source, Novel book, Uri uri) async {
    if (uri.host != _key(source, book)) throw const SourceFailure('插图不属于当前卷册');
    final file = File('${(await _root()).path}/${uri.host}${uri.path}');
    if (!await file.exists()) {
      await _invalidate(source, book);
      throw const SourceFailure('卷册插图缓存已被系统清理，请重试加载');
    }
    return file.readAsBytes();
  }

  Future<void> _invalidate(BookSource source, Novel book) async {
    final key = _key(source, book);
    _pending.remove(key);
    _created.remove(key);
    final index = File('${(await _root()).path}/$key/index.json');
    if (await index.exists()) await index.delete();
  }

  Future<void> _prune(Directory root, String keep) async {
    final entries = <({Directory folder, int size, DateTime date})>[];
    await for (final entry in root.list()) {
      if (entry is! Directory ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(entry.uri.pathSegments.where((p) => p.isNotEmpty).last)) {
        continue;
      }
      final index = File('${entry.path}/index.json');
      try {
        final value = jsonDecode(await index.readAsString()) as Map;
        entries.add((
          folder: entry,
          size: value['size'] as int,
          date: await index.lastModified(),
        ));
      } on FileSystemException {
        // Android may evict another cached volume while the index is scanned.
        continue;
      }
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    var size = entries.fold<int>(0, (total, entry) => total + entry.size);
    for (final entry in entries) {
      if (size <= 128 * 1024 * 1024) break;
      if (entry.folder.path == '${root.path}/$keep' ||
          _pending.containsKey(
            entry.folder.uri.pathSegments.where((p) => p.isNotEmpty).last,
          )) {
        continue;
      }
      try {
        await entry.folder.delete(recursive: true);
        size -= entry.size;
      } on FileSystemException {
        continue;
      }
    }
  }
}
