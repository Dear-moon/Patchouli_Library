import 'source_discovery_filters.dart';
import 'source_declarations.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_ui.dart';
import '../app_search_field.dart';
import '../app_interactions.dart';
import '../feature_pages.dart';
import '../glass_choices.dart';
import '../responsible_use.dart';
import '../library_state.dart';
import 'book_source.dart';
import 'source_repository.dart';
import 'source_fields.dart';

Future<void> openSourceManager(
  BuildContext context,
  SourceNovelRepository repository, {
  bool reduceMotion = false,
  LibraryState? library,
}) => pushNovelPage<void>(
  context,
  SourceManagerPage(
    repository: repository,
    reduceMotion: reduceMotion,
    library: library,
  ),
  reduceMotion: reduceMotion,
);

/// All import entries share the same preview, risk notice and explicit selection.
Future<void> previewSourceRules(
  BuildContext context,
  SourceNovelRepository repository,
  String text, {
  bool reduceMotion = false,
}) async {
  final trimmed = text.trimLeft().replaceFirst('\uFEFF', '');
  final parsed = trimmed.startsWith('{') || trimmed.startsWith('[')
      ? await compute(SourceImportReport.parse, text)
      : SourceImportReport([
          await repository.platform.inspectScript(text),
        ], const []);
  if (!context.mounted) return;
  final selected = await pushNovelPage<List<BookSource>>(
    context,
    SourceImportPage(
      sources: parsed.sources,
      rejected: parsed.rejected,
      existing: repository.store.sources.map((s) => s.key).toSet(),
    ),
    reduceMotion: reduceMotion,
  );
  if (selected == null || selected.isEmpty) return;
  await repository.store.saveSources(selected);
  if (context.mounted) showNovelFeedback(context, '已导入 ${selected.length} 个书源');
}

