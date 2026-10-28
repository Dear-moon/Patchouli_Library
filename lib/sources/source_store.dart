import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:path_provider/path_provider.dart';

import '../catalog.dart';
import 'book_source.dart';
import 'source_declarations.dart';

class _SourceIndexWrite {
  const _SourceIndexWrite(this.metadata, this.chapterIds, this.directories);
  final Map<String, Object?> metadata;
  final Map<int, Map<String, int>> chapterIds;
  final Map<int, List<NovelChapter>> directories;
}

String _encodeSourceIndex(_SourceIndexWrite write) => jsonEncode({
  ...write.metadata,
  'chapterIds': {for (final e in write.chapterIds.entries) '${e.key}': e.value},
  'directories': {
    for (final e in write.directories.entries)
      '${e.key}': [
        for (final c in e.value)
          {
            'id': c.id,
            'title': c.title,
            'url': c.url,
            'volumeId': c.volumeId,
            'volumeTitle': c.volumeTitle,
          },
      ],
  },
});
Map<String, dynamic> _decodeSourceIndex(String data) =>
    jsonDecode(data) as Map<String, dynamic>;

/// One atomic index owns identities. Existing shelf/progress/bookmark keys and
/// wenku8-offline-v1 are not rewritten by the 0.4 migration.
class SourceStore extends ChangeNotifier {
  SourceStore(this.file);
  final File file;
  final _sources = <BookSource>[];
  final _books = <int, Novel>{};
  final _chapterIds = <int, Map<String, int>>{};
  final _directories = <int, List<NovelChapter>>{};
  final _identities = <String, int>{};
  int _nextId = 0x20000000;
  Future<void> _writes = Future.value();
  String? selectedSource;
  String? selectedExplore;
  List<BookSource> get sources => List.unmodifiable(_sources);
  List<BookSource> get enabled => _sources.where((s) => s.enabled).toList();
  Novel? book(int id) => _books[id];
  Iterable<Novel> get books => _books.values;
  BookSource? source(String? key) =>
      _sources.where((s) => s.key == key).firstOrNull;
  List<NovelChapter>? directory(int id) => _directories[id];

  static Future<SourceStore> forApp() async {
    final root = await getApplicationSupportDirectory();
    return SourceStore(File('${root.path}/custom-sources-v1/index.json'));
  }

  Future<void>? _ready;
  Future<void> load() =>
      _ready ??= _load().catchError((Object e, StackTrace s) {
        _ready = null;
        Error.throwWithStackTrace(e, s);
      });
  Future<void> _load() async {
    if (!await file.exists()) return;
    final text = await file.readAsString();
    final decoded = text.length > 128 * 1024
        ? await compute(_decodeSourceIndex, text)
        : _decodeSourceIndex(text);
    if (decoded['version'] != 1) {
      throw const FormatException('书源数据版本无法识别，原文件已保留');
    }
    final sources = [
      for (final s in decoded['sources'] as List)
        BookSource(Map<String, dynamic>.from(s)),
    ];
    final books = <int, Novel>{};
    final ids = <String, int>{};
    for (final raw in decoded['books'] as List) {
      final value = Map<String, dynamic>.from(raw);
      value['author'] = sourceAuthorName('${value['author'] ?? ''}');
      final book = Novel.fromSnapshot(value);
      if (book.sourceId == null ||
          book.bookUrl == null ||
          books.containsKey(book.id)) {
        throw const FormatException('书源书籍索引损坏，原文件已保留');
      }
      books[book.id] = book;
      ids[_key(book.sourceId!, book.bookUrl!)] = book.id;
    }
    final canonical = decoded['identities'];
    if (canonical is Map) {
      ids.clear();
      for (final e in canonical.entries) {
        if (e.key is! String ||
            e.value is! int ||
            !books.containsKey(e.value)) {
          throw const FormatException('书籍来源索引无效，原文件已保留');
        }
        ids[e.key as String] = e.value as int;
      }
    }
    final chapterIds = <int, Map<String, int>>{};
    final directories = <int, List<NovelChapter>>{};
    for (final entry in (decoded['chapterIds'] as Map? ?? {}).entries) {
      chapterIds[int.parse(entry.key)] = Map.unmodifiable(
        Map<String, int>.from(entry.value),
      );
    }
    for (final entry in (decoded['directories'] as Map? ?? {}).entries) {
      directories[int.parse(entry.key)] = List.unmodifiable([
        for (final c in entry.value as List)
          NovelChapter(
            c['title'],
            '',
            id: c['id'],
            url: c['url'],
            volumeId: c['volumeId'] ?? 0,
            volumeTitle: c['volumeTitle'] ?? '',
          ),
      ]);
    }
    _sources
      ..clear()
      ..addAll(sources);
    SourceDeclarations.register(_sources);
    _books
      ..clear()
      ..addAll(books);
    _identities
      ..clear()
      ..addAll(ids);
    _chapterIds
      ..clear()
      ..addAll(chapterIds);
    _directories
      ..clear()
      ..addAll(directories);
    _nextId = decoded['nextId'] as int;
    if (_nextId < 0x20000000 ||
        _nextId >= 0x60000000 ||
        books.keys.any((id) => id >= _nextId && id >= 0x20000000)) {
      throw const FormatException('书源标识索引无效，原文件已保留');
    }
    selectedSource = decoded['selectedSource'] as String?;
    selectedExplore = decoded['selectedExplore'] as String?;
  }

