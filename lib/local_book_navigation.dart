part of 'local_books.dart';

Future<BookNavigation> _readStoredNavigation(
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
    final parsed = _epub(
      LocalBookInput(source['name'], Uint8List(0)),
      job.id,
      source['digest'],
      archive: readLocalBookArchive(buffer.stream, maxSize: 1024 * 1024 * 1024),
      autoTitles: job.options.autoTitles,
      mergeUnlistedIllustrations: job.options.inlineEpubImages,
      preserveRichText: (source['richText'] as int? ?? 0) > 0,
      richLayoutLevel: (source['richText'] as int? ?? 0) >= 2 ? 2 : 1,
      saveImage: (_, _) {},
      saveBody: (i, body) =>
          File('${staging.path}/$i.txt').writeAsStringSync(body),
      appendBody: (i, body) => File(
        '${staging.path}/$i.txt',
      ).writeAsStringSync(body, mode: FileMode.append),
    );
    if (parsed.novel.chapters.length != chapters.length) {
      throw const FormatException('原书与已保存目录不一致，未改动正文和阅读位置');
    }
    final prefix =
        {'layout-rich-v1', 'layout-rich-v2'}.contains(source['layoutFolder'])
        ? '${source['layoutFolder']}/'
        : '';
    final ids = <int, int>{};
    final enriched = <({File staged, File target})>[];
    for (var i = 0; i < chapters.length; i++) {
      final stored = await readLocalText(
        File('${folder.path}/${prefix}c${chapters[i]['id']}.txt'),
      );
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
      for (final e in after.formats.entries) {
        final links = e.value.references
            .where((r) => r.id.startsWith('epub-link:'))
            .toList();
        final old = formats[e.key] ?? const ReaderRichParagraph();
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
          next = next.replaceSpacing(e.value.spacing);
          next = next.withPublisherLanguage(e.value);
        }
        if (jsonEncode(old.toJson()) != jsonEncode(next.toJson())) {
          formats[e.key] = next;
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
    return BookNavigation(
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
    );
  } finally {
    buffer.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

extension LocalBookNavigation on LocalBookStore {
  /// Enrich navigation and link annotations without changing section IDs, plain
  /// prose, paragraph coordinates, series references or saved UTF-16 positions.
  Future<Novel> ensureNavigation(int id) async {
    final members = _series[id]?.volumes.map((v) => v.bookId).toList() ?? [id];
    final work = _writes.catchError((Object _) {}).then((_) async {
      var changed = false;
      for (final member in members) {
        final source = _sources[member];
        if (source == null ||
            source['epubNavigation'] == 1 &&
                (source['richText'] != 2 ||
                    source['publisherSpacing'] == 1 &&
                        source['publisherLanguages'] == 1) ||
            !(source['name'] as String).toLowerCase().endsWith('.epub')) {
          continue;
        }
        final nav = await _withOriginalInput(
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
          'navigation': nav.toJson(),
        }).withChapters(before.chapters);
        final metadata = File('${directory.path}/$member/book.json');
        final record =
            jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
        final nextSource = {
          ...source,
          'epubNavigation': 1,
          if (source['richText'] == 2) 'publisherSpacing': 1,
          if (source['richText'] == 2) 'publisherLanguages': 1,
        };
        final nextRecord = {
          ...record,
          'novel': nextBook.toSnapshot(),
          'source': nextSource,
        };
        if (utf8.encode(jsonEncode(nextRecord)).length > 4 * 1024 * 1024) {
          throw const FormatException('原书导航数据超过 4 MiB，已保留现有目录和阅读记录');
        }
        await _maintenanceRecord(metadata, nextRecord);
        _books[member] = nextBook;
        _sources[member] = nextSource;
        changed = true;
      }
      if (changed) {
        await _refreshSeries();
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
