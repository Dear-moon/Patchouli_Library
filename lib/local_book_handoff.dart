part of 'local_books.dart';

/// A local book travels with its existing, already parsed chapter files. This
/// preserves old EPUB layouts, custom TXT directories and source anchors rather
/// than reparsing the original into a potentially different chapter sequence.
class LocalHandoffFile {
  const LocalHandoffFile(this.bookId, this.name, this.length);
  final int bookId, length;
  final String name;
  String get key => '$bookId/$name';
  Map<String, Object> toJson() => {
    'book': bookId,
    'name': name,
    'length': length,
  };
  static bool validName(String name) => RegExp(
    r'^(book\.json|original|decoded\.txt|media\.json|(layout-rich-v[12]/)?c[1-9][0-9]{0,5}\.txt|(cover|cover-custom-[0-9]+|img-[0-9]+)\.(png|jpg|jpeg|webp|gif))$',
  ).hasMatch(name);
  static int limit(String name) => switch (name) {
    'book.json' => 4 * 1024 * 1024,
    'media.json' => 1024 * 1024,
    'decoded.txt' => maxLocalTextBytes,
    _ when name.startsWith('cover') || name.startsWith('img-') =>
      16 * 1024 * 1024,
    _ => maxLocalEpubBytes,
  };
}

class LocalBookHandoff {
  const LocalBookHandoff({
    required this.bookId,
    required this.identity,
    required this.title,
    required this.identities,
    required this.files,
    this.series,
    this.covers = const {},
  });
  final int bookId;
  final String identity, title;
  final Map<int, String> identities;
  final List<LocalHandoffFile> files;
  final LocalBookSeries? series;
  final Map<int, String> covers;
  int get length => files.fold(0, (sum, file) => sum + file.length);
  Map<String, Object> toJson() => {
    'version': 1,
    'book': bookId,
    'identity': identity,
    'title': title,
    'originals': {for (final e in identities.entries) '${e.key}': e.value},
    'files': [for (final file in files) file.toJson()],
    if (series != null) 'series': encodeLocalSeries([series!]),
    'covers': {for (final e in covers.entries) '${e.key}': e.value},
  };
  factory LocalBookHandoff.fromJson(Object? raw) {
    Never bad() => throw const FormatException('续读书籍信息有误');
    bool local(Object? value) =>
        value is int && value >= localBookIdStart && value <= 0x7fffffff;
    bool originalIdentity(Object? value) =>
        value is String && RegExp(r'^local:[a-f0-9]{64}$').hasMatch(value);
    if (raw is! Map ||
        raw['version'] != 1 ||
        !local(raw['book']) ||
        raw['title'] is! String ||
        (raw['title'] as String).length > 2048 ||
        raw['originals'] is! Map ||
        (raw['originals'] as Map).isEmpty ||
        (raw['originals'] as Map).length > 2000 ||
        raw['files'] is! List ||
        (raw['files'] as List).isEmpty ||
        (raw['files'] as List).length > 150000 ||
        raw['covers'] is! Map) {
      bad();
    }
    final originals = <int, String>{};
    for (final e in (raw['originals'] as Map).entries) {
      final id = e.key is String ? int.tryParse(e.key) : null;
      if (!local(id) || '$id' != e.key || !originalIdentity(e.value)) bad();
      originals[id!] = e.value;
    }
    LocalBookSeries? series;
    if (raw['series'] != null) {
      final values = decodeLocalSeries(raw['series']);
      if (values.length != 1 || values.single.deleted) bad();
      series = values.single;
      if (series.id != raw['book'] ||
          series.volumes.length != originals.length ||
          series.volumes.any((v) => !originals.containsKey(v.bookId))) {
        bad();
      }
    } else if (originals.length != 1 || !originals.containsKey(raw['book'])) {
      bad();
    }
    final identity = series == null
        ? originals[raw['book']]!
        : 'series:${series.volumes.map((v) => originals[v.bookId]).join('|')}';
    if (raw['identity'] != identity) bad();
    final covers = <int, String>{};
    for (final e in (raw['covers'] as Map).entries) {
      final id = e.key is String ? int.tryParse(e.key) : null;
      if (id == null ||
          '$id' != e.key ||
          (!originals.containsKey(id) && id != series?.id) ||
          e.value is! String ||
          !RegExp(r'^cover-custom-[0-9]+\.png$').hasMatch(e.value)) {
        bad();
      }
      covers[id] = e.value;
    }
    final files = <LocalHandoffFile>[], keys = <String>{};
    for (final value in raw['files'] as List) {
      if (value is! Map ||
          !local(value['book']) ||
          value['name'] is! String ||
          !LocalHandoffFile.validName(value['name']) ||
          value['length'] is! int ||
          value['length'] < 0 ||
          value['length'] > LocalHandoffFile.limit(value['name'])) {
        bad();
      }
      final file = LocalHandoffFile(
        value['book'],
        value['name'],
        value['length'],
      );
      if ((!originals.containsKey(file.bookId) &&
              !(file.bookId == series?.id &&
                  file.name == covers[file.bookId])) ||
          !keys.add(file.key)) {
        bad();
      }
      files.add(file);
    }
    for (final id in originals.keys) {
      if (!keys.contains('$id/book.json') || !keys.contains('$id/original')) {
        bad();
      }
    }
    for (final e in covers.entries) {
      if (!keys.contains('${e.key}/${e.value}')) bad();
    }
    return LocalBookHandoff(
      bookId: raw['book'],
      identity: identity,
      title: raw['title'],
      identities: Map.unmodifiable(originals),
      files: List.unmodifiable(files),
      series: series,
      covers: Map.unmodifiable(covers),
    );
  }
}

