import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../app_ui.dart';
import '../app_interactions.dart';
import '../catalog.dart';
import '../library_state.dart';
import 'source_repository.dart';
import 'source_platform_ui.dart';

class ShelfPlatformControls extends StatelessWidget {
  const ShelfPlatformControls({
    super.key,
    required this.state,
    required this.repository,
    this.offline = false,
  });
  final LibraryState state;
  final NovelRepository repository;
  final bool offline;

  List<BookPlatform> get platforms => bookPlatforms(
    sourceRepositoryOf(repository)?.store.sources ?? [],
    includeWenku: true,
  );

  Future<void> _save(
    BuildContext context, {
    String? platform,
    String? location,
  }) async {
    try {
      await state.setShelfView(platform: platform, location: location);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架偏好保存失败，请重试');
    }
  }

  Future<void> _choose(BuildContext context) async {
    final choices = platforms;
    final selected = await showGlassMenu<String>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menu) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(menu).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassMenuItem(
                label: '全部平台',
                selected: state.shelfPlatform == 'all',
                onPressed: () => Navigator.pop(menu, 'all'),
              ),
              for (final (index, platform) in choices.indexed)
                GlassMenuItem(
                  order: index + 1,
                  label: platform.name,
                  selected: state.shelfPlatform == platform.key,
                  onPressed: () => Navigator.pop(menu, platform.key),
                ),
              if (state.combinedShelf)
                GlassMenuItem(
                  label: '本地导入',
                  selected: state.shelfPlatform == 'local',
                  onPressed: () => Navigator.pop(menu, 'local'),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await _save(context, platform: selected);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassTextButton(
            key: const ValueKey('shelf-platform-picker'),
            compact: true,
            onPressed: () => _choose(anchor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  state.shelfPlatform == 'all'
                      ? '全部平台'
                      : state.shelfPlatform == 'local'
                      ? '本地导入'
                      : platforms
                                .where((p) => p.key == state.shelfPlatform)
                                .firstOrNull
                                ?.name ??
                            '已移除的平台',
                ),
                const SizedBox(width: 8),
                const ArchiveIcon(CupertinoIcons.chevron_down, size: 12),
              ],
            ),
          ),
        ),
      ),
      GlassTextButton(
        key: const ValueKey('shelf-location-local'),
        compact: true,
        selected: state.shelfLocation == 'local',
        onPressed: () => _save(context, location: 'local'),
        child: const AppText('本机收藏'),
      ),
      GlassTextButton(
        key: const ValueKey('shelf-location-cloud'),
        compact: true,
        selected: state.shelfLocation == 'cloud',
        onPressed: offline
            ? null
            : () {
                final current = sourceRepositoryOf(repository);
                final selected =
                    state.shelfPlatform == 'all' ||
                        state.shelfPlatform == 'local'
                    ? bookPlatformKey(current?.discoverySource?.key)
                    : state.shelfPlatform;
                unawaited(
                  _save(context, platform: selected, location: 'cloud'),
                );
              },
        child: const AppText('云端收藏'),
      ),
    ],
  );
}
