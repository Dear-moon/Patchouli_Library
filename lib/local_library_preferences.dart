import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'book_search.dart';
import 'book_text_encoding.dart';
import 'local_import_options.dart';
import 'local_text_rules.dart';
import 'book_grid_density.dart';
import 'book_collection_mode.dart';
import 'book_shelf_preferences.dart';
import 'book_shelf_content_preferences.dart';

enum LocalLibraryView { shelf, list, grid, shelfGrid }

enum LocalLibrarySort { recentAdded, recentRead, title }

typedef _AssignmentState = ({String group, int at, bool available});

/// Device layout stays local; named groups and timestamped assignments can be
/// merged with the original books. Deletion tombstones prevent resurrection.
class LocalLibraryPreferences extends ChangeNotifier {
  LocalLibraryPreferences(this.preferences);
  static const key = 'localLibraryView.v1';
  static const all = '_all', unfiled = '_unfiled';
  static const _authorPrefix = '_author:';
  static String authorName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return name.isEmpty || name == '本地书籍' ? '未知作者' : name;
  }

  static String authorCategory(String author) =>
      '$_authorPrefix${Uri.encodeComponent(authorName(author))}';
  static String? categoryAuthor(String category) {
    if (!category.startsWith(_authorPrefix)) return null;
    try {
      final name = Uri.decodeComponent(
        category.substring(_authorPrefix.length),
      );
      return name.isNotEmpty ? name : null;
    } on FormatException {
      return null;
    }
  }

  bool matchesCategory(Novel book, String category) {
    if (categoryAuthor(category) case final author?) {
      return authorName(book.author) == author;
    }
    return category == all || groupOf(book.id) == category;
  }

  final SharedPreferences preferences;
  LocalLibraryView view = LocalLibraryView.shelf;
  BookGridDensity gridDensity = const BookGridDensity.auto();
  BookShelfPreferences shelfPreferences = const BookShelfPreferences.defaults();
  BookShelfContentPreferences shelfContent =
      const BookShelfContentPreferences.defaults();
  LocalLibrarySort sort = LocalLibrarySort.recentAdded;
  String selected = all;
  String readingFilter = 'all';
  String shelfSelected = all;
  final Map<String, Map<String, dynamic>> _groups = {};
  final Map<int, Map<String, dynamic>> _assignments = {};
  final _assignmentRevisions = <int, int>{};
  int _nextAssignmentRevision = 0;
  int _clock = 0;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  Map<String, String> get groups => {
    for (final entry in _groups.entries)
      if (entry.value['deleted'] != true)
        entry.key: entry.value['name'] as String,
  };
  bool _hasGroup(String id) {
    final group = _groups[id];
    return group != null && group['deleted'] != true;
  }

  String groupOf(int id) {
    final value = _assignments[id]?['group'];
    return value is String && _hasGroup(value) ? value : unfiled;
  }

  /// An in-memory guard for delayed edits, not a value to persist or synchronize.
  /// Explicit assignments advance it even when their visible group stays equal.
  int assignmentRevision(int id) => _assignmentRevisions[id] ?? 0;

  void _assignmentChanged(int id) {
    _assignmentRevisions[id] = ++_nextAssignmentRevision;
  }

  Map<int, _AssignmentState> _assignmentState() => {
    for (final entry in _assignments.entries)
      entry.key: (
        group: entry.value['group'] as String,
        at: entry.value['at'] as int,
        available: _hasGroup(entry.value['group'] as String),
      ),
  };

  String nameOf(String id) => id == all
      ? '全部书籍'
      : id == unfiled
      ? '未分类'
      : categoryAuthor(id) != null
      ? '作者 · ${categoryAuthor(id)}'
      : _hasGroup(id)
      ? _groups[id]!['name'] as String
      : '全部书籍';
  BookCollectionMode get viewMode =>
      BookCollectionMode.parseOrDefault(view.name);
  bool showsShelf(int count) =>
      viewMode.hasShelf && shelfPreferences.featuredCount(count) > 0;
  void refresh() {
    load();
    if (!_disposed) notifyListeners();
  }

  String get encoding {
    final value = preferences.getString('localTxtEncoding');
    return localTextEncodingOptions.containsKey(value) ? value! : 'auto';
  }

  Future<void> setEncoding(String value) async {
    if (!localTextEncodingOptions.containsKey(value)) {
      throw const FormatException('不支持的文本编码');
    }
    if (!await preferences.setString('localTxtEncoding', value)) {
      throw const FormatException('编码设置保存失败');
    }
    if (!_disposed) notifyListeners();
  }

  bool get linkLocalBooks =>
      preferences.getBool('linkLocalBooks.v1') ??
      preferences.getBool('linkLocalTxt.v1') ??
      true;
  bool get linkLocalText => linkLocalBooks;
  Future<void> setLinkLocalText(bool value) => setLinkLocalBooks(value);
  Future<void> setLinkLocalBooks(bool value) async {
    if (!await preferences.setBool('linkLocalBooks.v1', value)) {
      throw const FormatException('保存方式设置未保存，请重试');
    }
    if (!_disposed) notifyListeners();
  }

  LocalImportOptions get importOptions => LocalImportOptions.decode(
    preferences.getString(LocalImportOptions.preferenceKey),
  );
  Future<void> setImportOptions(LocalImportOptions value) async {
    final checked = LocalImportOptions.fromJson(value.toJson());
    final validation = await LocalTextRuleMatcher.start(checked);
    await validation.close();
    if (!await preferences.setString(
      LocalImportOptions.preferenceKey,
      checked.encode(),
    )) {
      throw const FormatException('导入目录设置保存失败');
    }
    if (!_disposed) notifyListeners();
  }

  void load() {
    final text = preferences.getString(key);
    if (text == null) return;
    final raw = jsonDecode(text);
    if (raw is! Map || raw['version'] != 1) {
      throw const FormatException('本地分类记录格式有误');
    }
    view = LocalLibraryView.values.firstWhere(
      (v) => v.name == raw['view'],
      orElse: () => LocalLibraryView.shelf,
    );
    gridDensity = BookGridDensity.parseOrAuto(raw['gridDensity']);
    shelfPreferences = BookShelfPreferences.parseOrDefault(
      raw['shelfPreferences'],
    );
    shelfContent = BookShelfContentPreferences.parseOrDefault(
      raw['shelfContent'],
    );
    sort = LocalLibrarySort.values.firstWhere(
      (v) => v.name == raw['sort'],
      orElse: () => LocalLibrarySort.recentAdded,
    );
    readingFilter =
        ['unread', 'reading', 'finished'].contains(raw['readingFilter'])
        ? raw['readingFilter'] as String
        : 'all';
    _accept(raw['organization']);
    selected = raw['selected'] is String ? raw['selected'] : all;
    if (selected != all &&
        selected != unfiled &&
        categoryAuthor(selected) == null &&
        !groups.containsKey(selected)) {
      selected = all;
    }
    shelfSelected = raw['shelfSelected'] is String ? raw['shelfSelected'] : all;
    if (shelfSelected != all &&
        shelfSelected != unfiled &&
        categoryAuthor(shelfSelected) == null &&
        !groups.containsKey(shelfSelected)) {
      shelfSelected = all;
    }
    shelfContent = _visibleShelfContent(shelfContent);
  }

  BookShelfContentPreferences _visibleShelfContent(
    BookShelfContentPreferences value,
  ) {
    final category = value.category;
    return category == all ||
            category == unfiled ||
            categoryAuthor(category) != null ||
            _hasGroup(category)
        ? value
        : value.copyWith(category: all);
  }

  int _stamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _clock = now > _clock ? now : _clock + 1;
  }

  Map<String, Object> exportOrganization() => {
    'version': 1,
    'groups': {
      for (final e in _groups.entries)
        e.key: Map<String, dynamic>.from(e.value),
    },
    'assignments': {
      for (final e in _assignments.entries)
        '${e.key}': Map<String, dynamic>.from(e.value),
    },
  };

  static Map<String, dynamic> validateOrganization(Object? input) {
    if (input is! Map ||
        input['version'] != 1 ||
        input['groups'] is! Map ||
        input['assignments'] is! Map ||
        input['groups'].length > 1000 ||
        input['assignments'].length > 10000) {
      throw const FormatException('同步分类数据格式有误');
    }
    final result = <String, dynamic>{
      'version': 1,
      'groups': <String, dynamic>{},
      'assignments': <String, dynamic>{},
    };
    for (final e in (input['groups'] as Map).entries) {
      final v = e.value;
      if (e.key is! String ||
          e.key.length > 80 ||
          e.key.startsWith('_') ||
          v is! Map ||
          v['name'] is! String ||
          (v['name'] as String).trim().isEmpty ||
          v['name'].length > 30 ||
          v['at'] is! int ||
          v['at'] < 0 ||
          (v['deleted'] != null && v['deleted'] is! bool)) {
        throw const FormatException('同步分类数据格式有误');
      }
      result['groups'][e.key] = {
        'name': v['name'].trim(),
        'at': v['at'],
        'deleted': v['deleted'] == true,
      };
    }
    for (final e in (input['assignments'] as Map).entries) {
      final id = e.key is String ? int.tryParse(e.key) : null, v = e.value;
      if (id == null ||
          id > 0x7fffffff ||
          id <= 0 ||
          v is! Map ||
          v['group'] is! String ||
          v['group'].length > 80 ||
          v['at'] is! int ||
          v['at'] < 0) {
        throw const FormatException('同步书籍分类格式有误');
      }
      result['assignments']['$id'] = {'group': v['group'], 'at': v['at']};
    }
    return result;
  }

  void _accept(Object? raw, {bool replace = false}) {
    final valid = validateOrganization(raw);
    final before = _assignmentState();
    if (replace) {
      _groups.clear();
      _assignments.clear();
    }
    void accept<K>(
      Map<K, Map<String, dynamic>> target,
      K key,
      Map<String, dynamic> incoming,
    ) {
      final previous = target[key];
      if (previous == null ||
          (incoming['at'] as int) > (previous['at'] as int) ||
          (incoming['at'] == previous['at'] &&
              jsonEncode(incoming).compareTo(jsonEncode(previous)) > 0)) {
        target[key] = incoming;
      }
      if (incoming['at'] > _clock) _clock = incoming['at'];
    }

    for (final e in (valid['groups'] as Map<String, dynamic>).entries) {
      accept(_groups, e.key, Map<String, dynamic>.from(e.value));
    }
    for (final e in (valid['assignments'] as Map<String, dynamic>).entries) {
      accept(
        _assignments,
        int.parse(e.key),
        Map<String, dynamic>.from(e.value),
      );
    }
    final after = _assignmentState();
    for (final id in {...before.keys, ...after.keys}) {
      if (before[id] != after[id]) _assignmentChanged(id);
    }
  }

  Future<T> _organize<T>(Future<T> Function() action) {
    final work = _writes.catchError((Object _) {}).then((_) => action());
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<void> _replaceOrganization(Map<String, dynamic> valid) async {
    final record = jsonDecode(_record()) as Map<String, dynamic>;
    bool visible(String id) =>
        id == all ||
        id == unfiled ||
        categoryAuthor(id) != null ||
        valid['groups'][id] != null && valid['groups'][id]['deleted'] != true;
    record['organization'] = valid;
    record['selected'] = visible(selected) ? selected : all;
    record['shelfSelected'] = visible(shelfSelected) ? shelfSelected : all;
    final nextShelfContent = visible(shelfContent.category)
        ? shelfContent
        : shelfContent.copyWith(category: all);
    record['shelfContent'] = nextShelfContent.toJson();
    if (!await preferences.setString(key, jsonEncode(record))) {
      throw const FormatException('本地分类保存失败');
    }
    _accept(valid, replace: true);
    selected = record['selected'];
    shelfSelected = record['shelfSelected'];
    shelfContent = nextShelfContent;
    if (!_disposed) notifyListeners();
  }

  Future<void> mergeOrganization(Object? raw) {
    final incoming = validateOrganization(raw);
    return _organize(() async {
      final next = validateOrganization(exportOrganization());
      for (final collection in ['groups', 'assignments']) {
        for (final e in (incoming[collection] as Map).entries) {
          final previous = next[collection][e.key] as Map?;
          final value = e.value as Map;
          if (previous == null ||
              value['at'] > previous['at'] ||
              value['at'] == previous['at'] &&
                  jsonEncode(value).compareTo(jsonEncode(previous)) > 0) {
            next[collection][e.key] = value;
          }
        }
      }
      await _replaceOrganization(next);
    });
  }

  Future<void> applySyncedOrganization(Object? raw, String expected) {
    final valid = validateOrganization(raw);
    return _organize(() async {
      if (jsonEncode(exportOrganization()) != expected) {
        throw const FormatException('本机分类已变化，将在下次同步合并');
      }
      await _replaceOrganization(valid);
    });
  }

  String _record({
    Map<int, Map<String, dynamic>>? assignments,
    BookShelfContentPreferences? content,
  }) => jsonEncode({
    'version': 1,
    'view': view.name,
    'gridDensity': gridDensity.value,
    'shelfPreferences': shelfPreferences.toJson(),
    'shelfContent': (content ?? shelfContent).toJson(),
    'sort': sort.name,
    'readingFilter': readingFilter,
    'selected': selected,
    'shelfSelected': shelfSelected,
    'organization': assignments == null
        ? exportOrganization()
        : {
            ...exportOrganization(),
            'assignments': {
              for (final e in assignments.entries) '${e.key}': e.value,
            },
          },
  });

  Future<void> _save() {
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (!await preferences.setString(key, _record())) {
        throw const FormatException('本地分类保存失败');
      }
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  Future<void> setView(LocalLibraryView value) {
    view = value;
    return _save();
  }

  Future<void> setViewMode(BookCollectionMode value) => setView(switch (value) {
    BookCollectionMode.list => LocalLibraryView.list,
    BookCollectionMode.shelfList => LocalLibraryView.shelf,
    BookCollectionMode.shelfGrid => LocalLibraryView.shelfGrid,
    BookCollectionMode.grid => LocalLibraryView.grid,
  });

  Future<void> setGridDensity(BookGridDensity value) {
    gridDensity = value;
    return _save();
  }

  Future<void> setShelfPreferences(BookShelfPreferences value) {
    shelfPreferences = value;
    return _save();
  }

  /// The featured region is independent of the existing lower collection.
  Future<void> setShelfContent(BookShelfContentPreferences value) =>
      restoreShelfContent(
        value,
        commit: (record) async {
          if (!await preferences.setString(key, record)) {
            throw const FormatException('本地分类保存失败');
          }
        },
      );

  /// Keeps a backup transaction on the same queue as classification edits.
  /// The record is built at commit time, so delayed restores cannot replace
  /// newer categories or assignments with an earlier organization snapshot.
  Future<void> restoreShelfContent(
    BookShelfContentPreferences value, {
    required Future<void> Function(String record) commit,
  }) => _organize(() async {
    final next = _visibleShelfContent(value);
    await commit(_record(content: next));
    shelfContent = next;
    if (!_disposed) notifyListeners();
  });

  Future<void> setSort(LocalLibrarySort value) {
    sort = value;
    return _save();
  }

  Future<void> setReadingFilter(String value) {
    if (!['all', 'unread', 'reading', 'finished'].contains(value)) {
      throw const FormatException('阅读状态无效');
    }
    readingFilter = value;
    return _save();
  }

  Future<void> select(String value, {bool shelf = false}) {
    if (value != all &&
        value != unfiled &&
        categoryAuthor(value) == null &&
        !groups.containsKey(value)) {
      throw const FormatException('分类不存在');
    }
    if (shelf) {
      shelfSelected = value;
    } else {
      selected = value;
    }
    return _save();
  }

  Future<String> addGroup(String name) {
    name = name.trim();
    if (name.isEmpty || name.length > 30) {
      throw const FormatException('分类名称需要 1～30 个字');
    }
    return _organize(() async {
      if (groups.values.contains(name)) throw const FormatException('已有同名分类');
      if (groups.length >= 100 || _groups.length >= 1000) {
        throw const FormatException('分类记录已满，请合并现有分类');
      }
      final random = Random.secure();
      final at = _stamp(),
          id =
              'g${_clock.toRadixString(36)}-${random.nextInt(0x100000000).toRadixString(36)}${random.nextInt(0x100000000).toRadixString(36)}';
      final next = validateOrganization(exportOrganization());
      next['groups'][id] = {'name': name, 'at': at, 'deleted': false};
      await _replaceOrganization(next);
      return id;
    });
  }

  Future<void> renameGroup(String id, String name) {
    name = name.trim();
    return _organize(() async {
      if (!groups.containsKey(id) || name.isEmpty || name.length > 30) {
        throw const FormatException('分类名称需要 1～30 个字');
      }
      if (groups.entries.any((e) => e.key != id && e.value == name)) {
        throw const FormatException('已有同名分类');
      }
      final next = validateOrganization(exportOrganization());
      next['groups'][id] = {'name': name, 'at': _stamp(), 'deleted': false};
      await _replaceOrganization(next);
    });
  }

  Future<void> removeGroup(String id) {
    return _organize(() async {
      if (!groups.containsKey(id)) return;
      final next = validateOrganization(exportOrganization());
      next['groups'][id] = {..._groups[id]!, 'at': _stamp(), 'deleted': true};
      await _replaceOrganization(next);
    });
  }

  Future<void> assign(int book, String group) => assignMany([book], group);

  /// One durable record and one notification, even for a large selection.
  /// Failed writes leave every book in its previous category.
  /// [expectedRevisions] protects delayed operations: only IDs whose revision
  /// still matches are assigned; skipped IDs cause no write or notification.
  /// Existing callers omit it and retain unconditional explicit assignment.
  Future<void> assignMany(
    Iterable<int> books,
    String group, {
    Map<int, int>? expectedRevisions,
  }) {
    final ids = books.toSet();
    final expected = expectedRevisions == null
        ? null
        : Map<int, int>.of(expectedRevisions);
    final work = _writes.catchError((Object _) {}).then((_) async {
      if (ids.any((id) => id <= 0 || id > 0x7fffffff) ||
          (expected == null && group != unfiled && !_hasGroup(group))) {
        throw const FormatException('请选择有效分类');
      }
      final targets = expected == null
          ? ids
          : ids.where((id) => expected[id] == assignmentRevision(id)).toSet();
      if (targets.isEmpty) return;
      if (group != unfiled && !_hasGroup(group)) {
        throw const FormatException('请选择有效分类');
      }
      final at = _stamp();
      final next = {
        ..._assignments,
        for (final id in targets)
          id: <String, dynamic>{'group': group, 'at': at},
      };
      if (!await preferences.setString(key, _record(assignments: next))) {
        throw const FormatException('本地分类保存失败');
      }
      _assignments.addAll({for (final id in targets) id: next[id]!});
      for (final id in targets) {
        _assignmentChanged(id);
      }
      if (!_disposed) notifyListeners();
    });
    _writes = work;
    return work;
  }

  List<Novel> filter(
    Iterable<Novel> books, {
    String query = '',
    int Function(int)? readAt,
    int Function(int)? addedAt,
  }) {
    final pattern = BookSearch(query);
    final result = books.where((book) {
      // Looking up one assignment must not materialize every category.
      // With no query/filter, the book metadata needs no matching work.
      if (selected == all && pattern.terms.isEmpty) return true;
      final group = groupOf(book.id);
      if (!matchesCategory(book, selected)) return false;
      return pattern.terms.isEmpty ||
          pattern.matches(
            title: book.title,
            author: book.author,
            tags: book.genre,
            id: '${book.id}',
            classification: nameOf(group),
          );
    }).toList();
    result.sort((a, b) {
      final order = switch (sort) {
        LocalLibrarySort.title => a.title.compareTo(b.title),
        LocalLibrarySort.recentRead => (readAt?.call(b.id) ?? 0).compareTo(
          readAt?.call(a.id) ?? 0,
        ),
        LocalLibrarySort.recentAdded => (addedAt?.call(b.id) ?? 0).compareTo(
          addedAt?.call(a.id) ?? 0,
        ),
      };
      return order != 0 ? order : a.title.compareTo(b.title);
    });
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
