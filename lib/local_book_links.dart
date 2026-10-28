part of 'local_books.dart';

// One validated native block covers this many raw bytes on every host. Avoid
// a separate lease/index-isolate startup when it cannot replace repeated reads.
const _singleBlockLinkedTextBytes = 32 * 1024;

String linkedTextFailureMessage(Object error) {
  if (error is FormatException) return error.message;
  // Platform messages contain the recovery action, never the document URI.
  if (error is PlatformException && error.message != null) {
    return error.message!;
  }
  return '无法读取原文件，请确认文件仍在本机，或重新定位原文件';
}

extension LocalLinkedBooks on LocalBookStore {
  bool isLinkedText(int id) => _sources[id]?['linkedText'] is Map;
  LocalTextIndex _linkedIndex(int id) => _linkedIndices.putIfAbsent(
    id,
    () => LocalTextIndex.fromJson(_sources[id]?['linkedText']),
  );
  List<Novel> linkedOriginals(int id) => [
    for (final original in _series[id]?.volumes.map((v) => v.bookId) ?? [id])
      if (isLinkedBook(original) && _books[original] != null) _books[original]!,
  ];

  Future<void> _releaseUnusedTextReference(String reference) async {
    if (_sources.values.any(
      (s) =>
          s['linkedText']?['reference'] == reference ||
          s['linkedOriginal']?['reference'] == reference,
    )) {
      return;
    }
    try {
      await textAccess.release(reference);
    } catch (_) {
      /* A revoked grant must not undo removal of a library record. */
    }
  }

  Future<Novel> importLinkedText(
    String name,
    String reference, {
    String encoding = 'auto',
    LocalImportOptions options = const LocalImportOptions(),
    bool renewReference = false,
  }) async {
    late Novel result;
    final work = _writes.catchError((Object _) {}).then((_) async {
      try {
        final source = await textAccess.inspect(reference, encoding: encoding);
        _validateInput(name, source.size);
        if (!name.toLowerCase().endsWith('.txt')) {
          throw const FormatException('关联原文件目前支持 TXT');
        }
        final id =
            localBookIdStart |
            (int.parse(source.digest.substring(0, 8), radix: 16) & 0x1fffffff);
        if (_sources[id] case final old?) {
          if (old['digest'] != source.digest) {
            throw const FormatException('本地书籍标识冲突，原书已保留');
          }
          if (renewReference && isLinkedText(id)) {
            final before = _linkedIndex(id);
            if (before.source.reference != reference ||
                before.source.modified != source.modified) {
              // Same bytes, fresh system grant. Retain the original decoder,
              // directory and coordinates rather than importing a second book.
              final renewed = LocalTextSource(
                reference: reference,
                encoding: before.source.encoding,
                size: source.size,
                modified: source.modified,
                digest: source.digest,
              );
              await _replaceLinkedSource(id, {
                ...old,
                'linkedText': LocalTextIndex(
                  renewed,
                  before.checkpoints,
                  before.ranges,
                ).toJson(),
              });
              if (before.source.reference != reference) {
                await _releaseUnusedTextReference(before.source.reference);
              }
            }
          }
          result = _books[id]!;
          return;
        }
        if (_series.containsKey(id)) {
          throw const FormatException('本地书籍标识与合订本冲突');
        }
        final checkpoints = <List<int>>[];
        Stream<String> chunks() async* {
          var offset = 0, chars = 0;
          while (offset < source.size) {
            final block = await textAccess.block(source, offset);
            if (block.next <= offset ||
                block.next > source.size ||
                block.text.isEmpty) {
              throw const FormatException('原文件已变化，请重新选择');
            }
            checkpoints.add([chars, offset]);
            chars += block.text.length;
            offset = block.next;
            yield block.text;
          }
        }

        final access = textAccess;
        final ({List<NovelChapter> chapters, List<List<int>> ranges}) parsed;
        if (source.size > _singleBlockLinkedTextBytes &&
            access is LocalTextInputAccess &&
            supportsLinkedTextInput(source.encoding)) {
          final indexed = await (access as LocalTextInputAccess).withInput(
            source,
            (input) => compute(
              indexLinkedTextInput,
              LocalLinkedTextIndexJob(
                input: input,
                source: source,
                name: name,
                options: options.effective,
              ),
              debugLabel: 'local-linked-text-index',
            ),
          );
          checkpoints.addAll(indexed.checkpoints);
          parsed = (chapters: indexed.chapters, ranges: indexed.ranges);
        } else {
          parsed = await indexTextChapters(
            chunks(),
            name,
            options: options.effective,
          );
        }
        final index = LocalTextIndex(source, checkpoints, parsed.ranges);
        LocalTextIndex.fromJson(index.toJson());
        final title = name
            .replaceAll('\\', '/')
            .split('/')
            .last
            .replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
        final novel = Novel.fromSnapshot({
          ..._novel(id, title, '', parsed.chapters).toSnapshot(),
          'summary': '已关联本地原文件，可离线阅读。',
        }).withChapters(parsed.chapters);
        final metadata = <String, dynamic>{
          'name': name,
          'digest': source.digest,
          'encoding': source.encoding.toUpperCase() == 'UTF-8'
              ? 'utf8'
              : 'decoded',
          'parser': 2,
          'imageSizing': 1,
          'importedAt': DateTime.now().millisecondsSinceEpoch,
          if (!options.effective.isDefault)
            'importOptions': options.effective.toJson(),
          'linkedText': index.toJson(),
        };
        final record = jsonEncode({
          'version': 1,
          'novel': novel.toSnapshot(),
          'source': metadata,
          'chapters': [
            for (final c in parsed.chapters)
              {
                'id': c.id,
                'title': c.title,
                'volumeId': c.volumeId,
                'volumeTitle': c.volumeTitle,
              },
          ],
        });
        if (utf8.encode(record).length > 4 * 1024 * 1024) {
          throw const FormatException('书籍目录过大，请拆分原书后导入');
        }
        final staging = Directory('${directory.path}/.$id-link');
        try {
          await staging.create(recursive: true);
          await File(
            '${staging.path}/book.json',
          ).writeAsString(record, flush: true);
          await staging.rename('${directory.path}/$id');
        } finally {
          if (await staging.exists()) await staging.delete(recursive: true);
        }
        _books[id] = novel;
        _sources[id] = metadata;
        _linkedIndices[id] = index;
        await _refreshSeries(originals: {id});
        if (!_disposed) notifyListeners();
        result = novel;
      } finally {
        // A failed import or a duplicate selected from another location must
        // not retain an unused Android document grant.
        await _releaseUnusedTextReference(reference);
      }
    });
    _writes = work;
    try {
      await work;
    } catch (error) {
      rethrow;
    }
    return result;
  }

