import 'dart:convert';
import 'package:crypto/crypto.dart';

String replicaJson(Object? value) {
  Object? ordered(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(v[key])};
    }
    return v is List ? v.map(ordered).toList() : v;
  }

  return jsonEncode(ordered(value));
}

class LibraryVariant {
  LibraryVariant(this.clock, this.value);
  final Map<String, int> clock;
  final Map<String, dynamic>? value;
  bool get deleted => value == null || value?['deleted'] == true;
  Map<String, Object?> toJson() => {'clock': clock, 'value': value};
  // This digest is the synchronization version identity, cached once per
  // immutable record; it distinguishes same-clock conflicts without full data.
  late final String version = sha256
      .convert(utf8.encode(replicaJson(toJson())))
      .toString();
  bool dominates(LibraryVariant other) =>
      other.clock.entries.every((e) => (clock[e.key] ?? 0) >= e.value) &&
      clock.entries.any((e) => e.value > (other.clock[e.key] ?? 0));
  factory LibraryVariant.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['clock'] is! Map ||
        raw['clock'].length > 32 ||
        raw['clock'].isEmpty ||
        raw['value'] != null && raw['value'] is! Map) {
      throw const FormatException('同步版本格式有误');
    }
    final clock = <String, int>{};
    for (final e in (raw['clock'] as Map).entries) {
      if (e.key is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(e.key) ||
          e.value is! int ||
          e.value <= 0) {
        throw const FormatException('同步版本格式有误');
      }
      clock[e.key] = e.value;
    }
    return LibraryVariant(
      Map.unmodifiable(clock),
      raw['value'] == null ? null : Map<String, dynamic>.from(raw['value']),
    );
  }
}

class LibraryReplica {
  LibraryReplica(this.actor, [Map<String, List<LibraryVariant>>? records])
    : records = records ?? {};
  final String actor;
  final Map<String, List<LibraryVariant>> records;
  LibraryReplica fork() => LibraryReplica(actor, {
    for (final e in records.entries) e.key: List.of(e.value),
  });
  Map<String, Object> toJson() => {
    'version': 1,
    'actor': actor,
    'records': {
      for (final e in records.entries)
        e.key: e.value.map((v) => v.toJson()).toList(),
    },
  };
  factory LibraryReplica.decode(String actor, String? text) {
    final replica = LibraryReplica(actor);
    if (text == null) return replica;
    final value = jsonDecode(text);
    if (value is! Map || value['version'] != 1 || value['records'] is! Map) {
      throw const FormatException('同步记录读取失败，原书与书签保留');
    }
    replica.merge(value['records']);
    return replica;
  }
  static int compare(LibraryVariant a, LibraryVariant b) {
    if (a.deleted != b.deleted) return a.deleted ? 1 : -1;
    return a.version.compareTo(b.version);
  }

  LibraryVariant winner(String key) =>
      (records[key]!.toList()..sort(compare)).last;
  Map<String, String> get versions => {
    for (final e in records.entries)
      e.key: (e.value.map((v) => v.version).toList()..sort()).join(':'),
  };
  List<String> get conflicts => [
    for (final e in records.entries)
      if (e.value.length > 1 &&
          e.value.map((v) => replicaJson(v.value)).toSet().length > 1)
        e.key,
  ];
  Map<String, int> context(String key) {
    final clock = <String, int>{};
    for (final variant in records[key] ?? const <LibraryVariant>[]) {
      for (final e in variant.clock.entries) {
        if (e.value > (clock[e.key] ?? 0)) clock[e.key] = e.value;
      }
    }
    return clock;
  }

  void edit(String key, Map<String, dynamic>? value) {
    final clock = context(key);
    clock[actor] = (clock[actor] ?? 0) + 1;
    records[key] = [LibraryVariant(Map.unmodifiable(clock), value)];
  }

  bool capture(
    Map<String, Map<String, dynamic>?> snapshot, {
    Set<String> concurrentKeys = const {},
  }) {
    var changed = false;
    for (final key in {...records.keys, ...snapshot.keys}) {
      final before = records.containsKey(key) ? winner(key).value : null;
      final after = snapshot[key];
      if (replicaJson(before) != replicaJson(after)) {
        if (concurrentKeys.contains(key) && after != null) {
          // An incompatible book layout was deliberately not applied locally.
          // A local edit must branch from that layout, not overwrite the
          // unseen remote bookmark simply because its clock was received.
          final clock = <String, int>{};
          for (final variant in records[key] ?? const <LibraryVariant>[]) {
            if (variant.value?['identity'] != after['identity']) continue;
            for (final e in variant.clock.entries) {
              if (e.value > (clock[e.key] ?? 0)) clock[e.key] = e.value;
            }
          }
          clock[actor] = (context(key)[actor] ?? 0) + 1;
          merge({
            key: [LibraryVariant(clock, after).toJson()],
          });
        } else {
          edit(key, after);
        }
        changed = true;
      }
    }
    return changed;
  }

  static void validateKey(String key) {
    if (key.length > 512 ||
        !RegExp(
          r'^(b/[1-9][0-9]*/[^/]+|g/[^/]+|a/[1-9][0-9]*)$',
        ).hasMatch(key)) {
      throw const FormatException('同步记录标识有误');
    }
    final parts = key.split('/');
    if (parts.first != 'g' &&
        (int.tryParse(parts[1]) ?? 0x80000000) > 0x7fffffff) {
      throw const FormatException('同步书籍标识有误');
    }
  }

  void merge(Object? raw) {
    if (raw is! Map || raw.length > 20000) {
      throw const FormatException('同步记录数量有误');
    }
    final incoming = <String, List<LibraryVariant>>{};
    for (final e in raw.entries) {
      if (e.key is! String ||
          e.value is! List ||
          e.value.isEmpty ||
          e.value.length > 32) {
        throw const FormatException('同步记录格式有误');
      }
      validateKey(e.key);
      incoming[e.key] = [for (final v in e.value) LibraryVariant.fromJson(v)];
    }
    for (final e in incoming.entries) {
      final variants = {
        ...{
          for (final v in records[e.key] ?? const <LibraryVariant>[])
            v.version: v,
        },
        for (final v in e.value) v.version: v,
      }.values.toList();
      records[e.key] = variants
          .where((v) => !variants.any((other) => other.dominates(v)))
          .toList();
    }
  }

  Map<String, Object> delta(Object? versions) {
    final known = versions is Map ? versions : const {};
    final current = this.versions;
    final result = <String, Object>{};
    var bytes = 0;
    for (final e in records.entries) {
      if (known[e.key] == current[e.key]) continue;
      final value = e.value.map((v) => v.toJson()).toList();
      final size = utf8.encode(jsonEncode(value)).length;
      if (result.isNotEmpty &&
          (result.length >= 64 || bytes + size > 512 * 1024)) {
        break;
      }
      result[e.key] = value;
      bytes += size;
    }
    return result;
  }
}
