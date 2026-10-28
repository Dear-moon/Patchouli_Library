part of 'local_books.dart';

typedef _StoredNavigation = ({
  BookNavigation navigation,
  List<NovelChapter>? chapters,
  Map<String, dynamic>? source,
  String? coverUrl,
});

Future<_StoredNavigation> _readStoredNavigation(
  ({String root, int id, LocalDocumentInput input, LocalImportOptions options})
  job,
) async {
  final folder = Directory('${job.root}/${job.id}');
  final record =
      jsonDecode(await File('${folder.path}/book.json').readAsString()) as Map;
  final source = record['source'] as Map;
  final chapters = record['chapters'] as List;
  final staging = Directory('${folder.path}/.navigation-next');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create();
  final buffer = job.input.open();
  try {
    final archive = readLocalBookArchive(
      buffer.stream,
      maxSize: 1024 * 1024 * 1024,
    );
    final mediaFile = File('${folder.path}/media.json');
    final media = await mediaFile.exists()
        ? Map<String, dynamic>.from(
            (jsonDecode(await mediaFile.readAsString()) as Map)['entries'],
          )
        : <String, dynamic>{};
    final names = {for (final e in media.entries) e.value as String: e.key};
    final parsed = _epub(
      LocalBookInput(source['name'], Uint8List(0)),
      job.id,
      source['digest'],
      archive: archive,
      autoTitles: job.options.autoTitles,
      mergeUnlistedIllustrations: job.options.inlineEpubImages,
      preserveRichText: (source['richText'] as int? ?? 0) > 0,
      richLayoutLevel: (source['richText'] as int? ?? 0) >= 2 ? 2 : 1,
      imageNames: names,
      saveImage: (name, file) => names[file.name] = name,
      saveBody: (i, body) =>
          File('${staging.path}/$i.txt').writeAsStringSync(body),
      appendBody: (i, body) => File(
        '${staging.path}/$i.txt',
      ).writeAsStringSync(body, mode: FileMode.append),
    );
    final prefix =
        {
          'layout-rich-v1',
          'layout-rich-v2',
          'layout-markup-v1',
        }.contains(source['layoutFolder'])
        ? '${source['layoutFolder']}/'
        : '';
    final ids = <int, int>{};
    final storedFiles = [
      for (final chapter in chapters)
        File('${folder.path}/${prefix}c${chapter['id']}.txt'),
    ];
    var same = parsed.novel.chapters.length == chapters.length;
    if (same) {
      for (var i = 0; i < chapters.length; i++) {
        if (_sizingIndependent(await readLocalText(storedFiles[i])) !=
            _sizingIndependent(
              await File('${staging.path}/${i + 1}.txt').readAsString(),
            )) {
          same = false;
          break;
        }
      }
    }
    if (!same && source['epubMarkup'] != epubMarkupVersion) {
      return await _restoreMarkupBody(
        folder,
        staging,
        archive,
        job,
        source,
        chapters,
        storedFiles,
        parsed,
        names,
        media,
      );
    }
    if (!same) throw const FormatException('原书与已保存正文不一致，未改动阅读记录');
    final enriched = <({File staged, File target})>[];
    for (var i = 0; i < chapters.length; i++) {
      final stored = await readLocalText(storedFiles[i]);
      final parsedBody = await File(
        '${staging.path}/${i + 1}.txt',
      ).readAsString();
      if (_sizingIndependent(stored) != _sizingIndependent(parsedBody)) {
        throw const FormatException('原书与已保存正文不一致，未改动阅读记录');
      }
      // Enrich existing text without inserting a paragraph. Keep ruby, notes
      // and coordinate maps; publisher gaps are independent layout metadata.
      final before = ReaderRichBody.decode(stored),
          after = ReaderRichBody.decode(parsedBody);
      final formats = {...before.formats};
      var changed = false;
      final indices = {
        ...after.formats.keys,
        // A corrected language-only format can disappear from the new body.
        // Its old tag still needs removal without changing paragraph slots.
        if (source['richText'] == 2) ...before.formats.keys,
      };
      for (final index in indices) {
        final fresh = after.formats[index] ?? const ReaderRichParagraph();
        final links = fresh.references
            .where((r) => r.id.startsWith('epub-link:'))
            .toList();
        final old = formats[index] ?? const ReaderRichParagraph();
        var next = old;
        final refs = [
          ...old.references.where((r) => !r.id.startsWith('epub-link:')),
          ...links,
        ];
        if (links.isNotEmpty &&
            jsonEncode(old.references.map((r) => r.toJson()).toList()) !=
                jsonEncode(refs.map((r) => r.toJson()).toList())) {
          next = next.withReferences(refs);
        }
        if (source['richText'] == 2) {
          if (after.formats.containsKey(index)) {
            next = next.replaceSpacing(fresh.spacing);
          }
          next = next.withPublisherLanguage(fresh);
        }
        if (jsonEncode(old.toJson()) != jsonEncode(next.toJson())) {
          if (next.empty) {
            formats.remove(index);
          } else {
            formats[index] = next;
          }
          changed = true;
        }
      }
      if (changed) {
        final plain = File('${folder.path}/${prefix}c${chapters[i]['id']}.txt');
        final compressed = !await plain.exists();
        final target = compressed ? File('${plain.path}.gz') : plain;
        final pending = File('${staging.path}/link-${chapters[i]['id']}');
        final bytes = utf8.encode(
          ReaderRichBody(
            before.paragraphs,
            formats: formats,
            notes: before.notes,
            revision: before.revision,
            coordinateMap: before.coordinateMap,
          ).encode(),
        );
        await pending.writeAsBytes(
          compressed ? gzip.encode(bytes) : bytes,
          flush: true,
        );
        enriched.add((staged: pending, target: target));
      }
      ids[parsed.novel.chapters[i].id] = chapters[i]['id'];
    }
    for (final update in enriched) {
      await update.staged.rename(update.target.path);
    }
    final nav = parsed.novel.navigation!;
    return (
      navigation: BookNavigation(
        [
          for (final e in nav.entries)
            BookNavigationEntry(
              e.title,
              e.target.inChapter(ids[e.target.chapterId]!),
              depth: e.depth,
            ),
        ],
        targets: {
          for (final e in nav.targets.entries)
            e.key: e.value.inChapter(ids[e.value.chapterId]!),
        },
      ),
      chapters: null,
      source: null,
      coverUrl: parsed.novel.coverUrl,
    );
  } finally {
    buffer.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

Future<_StoredNavigation> _restoreMarkupBody(
  Directory folder,
  Directory staging,
  Archive archive,
  ({String root, int id, LocalDocumentInput input, LocalImportOptions options})
  job,
  Map source,
  List chapters,
  List<File> stored,
  ImportedBook parsed,
  Map<String, String> names,
  Map<String, dynamic> media,
) async {
  if (source['layoutFolder'] == 'layout-markup-v1') {
    throw const FormatException('当前恢复正文与原书不一致，已保留阅读记录');
  }
  // Reproduce the old tokenizer first. Never infer a user's old chapter from
  // a title or position, and never overwrite an edited/mismatched reading copy.
  final legacy = _epub(
    LocalBookInput(source['name'], Uint8List(0)),
    job.id,
    source['digest'],
    archive: archive,
    autoTitles: job.options.autoTitles,
    mergeUnlistedIllustrations: job.options.inlineEpubImages,
    preserveRichText: (source['richText'] as int? ?? 0) > 0,
    richLayoutLevel: (source['richText'] as int? ?? 0) >= 2 ? 2 : 1,
    normalizeMarkup: false,
    imageNames: {for (final e in media.entries) e.value as String: e.key},
    saveImage: (_, _) {},
    saveBody: (i, body) =>
        File('${staging.path}/legacy-$i.txt').writeAsStringSync(body),
    appendBody: (i, body) => File(
      '${staging.path}/legacy-$i.txt',
    ).writeAsStringSync(body, mode: FileMode.append),
  );
  if (legacy.novel.chapters.length != chapters.length ||
      legacy.origins.toSet().length != legacy.origins.length ||
      parsed.origins.toSet().length != parsed.origins.length) {
    throw const FormatException('旧目录与原书不一致，已保留正文和阅读记录');
  }
  for (var i = 0; i < stored.length; i++) {
    if (_sizingIndependent(await readLocalText(stored[i])) !=
        _sizingIndependent(
          await File('${staging.path}/legacy-${i + 1}.txt').readAsString(),
        )) {
      throw const FormatException('旧正文与原书不一致，已保留阅读记录');
    }
  }
  final oldByOrigin = {
    for (var i = 0; i < chapters.length; i++) legacy.origins[i]: i,
  };
  if (!oldByOrigin.keys.every(parsed.origins.contains)) {
    throw const FormatException('旧章节来源无法完整恢复，已保留阅读记录');
  }
  final ids = <int, int>{};
  var nextId = chapters.map((c) => c['id'] as int).fold(0, max);
  final result = <NovelChapter>[];
  final generation = Directory('${staging.path}/generation');
  await generation.create();
  for (var i = 0; i < parsed.novel.chapters.length; i++) {
    final oldIndex = oldByOrigin[parsed.origins[i]];
    final chapter = parsed.novel.chapters[i];
    final id = oldIndex == null ? ++nextId : chapters[oldIndex]['id'] as int;
    ids[chapter.id] = id;
    final fresh = ReaderRichBody.decode(
      await File('${staging.path}/${i + 1}.txt').readAsString(),
    );
    final before = oldIndex == null
        ? null
        : ReaderRichBody.decode(await readLocalText(stored[oldIndex]));
    if (before != null) {
      var at = 0;
      for (final paragraph in fresh.paragraphs) {
        if (at < before.paragraphs.length &&
            paragraph == before.paragraphs[at]) {
          at++;
        } else if (readerIllustrationUrl(paragraph) == null) {
          throw const FormatException('旧正文与恢复内容不一致，已保留阅读记录');
        }
      }
      if (at != before.paragraphs.length) {
        throw const FormatException('旧正文未完整保留，未改写阅读记录');
      }
    }
    final body = ReaderRichBody(
      fresh.paragraphs,
      formats: fresh.formats,
      notes: fresh.notes,
      revision: 'epub-markup-v1',
      coordinateMap: ReaderCoordinateMap.between(
        before?.paragraphs ?? fresh.paragraphs,
        fresh.paragraphs,
        sourceRevision: before?.revision ?? fresh.revision,
        previous: before?.coordinateMap,
      ),
    );
    await File(
      '${generation.path}/c$id.txt',
    ).writeAsString(body.encode(), flush: true);
    result.add(
      NovelChapter(
        oldIndex == null ? chapter.title : chapters[oldIndex]['title'],
        '',
        id: id,
        volumeId: oldIndex == null
            ? chapter.volumeId
            : chapters[oldIndex]['volumeId'] as int? ?? 0,
        volumeTitle: oldIndex == null
            ? chapter.volumeTitle
            : chapters[oldIndex]['volumeTitle'] as String? ?? '',
      ),
    );
  }
  final entries = {...media};
  for (final e in names.entries) {
    if (entries[e.value] != null && entries[e.value] != e.key) {
      throw const FormatException('插图索引冲突，已保留原书');
    }
    entries[e.value] = e.key;
  }
  await _maintenanceRecord(File('${folder.path}/media.json'), {
    'version': 1,
    'entries': entries,
  });
  final target = Directory('${folder.path}/layout-markup-v1');
  if (await target.exists()) {
    await target.delete(recursive: true); // uncommitted recovery only
  }
  await generation.rename(target.path);
  final nav = parsed.novel.navigation!;
  return (
    navigation: BookNavigation(
      [
        for (final e in nav.entries)
          BookNavigationEntry(
            e.title,
            e.target.inChapter(ids[e.target.chapterId]!),
            depth: e.depth,
          ),
      ],
      targets: {
        for (final e in nav.targets.entries)
          e.key: e.value.inChapter(ids[e.value.chapterId]!),
      },
    ),
    chapters: result,
    source: {
      ...Map<String, dynamic>.from(source),
      'layoutFolder': 'layout-markup-v1',
      'epubMarkup': epubMarkupVersion,
      'markupPriorChapterIds': [for (final c in chapters) c['id']],
    },
    coverUrl: parsed.novel.coverUrl,
  );
}

extension LocalBookNavigation on LocalBookStore {
  /// Enrich the reading copy while retaining existing section IDs and source
  /// anchors. Recovered omitted sections/images may add slots; coordinate maps
  /// and stable IDs preserve old positions and series references.
  Future<Novel> ensureNavigation(int id) async {
    final members = _series[id]?.volumes.map((v) => v.bookId).toList() ?? [id];
    final work = _writes.catchError((Object _) {}).then((_) async {
      var changed = false;
      for (final member in members) {
        final source = _sources[member];
        if (source == null ||
            source['epubNavigation'] == 1 &&
                source['epubMarkup'] == epubMarkupVersion &&
                (source['richText'] != 2 ||
                    source['publisherSpacing'] == 1 &&
                        source['publisherLanguages'] ==
                            epubPublisherLanguageVersion) ||
            !(source['name'] as String).toLowerCase().endsWith('.epub')) {
          continue;
        }
        final restored = await _withOriginalInput(
          member,
          (input) => compute(_readStoredNavigation, (
            root: directory.path,
            id: member,
            input: input,
            options: importOptionsFor(member),
          )),
        );
        final before = _books[member]!;
        final nextBook = Novel.fromSnapshot({
          ...before.toSnapshot(),
          'navigation': restored.navigation.toJson(),
          if (before.coverUrl == null) 'coverUrl': restored.coverUrl,
        }).withChapters(restored.chapters ?? before.chapters);
        final metadata = File('${directory.path}/$member/book.json');
        final record =
            jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
        final nextSource = {
          ...source,
          ...?restored.source,
          'epubMarkup': epubMarkupVersion,
          'epubNavigation': 1,
          if (source['richText'] == 2) 'publisherSpacing': 1,
          if (source['richText'] == 2)
            'publisherLanguages': epubPublisherLanguageVersion,
        };
        final nextRecord = {
          ...record,
          'novel': nextBook.toSnapshot(),
          'source': nextSource,
          if (restored.chapters != null)
            'chapters': [
              for (final c in restored.chapters!)
                {
                  'id': c.id,
                  'title': c.title,
                  'volumeId': c.volumeId,
                  'volumeTitle': c.volumeTitle,
                },
            ],
        };
        if (utf8.encode(jsonEncode(nextRecord)).length > 4 * 1024 * 1024) {
          throw const FormatException('原书导航数据超过 4 MiB，已保留现有目录和阅读记录');
        }
        await _maintenanceRecord(metadata, nextRecord);
        _books[member] = nextBook;
        _sources[member] = nextSource;
        if (restored.chapters != null) LocalBookMedia.evict(member);
        changed = true;
      }
      if (changed) {
        await _refreshSeries(originals: members.toSet());
        if (!_disposed) notifyListeners();
      }
    });
    _writes = work;
    await work;
    return book(id) ?? (throw const FormatException('本地原书不存在，请重新导入'));
  }

  BookReadingTarget? navigationTarget(int id, int chapterId, String key) {
    final member = _seriesChapters[id]?[chapterId]?.bookId;
    final target = _books[member ?? id]?.navigation?.targets[key];
    if (target == null || member == null) return target;
    final mapped = _seriesChapters[id]!.entries
        .where(
          (e) =>
              e.value.bookId == member && e.value.chapterId == target.chapterId,
        )
        .firstOrNull;
    return mapped == null ? null : target.inChapter(mapped.key);
  }

  BookNavigation? _seriesNavigation(LocalBookSeries series) {
    if (!series.volumes.any(
      (v) => _books[v.bookId]?.navigation?.entries.isNotEmpty == true,
    )) {
      return null;
    }
    return BookNavigation([
      for (final volume in series.volumes)
        for (final entry in _books[volume.bookId]!.directory)
          BookNavigationEntry(
            entry.title,
            entry.target.inChapter(volume.chapterIds[entry.chapter]),
            depth: entry.depth,
          ),
    ]);
  }
}

extension on LocalBookStore {
  /// Book metadata is the commit point. If a process stops before the additive
  /// series update, this source-ID record permits the next load to finish it.
  Future<void> _repairMarkupSeries({Set<int>? originals}) async {
    final next = {..._series};
    var changed = false;
    for (final series in _series.values.where(
      (s) =>
          !s.deleted &&
          (originals == null ||
              s.volumes.any((v) => originals.contains(v.bookId))),
    )) {
      var nextId = series.nextChapterId, updated = false;
      final volumes = <LocalSeriesVolume>[];
      for (final volume in series.volumes) {
        if (originals != null && !originals.contains(volume.bookId)) {
          volumes.add(volume);
          continue;
        }
        final book = _books[volume.bookId];
        final prior = _sources[volume.bookId]?['markupPriorChapterIds'];
        if (book == null ||
            book.chapters.length == volume.chapterIds.length ||
            prior is! List ||
            prior.length != volume.chapterIds.length) {
          volumes.add(volume);
          continue;
        }
        final oldIds = {
          for (var i = 0; i < prior.length; i++)
            prior[i] as int: volume.chapterIds[i],
        };
        if (!oldIds.keys.every((id) => book.chapters.any((c) => c.id == id))) {
          throw const FormatException('合订本旧章节未完整保留，未改动分卷记录');
        }
        volumes.add(
          LocalSeriesVolume(
            bookId: volume.bookId,
            title: volume.title,
            chapterIds: [
              for (final c in book.chapters) oldIds[c.id] ?? nextId++,
            ],
          ),
        );
        updated = true;
      }
      if (updated) {
        next[series.id] = series.copyWith(
          volumes: volumes,
          nextChapterId: nextId,
          updatedAt: max(
            DateTime.now().millisecondsSinceEpoch,
            series.updatedAt + 1,
          ),
        );
        changed = true;
      }
    }
    if (!changed) return;
    final data = encodeLocalSeries(next.values);
    decodeLocalSeries(data);
    if (utf8.encode(jsonEncode(data)).length > 4 * 1024 * 1024) {
      throw const FormatException('恢复后的合订本超过 4 MiB，已保留原分卷记录');
    }
    await _maintenanceRecord(File('${directory.path}/series.json'), data);
    _series
      ..clear()
      ..addAll(next);
  }
}