class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({
    super.key,
    required this.repository,
    this.reduceMotion = false,
    this.library,
  });
  final SourceNovelRepository repository;
  final bool reduceMotion;
  final LibraryState? library;
  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends State<SourceManagerPage> {
  SourceNovelRepository get repo => widget.repository;
  String _query = '', _group = '';
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = sourceErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(String? text) async {
    if (text == null || !mounted) return;
    await previewSourceRules(
      context,
      repo,
      text,
      reduceMotion: widget.reduceMotion,
    );
  }

  Future<void> _input({bool url = false}) async {
    final text = await pushNovelPage<String>(
      context,
      SourceTextPage(url: url),
      reduceMotion: widget.reduceMotion,
    );
    if (text == null) return;
    await _preview(url ? await repo.platform.fetchImport(text.trim()) : text);
  }

  Future<void> _edit([BookSource? source]) async {
    final value = await pushNovelPage<BookSource>(
      context,
      SourceEditorPage(source: source),
      reduceMotion: widget.reduceMotion,
    );
    if (value == null) return;
    if (source == null) {
      await repo.store.saveSources([value]);
    } else {
      await repo.store.configure(value);
    }
  }

  Future<void> _delete(BookSource source) async {
    if (!await confirmNovelAction(
      context,
      title: '移除「${source.name}」？',
      message: '不删除书架、缓存章节、阅读进度与书签。重新导入同一书源后可继续获取内容。',
      confirmLabel: '移除书源',
      reduceMotion: widget.reduceMotion,
    )) {
      return;
    }
    final shared =
        SourceDeclarations.sessionKey(source.key) != source.key &&
        repo.store.sources.any(
          (other) =>
              other.key != source.key &&
              SourceDeclarations.sessionKey(other.key) ==
                  SourceDeclarations.sessionKey(source.key),
        );
    if (!shared) await repo.platform.clearSession(source);
    await repo.store.remove(source);
  }

  Future<void> _export() async {
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(repo.store.sources.map((s) => s.exportRules()).toList());
    final saved = await repo.platform.export(text);
    if (mounted && saved) {
      showNovelFeedback(context, '书源已导出，不包含登录会话');
    }
  }

  Widget _actions() => LayoutBuilder(
    builder: (context, box) {
      const gap = 6.0;
      final minimum = MediaQuery.textScalerOf(context).scale(13) * 4 + 16;
      final width = ((box.maxWidth - gap * 3) / 4).clamp(
        minimum,
        double.infinity,
      );
      return SingleChildScrollView(
        key: const ValueKey('source-actions-row'),
        scrollDirection: Axis.horizontal,
        primary: false,
        child: Row(
          children: [
            for (final (id, label, action) in <(String, String, VoidCallback?)>[
              (
                'file',
                '文件导入',
                () => _run(() async => _preview(await repo.platform.pick())),
              ),
              ('url', '链接导入', () => _run(() => _input(url: true))),
              ('paste', '粘贴导入', () => _run(() => _input())),
              (
                'export',
                '导出规则',
                repo.store.sources.isEmpty ? null : () => _run(_export),
              ),
            ]) ...[
              if (id != 'file') const SizedBox(width: gap),
              SizedBox(
                width: width,
                child: GlassTextButton(
                  key: ValueKey('source-import-$id'),
                  compact: true,
                  onPressed: _busy ? null : action,
                  child: AppText(
                    label,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repo.store,
    builder: (context, _) {
      final groups = repo.store.sources
          .map((s) => s.group)
          .where((s) => s.isNotEmpty)
          .toSet();
      final group = groups.contains(_group) ? _group : '';
      final visible = repo.store.sources
          .where(
            (s) =>
                (group.isEmpty || s.group == group) &&
                '${s.name} ${s.group} ${s.key}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
          )
          .toList();
      return ArchiveFeaturePage(
        title: '书源管理',
        code: 'SOURCES / YOUR LIBRARY',
        actions: [
          GlassIconButton(
            icon: CupertinoIcons.plus,
            label: '新建书源',
            onPressed: _busy ? null : () => _run(() => _edit()),
          ),
        ],
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: featurePadding(context),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AppText(
                              '${repo.store.enabled.length} 个已启用 · ${repo.store.sources.length} 个书源',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlassTextButton(
                            compact: true,
                            onPressed: () => pushNovelPage<void>(
                              context,
                              const ResponsibleUsePage(),
                              reduceMotion: widget.reduceMotion,
                            ),
                            child: const AppText(
                              '使用与风险声明',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      _actions(),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: InlineSkeleton(label: '正在处理书源'),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AppText(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (repo.store.sources.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        AppSearchField(
                          hint: '搜索名称或分组',
                          onChanged: (s) => setState(() => _query = s),
                        ),
                        if (groups.isNotEmpty)
                          GlassChoiceRail<String>(
                            name: 'source-group',
                            label: '分组',
                            value: group,
                            options: {
                              '': '全部',
                              for (final group in groups) group: group,
                            },
                            onChanged: (s) => setState(() => _group = s),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (repo.store.sources.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 44),
                          child: Column(
                            children: [
                              ArchiveIcon(
                                CupertinoIcons.square_stack,
                                size: 36,
                              ),
                              SizedBox(height: 16),
                              AppText(
                                '还没有书源',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              AppText(
                                '导入阅读 3 书源，或从右上角新建。\n本地书籍与原有缓存仍可直接阅读。',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, height: 1.7),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, row) {
                      final source = visible[row];
                      final index = repo.store.sources.indexOf(source);
                      return Padding(
                        key: ValueKey('source-card-${source.key}'),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ContentPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          source.name,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        AppText(
                                          source.group.isEmpty
                                              ? (source.searchable
                                                    ? '搜索${source.exploreEnabled ? ' · 发现' : ''}'
                                                    : '未配置搜索')
                                              : source.group,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AppControls.toggle(
                                    context,
                                    key: ValueKey(
                                      'source-enabled-${source.key}',
                                    ),
                                    value: source.enabled,
                                    onChanged: _busy
                                        ? null
                                        : (value) => _run(
                                            () => repo.store.configure(
                                              source.copyWith(enabled: value),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                              if (repo.failures[source.key] case final message?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: AppText(
                                    message,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  GlassTextButton(
                                    compact: true,
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => _edit(source)),
                                    child: const AppText('编辑'),
                                  ),
                                  GlassTextButton(
                                    compact: true,
                                    onPressed: () => pushNovelPage<void>(
                                      context,
                                      SourceDebugPage(
                                        source: source,
                                        repository: repo,
                                      ),
                                      reduceMotion: widget.reduceMotion,
                                    ),
                                    child: const AppText('检查书源'),
                                  ),
                                  if (index > 0)
                                    GlassTextButton(
                                      compact: true,
                                      onPressed: _busy
                                          ? null
                                          : () => _run(() async {
                                              final all = repo.store.sources
                                                  .toList();
                                              final oldIndex = all.indexOf(
                                                source,
                                              );
                                              all.removeAt(oldIndex);
                                              all.insert(oldIndex - 1, source);
                                              await repo.store.reorder(all);
                                            }),
                                      child: const AppText('上移'),
                                    ),
                                  GlassTextButton(
                                    compact: true,
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => _delete(source)),
                                    child: const AppText('移除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  SliverList.list(
                    children: [
                      if (repo.store.sources.isNotEmpty && visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(30),
                          child: Center(child: AppText('没有匹配的书源')),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class SourceImportPage extends StatefulWidget {
  const SourceImportPage({
    super.key,
    required this.sources,
    required this.existing,
    this.rejected = const [],
  });
  final List<BookSource> sources;
  final Set<String> existing;
  final List<String> rejected;
  @override
  State<SourceImportPage> createState() => _SourceImportPageState();
}

class _SourceImportPageState extends State<SourceImportPage> {
  late final _selected = widget.sources.map((s) => s.key).toSet();
  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '确认导入',
    code: 'SOURCES / IMPORT PREVIEW',
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: featurePadding(context),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverList.list(
                children: [
                  AppText(
                    '${widget.sources.length} 个书源可导入',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const AppText(
                    '勾选需要的书源。同地址的规则将更新，原启用状态和书籍关联保留。',
                    style: TextStyle(fontSize: 13, height: 1.65),
                  ),
                  const SizedBox(height: 12),
                  const AppText(
                    sourceImportRisk,
                    key: ValueKey('source-import-risk'),
                    style: TextStyle(fontSize: 13, height: 1.65),
                  ),
                  GlassTextButton(
                    key: const ValueKey('source-import-policy'),
                    compact: true,
                    onPressed: () => pushNovelPage<void>(
                      context,
                      const ResponsibleUsePage(),
                      reduceMotion: MediaQuery.disableAnimationsOf(context),
                    ),
                    child: const AppText('使用与风险声明'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      GlassTextButton(
                        compact: true,
                        onPressed: () => setState(() {
                          _selected.clear();
                          _selected.addAll(widget.sources.map((s) => s.key));
                        }),
                        child: const AppText('全选'),
                      ),
                      const SizedBox(width: 8),
                      GlassTextButton(
                        compact: true,
                        onPressed: () => setState(_selected.clear),
                        child: const AppText('清空'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GlassTextButton(
                    key: const ValueKey('confirm-source-import'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            widget.sources
                                .where((s) => _selected.contains(s.key))
                                .toList(),
                          ),
                    child: AppText(
                      '导入 ${_selected.length} 个${_selected.intersection(widget.existing).isEmpty ? '' : ' · 更新 ${_selected.intersection(widget.existing).length} 个'}',
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
              SliverList.builder(
                itemCount: widget.sources.length,
                itemBuilder: (context, index) {
                  final source = widget.sources[index];
                  return Padding(
                    key: ValueKey('source-import-card-${source.key}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ContentPanel(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  source.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                AppText(
                                  source.key.split('##').first,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                AppText(
                                  widget.existing.contains(source.key)
                                      ? '已有书源 · 更新规则'
                                      : source.group.isEmpty
                                      ? '新书源'
                                      : source.group,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          AppControls.toggle(
                            context,
                            value: _selected.contains(source.key),
                            onChanged: (v) => setState(() {
                              if (v) {
                                _selected.add(source.key);
                              } else {
                                _selected.remove(source.key);
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SliverList.list(
                children: [
                  if (widget.rejected.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    AppText(
                      '${widget.rejected.length} 项暂不支持',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final item in widget.rejected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppText(
                          item,
                          style: const TextStyle(fontSize: 12, height: 1.6),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SourceTextPage extends StatefulWidget {
  const SourceTextPage({super.key, this.url = false});
  final bool url;
  @override
  State<SourceTextPage> createState() => _SourceTextPageState();
}

class _SourceTextPageState extends State<SourceTextPage> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.url ? '链接导入' : '粘贴书源',
    code: 'SOURCES / IMPORT',
    child: ListView(
      padding: featurePadding(context),
      children: [
        sourceField(
          context,
          widget.url ? '书源链接（JSON／JS）' : '阅读 3 书源（JSON／JS）',
          _text,
          lines: widget.url ? 2 : 16,
        ),
        const SizedBox(height: 20),
        GlassTextButton(
          onPressed: () {
            if (_text.text.trim().isNotEmpty) {
              Navigator.pop(context, _text.text);
            }
          },
          child: const AppText('预览书源'),
        ),
      ],
    ),
  );
}

class SourceEditorPage extends StatefulWidget {
  const SourceEditorPage({super.key, this.source});
  final BookSource? source;
  @override
  State<SourceEditorPage> createState() => _SourceEditorPageState();
}

class _SourceEditorPageState extends State<SourceEditorPage> {
  static const _sections = <String, Map<String, String>>{
    '基本': {
      'bookSourceName': '书源名称',
      'bookSourceUrl': '书源标识／基础地址',
      'bookSourceGroup': '分组',
      'searchUrl': '搜索地址',
      'exploreUrl': '发现列表',
      'header': '请求头 JSON',
      'jsLib': '公共 JavaScript',
      'loginUrl': '登录地址／脚本',
      'loginUi': '登录表单 JSON',
      'loginCheckJs': '登录检查脚本',
    },
    '搜索': {
      'bookList': '书籍列表',
      'name': '书名',
      'author': '作者',
      'kind': '标签',
      'bookUrl': '详情地址',
      'coverUrl': '封面',
      'intro': '简介',
      'lastChapter': '最新章节',
    },
    '发现': {
      'bookList': '书籍列表',
      'name': '书名',
      'author': '作者',
      'kind': '标签',
      'bookUrl': '详情地址',
      'coverUrl': '封面',
      'intro': '简介',
      'lastChapter': '最新章节',
    },
    '详情': {
      'init': '预处理',
      'name': '书名',
      'author': '作者',
      'kind': '标签',
      'intro': '简介',
      'coverUrl': '封面',
      'tocUrl': '目录地址',
    },
    '目录': {
      'chapterList': '章节列表',
      'chapterName': '章节名称',
      'chapterUrl': '章节地址',
      'isVolume': '分卷标题',
      'nextTocUrl': '下一页目录',
    },
    '正文': {
      'content': '正文',
      'nextContentUrl': '本章下一页',
      'replaceRegex': '正文替换规则',
    },
    '脚本': {'mainJs': '纯 JS 主脚本'},
  };
  static const _keys = {
    '搜索': 'ruleSearch',
    '发现': 'ruleExplore',
    '详情': 'ruleBookInfo',
    '目录': 'ruleToc',
    '正文': 'ruleContent',
  };
  late Map<String, dynamic> _data;
  final _fields = <String, TextEditingController>{};
  final _json = TextEditingController();
  String _section = '基本';
  final _account = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    _data = {...?widget.source?.data, 'bookSourceType': 0};
    _prepare();
  }

  void _prepare() {
    for (final entry in _sections.entries) {
      final map = entry.key == '基本' || entry.key == '脚本'
          ? _data
          : (_data[_keys[entry.key]] as Map? ?? {});
      for (final field in entry.value.keys) {
        (_fields['${entry.key}.$field'] ??= TextEditingController()).text =
            '${map[field] ?? ''}';
      }
    }
    _json.text = const JsonEncoder.withIndent('  ').convert(_data);
    _account.text = _data['ruleAccount'] == null
        ? ''
        : const JsonEncoder.withIndent('  ').convert(_data['ruleAccount']);
  }

  void _collect() {
    final accountText = _account.text.trim();
    if (accountText.isEmpty) {
      _data.remove('ruleAccount');
    } else {
      final account = jsonDecode(accountText);
      if (account is! Map) throw const FormatException('账号扩展应为 JSON 对象');
      _data['ruleAccount'] = account;
    }
    for (final entry in _sections.entries) {
      final root = entry.key == '基本' || entry.key == '脚本';
      final map = root
          ? _data
          : Map<String, dynamic>.from(_data[_keys[entry.key]] as Map? ?? {});
      for (final field in entry.value.keys) {
        final text = _fields['${entry.key}.$field']!.text.trim();
        if (text.isEmpty) {
          map.remove(field);
        } else {
          map[field] = text;
        }
      }
      if (!root) _data[_keys[entry.key]!] = map;
    }
  }

  void _switch(String section) {
    try {
      if (_section == 'JSON') {
        _data = Map<String, dynamic>.from(jsonDecode(_json.text));
        _prepare();
      } else {
        _collect();
        _json.text = const JsonEncoder.withIndent('  ').convert(_data);
      }
      setState(() {
        _section = section;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'JSON 格式不正确，请修改后再切换');
    }
  }

  void _save() {
    try {
      if (_section == 'JSON') {
        _data = Map<String, dynamic>.from(jsonDecode(_json.text));
      } else {
        _collect();
      }
      final source = BookSource(_data);
      if (widget.source != null && widget.source!.key != source.key) {
        throw const FormatException('现有书源标识不可修改；可新建书源后重新关联');
      }
      Navigator.pop(context, source);
    } catch (e) {
      setState(() => _error = sourceErrorMessage(e));
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _json.dispose();
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.source == null ? '新建书源' : '编辑书源',
    code: 'SOURCES / RULE EDITOR',
    actions: [
      GlassIconButton(
        icon: CupertinoIcons.check_mark,
        label: '保存书源',
        onPressed: _save,
      ),
    ],
    child: LoadedContentSequence(
      generation: _section,
      child: ListView(
        padding: featurePadding(context),
        children: [
          GlassChoiceGroup<String>(
            name: 'source-editor-section',
            label: '规则',
            value: _section,
            options: {
              for (final section in [..._sections.keys, '账号扩展', 'JSON'])
                section: section,
            },
            onChanged: _switch,
          ),
          const SizedBox(height: 20),
          if (_section == '基本') ...[
            Row(
              children: [
                const Expanded(
                  child: AppText('启用书源', style: TextStyle(fontSize: 14)),
                ),
                AppControls.toggle(
                  context,
                  key: const ValueKey('source-editor-enabled'),
                  value: _data['enabled'] != false,
                  onChanged: (value) =>
                      setState(() => _data['enabled'] = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: AppText('启用发现', style: TextStyle(fontSize: 14)),
                ),
                AppControls.toggle(
                  context,
                  key: const ValueKey('source-editor-explore'),
                  value: _data['enabledExplore'] != false,
                  onChanged: (value) =>
                      setState(() => _data['enabledExplore'] = value),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_section == 'JSON')
            sourceField(context, '完整书源 JSON', _json, lines: 20)
          else if (_section == '账号扩展') ...[
            const AppText(
              '可选的纸间账号扩展。验证、云书架和签到分别配置；请求与解析沿用阅读规则语法。没有配置的能力不会显示按钮。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 12),
            sourceField(context, 'ruleAccount JSON', _account, lines: 16),
          ] else
            for (final (index, field) in _sections[_section]!.entries.indexed)
              LoadedContentItem(
                key: ValueKey('$_section.${field.key}'),
                index: index,
                child: sourceField(
                  context,
                  field.value,
                  _fields['$_section.${field.key}']!,
                  readOnly:
                      widget.source != null && field.key == 'bookSourceUrl',
                  lines: field.key == 'mainJs'
                      ? 20
                      : [
                          'jsLib',
                          'exploreUrl',
                          'header',
                          'content',
                        ].contains(field.key)
                      ? 4
                      : 2,
                ),
              ),
        ],
      ),
    ),
  );
}

class SourceDebugPage extends StatefulWidget {
  const SourceDebugPage({
    super.key,
    required this.source,
    required this.repository,
  });
  final BookSource source;
  final SourceNovelRepository repository;
  @override
  State<SourceDebugPage> createState() => _SourceDebugPageState();
}

class _SourceDebugPageState extends State<SourceDebugPage> {
  final _keyword = TextEditingController();
  final _lines = <String>[];
  bool _running = false;
  static int _nextRequest = 0;
  String _id = '';
  int _ticket = 0;
  Future<void> _check() async {
    if (_keyword.text.trim().isEmpty || _running) return;
    final ticket = ++_ticket;
    _id = 'source-debug-${++_nextRequest}';
    setState(() {
      _running = true;
      _lines.clear();
    });
    void line(String text) {
      if (mounted && ticket == _ticket) setState(() => _lines.add(text));
    }

    var phase = '搜索';
    try {
      final platform = widget.repository.platform;
      final source = widget.source;
      final result =
          await platform.run(
                source,
                'search',
                key: _keyword.text.trim(),
                requestId: _id,
              )
              as Map;
      final items = result['items'] as List;
      if (!mounted || ticket != _ticket) return;
      line('搜索 · ${items.length} 本作品');
      if (items.isEmpty) return;
      final book = <String, dynamic>{
        ...Map<String, dynamic>.from(items.first),
        'origin': source.key,
        'originName': source.name,
      };
      phase = '详情';
      final detail =
          await platform.run(
                source,
                'detail',
                url: book['bookUrl'],
                book: book,
                requestId: _id,
              )
              as Map;
      line('详情 · ${detail['name'] ?? book['name']}');
      final full = {...book, ...Map<String, dynamic>.from(detail)};
      if (!mounted || ticket != _ticket) return;
      phase = '目录';
      final chapters =
          await platform.run(
                source,
                'toc',
                url: detail['tocUrl'] ?? book['bookUrl'],
                book: full,
                requestId: _id,
              )
              as List;
      final readable = chapters
          .where(
            (c) =>
                c['isVolume'] != true &&
                c['url'] is String &&
                (c['url'] as String).isNotEmpty,
          )
          .toList();
      if (!mounted || ticket != _ticket) return;
      line('目录 · ${readable.length} 章');
      if (readable.isEmpty) return;
      phase = '正文';
      final body =
          await platform.run(
                source,
                'content',
                url: readable.first['url'],
                book: full,
                chapter: {
                  ...Map<String, dynamic>.from(readable.first),
                  'title': readable.first['name'],
                  'index': 0,
                  'nextChapterUrl': readable.length > 1
                      ? readable[1]['url']
                      : null,
                },
                requestId: _id,
              )
              as String;
      if (body.trim().isEmpty) throw const SourceFailure('正文规则没有返回内容');
      line(
        '正文 · ${body.length} 字符 · ${RegExp('<!--image-->').allMatches(body).length ~/ 2} 张插图',
      );
      line('搜索、详情、目录和正文均已通过');
    } catch (e) {
      line('$phase · ${sourceErrorMessage(e)}');
    } finally {
      if (mounted && ticket == _ticket) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _ticket++;
    unawaited(widget.repository.platform.cancel(_id));
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '检查书源',
    code: 'SOURCES / ${widget.source.name}',
    child: ListView(
      padding: featurePadding(context),
      children: [
        sourceField(context, '用于检查的书名', _keyword),
        GlassTextButton(
          onPressed: _running ? null : _check,
          child: const AppText('检查搜索到正文'),
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          const InlineSkeleton(label: '正在检查书源'),
          GlassTextButton(
            onPressed: () {
              _ticket++;
              widget.repository.platform.cancel(_id);
              setState(() => _running = false);
            },
            child: const AppText('停止检查'),
          ),
        ],
        const SizedBox(height: 24),
        for (final text in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ContentPanel(
              child: AppText(
                text,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
          ),
      ],
    ),
  );
}

Future<void> chooseSourceDiscovery(
  BuildContext context,
  SourceNovelRepository repository, {
  bool reduceMotion = false,
}) async {
  await showJellySheet<void>(
    context: context,
    reduceMotion: reduceMotion,
    heightFactor: .85,
    builder: (_) => SourceDiscoveryChoices(repository: repository),
  );
}

class SourceDiscoveryChoices extends StatefulWidget {
  const SourceDiscoveryChoices({super.key, required this.repository});
  final SourceNovelRepository repository;
  @override
  State<SourceDiscoveryChoices> createState() => _SourceDiscoveryChoicesState();
}

class _SourceDiscoveryChoicesState extends State<SourceDiscoveryChoices> {
  late BookSource? _source = widget.repository.discoverySource;
  late Future<List<SourceExplore>> _choices = _source == null
      ? Future.value([])
      : _source!.data['linkOnly'] == true
      ? Future.value([const SourceExplore(title: '已添加书籍', url: 'stored')])
      : widget.repository.explores(_source!);
  final _query = TextEditingController();
  bool _pickingSource = false, _selecting = false;
  String? _group;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _select(SourceExplore explore) async {
    if (_source != null &&
        explore.url ==
            SourceDeclarations.section(_source!.key, 'filters')['trigger']) {
      final selection = await showJellySheet<SourceExplore>(
        context: context,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        heightFactor: .8,
        builder: (_) => SourceDiscoveryFilters(
          config: SourceDeclarations.section(_source!.key, 'filters'),
          current:
              widget.repository.store.selectedExplore ??
              SourceDeclarations.section(_source!.key, 'filters')['path']
                  as String,
        ),
      );
      if (selection == null || !mounted) return;
      explore = selection;
    }

    if (_selecting || _source == null) return;
    setState(() => _selecting = true);
    try {
      await widget.repository.selectExplore(_source!, explore);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showNovelFeedback(context, sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Padding(
      padding: box.maxHeight < 400
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: AppText(
                  '书源与发现',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassTextButton(
                  key: const ValueKey('discovery-source-picker'),
                  compact: true,
                  onPressed: () => setState(() {
                    _pickingSource = !_pickingSource;
                    _query.clear();
                  }),
                  child: Row(
                    children: [
                      const ArchiveIcon(CupertinoIcons.square_stack, size: 17),
                      const SizedBox(width: 6),
                      Expanded(
                        child: AppText(
                          _source?.name ?? '选择书源',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ArchiveIcon(
                        _pickingSource
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppSearchField(
            inputKey: const ValueKey('discovery-choice-search'),
            controller: _query,
            hint: _pickingSource ? '搜索书源或分组' : '搜索全部分类或榜单',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LoadedContentSequence(
              generation: (_pickingSource, _source?.key),
              child: _pickingSource ? _sources() : _categories(),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sources() {
    final query = _query.text.trim().toLowerCase();
    final sources = widget.repository.enabled
        .where(
          (s) =>
              s.exploreEnabled &&
              '${s.name} ${s.group}'.toLowerCase().contains(query),
        )
        .toList();
    return ListView.builder(
      key: const ValueKey('discovery-source-list'),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return LoadedContentItem(
          index: index,
          child: GlassMenuItem(
            order: index,
            label: source.name,
            selected: source.key == _source?.key,
            onPressed: () => setState(() {
              _source = source;
              _choices = source.data['linkOnly'] == true
                  ? Future.value([
                      const SourceExplore(title: '已添加书籍', url: 'stored'),
                    ])
                  : widget.repository.explores(source);
              _pickingSource = false;
              _group = null;
              _query.clear();
            }),
          ),
        );
      },
    );
  }

  Widget _categories() => FutureBuilder<List<SourceExplore>>(
    key: ValueKey(_source?.key),
    future: _choices,
    builder: (context, result) {
      if (result.hasError) {
        return ContentNotice(
          icon: CupertinoIcons.square_grid_2x2,
          title: '分类加载失败',
          message: sourceErrorMessage(result.error!),
          onRetry: () =>
              setState(() => _choices = widget.repository.explores(_source!)),
        );
      }
      if (!result.hasData) {
        return const LoadedContentSequence(
          generation: null,
          child: LoadingSkeleton(layout: SkeletonLayout.actions),
        );
      }
      final query = _query.text.trim().toLowerCase();
      final all = result.data!.where((e) => !e.isHeading).toList();
      final groups = <String, List<SourceExplore>>{};
      for (final choice in all) {
        (groups[choice.group] ??= []).add(choice);
      }
      final current = widget.repository.discoverySource?.key == _source?.key
          ? all
                .where((e) => e.url == widget.repository.store.selectedExplore)
                .firstOrNull
          : null;
      final group = groups.containsKey(_group)
          ? _group!
          : current?.group ?? groups.keys.firstOrNull ?? '';
      final choices = (query.isEmpty ? groups[group] ?? <SourceExplore>[] : all)
          .where((e) => '${e.title} ${e.group}'.toLowerCase().contains(query))
          .toList();
      if (choices.isEmpty) {
        return AppText(query.isEmpty ? '这个书源没有提供发现分类，可通过搜索查找作品。' : '没有匹配的分类');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (query.isEmpty && groups.length > 1)
            GlassChoiceRail<String>(
              name: 'discovery-group',
              value: group,
              options: {
                for (final entry in groups.entries)
                  entry.key:
                      '${entry.key.isEmpty ? '其他' : entry.key} ${entry.value.length}',
              },
              enabled: !_selecting,
              onChanged: (value) => setState(() => _group = value),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: AppText(
              query.isNotEmpty
                  ? '匹配 ${choices.length} 项'
                  : '${group.isEmpty ? '全部分类' : group} · ${choices.length} 项',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                final font = MediaQuery.textScalerOf(context).scale(13);
                final columns = ((width + 8) / (font * 6.5 + 24)).floor().clamp(
                  1,
                  6,
                );
                return LoadedContentSequence(
                  generation: (_source?.key, group, query),
                  child: GridView.builder(
                    key: ValueKey(
                      'discovery-categories-${_source?.key}-$group-$query',
                    ),
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 4,
                      mainAxisExtent: font * 1.4 * 2 + 28,
                    ),
                    itemCount: choices.length,
                    itemBuilder: (context, index) {
                      final explore = choices[index];
                      return LoadedContentItem(
                        index: index,
                        child: Tooltip(
                          message: explore.title,
                          child: GlassTextButton(
                            key: ValueKey('discovery-category-${explore.url}'),
                            compact: true,
                            selected:
                                widget.repository.store.selectedExplore ==
                                    explore.url &&
                                widget.repository.discoverySource?.key ==
                                    _source?.key,
                            onPressed: _selecting
                                ? null
                                : () => _select(explore),
                            child: AppText(
                              explore.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
