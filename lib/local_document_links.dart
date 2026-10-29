part of 'local_books.dart';

extension LocalDocumentLinks on LocalBookStore {
  /// Reopens committed metadata, its original and boundary chapters before a
  /// move may remove the external source. Native code then compares all bytes.
  Future<String> verifiedMoveCopy(int id) async {
    await _writes;
    if (_seriesBooks.containsKey(id) || isLinkedBook(id)) {
      throw const FormatException('书籍仍有原文件关联，已保留原文件');
    }
    final folder = '${directory.path}/$id';
    final metadata = File('$folder/book.json');
    if (await metadata.length() > 4 * 1024 * 1024) {
      throw const FormatException('书库目录无法核对，已保留原文件');
    }
    final saved =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    final novel = Novel.fromSnapshot(Map<String, dynamic>.from(saved['novel']));
    final source = Map<String, dynamic>.from(saved['source']);
    if ((source['epubImportIssues'] as List?)?.isNotEmpty == true) {
      throw const FormatException('这本书只导入了可读部分，已保留原文件；请先获取完整原件');
    }
    final chapters = saved['chapters'] as List;
    final name = source['name'] as String? ?? '';
    if (novel.id != id ||
        chapters.isEmpty ||
        source['linkedText'] != null ||
        source['linkedOriginal'] != null ||
        !RegExp(r'\.(txt|epub)$', caseSensitive: false).hasMatch(name)) {
      throw const FormatException('书库未保存完整独立原件，已保留原文件');
    }
    final original = File('$folder/original');
    final handle = await original.open();
    try {
      if (await handle.length() == 0 || (await handle.read(1)).isEmpty) {
        throw const FormatException('书库原件无法重新读取，已保留原文件');
      }
    } finally {
      await handle.close();
    }
    final layout =
        {
          'layout-rich-v1',
          'layout-rich-v2',
          'layout-markup-v1',
        }.contains(source['layoutFolder'])
        ? '${source['layoutFolder']}/'
        : '';
    for (final chapter in [chapters.first, chapters.last]) {
      final chapterId = chapter['id'] as int;
      if (chapterId <= 0) throw const FormatException('书库章节无法核对，已保留原文件');
      await readLocalText(File('$folder/${layout}c$chapterId.txt'));
    }
    return original.path;
  }

  bool isLinkedBook(int id) =>
      isLinkedText(id) || _sources[id]?['linkedOriginal'] is Map;
  bool _directOriginal(int id) =>
      _sources[id]?['linkedOriginal']?['direct'] == true;
  LocalDocumentSource _documentSource(int id) =>
      LocalDocumentSource.fromJson(_sources[id]?['linkedOriginal']);

  /// The picker/batch owns unused grants until all converted children finish.
  Future<void> releaseUnusedOriginalReference(String reference) =>
      _releaseUnusedTextReference(reference);

  Future<Novel> importLinkedDocument(
    String name,
    String reference, {
    LocalImportOptions options = const LocalImportOptions(),
    bool renewReference = false,
    bool recoverDamagedEpub = false,
  }) async {
    if (!name.toLowerCase().endsWith('.epub')) {
      throw const FormatException('此格式需要先生成阅读排版');
    }
    try {
      if (documentAccess is LocalDocumentImportAccess) {
        return await _import(
          name,
          linkedOriginalReference: reference,
          options: options,
          renewOriginalReference: renewReference,
          recoverDamagedEpub: recoverDamagedEpub,
        );
      }
      final source = await documentAccess.inspect(reference);
      return await documentAccess.withInput(
        source,
        (input) => _import(
          name,
          document: input,
          options: options,
          linkedOriginal: {...source.toJson(), 'name': name, 'direct': true},
          renewOriginalReference: renewReference,
          recoverDamagedEpub: recoverDamagedEpub,
        ),
      );
    } finally {
      await _releaseUnusedTextReference(reference);
    }
  }

  Future<Novel> importDerivedDocument(
    String name,
    String path, {
    required String originalName,
    required LocalDocumentSource original,
    String? decodedPath,
    LocalImportOptions options = const LocalImportOptions(),
    bool renewReference = false,
  }) => _import(
    name,
    path: path,
    decodedPath: decodedPath,
    options: options,
    linkedOriginal: {
      ...original.toJson(),
      'name': originalName,
      'direct': false,
    },
    renewOriginalReference: renewReference,
  );

  Future<T> _withOriginalInput<T>(
    int id,
    Future<T> Function(LocalDocumentInput input) read,
  ) => _directOriginal(id)
      ? documentAccess.withInput(_documentSource(id), read)
      : read(LocalDocumentInput.file('${directory.path}/$id/original'));

  Future<void> relinkOriginal(int id, String reference) async {
    if (isLinkedText(id)) return relinkText(id, reference);
    final work = _writes.catchError((Object _) {}).then((_) async {
      try {
        if (!isLinkedBook(id)) throw const FormatException('这本书没有关联原文件');
        final before = _documentSource(id),
            after = await documentAccess.inspect(reference);
        if (after.digest != before.digest || after.size != before.size) {
          throw const FormatException('文件内容不同，未改动原有进度与书签；请选择原文件');
        }
        await _replaceLinkedSource(id, {
          ..._sources[id]!,
          'linkedOriginal': {
            ...Map<String, dynamic>.from(_sources[id]!['linkedOriginal']),
            ...after.toJson(),
          },
        });
        if (before.reference != reference) {
          await _releaseUnusedTextReference(before.reference);
        }
      } finally {
        await _releaseUnusedTextReference(reference);
      }
    });
    _writes = work;
    await work;
  }

  Future<void> saveOriginalCopy(int id, {String? path}) async {
    if (isLinkedText(id)) return saveLinkedCopy(id);
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (!isLinkedBook(id)) return;
      final source = _documentSource(id), folder = '${directory.path}/$id';
      final next = File('$folder/.original-next'),
          target = File('$folder/original');
      var installed = false, committed = false;
      try {
        if (_directOriginal(id)) {
          if (await target.exists()) {
            throw const FormatException('本地已有原书文件，未覆盖');
          }
          if (path == null) {
            await documentAccess.bytes(source).pipe(next.openWrite());
          } else {
            final file = File(path);
            if (await file.length() != source.size ||
                (await sha256.bind(file.openRead()).first).toString() !=
                    source.digest) {
              throw const FormatException('不是同一份原文件，未更改现有书籍');
            }
            await file.openRead().pipe(next.openWrite());
          }
          await next.rename(target.path);
          installed = true;
        }
        // Converted formats already own their necessary EPUB reading result.
        await _replaceLinkedSource(
          id,
          {..._sources[id]!}..remove('linkedOriginal'),
        );
        committed = true;
        await _releaseUnusedTextReference(source.reference);
      } finally {
        if (!committed && installed && await target.exists()) {
          await target.delete();
        }
        if (await next.exists()) await next.delete();
      }
    });
    _writes = work;
    await work;
  }

  Future<Uint8List> _portableBookMetadata(int id) async {
    final raw =
        jsonDecode(await File('${directory.path}/$id/book.json').readAsString())
            as Map<String, dynamic>;
    final source = Map<String, dynamic>.from(raw['source'])
      ..remove('linkedText')
      ..remove('linkedOriginal');
    return Uint8List.fromList(
      utf8.encode(jsonEncode({...raw, 'source': source})),
    );
  }
}
