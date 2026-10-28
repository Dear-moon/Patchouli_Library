import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_replica.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_library_preferences.dart';
import 'local_coordinate_upgrade.dart';

export 'library_replica.dart' show LibraryVariant;

({LibraryReplica replica, String? encoded}) _captureReplica(
  ({
    LibraryReplica replica,
    Map<String, Map<String, dynamic>?> snapshot,
    Set<String> concurrent,
  })
  input,
) {
  final next = input.replica.fork();
  return next.capture(input.snapshot, concurrentKeys: input.concurrent)
      ? (replica: next, encoded: jsonEncode(next.toJson()))
      : (replica: input.replica, encoded: null);
}

String _encodeReplica(LibraryReplica value) => jsonEncode(value.toJson());

/// One journal owns bookmark/category replication. Pairing, encrypted transport
/// and foreground policy remain with the existing LAN service.
class LibraryIncrementalSync extends ChangeNotifier {
  LibraryIncrementalSync({
    required this.actor,
    required this.state,
    required this.preferences,
    this.books,
  });
  static const key = 'librarySync.records.v1',
      pendingKey = 'librarySync.pending.v1';
  final String actor;
  final LibraryState state;
  final SharedPreferences preferences;
  final LocalBookStore? books;
  late LibraryReplica _replica;
  bool _loaded = false, _disposed = false;
  Future<void> _writes = Future.value();
  final _blocked = <String>{};
  final _incompatible = <String>{};
  List<String> get conflicts => !_loaded ? const [] : _replica.conflicts;
  List<LibraryVariant> alternatives(String id) =>
      List.unmodifiable(_replica.records[id] ?? const []);
  LibraryVariant? current(String id) =>
      _replica.records.containsKey(id) ? _replica.winner(id) : null;
  int get pendingBooks =>
      _blocked.map((key) => key.split('/')[1]).toSet().length;
  String title(String id) {
    final parts = id.split('/');
    if (parts.first == 'b') {
      return state.cachedNovel(int.parse(parts[1]))?.title ??
          books?.book(int.parse(parts[1]))?.title ??
          '书签';
    }
    if (parts.first == 'a') {
      return books?.book(int.parse(parts[1]))?.title ??
          state.cachedNovel(int.parse(parts[1]))?.title ??
          '书籍分类';
    }
    return '分类名称';
  }

