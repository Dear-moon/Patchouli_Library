import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'app_ui.dart';
import 'app_search_field.dart';
import 'catalog.dart';
import 'book_tag_catalog.dart';
import 'glass_choices.dart';
import 'tag_catalogue.dart';
import 'publication_catalog.dart';

/// The selected discovery source. Publication, ranking and tags are mutually
/// exclusive; a publication's service cannot apply ranking or tag parameters.
class DiscoverySelection {
  const DiscoverySelection({this.sort, this.tags, this.publication});
  final NovelSort? sort;
  final Set<String>? tags;
  final PublicationLibrary? publication;
}

class DiscoveryFilters extends StatefulWidget {
  const DiscoveryFilters({
    super.key,
    required this.sort,
    required this.books,
    this.selectedTags = const {},
    this.availableTags = const [],
    this.blockedTags = const {},
    this.onBlockedTagsChanged,
    this.editingBlockedTags = false,
    this.publicationCatalog,
    this.selectedPublication,
    this.preparePublications,
  });
  final NovelSort sort;
  final List<Novel> books;
  final Set<String> selectedTags;
  final Iterable<String> availableTags;
  final Set<String> blockedTags;
  final Future<void> Function(Set<String>)? onBlockedTagsChanged;
  final bool editingBlockedTags;
  final PublicationCatalog? publicationCatalog;
  final PublicationLibrary? selectedPublication;
  final Future<void> Function()? preparePublications;
  @override
  State<DiscoveryFilters> createState() => _DiscoveryFiltersState();
}

class _DiscoveryFiltersState extends State<DiscoveryFilters> {
  late String mode =
      widget.editingBlockedTags && widget.onBlockedTagsChanged != null
      ? 'blocked'
      : widget.selectedPublication != null && widget.publicationCatalog != null
      ? 'publication'
      : widget.selectedTags.isEmpty
      ? 'sort'
      : 'tags';
  late final selected = {...widget.selectedTags};
  late final blocked = {...widget.blockedTags};
  final query = TextEditingController();
  bool _saving = false;
  String? _saveError;
  List<PublicationLibrary>? _publications;
  bool _loadingPublications = false;
  String? _publicationError;
  Set<String> get _editing => mode == 'blocked' ? blocked : selected;
  bool _isSelected(String tag) => mode == 'blocked'
      ? blocked.any((value) => _tagKey(value) == _tagKey(tag))
      : selected.contains(tag);
  String _tagKey(String value) => value.trim().toLowerCase();
  @override
  void initState() {
    super.initState();
    if (mode == 'publication') unawaited(_loadPublications());
  }

  Future<void> _loadPublications() async {
    final catalog = widget.publicationCatalog;
    if (catalog == null || _loadingPublications) return;
    setState(() {
      _loadingPublications = true;
      _publicationError = null;
    });
    try {
      await widget.preparePublications?.call();
      if (!mounted) return;
      final libraries = await catalog.publicationLibraries(refresh: true);
      if (mounted) setState(() => _publications = libraries);
    } catch (_) {
      if (mounted) {
        setState(() => _publicationError = '出版文库暂未载入，请重试。');
      }
    } finally {
      if (mounted) setState(() => _loadingPublications = false);
    }
  }

