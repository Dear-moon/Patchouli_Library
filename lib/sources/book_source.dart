import 'dart:convert';

String sourceAuthorName(String raw) => raw
    .replaceFirst(
      RegExp(
        r'^\s*(?:作\s*者|著\s*者|authors?)\s*(?:[:：]\s*|\s+)',
        caseSensitive: false,
      ),
      '',
    )
    .trim();

/// The public Legado 3 JSON field names are kept verbatim. Unknown fields are
/// retained when editing/exporting instead of silently destroying a source.
class BookSource {
  BookSource(Map<String, dynamic> json)
    : data = Map.unmodifiable(json),
      homeSections = _readHomeSections(json['homeSections']) {
    final engine = data['engine'];
    if (engine != null && (engine is! Map || engine['version'] != 1)) {
      throw const FormatException('书源声明版本不支持，请更新应用');
    }
    if (name.isEmpty || key.isEmpty) {
      throw const FormatException('书源缺少名称或 bookSourceUrl');
    }
    if (data['bookSourceType'] != null && data['bookSourceType'] != 0) {
      throw const FormatException('当前支持文本小说书源');
    }
    for (final field in [
      'ruleSearch',
      'ruleExplore',
      'ruleBookInfo',
      'ruleToc',
      'ruleContent',
    ]) {
      if (data[field] != null && data[field] is! Map) {
        throw FormatException('$field 应为规则对象，请使用阅读 3 格式');
      }
    }
  }

  final Map<String, dynamic> data;
  String get key => '${data['bookSourceUrl'] ?? ''}'.trim();
  String get name => '${data['bookSourceName'] ?? ''}'.trim();
  String get group => '${data['bookSourceGroup'] ?? ''}'.trim();
  bool get enabled => data['enabled'] != false;
  bool get exploreEnabled => enabled && data['enabledExplore'] != false;
  final List<SourceHomeSection> homeSections;
  bool get isScript => '${data['mainJs'] ?? ''}'.trim().isNotEmpty;
  bool get searchable =>
      isScript || '${data['searchUrl'] ?? ''}'.trim().isNotEmpty;
  String get loginUrl => '${data['loginUrl'] ?? ''}'.trim();
  BookSource copyWith({bool? enabled, bool? exploreEnabled, String? group}) =>
      BookSource({
        ...data,
        'enabled': ?enabled,
        'enabledExplore': ?exploreEnabled,
        'bookSourceGroup': ?group,
      });

  static List<BookSource> parse(String text) {
    if (utf8.encode(text).length > 8 * 1024 * 1024) {
      throw const FormatException('书源文件超过 8 MiB');
    }
    final decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
    final list = decoded is List ? decoded : [decoded];
    if (list.length > 2000) throw const FormatException('一次最多导入 2000 个书源');
    final found = <String, BookSource>{};
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) throw FormatException('第 ${i + 1} 项不是书源对象');
      final source = BookSource(Map<String, dynamic>.from(item));
      found[source.key] = source;
    }
    if (found.isEmpty) throw const FormatException('文件中没有书源');
    return found.values.toList(growable: false);
  }

  /// Credentials are a device-local setting, never part of rule sharing.
  Map<String, dynamic> exportRules() {
    final result = Map<String, dynamic>.from(data);
    for (final key in [
      'loginInfo',
      'loginHeader',
      'cookie',
      'cookies',
      'password',
      'token',
    ]) {
      result.remove(key);
    }
    final raw = result['header'];
    Map<dynamic, dynamic> withoutCredentials(Map<dynamic, dynamic> header) =>
        Map<dynamic, dynamic>.from(header)..removeWhere(
          (k, _) => RegExp(
            r'cookie|authorization|token|api[-_]?key',
            caseSensitive: false,
          ).hasMatch('$k'),
        );
    if (raw is Map) result['header'] = withoutCredentials(raw);
    if (raw is String) {
      try {
        final header = jsonDecode(raw);
        if (header is Map) {
          result['header'] = jsonEncode(withoutCredentials(header));
        }
      } on FormatException {
        // Executable header rules are part of the source grammar, not the
        // device's encrypted login vault. Preserve them when sharing rules.
        if (!raw.trimLeft().startsWith('@js:') &&
            !raw.trimLeft().startsWith('<js>')) {
          result.remove('header');
        }
      }
    }
    return result;
  }
}

class SourceFailure implements Exception {
  const SourceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

List<SourceHomeSection> _readHomeSections(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) throw const FormatException('首页栏目应为列表');
  final ids = <String>{};
  final result = <SourceHomeSection>[];
  for (final entry in raw) {
    if (entry is! Map) throw const FormatException('首页栏目应为对象');
    result.add(
      SourceHomeSection.fromMap(Map<String, dynamic>.from(entry), ids),
    );
  }
  return List.unmodifiable(result);
}

class SourceHomeSection {
  const SourceHomeSection({
    required this.id,
    required this.title,
    this.url = '',
    this.operation = 'explore',
  });
  factory SourceHomeSection.fromMap(
    Map<String, dynamic> value,
    Set<String> ids,
  ) {
    final id = value['id'], title = value['title'];
    final operation = value['operation'] ?? 'explore', url = value['url'] ?? '';
    if (id is! String ||
        title is! String ||
        id.isEmpty ||
        title.isEmpty ||
        !ids.add(id)) {
      throw const FormatException('首页栏目标识或标题无效');
    }
    if (operation is! String ||
        url is! String ||
        !['explore', 'cloudShelf'].contains(operation) ||
        operation == 'explore' && url.isEmpty) {
      throw const FormatException('首页栏目操作或地址无效');
    }
    return SourceHomeSection(
      id: id,
      title: title,
      url: url,
      operation: operation,
    );
  }
  final String id, title, url, operation;
  bool get requiresLogin => operation == 'cloudShelf';
}

class SourceExplore {
  const SourceExplore({
    required this.title,
    required this.url,
    this.group = '',
    this.columnFraction,
  });
  final String title, url, group;
  final double? columnFraction;
  bool get isHeading => url.trim().isEmpty;
}

class SourceImportReport {
  const SourceImportReport(this.sources, this.rejected);
  final List<BookSource> sources;
  final List<String> rejected;
  static SourceImportReport parse(String text) {
    if (utf8.encode(text).length > 8 * 1024 * 1024) {
      throw const FormatException('书源文件超过 8 MiB');
    }
    final decoded = jsonDecode(text.replaceFirst('\uFEFF', ''));
    final list = decoded is List ? decoded : [decoded];
    if (list.isEmpty || list.length > 2000) {
      throw const FormatException('书源数量应为 1～2000 个');
    }
    final valid = <String, BookSource>{};
    final rejected = <String>[];
    for (final (index, value) in list.indexed) {
      try {
        if (value is! Map) throw const FormatException('不是书源对象');
        final source = BookSource(Map<String, dynamic>.from(value));
        valid[source.key] = source;
      } on FormatException catch (e) {
        final name = value is Map
            ? '${value['bookSourceName'] ?? '第 ${index + 1} 项'}'
            : '第 ${index + 1} 项';
        rejected.add('$name · ${e.message}');
      }
    }
    return SourceImportReport(valid.values.toList(), rejected);
  }
}
