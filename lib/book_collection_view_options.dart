import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'book_collection_mode.dart';
import 'book_grid_density.dart';
import 'book_grid_density_controls.dart';
import 'book_shelf_preferences.dart';
import 'book_shelf_content_preferences.dart';
import 'glass_choices.dart';
import 'setting_menu.dart';

/// Region-specific view sheets never change the other region's presentation.
enum BookCollectionViewTarget { all, shelf, collection }

/// Shared view controls for discovery, shelf and local collections.
class BookCollectionViewOptions extends StatelessWidget {
  const BookCollectionViewOptions({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.gridDensity,
    required this.onGridDensityChanged,
    this.shelfPreferences = const BookShelfPreferences.defaults(),
    this.onShelfPreferencesChanged,
    this.shelfContent = const BookShelfContentPreferences.defaults(),
    this.onShelfContentChanged,
    this.shelfCategoryOptions = const {'_all': '全部书籍'},
    this.shelfSourceOptions = const {},
    this.shelfSortOptions,
    this.shelfContentHint,
    this.reduceMotion = false,
    this.gridViewport,
    this.target = BookCollectionViewTarget.all,
    this.onShowLayoutOptions,
  });

  final BookCollectionMode mode;
  final ValueChanged<BookCollectionMode> onModeChanged;
  final BookGridDensity gridDensity;
  final ValueChanged<BookGridDensity> onGridDensityChanged;
  final BookGridViewport? gridViewport;
  final BookShelfPreferences shelfPreferences;
  final ValueChanged<BookShelfPreferences>? onShelfPreferencesChanged;
  final BookShelfContentPreferences shelfContent;
  final ValueChanged<BookShelfContentPreferences>? onShelfContentChanged;
  final Map<String, String> shelfCategoryOptions, shelfSourceOptions;
  final Map<BookShelfContentSort, String>? shelfSortOptions;
  final String? shelfContentHint;
  final bool reduceMotion;
  final BookCollectionViewTarget target;
  final VoidCallback? onShowLayoutOptions;

