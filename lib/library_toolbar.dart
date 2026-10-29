import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'glass_choices.dart';
import 'book_grid_density.dart';
import 'book_grid_density_controls.dart';
import 'native_effects.dart';

/// A single quiet line shared by the separate and merged libraries.
class LibraryToolbar extends StatelessWidget {
  @visibleForTesting
  static bool debugDisableBatch = false;

  const LibraryToolbar({
    super.key,
    required this.category,
    required this.count,
    required this.onCategory,
    required this.onOptions,
    this.categoryKey,
    this.optionsKey,
    this.onView,
    this.viewKey,
    this.onManage,
    this.manageKey,
    this.activeFilters = 0,
    this.loading = false,
  });
  final String category;
  final int count, activeFilters;
  final bool loading;
  final VoidCallback? onCategory, onOptions, onView, onManage;
  final Key? categoryKey, optionsKey, viewKey, manageKey;
  @override
  Widget build(BuildContext context) {
    var shareInput = const bool.fromEnvironment(
      'GLASS_TOOLBAR_BATCH',
      defaultValue: true,
    );
    assert(() {
      shareInput = shareInput && !debugDisableBatch;
      return true;
    }());
    final textScaler = MediaQuery.textScalerOf(context);
    final compact = CompactMainPageControls.of(context);
    final countLabel = loading
        ? const InlineSkeleton(width: 38, height: 18)
        : AppText(
            '${activeFilters == 0 ? '' : '筛选 · '}$count 本',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
    // These clear controls occupy separate lanes over the same completed row
    // background. Share its input while keeping each original outline clip.
    // The group is local: pushed sheets keep their own backdrop and sizing.
    return NativeGlassGroup(
      inherit: false,
      preserveMemberClip: true,
      enabled: shareInput,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final separateCount =
              compact &&
              constraints.maxWidth < 340 &&
              textScaler.scale(14) > 17;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: compact ? 240 : double.infinity,
                        ),
                        child: GlassTextButton(
                          key: categoryKey,
                          compact: true,
                          onPressed: onCategory,
                          child: LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                if (!compact ||
                                    constraints.maxWidth >= 100) ...[
                                  ArchiveIcon(
                                    CupertinoIcons.folder,
                                    size: compact ? 20 : 16,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: AppText(
                                    category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ArchiveIcon(
                                  CupertinoIcons.chevron_down,
                                  size: compact ? 12 : 11,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!separateCount) ...[
                    const SizedBox(width: 12),
                    countLabel,
                  ],
                  const SizedBox(width: 8),
                  Semantics(
                    value: activeFilters == 0 ? '未筛选' : '$activeFilters 项筛选',
                    child: GlassIconButton(
                      key: optionsKey,
                      icon: CupertinoIcons.line_horizontal_3_decrease,
                      label: '筛选',
                      onPressed: onOptions,
                    ),
                  ),
                  if (onView != null) ...[
                    if (compact) const SizedBox(width: 4),
                    GlassIconButton(
                      key: viewKey,
                      icon: CupertinoIcons.rectangle_grid_1x2,
                      label: '视图',
                      onPressed: onView,
                    ),
                  ],
                  if (onManage != null) ...[
                    if (compact) const SizedBox(width: 4),
                    GlassIconButton(
                      key: manageKey,
                      icon: CupertinoIcons.checkmark_circle,
                      label: '批量整理本地书',
                      onPressed: onManage,
                    ),
                  ],
                ],
              ),
              if (separateCount)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: countLabel,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class LibraryViewOptions extends StatelessWidget {
  const LibraryViewOptions({
    super.key,
    required this.shelf,
    required this.reading,
    required this.sort,
    required this.onView,
    required this.onReading,
    required this.onSort,
    this.source,
    this.onSource,
    this.footer,
    this.viewHint,
    this.layout,
    this.onLayout,
    this.gridDensity = const BookGridDensity.auto(),
    this.gridViewport,
    this.onGridDensity,
    this.showView = true,
  });
  final bool shelf;
  final bool showView;
  final String? layout;
  final ValueChanged<String>? onLayout;
  final BookGridDensity gridDensity;
  final BookGridViewport? gridViewport;
  final ValueChanged<BookGridDensity>? onGridDensity;
  final String reading, sort;
  final String? source;
  final ValueChanged<bool> onView;
  final ValueChanged<String> onReading, onSort;
  final ValueChanged<String>? onSource;
  final Widget? footer;
  final String? viewHint;
  Widget _choices(
    String label,
    Map<String, String> values,
    String current,
    ValueChanged<String> changed,
  ) => GlassChoiceGroup<String>(
    name: 'library-option-$label',
    label: label,
    value: current,
    options: values,
    onChanged: changed,
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArchiveSection(
          title: showView ? '显示与筛选' : '筛选',
          code: showView ? 'LIBRARY / VIEW' : 'LIBRARY / FILTER',
        ),
        if (showView)
          _choices(
            '视图',
            {
              'shelf': '立体书架 + 列表',
              'list': '仅列表',
              if (onLayout != null) 'grid': '宫格',
            },
            layout ?? (shelf ? 'shelf' : 'list'),
            onLayout ?? ((v) => onView(v == 'shelf')),
          ),
        if (showView && viewHint != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: AppText(
              viewHint!,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (showView && layout == 'grid' && onGridDensity != null)
          BookGridDensityOptions(
            value: gridDensity,
            viewport: gridViewport,
            onChanged: onGridDensity!,
          ),
        _choices(
          '阅读状态',
          const {
            'all': '全部',
            'unread': '未读',
            'reading': '阅读中',
            'finished': '已读完',
          },
          reading,
          onReading,
        ),
        if (source != null && onSource != null)
          _choices(
            '书籍来源',
            const {
              'all': '全部',
              'local': '本地导入',
              'cached': '已缓存',
              'online': '在线收藏',
            },
            source!,
            onSource!,
          ),
        _choices(
          '排列顺序',
          const {'recentRead': '最近阅读', 'recentAdded': '最近加入', 'title': '书名'},
          sort,
          onSort,
        ),
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    ),
  );
}