  Future<void> _replaceLinkedSource(int id, Map<String, dynamic> source) async {
    final target = File('${directory.path}/$id/book.json');
    final record =
        jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    Novel? changed;
    if (source['linkedText'] == null &&
        source['userMetadata'] == null &&
        _books[id]?.summary == '已关联本地原文件，可离线阅读。') {
      changed = Novel.fromSnapshot({
        ..._books[id]!.toSnapshot(),
        'summary': '已保存到本地书库，可离线阅读。',
      }).withChapters(_books[id]!.chapters);
      record['novel'] = changed.toSnapshot();
    }
    final next = File('${target.path}.link-next');
    try {
      await next.writeAsString(
        jsonEncode({...record, 'source': source}),
        flush: true,
      );
      await next.rename(target.path);
    } finally {
      if (await next.exists()) await next.delete();
    }
    _sources[id] = source;
    if (changed != null) _books[id] = changed;
    _linkedIndices.remove(id);
    LocalBookMedia.evict(id);
    if (!_disposed) notifyListeners();
  }

  /// A byte-identical relocation changes the grant only: no reparsing, new ID,
  /// chapter movement, metadata reset or saved-position change.
  Future<void> relinkText(int id, String reference) async {
    final work = _writes.catchError((Object _) {}).then((_) async {
      try {
        if (!isLinkedText(id)) throw const FormatException('这本书未关联外部 TXT');
        final previous = _linkedIndex(id);
        final next = await textAccess.inspect(
          reference,
          encoding: previous.source.encoding,
        );
        if (next.digest != previous.source.digest ||
            next.size != previous.source.size) {
          throw const FormatException(
            '文件内容不同，未改动原有进度与书签；请选择原文件，修改后的 TXT 可重新导入为新书',
          );
        }
        await _replaceLinkedSource(id, {
          ..._sources[id]!,
          'linkedText': LocalTextIndex(
            next,
            previous.checkpoints,
            previous.ranges,
          ).toJson(),
        });
        if (previous.source.reference != reference) {
          await _releaseUnusedTextReference(previous.source.reference);
        }
      } finally {
        await _releaseUnusedTextReference(reference);
      }
    });
    _writes = work;
    await work;
  }

  /// Explicit opt-in; ordinary linked reading/import never calls this path.
  Future<void> saveLinkedCopy(int id, {String? reference}) async {
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (!isLinkedText(id)) return;
      final previous = _linkedIndex(id);
      var index = previous;
      if (reference != null) {
        final source = await textAccess.inspect(
          reference,
          encoding: previous.source.encoding,
        );
        if (source.digest != previous.source.digest ||
            source.size != previous.source.size) {
          throw const FormatException('不是同一份原文件，未更改现有书籍');
        }
        index = LocalTextIndex(source, previous.checkpoints, previous.ranges);
      }
      final folder = Directory('${directory.path}/$id');
      final staging = Directory('${folder.path}/.managed-next');
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create();
      final installed = <File>[];
      var committed = false;
      try {
        await textAccess
            .bytes(index.source)
            .pipe(File('${staging.path}/original').openWrite());
        if (index.source.encoding.toUpperCase() != 'UTF-8') {
          await index
              .decodedBytes(textAccess)
              .transform(gzip.encoder)
              .pipe(File('${staging.path}/decoded.txt.gz').openWrite());
        }
        for (final (at, chapter) in _books[id]!.chapters.indexed) {
          writeCompressedLocalText(
            File('${staging.path}/c${chapter.id}.txt'),
            await index.body(textAccess, at),
          );
        }
        await for (final file in staging.list()) {
          final target = File('${folder.path}/${file.uri.pathSegments.last}');
          if (await target.exists()) {
            throw const FormatException('本地已有同名文件，未覆盖');
          }
          installed.add(await file.rename(target.path) as File);
        }
        await _replaceLinkedSource(
          id,
          {..._sources[id]!}..remove('linkedText'),
        );
        committed = true;
        await _releaseUnusedTextReference(previous.source.reference);
      } finally {
        if (!committed) {
          for (final file in installed) {
            if (await file.exists()) await file.delete();
          }
        }
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    });
    _writes = work;
    await work;
  }
}