  static String _key(String source, String url) => jsonEncode([source, url]);

  /// Restored metadata keeps the original numeric key used by shelf and
  /// bookmarks. Reserve all keys before allocating any new search result.
  void reserveBooks(Iterable<Novel> books) {
    for (final book in books) {
      if (book.sourceId == null || book.bookUrl == null) continue;
      final key = _key(book.sourceId!, book.bookUrl!);
      final previous = _books[book.id];
      if (previous != null &&
          (previous.sourceId != book.sourceId ||
              previous.bookUrl != book.bookUrl)) {
        throw const FormatException('恢复的书籍标识与现有书库冲突，请先备份当前书库');
      }
      _books.putIfAbsent(book.id, () => book);
      _identities.putIfAbsent(key, () => book.id);
      if (book.id >= _nextId && book.id < 0x60000000) _nextId = book.id + 1;
    }
  }

  Future<void> saveSources(
    List<BookSource> incoming, {
    bool replace = true,
  }) async {
    await load();
    final next = [..._sources];
    for (final source in incoming) {
      final index = next.indexWhere((s) => s.key == source.key);
      if (index < 0) {
        next.add(source);
      } else if (replace) {
        // Rule updates do not silently re-enable a user-disabled source.
        next[index] = source.copyWith(enabled: next[index].enabled);
      }
    }
    final old = [..._sources];
    _sources
      ..clear()
      ..addAll(next);
    try {
      await _save();
    } catch (_) {
      _sources
        ..clear()
        ..addAll(old);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> remove(BookSource source) async {
    final index = _sources.indexWhere((s) => s.key == source.key);
    if (index < 0) return;
    _sources.removeAt(index);
    try {
      await _save();
    } catch (_) {
      _sources.insert(index, source);
      rethrow;
    }
    // Metadata, chapter identities and caches outlive removal of a source.
    notifyListeners();
  }

  Future<void> configure(BookSource value) async {
    final index = _sources.indexWhere((s) => s.key == value.key);
    if (index < 0) return;
    final old = _sources[index];
    _sources[index] = value;
    try {
      await _save();
    } catch (_) {
      _sources[index] = old;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> reorder(List<BookSource> sources) async {
    if (!setEquals(
          sources.map((s) => s.key).toSet(),
          _sources.map((s) => s.key).toSet(),
        ) ||
        sources.length != _sources.length) {
      throw const FormatException('书源排序包含未知或重复项目');
    }
    final old = [..._sources];
    _sources
      ..clear()
      ..addAll(sources);
    SourceDeclarations.register(_sources);
    try {
      await _save();
    } catch (_) {
      _sources
        ..clear()
        ..addAll(old);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> select(String? key, String? explore) async {
    if (selectedSource == key && selectedExplore == explore) return;
    final previousSource = selectedSource, previousExplore = selectedExplore;
    selectedSource = key;
    selectedExplore = explore;
    try {
      await _save();
    } catch (_) {
      selectedSource = previousSource;
      selectedExplore = previousExplore;
      rethrow;
    }
    notifyListeners();
  }

  Novel remember(BookSource source, Map<String, dynamic> value) {
    final url = '${value['bookUrl'] ?? ''}';
    if (url.isEmpty) throw const FormatException('书籍没有详情地址');
    final identity = _key(source.key, url);
    final id = _identities[identity] ??= _bookId(source, url, identity);
    final previous = _books[id];
    String text(String key, String old) =>
        '${value[key] ?? ''}'.trim().isEmpty ? old : '${value[key]}'.trim();
    final book = Novel(
      id: id,
      title: text('name', previous?.title ?? ''),
      author: sourceAuthorName(text('author', previous?.author ?? '')),
      genre: text('kind', previous?.genre ?? ''),
      summary: text('intro', previous?.summary ?? ''),
      colors: previous?.colors ?? const [Color(0xFF353A42), Color(0xFF555961)],
      coverUrl: text('coverUrl', previous?.coverUrl ?? '').isEmpty
          ? null
          : text('coverUrl', previous?.coverUrl ?? ''),
      lastUpdate: text('lastChapter', previous?.lastUpdate ?? ''),
      isComplete: value['complete'] is bool
          ? value['complete'] as bool
          : previous?.isComplete ?? false,
      sourceId: source.key,
      bookUrl: url,
      tocUrl: text('tocUrl', previous?.tocUrl ?? url),
      authorUrl: value.containsKey('authorUrl')
          ? value['authorUrl'] as String?
          : previous?.authorUrl,
      tagUrls: value['tagUrls'] is Map
          ? Map.unmodifiable(Map<String, String>.from(value['tagUrls'] as Map))
          : previous?.tagUrls ?? const {},
      chapters: _directories[id] ?? previous?.chapters ?? const [],
      chapterCount: _directories[id]?.length ?? previous?.chapterCount ?? 0,
    );
    if (book.title.isEmpty) throw const FormatException('书籍没有名称，请检查书名规则');
    _books[id] = book;
    return book;
  }

  int _bookId(BookSource source, String url, String identity) {
    final pattern =
        SourceDeclarations.section(source.key, 'identity')['bookIdPattern']
            as String?;
    if (pattern == null) return _allocate();
    final match = RegExp(pattern).firstMatch(url);
    if (match == null) throw const FormatException('书籍地址不符合声明的 ID 规则');
    final id = int.parse(match.group(1)!);
    if (id <= 0 || id >= 0x20000000) {
      throw const FormatException('声明的书籍 ID 超出保留范围');
    }
    if (_identities.entries.any(
      (entry) => entry.value == id && entry.key != identity,
    )) {
      throw const FormatException('声明的书籍 ID 与其他书源冲突');
    }
    return id;
  }

  int _allocate() {
    if (_nextId >= 0x60000000) throw const FormatException('书籍标识空间已满');
    return _nextId++;
  }

  Future<List<NovelChapter>> rememberChapters(
    int id,
    List<Map<String, dynamic>> values,
  ) async {
    final stable = Map<String, int>.of(_chapterIds[id] ?? const {});
    var next = stable.values.fold(0, (a, b) => a > b ? a : b) + 1;
    final seen = <String>{};
    final chapters = <NovelChapter>[];
    var volume = '', volumeId = 0;
    final volumeIds = <String, int>{};
    for (final value in values) {
      final title = '${value['name'] ?? ''}'.trim();
      if (value['isVolume'] == true) {
        volume = title;
        volumeId = volumeIds.putIfAbsent(volume, () => volumeIds.length + 1);
        continue;
      }
      // Per-chapter ownership also survives a reversed directory or rules that
      // select chapter links but deliberately omit their volume headers.
      final ownVolume = value['volumeTitle'];
      if (ownVolume is String) {
        volume = ownVolume.trim();
        volumeId = volume.isEmpty
            ? 0
            : volumeIds.putIfAbsent(volume, () => volumeIds.length + 1);
      }
      final url = '${value['url'] ?? ''}';
      if (url.isEmpty || title.isEmpty || !seen.add(url)) continue;
      final idPattern =
          SourceDeclarations.section(
                _books[id]?.sourceId,
                'identity',
              )['chapterIdPattern']
              as String?;
      final declaredId = idPattern == null
          ? null
          : RegExp(idPattern).firstMatch(url);
      final cid = stable[url] ??= declaredId == null
          ? next++
          : int.parse(declaredId.group(1)!);
      chapters.add(
        NovelChapter(
          title,
          '',
          id: cid,
          url: url,
          volumeTitle: volume,
          volumeId: _books[id]?.sourceId == 'builtin:wenku8'
              ? value['volumeId'] as int
              : volumeId,
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('未解析到章节，请检查目录规则');
    _chapterIds[id] = Map.unmodifiable(stable);
    _directories[id] = List.unmodifiable(chapters);
    final book = _books[id];
    if (book != null) _books[id] = book.withChapters(chapters);
    await flush();
    return _directories[id]!;
  }

  void importIdentity(Novel book, Map<String, int> chapterIds) {
    reserveBooks([book]);
    _chapterIds[book.id] = Map.unmodifiable(chapterIds);
    _directories[book.id] = List.unmodifiable(book.chapters);
  }

  Future<void> flush() => _save();
  Future<Novel> bindLegacy(
    Novel old,
    Novel target,
    List<NovelChapter> directory,
  ) async {
    if (old.sourceId != null ||
        target.sourceId == null ||
        target.bookUrl == null) {
      throw const FormatException('只能为尚未关联书源的旧版书籍建立关联');
    }
    String title(NovelChapter c) =>
        c.title.replaceAll(RegExp(r'[\s\u3000]+'), '').trim();
    final targetNames = <String, List<NovelChapter>>{};
    for (final c in directory) {
      targetNames.putIfAbsent(title(c), () => []).add(c);
    }
    final oldIds = <String, int>{};
    for (final c in old.chapters) {
      final named = targetNames[title(c)] ?? const <NovelChapter>[];
      final sameVolume = named
          .where(
            (target) =>
                c.volumeTitle.isNotEmpty && c.volumeTitle == target.volumeTitle,
          )
          .toList();
      final matches = sameVolume.length == 1 ? sameVolume : named;
      if (matches.length != 1 ||
          matches.single.url == null ||
          oldIds.containsKey(matches.single.url)) {
        throw const FormatException('新旧目录存在无法唯一匹配的章节，未更改旧书；可将这个来源作为新书添加');
      }
      oldIds[matches.single.url!] = c.id;
    }
    final oldStable = _chapterIds[old.id];
    final stable = Map<String, int>.from(oldStable ?? {});
    var next =
        [...oldIds.values, ...stable.values].fold(0, (a, b) => a > b ? a : b) +
        1;
    final chapters = [
      for (final c in directory)
        NovelChapter(
          c.title,
          '',
          id: stable[c.url!] ??= oldIds[c.url!] ?? next++,
          url: c.url,
          volumeId: c.volumeId,
          volumeTitle: c.volumeTitle,
        ),
    ];
    final bound = Novel.fromSnapshot({
      ...target.toSnapshot(),
      'id': old.id,
    }).withChapters(chapters);
    final previousBook = _books[old.id];
    final previousDirectory = _directories[old.id];
    final identity = _key(target.sourceId!, target.bookUrl!);
    final previousIdentity = _identities[identity];
    _chapterIds[old.id] = Map.unmodifiable(stable);
    _books[old.id] = bound;
    _directories[old.id] = List.unmodifiable(chapters);
    _identities[identity] = old.id;
    try {
      await flush();
    } catch (_) {
      if (oldStable == null) {
        _chapterIds.remove(old.id);
      } else {
        _chapterIds[old.id] = oldStable;
      }
      if (previousBook == null) {
        _books.remove(old.id);
      } else {
        _books[old.id] = previousBook;
      }
      if (previousDirectory == null) {
        _directories.remove(old.id);
      } else {
        _directories[old.id] = previousDirectory;
      }
      if (previousIdentity == null) {
        _identities.remove(identity);
      } else {
        _identities[identity] = previousIdentity;
      }
      rethrow;
    }
    notifyListeners();
    return bound;
  }

  Future<void> _save() {
    final data = _SourceIndexWrite(
      {
        'version': 1,
        'nextId': _nextId,
        'sources': _sources.map((s) => s.data).toList(),
        'books': _books.values.map((b) => b.toSnapshot()).toList(),
        'identities': Map<String, int>.of(_identities),
        'selectedSource': selectedSource,
        'selectedExplore': selectedExplore,
      },
      Map.of(_chapterIds),
      Map.of(_directories),
    );
    // Directory lists and URL->ID maps are replaced, never mutated after
    // publication. A shallow snapshot is stable while encoding in an isolate.
    final chapterCount = _directories.values.fold(
      0,
      (n, rows) => n + rows.length,
    );
    final encoded =
        chapterCount > 512 || _books.length > 100 || _sources.length > 20
        ? compute(_encodeSourceIndex, data)
        : Future.value(_encodeSourceIndex(data));
    final result = Future.wait<Object?>([_writes, encoded]).then((ready) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.part');
      await temp.writeAsString(ready[1] as String, flush: true);
      await temp.rename(file.path);
      SourceDeclarations.register(_sources);
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
