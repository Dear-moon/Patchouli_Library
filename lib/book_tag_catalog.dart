/// Shared, offline-ready suggestions for online filters and local book editing.
///
/// These are editorial common presets, not a copy of the site's authenticated
/// Tags directory. Tags observed in online results extend this catalogue for
/// the running session; selecting or creating a local tag never adds a request.
class BookTagCatalog {
  /// The discovery feeds and local editor share one lightweight in-memory set.
  static final shared = BookTagCatalog();

  /// A short first row keeps book editing quick; the sheet exposes every preset.
  static const quickTags = ['校园', '恋爱', '奇幻', '冒险', '日常', '科幻'];

  /// Common light-novel descriptors, deliberately labelled as common presets.
  static const commonTags = [
    ...quickTags,
    '青春',
    '欢乐向',
    '治愈',
    '温馨',
    '感动',
    '友情',
    '家庭',
    '成长',
    '悬疑',
    '推理',
    '惊悚',
    '恐怖',
    '黑暗',
    '战斗',
    '异能',
    '魔法',
    '异世界',
    '转生',
    '穿越',
    '游戏',
    '机战',
    '战争',
    '历史',
    '末日',
    '旅行',
    '经营',
    '职场',
    '竞技',
    '运动',
    '音乐',
    '美食',
    '群像',
    '间谍',
    '大逃杀',
    '龙傲天',
    '青梅竹马',
    '妹妹',
    '女儿',
    '大小姐',
    '人外',
    '性转',
    '伪娘',
    '后宫',
    '百合',
    '耽美',
    '女性视角',
  ];

  final _observed = <String, String>{};

  /// Adds actual result tags without changing a feed's own filtering state.
  void observe(Iterable<String> tags) {
    for (final tag in normalizeBookTags(tags)) {
      _observed.putIfAbsent(bookTagKey(tag), () => tag);
    }
  }

  /// Every preset and observed tag, with canonical preset spelling first.
  List<String> get suggestions =>
      normalizeBookTags([...commonTags, ..._observed.values]);
}

final _tagSeparators = RegExp(r'[\s\u3000·,，、;；|/]+');
const _localMarkers = {'轻小说', '本地导入', '本地合订本'};

String _halfWidth(String value) => String.fromCharCodes(
  value.runes.map(
    (rune) => rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune,
  ),
);

/// ASCII case and full-width Latin input do not create duplicate tags.
String bookTagKey(String value) => _halfWidth(value).trim().toLowerCase();

/// Shares Novel.genre's separator contract so a saved tag round-trips exactly.
List<String> normalizeBookTags(Iterable<String> values) {
  final tags = <String, String>{};
  for (final value in values) {
    for (final tag in _halfWidth(value).split(_tagSeparators)) {
      if (tag.isEmpty || _localMarkers.contains(tag)) continue;
      tags.putIfAbsent(bookTagKey(tag), () => tag);
    }
  }
  return List.unmodifiable(tags.values);
}

/// Optional backup fields use this only when present; absence means preserve.
List<String> decodeBookTags(Object? value) {
  if (value is! List ||
      value.length > 100 ||
      value.any((tag) => tag is! String || tag.length > 160)) {
    throw const FormatException('标签格式有误：最多 100 个，每个限 160 字');
  }
  final tags = normalizeBookTags(value.cast<String>());
  if (tags.length > 100) {
    throw const FormatException('每本书最多保存 100 个标签');
  }
  return tags;
}

/// Keeps the local provenance marker separate from user-visible book tags.
String localBookGenre(Iterable<String> tags, {bool series = false}) =>
    [series ? '本地合订本' : '本地导入', ...normalizeBookTags(tags)].join(' ');