  String describe(LibraryVariant variant) {
    final value = variant.value;
    if (variant.deleted) return '已删除';
    if (value?['mark'] is Map) {
      final mark = value!['mark'] as Map;
      return '${mark['category'] == null || mark['category'] == '' ? '未分类' : mark['category']} · ${mark['quote'] ?? mark['chapterTitle']}';
    }
    if (value?['name'] is String) return value!['name'];
    final group = value?['group'];
    return group is String ? state.organization.nameOf(group) : '未分类';
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.catchError((Object _) {}).then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> initialize() => _serialize(() async {
    if (_loaded) return;
    _replica = LibraryReplica.decode(actor, preferences.getString(key));
    _loaded = true;
    try {
      await _capture();
    } catch (_) {
      _loaded = false;
      rethrow;
    }
  });
  Map<String, Map<String, dynamic>?> _snapshot() {
    final values = <String, Map<String, dynamic>?>{};
    final identities = <int, String?>{};
    for (final entry in state.bookmarkEntries) {
      final id = entry.novelId;
      final name = 'b/$id/${Uri.encodeComponent(entry.bookmark.id)}';
      final identity = isLocalBook(id)
          ? identities.putIfAbsent(id, () => books?.readingIdentity(id))
          : 'wenku8:$id';
      final knownIdentity = _replica.records.containsKey(name)
          ? (_replica.winner(name).value?['identity'] as String?)
          : null;
      values[name] = {
        'mark': entry.bookmark.toJson(),
        'identity': ?identity ?? knownIdentity,
      };
    }
    final organization = state.organization.exportOrganization();
    for (final e in (organization['groups'] as Map).entries) {
      values['g/${Uri.encodeComponent(e.key)}'] = Map<String, dynamic>.from(
        e.value,
      );
    }
    for (final e in (organization['assignments'] as Map).entries) {
      values['a/${e.key}'] = Map<String, dynamic>.from(e.value);
    }
    _incompatible.clear();
    for (final name in _replica.records.keys.where(
      (name) => name.startsWith('b/'),
    )) {
      final id = int.parse(name.split('/')[1]);
      if (!isLocalBook(id) || books?.contains(id) != true) continue;
      final winner = _replica.winner(name).value;
      final identity = identities.putIfAbsent(
        id,
        () => books!.readingIdentity(id),
      );
      if (winner == null ||
          winner['identity'] == null ||
          winner['identity'] == identity) {
        continue;
      }
      _incompatible.add(name);
      final local = values[name];
      final sameLayout = _replica.records[name]!.where(
        (v) => v.value?['identity'] == identity,
      );
      if (local == null && sameLayout.isEmpty ||
          sameLayout.any((v) => replicaJson(v.value) == replicaJson(local))) {
        values[name] = winner;
      }
    }
    return values;
  }

  Future<void> _capture() async {
    final pending = preferences.getString(pendingKey);
    if (pending != null) {
      // A storage failure can recover on the next exchange without requiring
      // an app restart. Capture intervening local edits before the retry.
      final recovering = LibraryReplica.decode(actor, pending);
      final snapshot = _snapshot();
      final next = _replica.fork()
        ..capture(snapshot, concurrentKeys: _incompatible);
      next.merge(recovering.toJson()['records']);
      await _commit(next);
    }
    if (books != null) await normalizeLocalReadingRecords(books!, state);
    final snapshot = _snapshot();
    final result = snapshot.length > 16 || _replica.records.length > 16
        ? await compute(_captureReplica, (
            replica: _replica,
            snapshot: snapshot,
            concurrent: _incompatible,
          ))
        : _captureReplica((
            replica: _replica,
            snapshot: snapshot,
            concurrent: _incompatible,
          ));
    if (result.encoded == null) return;
    if (!await preferences.setString(key, result.encoded!)) {
      throw const FormatException('同步记录未保存');
    }
    _replica = result.replica;
  }

  Future<Map<String, Object>> packet(Object? acknowledged) =>
      _serialize(() async {
        if (!_loaded) throw const FormatException('同步尚未准备好');
        await _capture();
        return {
          'versions': _replica.versions,
          'records': _replica.delta(acknowledged),
        };
      });
  Future<void> receive(Object? packet) => _serialize(() async {
    if (packet == null) return; // Compatible with previous LAN clients.
    if (packet is! Map ||
        packet['records'] is! Map ||
        packet['versions'] is! Map) {
      throw const FormatException('同步书签与分类格式有误');
    }
    await _capture();
    final next = _replica.fork();
    next.merge(packet['records']);
    await _commit(next);
  });
  Future<void> resolve(String id, LibraryVariant variant) =>
      _serialize(() async {
        await _capture();
        if (!_replica.records[id]!.any((v) => v.version == variant.version)) {
          throw const FormatException('冲突已变化，请刷新后重试');
        }
        final next = _replica.fork();
        next.edit(id, variant.value);
        await _commit(next);
      });
  Future<void> _commit(LibraryReplica next) async {
    final byBook = <int, Map<String, ReaderBookmark>>{};
    final expected = <int, String>{};
    final organization = state.organization.exportOrganization();
    final expectedOrganization = jsonEncode(organization);
    final groups = Map<String, dynamic>.from(organization['groups'] as Map);
    final assignments = Map<String, dynamic>.from(
      organization['assignments'] as Map,
    );
    final blocked = <String>{};
    for (final name in next.records.keys) {
      final parts = name.split('/'),
          variant = next.winner(name),
          value = variant.value;
      switch (parts.first) {
        case 'b':
          final id = int.parse(parts[1]),
              markId = Uri.decodeComponent(parts[2]);
          final identity = value?['identity'];
          if (isLocalBook(id) &&
              value != null &&
              books?.contains(id) == true &&
              identity != null &&
              identity != books!.readingIdentity(id)) {
            blocked.add(name);
            continue;
          }
          final marks = byBook.putIfAbsent(id, () {
            final current = state.bookmarksFor(id);
            expected[id] = jsonEncode(current.map((m) => m.toJson()).toList());
            return {for (final mark in current) mark.id: mark};
          });
          if (value == null) {
            marks.remove(markId);
          } else {
            if (value['mark'] is! Map) throw const FormatException('同步书签格式有误');
            final mark = ReaderBookmark.fromJson(
              Map<String, dynamic>.from(value['mark']),
            );
            if (mark.id != markId) throw const FormatException('同步书签标识不一致');
            marks[mark.id] = mark;
          }
        case 'g':
          final id = Uri.decodeComponent(parts[1]);
          if (value == null) {
            if (groups[id] != null) {
              groups[id] = {...groups[id] as Map, 'deleted': true};
            }
          } else {
            groups[id] = value;
          }
        case 'a':
          if (value == null) {
            assignments.remove(parts[1]);
          } else {
            assignments[parts[1]] = value;
          }
      }
    }
    final nextOrganization = LocalLibraryPreferences.validateOrganization({
      'version': 1,
      'groups': groups,
      'assignments': assignments,
    });
    final updates = <int, List<ReaderBookmark>>{
      for (final e in byBook.entries)
        if (jsonEncode(e.value.values.map((m) => m.toJson()).toList()) !=
            expected[e.key])
          e.key: e.value.values.toList(),
    };
    final organizationChanged =
        replicaJson(nextOrganization) != replicaJson(organization);
    if (updates.isEmpty &&
        !organizationChanged &&
        mapEquals(next.versions, _replica.versions) &&
        setEquals(blocked, _blocked) &&
        !preferences.containsKey(pendingKey)) {
      return;
    }
    final encoded = next.records.length > 16
        ? await compute(_encodeReplica, next)
        : _encodeReplica(next);
    if (!await preferences.setString(pendingKey, encoded)) {
      throw const FormatException('同步恢复记录未保存');
    }
    if (updates.isNotEmpty) await state.applySyncedBookmarks(updates, expected);
    if (organizationChanged) {
      await state.organization.applySyncedOrganization(
        nextOrganization,
        expectedOrganization,
      );
    }
    if (!await preferences.setString(key, encoded)) {
      throw const FormatException('同步记录未保存，下次会继续合并');
    }
    _replica = next;
    _blocked
      ..clear()
      ..addAll(blocked);
    await preferences.remove(pendingKey);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
