import 'app_language.dart';
import 'catalog.dart';

/// An exact-tag rule. Stored labels remain separate from their match keys.
class BlockedTags {
  const BlockedTags._(this.tags, this._keys);

  static const preferenceKey = 'blockedTags';
  static const empty = BlockedTags._(<String>{}, <String>{});

  factory BlockedTags(Iterable<String> values) {
    final tags = <String>{};
    final keys = <String>{};
    for (final value in values) {
      final tag = value.trim();
      if (tag.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(tag)) {
        throw const FormatException('标签不能为空或包含控制字符');
      }
      if (keys.add(_key(tag))) tags.add(tag);
    }
    return tags.isEmpty
        ? empty
        : BlockedTags._(Set.unmodifiable(tags), Set.unmodifiable(keys));
  }

  static BlockedTags fromRecord(Object? record) {
    if (record is! List || record.any((value) => value is! String)) {
      return empty;
    }
    try {
      return BlockedTags(record.cast<String>());
    } on FormatException {
      return empty;
    }
  }

  /// Reuse catalogue conversion once when a rule is saved, never in painting.
  static Future<BlockedTags> fromInput(Iterable<String> values) async {
    final normalized = <String>[];
    for (final value in values) {
      normalized.add(await ChineseText.searchQuery(value.trim()));
    }
    return BlockedTags(normalized);
  }

  final Set<String> tags;
  final Set<String> _keys;
  bool get isEmpty => tags.isEmpty;
  bool get isNotEmpty => tags.isNotEmpty;
  bool blocks(Novel book) => book.tags.any((tag) => _keys.contains(_key(tag)));
  bool sameAs(BlockedTags other) =>
      _keys.length == other._keys.length && _keys.every(other._keys.contains);
  List<String> toRecord() => tags.toList(growable: false);

  static String _key(String tag) => tag.trim().toLowerCase();
}