Future<LocalBookHandoff> _scanLocalHandoff(
  ({
    String root,
    LocalBookHandoff manifest,
    Map<int, List<LocalHandoffFile>> linked,
  })
  input,
) async {
  final manifest = input.manifest,
      files = <LocalHandoffFile>[
        for (final entries in input.linked.values) ...entries,
      ];
  for (final id in {
    ...manifest.identities.keys,
    if (manifest.series != null && manifest.covers.containsKey(manifest.bookId))
      manifest.bookId,
  }) {
    final folder = Directory('${input.root}/$id');
    final upgraded =
        manifest.identities.containsKey(id) &&
        {'layout-rich-v1', 'layout-rich-v2'}.contains(
          (jsonDecode(
                await File('${folder.path}/book.json').readAsString(),
              )['source']
              as Map)['layoutFolder'],
        );
    await for (final entry in folder.list(
      followLinks: false,
      recursive: true,
    )) {
      if (entry is! File) continue;
      var name = entry.path.substring(folder.path.length + 1);
      if (input.linked.containsKey(id) && !name.startsWith('cover')) continue;
      final compressed = name.endsWith('.txt.gz');
      if (compressed) {
        name = name.substring(0, name.length - 3);
        // Wire format stays plain UTF-8 for existing receiving versions. A
        // compressed local copy is decoded as a stream, never a second library.
        if (await File('${folder.path}/$name').exists()) continue;
      }
      if (upgraded && RegExp(r'^c[0-9]+\.txt$').hasMatch(name)) continue;
      if (!LocalHandoffFile.validName(name) ||
          (!manifest.identities.containsKey(id) &&
              manifest.covers[id] != name)) {
        continue;
      }
      files.add(
        LocalHandoffFile(
          id,
          name,
          compressed
              ? await localTextByteLength(File('${folder.path}/$name'))
              : await entry.length(),
        ),
      );
    }
  }
  files.sort((a, b) => a.key.compareTo(b.key));
  return LocalBookHandoff.fromJson({
    ...manifest.toJson(),
    'files': [for (final file in files) file.toJson()],
  });
}