  Widget _publicationChoices() {
    if (_loadingPublications) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_publicationError case final error?) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            AppText(error),
            const SizedBox(height: 12),
            GlassTextButton(
              key: const ValueKey('discover-publication-retry'),
              onPressed: _loadPublications,
              child: const AppText('重新加载'),
            ),
          ],
        ),
      );
    }
    final libraries = _publications ?? const <PublicationLibrary>[];
    if (libraries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: AppText('暂无出版文库'),
      );
    }
    return GlassChoiceGroup<int?>(
      name: 'discover-publication',
      label: '选择出版文库',
      value: widget.selectedPublication?.id,
      options: {for (final library in libraries) library.id: library.name},
      onChanged: (id) => Navigator.pop<DiscoverySelection>(
        context,
        DiscoverySelection(
          publication: libraries.firstWhere((library) => library.id == id),
        ),
      ),
    );
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void addTags(String value) {
    final tags = mode == 'blocked'
        ? tagSearchTerms(value)
        : value.split(RegExp(r'[\s,，、]+')).where((t) => t.isNotEmpty);
    setState(() {
      for (final tag in tags) {
        if (!_isSelected(tag)) _editing.add(tag);
      }
      query.clear();
      _saveError = null;
    });
  }

  Future<void> _applyBlocked() async {
    if (_saving || widget.onBlockedTagsChanged == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onBlockedTagsChanged!(Set.unmodifiable(blocked));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '屏蔽标签保存失败，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final frequency = <String, int>{
      for (final tag in [
        ...BookTagCatalog.shared.suggestions,
        ...widget.availableTags,
        ...selected,
        ...blocked,
      ])
        tag: 0,
    };
    for (final book in widget.books) {
      for (final tag in book.tags) {
        frequency.update(tag, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final candidates = mode == 'blocked'
        ? {for (final tag in frequency.keys) _tagKey(tag): tag}.values
        : frequency.keys;
    final tags =
        candidates
            .where(
              (tag) =>
                  _isSelected(tag) ||
                  tag.toLowerCase().contains(query.text.trim().toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final order = frequency[b]!.compareTo(frequency[a]!);
            return order == 0 ? a.compareTo(b) : order;
          });
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArchiveSection(
            title: mode == 'blocked' ? '屏蔽标签' : '筛选',
            code: 'DISCOVER / CATALOGUE',
          ),
          const SizedBox(height: 16),
          AppControls.segments<String>(
            context,
            groupValue: mode,
            children: {
              'sort': const AppText('榜单'),
              'tags': const AppText('标签'),
              if (widget.publicationCatalog != null)
                'publication': const AppText('出版文库'),
              if (widget.onBlockedTagsChanged != null)
                'blocked': const AppText('屏蔽'),
            },
            onValueChanged: (value) {
              if (value == null || _saving) return;
              setState(() => mode = value);
              if (value == 'publication' && _publications == null) {
                unawaited(_loadPublications());
              }
            },
          ),
          const SizedBox(height: 12),
          if (mode == 'sort')
            GlassChoiceGroup<NovelSort?>(
              name: 'discover-sort',
              label: '选择榜单',
              value:
                  widget.selectedPublication == null &&
                      widget.selectedTags.isEmpty
                  ? widget.sort
                  : null,
              options: {for (final sort in NovelSort.values) sort: sort.label},
              optionName: (sort) => sort?.name ?? 'none',
              onChanged: (sort) => Navigator.pop<DiscoverySelection>(
                context,
                DiscoverySelection(sort: sort),
              ),
            )
          else if (mode == 'publication')
            _publicationChoices()
          else ...[
            Row(
              children: [
                GlassTextButton(
                  key: ValueKey(
                    mode == 'blocked'
                        ? 'blocked-tags-clear'
                        : 'discover-tags-clear',
                  ),
                  onPressed: _editing.isEmpty || _saving
                      ? null
                      : () => setState(() {
                          _editing.clear();
                          _saveError = null;
                        }),
                  child: const AppText('清空'),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GlassTextButton(
                      key: ValueKey(
                        mode == 'blocked'
                            ? 'blocked-tags-apply'
                            : 'discover-tags-apply',
                      ),
                      selected: _editing.isNotEmpty,
                      onPressed: _saving
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              if (mode == 'blocked') {
                                _applyBlocked();
                                return;
                              }
                              Navigator.pop<DiscoverySelection>(
                                context,
                                DiscoverySelection(
                                  tags: Set.unmodifiable(selected),
                                ),
                              );
                            },
                      child: AppText(
                        mode == 'blocked'
                            ? _saving
                                  ? '保存中…'
                                  : blocked.isEmpty
                                  ? '解除全部屏蔽'
                                  : '屏蔽 ${blocked.length} 个标签'
                            : selected.isEmpty
                            ? '显示全部'
                            : '应用 ${selected.length} 个标签',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSearchField(
              inputKey: ValueKey(
                mode == 'blocked' ? 'blocked-tag-input' : 'discover-tag-input',
              ),
              controller: query,
              hint: mode == 'blocked' ? '搜索或添加屏蔽标签' : '搜索或添加标签',
              onChanged: (_) => setState(() {}),
              onSubmitted: addTags,
              trailing: ArchiveIconButton(
                tooltip: appText(context, '加入标签'),
                icon: const ArchiveIcon(CupertinoIcons.plus, size: 18),
                onPressed: query.text.trim().isEmpty
                    ? null
                    : () => addTags(query.text),
              ),
            ),
            const SizedBox(height: 14),
            AppText(
              mode == 'blocked' ? '在发现与在线搜索中隐藏含任一所选标签的书。' : '同时包含所选标签',
              style: const TextStyle(fontSize: 13),
            ),
            if (_saveError case final error?) ...[
              const SizedBox(height: 8),
              AppText(error, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in tags)
                  GlassTextButton(
                    key: ValueKey(
                      mode == 'blocked'
                          ? 'blocked-tag-$tag'
                          : 'discover-tag-$tag',
                    ),
                    compact: true,
                    selected: _isSelected(tag),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            if (_isSelected(tag)) {
                              if (mode == 'blocked') {
                                blocked.removeWhere(
                                  (value) => _tagKey(value) == _tagKey(tag),
                                );
                              } else {
                                selected.remove(tag);
                              }
                            } else {
                              _editing.add(tag);
                            }
                            _saveError = null;
                          }),
                    child: AppText(tag, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
