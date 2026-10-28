import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'feature_pages.dart' show confirmNovelAction;
import 'local_library_preferences.dart';
import 'catalog.dart';

/// Shelf and local library use one category vocabulary and assignment store.
Future<void> showBookCategories(
  BuildContext context,
  LocalLibraryPreferences organization, {
  bool shelf = false,
  bool reduceMotion = false,
  Iterable<Novel> books = const [],
  int unknownAuthorCount = 0,
}) async {
  final selected = shelf ? organization.shelfSelected : organization.selected;
  final result = await showJellySheet<String>(
    context: context,
    reduceMotion: reduceMotion,
    heightFactor: .72,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ArchiveSection(title: '书籍分类', code: 'LIBRARY / CATEGORIES'),
          const SizedBox(height: 16),
          for (final entry in {
            LocalLibraryPreferences.all: '全部书籍',
            LocalLibraryPreferences.unfiled: '未分类',
            ...organization.groups,
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: GlassTextButton(
                      onPressed: () => Navigator.pop(sheet, entry.key),
                      child: AppText(
                        '${entry.key == selected ? '✓  ' : ''}${entry.value}',
                      ),
                    ),
                  ),
                  if (!entry.key.startsWith('_')) ...[
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: CupertinoIcons.pencil,
                      label: '重命名 ${entry.value}',
                      onPressed: () =>
                          Navigator.pop(sheet, 'rename:${entry.key}'),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: CupertinoIcons.trash,
                      label: '删除分类 ${entry.value}',
                      onPressed: () =>
                          Navigator.pop(sheet, 'delete:${entry.key}'),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          GlassTextButton(
            key: const ValueKey('category-by-author'),
            onPressed: () => Navigator.pop(sheet, '_authors'),
            child: const AppText('按作者分类'),
          ),
          const SizedBox(height: 12),
          GlassPillButton(
            icon: CupertinoIcons.plus,
            label: '新建分类',
            onPressed: () => Navigator.pop(sheet, '_new'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || result == null) return;
  try {
    if (result == '_authors') {
      final counts = <String, int>{};
      for (final book in books) {
        final author = LocalLibraryPreferences.authorName(book.author);
        counts[author] = (counts[author] ?? 0) + 1;
      }
      if (unknownAuthorCount > 0) {
        counts['未知作者'] = (counts['未知作者'] ?? 0) + unknownAuthorCount;
      }
      final authors = counts.keys.toList()..sort();
      final category = await showJellySheet<String>(
        context: context,
        reduceMotion: reduceMotion,
        heightFactor: .72,
        builder: (sheet) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const ArchiveSection(title: '按作者分类', code: 'LIBRARY / AUTHORS'),
            const SizedBox(height: 16),
            if (authors.isEmpty) const AppText('当前书库暂无作者信息'),
            for (final author in authors)
              GlassTextButton(
                key: ValueKey('category-author-$author'),
                selected:
                    selected == LocalLibraryPreferences.authorCategory(author),
                onPressed: () => Navigator.pop(
                  sheet,
                  LocalLibraryPreferences.authorCategory(author),
                ),
                child: Row(
                  children: [
                    Expanded(child: AppText(author)),
                    const SizedBox(width: 12),
                    AppText(
                      '${counts[author]} 本',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (category != null) await organization.select(category, shelf: shelf);
    } else if (result == '_new' || result.startsWith('rename:')) {
      await showJellySheet<void>(
        context: context,
        reduceMotion: reduceMotion,
        heightFactor: .58,
        builder: (_) => _CategoryNameSheet(
          organization: organization,
          id: result == '_new' ? null : result.substring(7),
        ),
      );
    } else if (result.startsWith('delete:')) {
      if (await confirmNovelAction(
        context,
        title: '删除这个分类？',
        message: '书籍会回到未分类，原书与阅读记录保留。',
        confirmLabel: '删除分类',
        reduceMotion: reduceMotion,
      )) {
        await organization.removeGroup(result.substring(7));
      }
    } else {
      await organization.select(result, shelf: shelf);
    }
  } catch (e) {
    if (context.mounted) {
      showNovelFeedback(
        context,
        e is FormatException ? e.message : '分类保存失败，请重试',
      );
    }
  }
}

Future<String?> chooseBookCategory(
  BuildContext context,
  LocalLibraryPreferences organization, {
  int? bookId,
  Iterable<int>? bookIds,
  bool reduceMotion = false,
}) async {
  final ids = bookIds?.toSet() ?? {?bookId};
  final current = ids.map(organization.groupOf).toSet();
  final result = await showJellySheet<String>(
    context: context,
    reduceMotion: reduceMotion,
    heightFactor: .6,
    builder: (sheet) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const ArchiveSection(title: '移至分类', code: 'LIBRARY / ORGANIZE'),
        const SizedBox(height: 16),
        for (final entry in {
          LocalLibraryPreferences.unfiled: '未分类',
          ...organization.groups,
        }.entries)
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, entry.key),
            child: AppText(
              '${current.length == 1 && current.single == entry.key ? '✓  ' : ''}${entry.value}',
            ),
          ),
        const SizedBox(height: 12),
        GlassPillButton(
          icon: CupertinoIcons.plus,
          label: '新建分类',
          onPressed: () => Navigator.pop(sheet, '_new'),
        ),
      ],
    ),
  );
  if (result != '_new' || !context.mounted) return result;
  await showJellySheet<void>(
    context: context,
    reduceMotion: reduceMotion,
    heightFactor: .58,
    builder: (_) => _CategoryNameSheet(organization: organization),
  );
  if (!context.mounted) return null;
  return chooseBookCategory(
    context,
    organization,
    bookIds: ids,
    reduceMotion: reduceMotion,
  );
}

class _CategoryNameSheet extends StatefulWidget {
  const _CategoryNameSheet({required this.organization, this.id});
  final LocalLibraryPreferences organization;
  final String? id;
  @override
  State<_CategoryNameSheet> createState() => _CategoryNameSheetState();
}

class _CategoryNameSheetState extends State<_CategoryNameSheet> {
  late final text = TextEditingController(
    text: widget.id == null ? '' : widget.organization.groups[widget.id],
  );
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      if (widget.id == null) {
        await widget.organization.addGroup(text.text);
      } else {
        await widget.organization.renameGroup(widget.id!, text.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showNovelFeedback(context, e is FormatException ? e.message : '分类保存失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArchiveSection(
          title: widget.id == null ? '新建分类' : '重命名分类',
          code: 'LIBRARY / CATEGORY',
        ),
        const SizedBox(height: 20),
        CupertinoTextField(
          onTap: () => AppHaptics.play(context, HapticCue.selection),
          onSubmitted: (_) => AppHaptics.play(context, HapticCue.action),
          controller: text,
          enabled: !busy,
          placeholder: appText(context, '分类名称'),
          maxLength: 30,
          padding: const EdgeInsets.all(16),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 18),
        GlassPillButton(
          icon: CupertinoIcons.checkmark,
          label: '保存分类',
          onPressed: busy ? null : save,
        ),
      ],
    ),
  );
}
