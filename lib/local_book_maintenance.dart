part of 'local_books.dart';

enum LocalMaintenanceTask { layout, covers, storage }

ReaderRichBody _decodeCoordinateBody(String text) =>
    ReaderRichBody.decode(text);

class LocalMaintenanceResult {
  const LocalMaintenanceResult(
    this.message, {
    this.changed = false,
    this.freedBytes = 0,
  });
  final String message;
  final bool changed;
  final int freedBytes;
}

Future<void> _maintenanceRecord(File target, Object record) async {
  final next = File('${target.path}.maintenance-next');
  try {
    await next.writeAsString(jsonEncode(record), flush: true);
    await next.rename(target.path);
  } finally {
    if (await next.exists()) await next.delete();
  }
}

String _sizingIndependent(String body) => ReaderRichBody.decode(body).paragraphs
    .map((p) {
      final image = readerIllustrationUrl(p);
      return image == null ? p : '<!--image-->$image<!--image-->';
    })
    .join('\n\n');

/// All work is file-backed on a worker isolate. One metadata rename commits the
/// new body generation; until then the complete old generation stays readable.
Future<Map<String, dynamic>> _upgradeStoredEpub(
  ({String root, int id, LocalImportOptions options}) job,
) async {
  final folder = Directory('${job.root}/${job.id}');
  final metadata = File('${folder.path}/book.json');
  final record =
      jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
  final source = Map<String, dynamic>.from(record['source']);
  if (source['richText'] == 2) return source;
  final oldPrefix =
      {'layout-rich-v1', 'layout-rich-v2'}.contains(source['layoutFolder'])
      ? '${source['layoutFolder']}/'
      : '';
  final staging = Directory('${folder.path}/.layout-rich-next');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create();
  final stream = InputFileStream('${folder.path}/original');
  try {
    final archive = readLocalBookArchive(stream, maxSize: 1024 * 1024 * 1024);
    final names = <String, String>{};
    final old = _epub(
      LocalBookInput(source['name'], Uint8List(0)),
      job.id,
      source['digest'],
      archive: archive,
      preserveRichText: source['richText'] == 1,
      richLayoutLevel: 1,
      autoTitles: job.options.autoTitles,
      mergeUnlistedIllustrations: job.options.inlineEpubImages,
      saveBody: (i, body) =>
          File('${staging.path}/old-$i.txt').writeAsStringSync(body),
      appendBody: (i, body) => File(
        '${staging.path}/old-$i.txt',
      ).writeAsStringSync(body, mode: FileMode.append),
      saveImage: (name, file) => names[file.name] = name,
    );
    final chapters = record['chapters'] as List;
    if (old.novel.chapters.length != chapters.length ||
        old.origins.toSet().length != old.origins.length) {
      throw const FormatException('旧目录与原书不一致，已保留原书和阅读记录');
    }
    for (var i = 0; i < chapters.length; i++) {
      final before = await File(
        '${folder.path}/${oldPrefix}c${chapters[i]['id']}.txt',
      ).readAsString();
      final restored = await File(
        '${staging.path}/old-${i + 1}.txt',
      ).readAsString();
      if (_sizingIndependent(before) != _sizingIndependent(restored)) {
        throw const FormatException('旧正文与原书不一致，未改写正文或阅读记录');
      }
    }
    final rich = _epub(
      LocalBookInput(source['name'], Uint8List(0)),
      job.id,
      source['digest'],
      archive: archive,
      autoTitles: job.options.autoTitles,
      mergeUnlistedIllustrations: job.options.inlineEpubImages,
      imageNames: names,
      saveBody: (i, body) =>
          File('${staging.path}/new-$i.txt').writeAsStringSync(body),
      appendBody: (i, body) => File(
        '${staging.path}/new-$i.txt',
      ).writeAsStringSync(body, mode: FileMode.append),
      saveImage: (name, file) => names.putIfAbsent(file.name, () => name),
    );
    final targets = {
      for (final (i, origin) in rich.origins.indexed) origin: i + 1,
    };
    for (var i = 0; i < chapters.length; i++) {
      final before = ReaderRichBody.decode(
        await File(
          '${folder.path}/${oldPrefix}c${chapters[i]['id']}.txt',
        ).readAsString(),
      );
      final index = targets[old.origins[i]];
      // A standalone notes-only section remains in its old directory slot.
      // No chapter ID or series reference is removed by an enrichment.
      final next = index == null
          ? before
          : ReaderRichBody.decode(
              await File('${staging.path}/new-$index.txt').readAsString(),
            );
      final body = ReaderRichBody(
        next.paragraphs,
        formats: next.formats,
        notes: next.notes,
        revision: 'epub-rich-v2',
        coordinateMap: ReaderCoordinateMap.between(
          before.paragraphs,
          next.paragraphs,
          sourceRevision: before.revision,
          previous: before.coordinateMap,
        ),
      ).encode();
      ReaderRichBody.decode(
        body,
      ); // Validate the exact persisted map, not a second parser result.
      await File(
        '${staging.path}/c${chapters[i]['id']}.txt',
      ).writeAsString(body, flush: true);
    }
    await for (final file in staging.list()) {
      if (file is File &&
          RegExp(
            r'^(old|new)-[0-9]+\.txt$',
          ).hasMatch(file.uri.pathSegments.last)) {
        await file.delete();
      }
    }
    final mediaFile = File('${folder.path}/media.json');
    final entries = <String, dynamic>{};
    if (await mediaFile.exists()) {
      final media = jsonDecode(await mediaFile.readAsString());
      if (media is! Map || media['version'] != 1 || media['entries'] is! Map) {
        throw const FormatException('旧插图索引需要修复，已保留原书');
      }
      entries.addAll(Map<String, dynamic>.from(media['entries']));
    }
    for (final entry in names.entries) {
      if (entries[entry.value] != null && entries[entry.value] != entry.key) {
        throw const FormatException('旧插图索引与原书不一致，未改写');
      }
      entries[entry.value] = entry.key;
    }
    await _maintenanceRecord(mediaFile, {'version': 1, 'entries': entries});
    final target = Directory('${folder.path}/layout-rich-v2');
    if (await target.exists()) await target.delete(recursive: true);
    await staging.rename(target.path);
    final changed = {
      ...source,
      'richText': 2,
      'layoutFolder': 'layout-rich-v2',
      'publisherSpacing': 1,
      'publisherLanguages': 1,
      'imageSizing': 1,
    };
    await _maintenanceRecord(metadata, {...record, 'source': changed});
    return changed;
  } finally {
    stream.closeSync();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

Future<String?> _rebuildStoredCover(
  ({String root, int id, LocalDocumentInput original}) job,
) async {
  final folder = Directory('${job.root}/${job.id}');
  final metadata = File('${folder.path}/book.json');
  final record =
      jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
  final source = record['source'] as Map;
  final buffer = job.original.open();
  try {
    final parsed = _epub(
      LocalBookInput(source['name'], Uint8List(0)),
      job.id,
      source['digest'],
      archive: readLocalBookArchive(buffer.stream, maxSize: 1024 * 1024 * 1024),
      coverOnly: true,
    );
    if (parsed.novel.coverUrl == null || parsed.images.isEmpty) return null;
    final image = parsed.images.entries.first;
    final target = File('${folder.path}/${image.key}');
    final next = File('${target.path}.maintenance-next');
    try {
      await next.writeAsBytes(image.value, flush: true);
      await next.rename(target.path);
    } finally {
      if (await next.exists()) await next.delete();
    }
    await _maintenanceRecord(metadata, {
      ...record,
      'novel': {...record['novel'] as Map, 'coverUrl': parsed.novel.coverUrl},
    });
    return parsed.novel.coverUrl;
  } finally {
    buffer.close();
  }
}

Future<int> _compactStoredEpub(
  ({String root, int id, LocalImportOptions options}) job,
) async {
  final folder = Directory('${job.root}/${job.id}');
  final metadata =
      jsonDecode(await File('${folder.path}/book.json').readAsString())
          as Map<String, dynamic>;
  final source = metadata['source'] as Map;
  final stream = InputFileStream('${folder.path}/original');
  var freed = 0;
  try {
    final archive = readLocalBookArchive(stream, maxSize: 1024 * 1024 * 1024);
    final entries = <String, String>{};
    final index = File('${folder.path}/media.json');
    if (await index.exists()) {
      final value = jsonDecode(await index.readAsString());
      if (value is! Map || value['version'] != 1 || value['entries'] is! Map) {
        throw const FormatException('插图索引有误，未清理原书资源');
      }
      entries.addAll(Map<String, String>.from(value['entries']));
    } else {
      _epub(
        LocalBookInput(source['name'], Uint8List(0)),
        job.id,
        source['digest'],
        archive: archive,
        autoTitles: job.options.autoTitles,
        preserveRichText: (source['richText'] as int? ?? 0) >= 1,
        richLayoutLevel: source['richText'] as int? ?? 1,
        mergeUnlistedIllustrations: job.options.inlineEpubImages,
        saveBody: (_, _) {},
        appendBody: (_, _) {},
        saveImage: (name, file) => entries[name] = file.name,
      );
      await _maintenanceRecord(index, {'version': 1, 'entries': entries});
    }
    // Only exact, recoverable duplicate images are removed. Covers retain their
    // fast local path; damaged originals or unmatched files remain untouched.
    for (final entry in entries.entries) {
      if (!RegExp(
        r'^img-[0-9]+\.(png|jpg|jpeg|webp|gif)$',
      ).hasMatch(entry.key)) {
        continue;
      }
      final file = File('${folder.path}/${entry.key}'),
          original = archive.findFile(entry.value);
      if (!await file.exists() ||
          original == null ||
          !original.isFile ||
          original.size > 8 * 1024 * 1024 ||
          await file.length() != original.size) {
        continue;
      }
      if (!listEquals(await file.readAsBytes(), original.readBytes())) continue;
      final length = await file.length();
      await file.delete();
      freed += length;
    }
    if ({'layout-rich-v1', 'layout-rich-v2'}.contains(source['layoutFolder'])) {
      final chapters = metadata['chapters'] as List;
      for (final chapter in chapters) {
        final active = File(
          '${folder.path}/${source['layoutFolder']}/c${chapter['id']}.txt',
        );
        if (!await active.exists()) {
          throw const FormatException('升级正文不完整，旧正文已保留');
        }
        final body = ReaderRichBody.decode(await active.readAsString());
        if (body.coordinateMap == null || body.paragraphs.isEmpty) {
          throw const FormatException('定位数据不完整，旧正文已保留');
        }
      }
      for (final chapter in chapters) {
        final obsolete = File('${folder.path}/c${chapter['id']}.txt');
        if (await obsolete.exists()) {
          final size = await obsolete.length();
          await obsolete.delete();
          freed += size;
        }
      }
      if (source['layoutFolder'] == 'layout-rich-v2') {
        // The previous rich generation is also recoverable after all active
        // chapters and chained coordinate maps have been validated.
        final previous = Directory('${folder.path}/layout-rich-v1');
        if (await previous.exists()) {
          for (final chapter in chapters) {
            final file = File('${previous.path}/c${chapter['id']}.txt');
            if (await file.exists()) {
              final size = await file.length();
              await file.delete();
              freed += size;
            }
          }
          if (await previous.list().isEmpty) await previous.delete();
        }
      }
    }
    return freed;
  } finally {
    stream.closeSync();
  }
}

extension LocalBookMaintenance on LocalBookStore {
  bool canResolveCoordinates(int id, Map<String, dynamic> position) {
    if (position['contentRevision'] == 'epub-rich-v2') return false;
    final book = this.book(id);
    if (book == null || book.chapters.isEmpty) return false;
    final chapter = position['chapterId'] is int && position['chapterId'] > 0
        ? book.chapters.where((c) => c.id == position['chapterId']).firstOrNull
        : book.chapters.elementAtOrNull(position['chapter'] as int? ?? 0);
    if (chapter == null) return false;
    final base = _seriesChapters[id]?[chapter.id]?.bookId ?? id;
    return _sources[base]?['richText'] == 2;
  }

  Future<Map<String, dynamic>> resolveReadingCoordinates(
    int id,
    Map<String, dynamic> position, {
    Map<int, Future<ReaderRichBody>>? chapterCache,
  }) async {
    if (!canResolveCoordinates(id, position)) return position;
    final novel = book(id);
    if (novel == null || novel.chapters.isEmpty) return position;
    final chapter = position['chapterId'] is int && position['chapterId'] > 0
        ? novel.chapters.where((c) => c.id == position['chapterId']).firstOrNull
        : novel.chapters.elementAtOrNull(position['chapter'] as int? ?? 0);
    if (chapter == null) return position;
    Future<ReaderRichBody> read() async {
      final text = await chapterContent(id, chapter);
      return text.length > 64 * 1024
          ? compute(_decodeCoordinateBody, text)
          : ReaderRichBody.decode(text);
    }

    final pending = chapterCache?.remove(chapter.id) ?? read();
    if (chapterCache != null) {
      chapterCache[chapter.id] = pending;
      if (chapterCache.length > 2) chapterCache.remove(chapterCache.keys.first);
    }
    final body = await pending;
    if (body.revision.isEmpty) return position;
    final coordinates = body.coordinateMap;
    if (coordinates == null) {
      return {...position, 'contentRevision': body.revision};
    }
    if (!coordinates.accepts(position['contentRevision'] as String? ?? '')) {
      return position;
    }
    final target = coordinates.resolve(
      paragraphs: body.paragraphs,
      paragraph: position['paragraphIndex'] as int?,
      offset: position['textOffset'] as int?,
      paragraphFraction: (position['paragraphFraction'] as num? ?? 0)
          .toDouble(),
      fraction: (position['fraction'] as num? ?? 0).toDouble(),
      revision: position['contentRevision'] as String? ?? '',
    );
    return {
      ...position,
      'contentRevision': body.revision,
      'paragraphIndex': target.paragraph,
      'textOffset': target.offset,
      'paragraphFraction': target.fraction,
      'offset': 0,
      'width': 0,
      'layout': '',
    };
  }

  Set<int> maintenanceOriginals(Iterable<int> ids) => {
    for (final id in ids)
      if (_books.containsKey(id))
        id
      else
        ...?_series[id]?.volumes.map((v) => v.bookId),
  };

  Future<LocalMaintenanceResult> maintain(
    int id,
    LocalMaintenanceTask task,
  ) async {
    late LocalMaintenanceResult result;
    final work = _writes.catchError((Object _) {}).then((_) async {
      final source = _sources[id], before = _books[id];
      if (source == null || before == null) {
        throw const FormatException('本地原书不存在');
      }
      if (isLinkedBook(id) && task == LocalMaintenanceTask.storage) {
        result = const LocalMaintenanceResult('已关联原文件，无重复原书需要清理；必要的排版缓存保留');
        return;
      }
      if ((source['name'] as String).toLowerCase().endsWith('.txt') &&
          task == LocalMaintenanceTask.storage) {
        final bytes = await compute(_compactStoredText, (
          root: directory.path,
          id: id,
        ));
        result = LocalMaintenanceResult(
          bytes > 0 ? '已压缩阅读副本，原书与阅读记录保留' : '无需清理',
          changed: bytes > 0,
          freedBytes: bytes,
        );
        return;
      }
      if (!(source['name'] as String).toLowerCase().endsWith('.epub')) {
        result = const LocalMaintenanceResult('此项用于 EPUB，原书保留');
        return;
      }
      switch (task) {
        case LocalMaintenanceTask.layout:
          if (source['richText'] == 2) {
            result = const LocalMaintenanceResult('已使用新版排版');
            break;
          }
          final next = await compute(_upgradeStoredEpub, (
            root: directory.path,
            id: id,
            options: importOptionsFor(id),
          ));
          _sources[id] = next;
          result = const LocalMaintenanceResult(
            '排版已升级，目录与旧定位保留',
            changed: true,
          );
        case LocalMaintenanceTask.covers:
          final cover = await _withOriginalInput(
            id,
            (path) => compute(_rebuildStoredCover, (
              root: directory.path,
              id: id,
              original: path,
            )),
          );
          if (cover == null) {
            result = const LocalMaintenanceResult('原书未提供封面');
            break;
          }
          _books[id] = Novel.fromSnapshot({
            ...before.toSnapshot(),
            'coverUrl': cover,
          }).withChapters(before.chapters);
          LocalBookMedia.evict(id);
          _coveredBooks.remove(id);
          result = LocalMaintenanceResult(
            _coverOverrides.containsKey(id) ? '原书封面已重建，自选封面仍保留' : '原书封面已重建',
            changed: true,
          );
        case LocalMaintenanceTask.storage:
          final bytes = await compute(_compactStoredEpub, (
            root: directory.path,
            id: id,
            options: importOptionsFor(id),
          ));
          result = LocalMaintenanceResult(
            bytes > 0 ? '已整理重复资源' : '无需清理',
            changed: bytes > 0,
            freedBytes: bytes,
          );
      }
      // Layout and compaction keep chapter identities unchanged. Only a cover
      // rebuild needs affected first-volume series refreshed, not all chapters
      // of every merged book for every task in a 700-book batch.
      if (task == LocalMaintenanceTask.covers && result.changed) {
        await _refreshSeries(coverOriginals: {id});
      }
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    await work;
    return result;
  }
}

Future<int> _compactStoredText(({String root, int id}) job) async {
  final folder = '${job.root}/${job.id}';
  final raw = jsonDecode(await File('$folder/book.json').readAsString()) as Map;
  // Only known derived files are candidates. Neither original nor unknown
  // files, chapter IDs, series definitions or reading coordinates are changed.
  var freed = 0;
  for (final chapter in raw['chapters'] as List) {
    final id = chapter['id'];
    if (id is! int || id <= 0) throw const FormatException('本地目录有误，未整理正文');
    final file = File('$folder/c$id.txt');
    if (!await localTextExists(file)) {
      throw const FormatException('本地正文不完整，请先恢复原书');
    }
    freed += await compactLocalText(file);
  }
  final decoded = File('$folder/decoded.txt');
  if (await decoded.exists()) {
    final original = File('$folder/original');
    if (await original.exists() &&
        await original.length() == await decoded.length() &&
        await sameLocalTextBytes(original.openRead(), decoded.openRead())) {
      final size = await decoded.length();
      await decoded.delete();
      freed += size;
    } else {
      freed += await compactLocalText(decoded);
    }
  }
  return freed;
}