  static IconData iconFor(BookCollectionMode mode) => switch (mode) {
    BookCollectionMode.list => CupertinoIcons.list_bullet,
    BookCollectionMode.shelfList => CupertinoIcons.rectangle_grid_1x2,
    BookCollectionMode.shelfGrid => CupertinoIcons.rectangle_grid_2x2,
    BookCollectionMode.grid => CupertinoIcons.square_grid_2x2,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ArchiveSection(
        title: switch (target) {
          BookCollectionViewTarget.all => '整体布局',
          BookCollectionViewTarget.shelf => '立体书架视图',
          BookCollectionViewTarget.collection => '列表与宫格',
        },
        code: 'COLLECTION / VIEW',
      ),
      if (target == BookCollectionViewTarget.all)
        GlassChoiceGroup<BookCollectionMode>(
          name: 'collection-view',
          label: '布局',
          value: mode,
          options: {
            for (final value in BookCollectionMode.values) value: value.label,
          },
          optionName: (value) => value.storageValue,
          leading: (value) => ArchiveIcon(iconFor(value), size: 16),
          onChanged: onModeChanged,
        ),
      if (target == BookCollectionViewTarget.collection)
        GlassChoiceGroup<bool>(
          name: 'collection-region-view',
          label: '显示方式',
          value: mode.isGrid,
          options: const {false: '列表', true: '宫格'},
          leading: (grid) => ArchiveIcon(
            grid ? CupertinoIcons.square_grid_2x2 : CupertinoIcons.list_bullet,
            size: 16,
          ),
          onChanged: (grid) => onModeChanged(
            mode.hasShelf
                ? (grid
                      ? BookCollectionMode.shelfGrid
                      : BookCollectionMode.shelfList)
                : (grid ? BookCollectionMode.grid : BookCollectionMode.list),
          ),
        ),
      if (target != BookCollectionViewTarget.collection &&
          onShelfPreferencesChanged != null)
        AnimatedOptionSection(
          expanded: mode.hasShelf,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                if (target == BookCollectionViewTarget.all)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: AppText(
                        '上方 · 立体书架',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (target == BookCollectionViewTarget.all &&
                    onShelfContentChanged != null) ...[
                  _ShelfToggle(
                    label: '跟随下方分类与排序',
                    value: shelfContent.followCollection,
                    onChanged: (value) => onShelfContentChanged!(
                      shelfContent.copyWith(followCollection: value),
                    ),
                  ),
                  AnimatedOptionSection(
                    expanded: !shelfContent.followCollection,
                    child: _contentOptions(context),
                  ),
                  const SizedBox(height: 14),
                ],
                _ShelfCountSetting(
                  key: const ValueKey('shelf-minimum-books'),
                  label: '显示所需最少本数',
                  value: shelfPreferences.minimumBooks,
                  onChanged: (value) => onShelfPreferencesChanged!(
                    shelfPreferences.copyWith(minimumBooks: value),
                  ),
                ),
                const SizedBox(height: 8),
                _ShelfCountSetting(
                  key: const ValueKey('shelf-maximum-books'),
                  label: '最多展示本数',
                  value: shelfPreferences.maximumBooks,
                  onChanged: (value) => onShelfPreferencesChanged!(
                    shelfPreferences.copyWith(maximumBooks: value),
                  ),
                ),
                const SizedBox(height: 8),
                _ShelfToggle(
                  key: const ValueKey('shelf-repeat-fill'),
                  label: '重复填充',
                  value: shelfPreferences.repeatFill,
                  onChanged: (value) => onShelfPreferencesChanged!(
                    shelfPreferences.copyWith(repeatFill: value),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    '关闭重复填充时，每本书只展示一次。展示本数不限制藏书数量。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (target != BookCollectionViewTarget.shelf)
        AnimatedOptionSection(
          expanded: mode.isGrid,
          child: BookGridDensityOptions(
            value: gridDensity,
            viewport: gridViewport,
            onChanged: onGridDensityChanged,
          ),
        ),
      if (target != BookCollectionViewTarget.all &&
          onShowLayoutOptions != null) ...[
        const SizedBox(height: 20),
        GlassTextButton(
          key: const ValueKey('collection-all-layout-options'),
          onPressed: onShowLayoutOptions,
          child: const AppText('整体布局'),
        ),
      ],
    ],
  );

  Widget _contentOptions(BuildContext context) => BookShelfContentOptions(
    value: shelfContent,
    onChanged: onShelfContentChanged!,
    categoryOptions: shelfCategoryOptions,
    sourceOptions: shelfSourceOptions,
    sortOptions: shelfSortOptions,
    hint: shelfContentHint,
    reduceMotion: reduceMotion,
    showHeader: false,
    showFollow: false,
  );
}

/// Content controls are shared by the upper region's own filter button.
class BookShelfContentOptions extends StatelessWidget {
  const BookShelfContentOptions({
    super.key,
    required this.value,
    required this.onChanged,
    this.categoryOptions = const {'_all': '全部书籍'},
    this.sourceOptions = const {},
    this.sortOptions,
    this.hint,
    this.reduceMotion = false,
    this.showHeader = true,
    this.showFollow = true,
    this.showCategory = true,
  });
  final BookShelfContentPreferences value;
  final ValueChanged<BookShelfContentPreferences> onChanged;
  final Map<String, String> categoryOptions, sourceOptions;
  final Map<BookShelfContentSort, String>? sortOptions;
  final String? hint;
  final bool reduceMotion, showHeader, showFollow, showCategory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeader)
        const ArchiveSection(title: '立体书架筛选', code: 'UPPER / FILTER'),
      if (showFollow) ...[
        const SizedBox(height: 16),
        _ShelfToggle(
          label: '跟随下方分类与排序',
          value: value.followCollection,
          onChanged: (follow) =>
              onChanged(value.copyWith(followCollection: follow)),
        ),
      ],
      AnimatedOptionSection(
        expanded: !showFollow || !value.followCollection,
        child: _contentOptions(context),
      ),
    ],
  );