({Novel novel, Map<String, dynamic> source}) _readHandoffBook(
  Directory staging,
  int id,
  LocalBookHandoff manifest,
) {
  Never bad() => throw const FormatException('接收的原书或目录不完整，请重试');
  final metadata = File('${staging.path}/$id/book.json');
  if (metadata.lengthSync() > LocalHandoffFile.limit('book.json')) bad();
  final raw = jsonDecode(metadata.readAsStringSync());
  if (raw is! Map ||
      raw['version'] != 1 ||
      raw['novel'] is! Map ||
      raw['source'] is! Map ||
      raw['chapters'] is! List ||
      (raw['chapters'] as List).isEmpty ||
      (raw['chapters'] as List).length > 100000) {
    bad();
  }
  final source = Map<String, dynamic>.from(raw['source']);
  // Device-local document grants are never accepted from another device.
  if (source.containsKey('linkedText') ||
      source.containsKey('linkedOriginal')) {
    bad();
  }
  if (source['digest'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(source['digest']) ||
      source['name'] is! String ||
      source['name'].length > 2048 ||
      source['parser'] != null && ![1, 2, 3].contains(source['parser']) ||
      source['richText'] != null && ![1, 2].contains(source['richText'])) {
    bad();
  }
  final digest = source['digest'] as String;
  if ((localBookIdStart |
          (int.parse(digest.substring(0, 8), radix: 16) & 0x1fffffff)) !=
      id) {
    bad();
  }
  final structure = jsonEncode([
    digest,
    LocalImportOptions.fromJson(source['importOptions']).effective.toJson()
      ..remove('autoTitles'),
    source['parser'] ?? 1,
    source['richText'] ?? 0,
  ]);
  if ('local:${sha256.convert(utf8.encode(structure))}' !=
      manifest.identities[id]) {
    bad();
  }
  final chapters = <NovelChapter>[], chapterIds = <int>{};
  if (source['layoutFolder'] != null &&
      !{'layout-rich-v1', 'layout-rich-v2'}.contains(source['layoutFolder'])) {
    bad();
  }
  final prefix =
      {'layout-rich-v1', 'layout-rich-v2'}.contains(source['layoutFolder'])
      ? '${source['layoutFolder']}/'
      : '';
  final names = {
    for (final f in manifest.files.where((f) => f.bookId == id)) f.name,
  };
  for (final chapter in raw['chapters']) {
    if (chapter is! Map ||
        chapter['id'] is! int ||
        !chapterIds.add(chapter['id']) ||
        !names.contains('${prefix}c${chapter['id']}.txt') ||
        chapter['title'] is! String ||
        chapter['title'].length > 2048) {
      bad();
    }
    chapters.add(
      NovelChapter(
        chapter['title'],
        '',
        id: chapter['id'],
        volumeId: chapter['volumeId'] as int? ?? 0,
        volumeTitle: chapter['volumeTitle'] as String? ?? '',
      ),
    );
  }
  final novel = Novel.fromSnapshot(Map<String, dynamic>.from(raw['novel']));
  if (novel.id != id ||
      novel.coverUrl != null &&
          (!LocalBookMedia.valid(Uri.parse(novel.coverUrl!)) ||
              Uri.parse(novel.coverUrl!).host != '$id')) {
    bad();
  }
  return (novel: novel.withChapters(chapters), source: source);
}

extension LocalBookHandoffStore on LocalBookStore {
  Future<List<int>> _portableTextMetadata(int id) async {
    final raw =
        jsonDecode(await File('${directory.path}/$id/book.json').readAsString())
            as Map<String, dynamic>;
    final source = Map<String, dynamic>.from(raw['source'])
      ..remove('linkedText');
    return utf8.encode(jsonEncode({...raw, 'source': source}));
  }

  Stream<List<int>> openHandoffFile(LocalHandoffFile file) async* {
    if (!isLocalBook(file.bookId) || !LocalHandoffFile.validName(file.name)) {
      throw const FormatException('续读书籍文件路径有误');
    }
    final owned = File('${directory.path}/${file.key}');
    Stream<List<int>> source;
    if (isLinkedText(file.bookId)) {
      final index = _linkedIndex(file.bookId);
      if (file.name == 'book.json') {
        source = Stream.value(await _portableTextMetadata(file.bookId));
      } else if (file.name == 'original') {
        source = textAccess.bytes(index.source);
      } else if (file.name == 'decoded.txt') {
        source = index.decodedBytes(textAccess);
      } else if (RegExp(r'^c[0-9]+\.txt$').hasMatch(file.name)) {
        final id = int.parse(file.name.substring(1, file.name.length - 4));
        final at = _books[file.bookId]!.chapters.indexWhere((c) => c.id == id);
        if (at < 0) throw const FormatException('本地章节已变化，请重试');
        source = Stream.value(utf8.encode(await index.body(textAccess, at)));
      } else {
        source = owned.openRead();
      }
    } else if (isLinkedBook(file.bookId) && file.name == 'book.json') {
      source = Stream.value(await _portableBookMetadata(file.bookId));
    } else if (_directOriginal(file.bookId) && file.name == 'original') {
      source = documentAccess.bytes(_documentSource(file.bookId));
    } else {
      source = file.name.endsWith('.txt')
          ? localTextBytes(owned)
          : owned.openRead();
    }
    var sent = 0;
    await for (final chunk in source) {
      sent += chunk.length;
      if (sent > file.length) throw const FormatException('本机书籍发生变化，请重试');
      yield chunk;
    }
    if (sent != file.length) throw const FormatException('本机书籍发生变化，请重试');
  }

  Future<LocalBookHandoff> prepareHandoff(int id) async {
    await _writes;
    final selected = book(id);
    if (selected == null) throw const FormatException('本地原书已不存在');
    final series = _seriesBooks.containsKey(id) ? _series[id] : null;
    final ids = series?.volumes.map((v) => v.bookId).toList() ?? [id];
    final manifest = LocalBookHandoff(
      bookId: id,
      title: selected.title,
      identity: readingIdentity(id)!,
      identities: {
        for (final original in ids) original: readingIdentity(original)!,
      },
      series: series,
      files: const [],
      covers: {
        for (final entry in _coverOverrides.entries)
          if (ids.contains(entry.key) || entry.key == series?.id)
            entry.key: entry.value,
      },
    );
    final linked = <int, List<LocalHandoffFile>>{};
    for (final original in ids.where(isLinkedText)) {
      final index = _linkedIndex(original);
      linked[original] = [
        LocalHandoffFile(
          original,
          'book.json',
          (await _portableTextMetadata(original)).length,
        ),
        LocalHandoffFile(original, 'original', index.source.size),
        if (index.source.encoding.toUpperCase() != 'UTF-8')
          LocalHandoffFile(
            original,
            'decoded.txt',
            await index
                .decodedBytes(textAccess)
                .fold<int>(0, (n, chunk) => n + chunk.length),
          ),
        for (final (at, chapter) in _books[original]!.chapters.indexed)
          LocalHandoffFile(
            original,
            'c${chapter.id}.txt',
            utf8.encode(await index.body(textAccess, at)).length,
          ),
      ];
    }
    for (final original in ids.where(
      (id) => isLinkedBook(id) && !isLinkedText(id),
    )) {
      final folder = '${directory.path}/$original';
      final files = <LocalHandoffFile>[
        LocalHandoffFile(
          original,
          'book.json',
          (await _portableBookMetadata(original)).length,
        ),
        LocalHandoffFile(
          original,
          'original',
          _directOriginal(original)
              ? _documentSource(original).size
              : await File('$folder/original').length(),
        ),
      ];
      await for (final file in Directory(
        folder,
      ).list(recursive: true, followLinks: false)) {
        if (file is! File) continue;
        var name = file.path.substring(folder.length + 1);
        if (name == 'book.json' ||
            name == 'original' ||
            name.startsWith('cover')) {
          continue;
        }
        if (name.endsWith('.txt.gz')) name = name.substring(0, name.length - 3);
        if (!LocalHandoffFile.validName(name)) continue;
        files.add(
          LocalHandoffFile(
            original,
            name,
            name.endsWith('.txt')
                ? await localTextByteLength(File('$folder/$name'))
                : await file.length(),
          ),
        );
      }
      linked[original] = files;
    }
    return compute(_scanLocalHandoff, (
      root: directory.path,
      manifest: manifest,
      linked: linked,
    ));
  }

  Novel? bookForHandoff(String identity) =>
      [..._seriesBooks.keys, ..._books.keys]
          .map((id) => book(id)!)
          .where((b) => readingIdentity(b.id) == identity)
          .firstOrNull;

  /// Only absent originals are accepted. Different directory interpretations or
  /// conflicting series never overwrite the receiving device's existing book.
  List<LocalHandoffFile> neededHandoffFiles(LocalBookHandoff manifest) {
    if (bookForHandoff(manifest.identity) != null) return const [];
    for (final entry in manifest.identities.entries) {
      if (contains(entry.key) && readingIdentity(entry.key) != entry.value ||
          _series.containsKey(entry.key)) {
        throw const FormatException('两端这本书的目录不同，已保留本机书籍，请先统一目录');
      }
    }
    if (manifest.series case final incoming?) {
      if (contains(incoming.id) || _series.containsKey(incoming.id)) {
        throw const FormatException('本机已有不同的合订本，已保留本机分卷');
      }
      if (series.any(
        (s) => s.volumes.any((v) => manifest.identities.containsKey(v.bookId)),
      )) {
        throw const FormatException('部分分卷已属于本机其他合订本，已保留原有分类与分卷');
      }
    }
    return [
      for (final file in manifest.files)
        if (!contains(file.bookId)) file,
    ];
  }

  Future<Novel> receiveHandoff(
    LocalBookHandoff manifest,
    Directory staging,
  ) async {
    late Novel received;
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (bookForHandoff(manifest.identity) case final existing?) {
        received = existing;
        return;
      }
      final needed = neededHandoffFiles(manifest);
      final parsed = await compute((
        ({String root, LocalBookHandoff manifest, List<LocalHandoffFile> files})
        input,
      ) async {
        for (final file in input.files) {
          final path = File('${input.root}/${file.key}');
          if (!path.existsSync() || path.lengthSync() != file.length) {
            throw const FormatException('书籍传输未完成，请重试');
          }
        }
        final parsed = {
          for (final id
              in input.files
                  .where((f) => f.name == 'book.json')
                  .map((f) => f.bookId))
            id: _readHandoffBook(Directory(input.root), id, input.manifest),
        };
        for (final entry in parsed.entries) {
          if ((entry.value.source['name'] as String).toLowerCase().endsWith(
            '.txt',
          )) {
            await _compactStoredText((root: input.root, id: entry.key));
          }
        }
        return parsed;
      }, (root: staging.path, manifest: manifest, files: needed));
      // New originals commit by directory rename, just like a local import.
      // No existing original is removed, rewritten or reparsed.
      for (final entry in parsed.entries) {
        final target = Directory('${directory.path}/${entry.key}');
        if (await target.exists()) {
          throw const FormatException('本机有未能识别的同名书籍目录，未覆盖原文件');
        }
      }
      final previousSeries = {..._series},
          previousCovers = {..._coverOverrides};
      final installed = <int>[];
      try {
        if (manifest.series case final incoming?) {
          if (await Directory('${directory.path}/${incoming.id}').exists()) {
            throw const FormatException('本机已有同名分卷目录，未覆盖原文件');
          }
          if (incoming.volumes.any(
            (v) =>
                (parsed[v.bookId]?.novel ?? _books[v.bookId])
                    ?.chapters
                    .length !=
                v.chapterIds.length,
          )) {
            throw const FormatException('两端分卷目录不一致，未更改本机书籍');
          }
        }
        for (final entry in parsed.entries) {
          await Directory(
            '${staging.path}/${entry.key}',
          ).rename('${directory.path}/${entry.key}');
          installed.add(entry.key);
          _books[entry.key] = entry.value.novel;
          _sources[entry.key] = entry.value.source;
        }
        if (manifest.series case final incoming?) {
          final folder = Directory('${staging.path}/${incoming.id}');
          if (await folder.exists()) {
            await folder.rename('${directory.path}/${incoming.id}');
            installed.add(incoming.id);
          }
          await _writeSeries({..._series, incoming.id: incoming});
        }
        final covers = {
          ..._coverOverrides,
          for (final entry in manifest.covers.entries)
            if (needed.any(
              (f) => f.bookId == entry.key && f.name == entry.value,
            ))
              entry.key: entry.value,
        };
        if (!mapEquals(covers, _coverOverrides)) await _writeCovers(covers);
        await _refreshSeries();
        received =
            bookForHandoff(manifest.identity) ??
            (throw const FormatException('未能恢复对应目录，请重试'));
        if (!_disposed) notifyListeners();
      } catch (_) {
        // Only these newly installed directories belong to this serial writer.
        // Release their space before restoring the old, small indices.
        for (final id in installed.reversed) {
          final folder = Directory('${directory.path}/$id');
          if (await folder.exists()) await folder.delete(recursive: true);
          _books.remove(id);
          _sources.remove(id);
          _coveredBooks.remove(id);
        }
        if (!mapEquals(_series, previousSeries)) {
          await _writeSeries(previousSeries);
        }
        if (!mapEquals(_coverOverrides, previousCovers)) {
          await _writeCovers(previousCovers);
        }
        await _refreshSeries();
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
    _writes = work;
    await work;
    return received;
  }
}
