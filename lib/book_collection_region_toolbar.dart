import 'package:flutter/widgets.dart';

import 'app_ui.dart';
import 'library_toolbar.dart';

/// A region's controls stay beside the books they affect, using the same
/// category, filter and view hit areas as the existing collection toolbar.
class BookCollectionRegionToolbar extends StatelessWidget {
  const BookCollectionRegionToolbar({
    super.key,
    required this.title,
    required this.category,
    required this.count,
    required this.onCategory,
    required this.onFilter,
    required this.onView,
    this.categoryKey,
    this.filterKey,
    this.viewKey,
    this.subtitle,
    this.loading = false,
    this.activeFilters = 0,
    this.onLayout,
    this.layoutKey,
  });
  final String title, category;
  final String? subtitle;
  final int count, activeFilters;
  final bool loading;
  final VoidCallback? onCategory, onFilter, onView, onLayout;
  final Key? categoryKey, filterKey, viewKey, layoutKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: ArchiveSection(
              title: title,
              code: 'COLLECTION / REGION',
              subtitle: subtitle ?? '',
            ),
          ),
          if (onLayout != null) ...[
            const SizedBox(width: 12),
            GlassTextButton(
              key: layoutKey,
              compact: true,
              onPressed: onLayout,
              child: const AppText('整体布局'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      LibraryToolbar(
        category: category,
        count: count,
        onCategory: onCategory,
        onOptions: onFilter,
        onView: onView,
        categoryKey: categoryKey,
        optionsKey: filterKey,
        viewKey: viewKey,
        loading: loading,
        activeFilters: activeFilters,
      ),
    ],
  );
}

/// Picking a region category changes only the caller's view preference, never
/// book membership. Source and follow controls stay in the filter drawer.
Future<String?> chooseBookCollectionRegionCategory(
  BuildContext context, {
  required Map<String, String> options,
  required String selected,
  required bool reduceMotion,
}) => showJellySheet<String>(
  context: context,
  reduceMotion: reduceMotion,
  heightFactor: .72,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '立体书架分类', code: 'UPPER / CATEGORY'),
        const SizedBox(height: 12),
        for (final (index, entry) in options.entries.indexed)
          GlassMenuItem(
            order: index,
            label: entry.value,
            selected: entry.key == selected,
            onPressed: () => Navigator.pop(sheet, entry.key),
          ),
      ],
    ),
  ),
);