  Widget _contentOptions(BuildContext context) {
    final shelfContent = value;
    final change = onChanged;
    final categories = Map<String, String>.of(categoryOptions);
    final dynamicLabel = shelfContentDynamicCategoryLabel(
      shelfContent.category,
    );
    if (!categories.containsKey(shelfContent.category) &&
        dynamicLabel != null) {
      categories[shelfContent.category] = '$dynamicLabel（暂无匹配）';
    }
    final category = categories.containsKey(shelfContent.category)
        ? shelfContent.category
        : '_all';
    final sources = sourceOptions;
    final source = sources.containsKey(shelfContent.source)
        ? shelfContent.source
        : 'all';
    final sorts =
        sortOptions ??
        const {
          BookShelfContentSort.recentRead: '最近阅读',
          BookShelfContentSort.recentAdded: '最近加入',
          BookShelfContentSort.title: '书名',
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sources.length > 1)
          GlassChoiceGroup<String>(
            name: 'shelf-content-source',
            label: '内容来源',
            value: source,
            options: sources,
            onChanged: (value) =>
                change(shelfContent.copyWith(source: value, category: '_all')),
          ),
        if (showCategory) ...[
          const SizedBox(height: 14),
          GlassSettingMenu<String>(
            key: const ValueKey('shelf-content-category'),
            icon: CupertinoIcons.folder,
            label: '分类',
            value: category,
            options: categories,
            reduceMotion: reduceMotion,
            onChanged: (value) =>
                change(shelfContent.copyWith(category: value)),
          ),
        ],
        GlassChoiceGroup<String>(
          name: 'shelf-content-reading',
          label: '阅读范围',
          value: shelfContent.readingFilter,
          options: const {
            'all': '全部',
            'recent': '最近阅读',
            'unread': '未读',
            'reading': '在读',
            'finished': '已读完',
          },
          onChanged: (value) =>
              change(shelfContent.copyWith(readingFilter: value)),
        ),
        const SizedBox(height: 14),
        GlassSettingMenu<BookShelfContentSort>(
          key: const ValueKey('shelf-content-sort'),
          icon: CupertinoIcons.sort_down,
          label: '排序',
          value: sorts.containsKey(shelfContent.sort)
              ? shelfContent.sort
              : sorts.keys.first,
          options: sorts,
          reduceMotion: reduceMotion,
          onChanged: (value) => change(shelfContent.copyWith(sort: value)),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppText(
              hint!,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ShelfToggle extends StatelessWidget {
  const _ShelfToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: AppText(label, style: const TextStyle(fontSize: 13))),
      const SizedBox(width: 12),
      AppControls.toggle(context, value: value, onChanged: onChanged),
    ],
  );
}

class _ShelfCountSetting extends StatefulWidget {
  const _ShelfCountSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_ShelfCountSetting> createState() => _ShelfCountSettingState();
}

class _ShelfCountSettingState extends State<_ShelfCountSetting> {
  late final _text = TextEditingController(text: '${widget.value}');
  late final _focus = FocusNode()..addListener(_focusChanged);

  void _focusChanged() {
    if (!_focus.hasFocus) _finish();
  }

  void _finish() {
    final value = int.tryParse(_text.text);
    if (value == null || value < 1 || value > BookShelfPreferences.maximum) {
      _text.text = '${widget.value}';
      showNovelFeedback(context, '请输入 1–100 本');
      return;
    }
    _commit(value);
  }

  void _commit(int value) {
    _text.text = '$value';
    if (value != widget.value) widget.onChanged(value);
  }

  void _step(int delta) {
    final value = int.tryParse(_text.text) ?? widget.value;
    _commit((value + delta).clamp(1, BookShelfPreferences.maximum));
  }

  @override
  void didUpdateWidget(_ShelfCountSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus) _text.text = '${widget.value}';
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: AppText(widget.label, style: const TextStyle(fontSize: 13)),
      ),
      const SizedBox(width: 8),
      GlassIconButton(
        icon: CupertinoIcons.minus,
        label: '减少${widget.label}',
        onPressed: widget.value > 1 ? () => _step(-1) : null,
      ),
      SizedBox(
        width: 54,
        child: CupertinoTextField(
          key: ValueKey('${widget.key}-input'),
          controller: _text,
          focusNode: _focus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          textAlign: TextAlign.center,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: const BoxDecoration(),
          onTap: () => _text.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _text.text.length,
          ),
          onTapOutside: (_) => _focus.unfocus(),
          onSubmitted: (_) => _focus.unfocus(),
        ),
      ),
      GlassIconButton(
        icon: CupertinoIcons.plus,
        label: '增加${widget.label}',
        onPressed: widget.value < BookShelfPreferences.maximum
            ? () => _step(1)
            : null,
      ),
    ],
  );
}
