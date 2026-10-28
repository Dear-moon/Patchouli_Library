import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_interactions.dart';
import '../app_ui.dart';
import 'book_platform.dart';
export 'book_platform.dart';
import 'source_repository.dart';

class BookPlatformMark extends StatelessWidget {
  const BookPlatformMark(this.mark, {super.key});
  final String mark;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 30,
      height: 34,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.onSurface,
      child: AppText(
        mark,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Theme.of(context).colorScheme.surface,
          fontWeight: FontWeight.w800,
          fontSize: 14,
          letterSpacing: -.7,
        ),
      ),
    ),
  );
}

class DiscoveryPlatformHeader extends StatelessWidget {
  const DiscoveryPlatformHeader({
    super.key,
    required this.repository,
    required this.reduceMotion,
  });
  final SourceNovelRepository? repository;
  final bool reduceMotion;

  Future<void> _choose(BuildContext context) async {
    final repo = repository!;
    final selected = await showGlassMenu<String>(
      context: context,
      reduceMotion: reduceMotion,
      builder: (_) =>
          _PlatformMenu(repository: repo, reduceMotion: reduceMotion),
    );
    if (selected == null) return;
    try {
      await repo.store.select(
        selected,
        repo.store.source(selected)?.data['linkOnly'] == true ? 'stored' : null,
      );
    } catch (error) {
      if (context.mounted) {
        showNovelFeedback(context, sourceErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    if (repo == null) {
      return const ArchiveMasthead(
        title: '轻小说文库',
        code: 'WENKU8 / READING ARCHIVE',
        brand: true,
      );
    }
    return AnimatedBuilder(
      animation: repo,
      builder: (context, _) {
        final platforms = bookPlatforms(
          repo.enabled.where((source) => source.exploreEnabled),
          includeWenku: repo.legacy != null,
        );
        final source = repo.discoverySource;
        final selected = platforms
            .where(
              (platform) => repo.legacySelected
                  ? platform.isWenku
                  : platform.sources.any((entry) => entry.key == source?.key),
            )
            .firstOrNull;
        return GlassMenuAnchor(
          child: Builder(
            builder: (anchor) => LiquidGlass(
              key: const ValueKey('discovery-platform-picker'),
              radius: 16,
              semanticLabel: '切换平台，当前${selected?.name ?? '未选择'}',
              onTap: () => _choose(anchor),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    BookPlatformMark(selected?.mark ?? '+'),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ArchiveMasthead(
                        title: selected?.name ?? '选择平台',
                        code: selected != null && selected.sources.length > 1
                            ? '${source!.name.split(' · ').last} / ${selected.mark}'
                            : selected?.code ?? 'READING ARCHIVE',
                      ),
                    ),
                    const SizedBox(width: 6),
                    const ArchiveIcon(CupertinoIcons.chevron_down, size: 13),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlatformMenu extends StatefulWidget {
  const _PlatformMenu({required this.repository, required this.reduceMotion});
  final SourceNovelRepository repository;
  final bool reduceMotion;
  @override
  State<_PlatformMenu> createState() => _PlatformMenuState();
}

class _PlatformMenuState extends State<_PlatformMenu> {
  BookPlatform? _platform;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final platforms = bookPlatforms(
      repo.enabled.where((source) => source.exploreEnabled),
      includeWenku: repo.legacy != null,
    );
    final platform = _platform;
    final quiet =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    Widget resize(Widget child) => quiet
        ? child
        : AnimatedSize(
            duration: NovelMotion.enter,
            curve: NovelMotion.ease,
            alignment: Alignment.topCenter,
            child: child,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .65,
      ),
      child: SingleChildScrollView(
        child: resize(
          AnimatedSwitcher(
            key: const ValueKey('platform-menu-transition'),
            duration: quiet ? Duration.zero : NovelMotion.enter,
            reverseDuration: quiet ? Duration.zero : NovelMotion.exit,
            switchInCurve: NovelMotion.ease,
            switchOutCurve: NovelMotion.retract,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [
                for (final child in previous)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: child),
                  ),
                ?current,
              ],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .035),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey('platform-menu-${platform?.key ?? 'root'}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (platform == null)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: AppText(
                      '切换平台',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  GlassTextButton(
                    key: const ValueKey('platform-menu-back'),
                    compact: true,
                    onPressed: () => setState(() => _platform = null),
                    child: Row(
                      children: [
                        const ArchiveIcon(
                          CupertinoIcons.chevron_left,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        AppText(platform.name),
                      ],
                    ),
                  ),
                if (platform == null)
                  for (final (index, item) in platforms.indexed)
                    GlassMenuItem(
                      key: ValueKey('discovery-platform-${item.key}'),
                      order: index,
                      label:
                          '${item.name}${item.sources.length > 1 ? '  ›' : ''}',
                      selected: item.isWenku
                          ? repo.legacySelected
                          : item.sources.any(
                              (source) =>
                                  source.key == repo.discoverySource?.key,
                            ),
                      onPressed: () => item.sources.length > 1
                          ? setState(() => _platform = item)
                          : Navigator.pop(
                              context,
                              item.isWenku ? item.key : item.sources.single.key,
                            ),
                    )
                else
                  for (final (index, source) in platform.sources.indexed)
                    GlassMenuItem(
                      key: ValueKey('discovery-platform-source-${source.key}'),
                      order: index,
                      label: source.name,
                      selected: source.key == repo.discoverySource?.key,
                      onPressed: () => Navigator.pop(context, source.key),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
