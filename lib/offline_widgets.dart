import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'archive_progress.dart';
import 'app_interactions.dart';
import 'catalog.dart';
import 'offline_cache.dart';
import 'offline_repository.dart';

class OfflineBookStatus extends StatelessWidget {
  const OfflineBookStatus({
    super.key,
    required this.repository,
    required this.novel,
    this.localDirectory = false,
    this.reduceMotion = false,
  });
  final OfflineNovelRepository repository;
  final Novel novel;
  final bool localDirectory, reduceMotion;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: repository.bookChanges(novel.id),
      builder: (context, _) {
        final job = repository.jobFor(novel.id);
        final saved = repository.cache.book(novel.id);
        final count = saved == null
            ? 0
            : identical(saved.novel.chapters, novel.chapters)
            ? saved.cachedCount
            : novel.chapters
                  .where(
                    (chapter) => saved.chapterBytes.containsKey(chapter.id),
                  )
                  .length;
        final label =
            job?.active == true ||
                job?.phase == DownloadPhase.failed ||
                job?.phase == DownloadPhase.cancelled
            ? job!.label
            : novel.chapters.isEmpty
            ? '暂无章节缓存'
            : '${localDirectory ? '本地目录 · ' : ''}缓存 $count / ${novel.chapters.length} 章'
                  '${(saved?.illustrationBytes.length ?? 0) > 0 ? ' · ${saved!.illustrationBytes.length} 张插图' : ''}';
        return AppText(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.5,
          ),
        );
      },
    );
    return reduceMotion || MediaQuery.disableAnimationsOf(context)
        ? content
        : AnimatedSize(
            duration: NovelMotion.enter,
            reverseDuration: NovelMotion.exit,
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: content,
          );
  }
}

enum _BookAction { all, next, retry, cancel, remove }

class OfflineBookMenu extends StatelessWidget {
  const OfflineBookMenu({
    super.key,
    required this.repository,
    required this.novel,
    this.startChapter = 0,
    this.reduceMotion = false,
  });
  final OfflineNovelRepository repository;
  final Novel novel;
  final int startChapter;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository.bookChanges(novel.id),
    builder: (context, _) {
      final job = repository.jobFor(novel.id);
      final active = job?.active == true;
      final done = job?.phase == DownloadPhase.completed;
      return GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => ArchiveTransferButton(
            key: ValueKey('book-cache-action-${novel.id}'),
            icon: done
                ? CupertinoIcons.check_mark
                : CupertinoIcons.cloud_download,
            label: active ? '取消缓存' : '离线缓存',
            working: active,
            completed: done,
            value: job?.phase == DownloadPhase.queued
                ? 0
                : (job?.total ?? 0) > 0
                ? job!.completed / job.total
                : null,
            status: job?.label,
            reduceMotion: reduceMotion,
            onPressed: active
                ? () => repository.cancel(novel.id)
                : () => _show(anchor),
          ),
        ),
      );
    },
  );

  Future<void> _show(BuildContext context) async {
    final job = repository.jobFor(novel.id);
    final selected = await showGlassMenu<_BookAction>(
      context: context,
      reduceMotion: reduceMotion || MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job?.active == true)
            GlassMenuItem(
              label: '取消缓存',
              onPressed: () => Navigator.pop(menu, _BookAction.cancel),
            )
          else ...[
            GlassMenuItem(
              label: '缓存全部章节',
              onPressed: () => Navigator.pop(menu, _BookAction.all),
            ),
            if (novel.chapters.isNotEmpty)
              GlassMenuItem(
                order: 1,
                label: '缓存后续 20 章',
                onPressed: () => Navigator.pop(menu, _BookAction.next),
              ),
            if (job?.phase == DownloadPhase.failed ||
                job?.phase == DownloadPhase.cancelled)
              GlassMenuItem(
                order: 2,
                label: '继续缓存',
                onPressed: () => Navigator.pop(menu, _BookAction.retry),
              ),
          ],
          if (repository.cache.book(novel.id) != null)
            GlassMenuItem(
              order: 3,
              label: '清除这本缓存',
              onPressed: () => Navigator.pop(menu, _BookAction.remove),
            ),
        ],
      ),
    );
    if (!context.mounted || selected == null) return;
    switch (selected) {
      case _BookAction.all:
        repository.download(novel);
        return;
      case _BookAction.next:
        final start = startChapter.clamp(0, novel.chapters.length - 1);
        repository.download(
          novel,
          chapterIds: novel.chapters
              .skip(start)
              .take(20)
              .map((c) => c.id)
              .toSet(),
        );
        return;
      case _BookAction.retry:
        repository.retry(novel.id);
        return;
      case _BookAction.cancel:
        repository.cancel(novel.id);
        return;
      case _BookAction.remove:
        if (await _confirmClear(
          context,
          '清除这本缓存',
          reduceMotion: reduceMotion,
        )) {
          try {
            await repository.removeCachedBook(novel.id);
          } catch (_) {
            if (context.mounted) _storageFailure(context);
          }
        }
    }
  }
}

Future<bool> _confirmClear(
  BuildContext context,
  String label, {
  bool reduceMotion = false,
}) async =>
    await showGlassMenu<bool>(
      context: context,
      reduceMotion: reduceMotion || MediaQuery.disableAnimationsOf(context),
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuItem(
            label: label,
            onPressed: () => Navigator.pop(menu, true),
          ),
          GlassMenuItem(
            order: 1,
            label: '保留缓存',
            onPressed: () => Navigator.pop(menu, false),
          ),
        ],
      ),
    ) ==
    true;

void _storageFailure(BuildContext context) =>
    showNovelFeedback(context, '缓存操作失败，请重试');

/// Uses the same queue and durable byte inventory as the cache-management page.
class OfflineVolumeCacheSheet extends StatefulWidget {
  const OfflineVolumeCacheSheet({
    super.key,
    required this.repository,
    required this.novel,
  });
  final OfflineNovelRepository repository;
  final Novel novel;

  @override
  State<OfflineVolumeCacheSheet> createState() =>
      _OfflineVolumeCacheSheetState();
}

class _OfflineVolumeCacheSheetState extends State<OfflineVolumeCacheSheet> {
  late Future<void> _loaded = widget.repository.loadCache();
  late final _volumes = NovelVolume.of(widget.novel.chapters);
  late final _ids = {
    for (final volume in _volumes)
      volume.key: widget.novel.chapters
          .skip(volume.start)
          .take(volume.length)
          .map((c) => c.id)
          .toSet(),
  };
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(650, MediaQuery.sizeOf(context).height * .76),
    child: FutureBuilder<void>(
      future: _loaded,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: GlassTextButton(
              onPressed: () =>
                  setState(() => _loaded = widget.repository.loadCache()),
              child: const AppText('缓存信息读取失败，点按重试'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CupertinoActivityIndicator());
        }
        return AnimatedBuilder(
          animation: widget.repository.bookChanges(widget.novel.id),
          builder: (context, _) => _contents(context),
        );
      },
    ),
  );

  Widget _contents(BuildContext context) {
    final repository = widget.repository;
    final saved = repository.cache.book(widget.novel.id);
    final sizes = saved?.chapterBytes ?? const <int, int>{};
    final job = repository.jobFor(widget.novel.id);
    final active = job?.active == true;
    final missingVolumes = _volumes
        .where((v) => _ids[v.key]!.any((id) => !sizes.containsKey(id)))
        .toList();
    final selected = missingVolumes
        .where((v) => _selected.contains(v.key))
        .toList();
    final missingIds = {
      for (final volume in selected)
        for (final id in _ids[volume.key]!)
          if (!sizes.containsKey(id)) id,
    };
    final samples = widget.novel.chapters
        .map((c) => sizes[c.id])
        .whereType<int>()
        .toList();
    final estimate = samples.isEmpty
        ? null
        : (samples.fold<int>(0, (a, b) => a + b) /
                  samples.length *
                  missingIds.length)
              .ceil();
    final allSelected =
        missingVolumes.isNotEmpty && selected.length == missingVolumes.length;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final primaryLabel = active
        ? '正在缓存'
        : missingVolumes.isEmpty
        ? '已全部缓存'
        : selected.isEmpty
        ? '请选择卷'
        : '缓存 ${selected.length} 卷\n${estimate == null ? '大小待下载后统计' : '正文约 ${formatCacheBytes(estimate)}'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 4),
          child: Row(
            children: [
              const Expanded(
                child: AppText(
                  '离线缓存',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (active)
                GlassTextButton(
                  onPressed: () => repository.cancel(widget.novel.id),
                  child: const AppText('取消缓存'),
                ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭缓存列表',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: AppText(
            '已占用 ${formatCacheBytes(saved?.bytes ?? 0)} · 含已缓存插图',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
        if (job != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppText(
                    job.label,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                if (!active &&
                    (job.phase == DownloadPhase.failed ||
                        job.phase == DownloadPhase.cancelled))
                  GlassTextButton(
                    onPressed: () => repository.retry(widget.novel.id),
                    child: const AppText('继续缓存'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _volumes.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (context, index) {
              final volume = _volumes[index];
              final ids = _ids[volume.key]!;
              final count = ids.where(sizes.containsKey).length;
              final bytes = ids.fold<int>(
                0,
                (total, id) => total + (sizes[id] ?? 0),
              );
              final cached = count == ids.length;
              final checked = cached || _selected.contains(volume.key);
              return Semantics(
                checked: checked,
                enabled: !cached && !active,
                child: JellyTapSurface(
                  key: ValueKey('cache-volume-${volume.key}'),
                  onTap: cached || active
                      ? null
                      : () => setState(() {
                          if (!_selected.add(volume.key)) {
                            _selected.remove(volume.key);
                          }
                        }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                volume.title.isEmpty ? '全部章节' : volume.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AppText(
                                count == 0
                                    ? '${ids.length} 章 · 未缓存'
                                    : '${cached ? '已缓存' : '已缓存 $count / ${ids.length} 章'} · 正文占用 ${formatCacheBytes(bytes)}',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ArchiveIcon(
                          checked
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 22,
                          color: cached ? muted : null,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (estimate != null && selected.isNotEmpty && !active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppText(
                    '正文大小按已缓存章节估算，插图以下载后实际占用为准。',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
              Row(
                children: [
                  GlassTextButton(
                    key: const ValueKey('cache-select-uncached'),
                    onPressed: active || missingVolumes.isEmpty
                        ? null
                        : () => setState(() {
                            if (allSelected) {
                              _selected.clear();
                            } else {
                              _selected.addAll(
                                missingVolumes.map((v) => v.key),
                              );
                            }
                          }),
                    child: AppText(
                      allSelected ? '取消全选' : '全选未缓存',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassPillButton(
                      key: const ValueKey('cache-selected-volumes'),
                      icon: active
                          ? CupertinoIcons.arrow_down
                          : CupertinoIcons.cloud_download,
                      label: primaryLabel,
                      fontSize: 12,
                      onPressed: active || missingIds.isEmpty
                          ? null
                          : () => repository.download(
                              widget.novel,
                              chapterIds: {
                                for (final volume in selected)
                                  ..._ids[volume.key]!,
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({
    super.key,
    required this.repository,
    required this.onOpen,
    this.reduceMotion = false,
  });
  final OfflineNovelRepository repository;
  final void Function(BuildContext context, Novel novel) onOpen;
  final bool reduceMotion;

  @override
  State<OfflineCachePage> createState() => _OfflineCachePageState();
}

class _OfflineCachePageState extends State<OfflineCachePage> {
  late Future<void> _loaded = widget.repository.loadCache();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: () => Navigator.pop(context),
          ),
          title: const ArchiveRouteTitle(
            title: '离线缓存',
            code: 'ARCHIVE / LOCAL STORAGE',
          ),
          actions: [
            GlassMenuAnchor(
              child: Builder(
                builder: (anchor) => GlassIconButton(
                  icon: CupertinoIcons.trash,
                  label: '清空缓存',
                  onPressed: () => _clear(anchor),
                ),
              ),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _loaded,
          builder: (context, snapshot) => LoadedContentSequence(
            generation:
                snapshot.connectionState == ConnectionState.done ||
                    widget.repository.cache.books.isNotEmpty
                ? 'cache-ready'
                : null,
            child: AnimatedBuilder(
              animation: widget.repository,
              builder: (context, _) {
                final books = widget.repository.cache.books;
                final known = books.map((b) => b.novel.id).toSet();
                final pending = widget.repository.jobs
                    .where((j) => !known.contains(j.novel.id))
                    .toList();
                final count = books.length + pending.length;
                final loading =
                    snapshot.connectionState != ConnectionState.done &&
                    count == 0;
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.paddingOf(context).top +
                        FrostedHeader.toolbarHeight +
                        20,
                    24,
                    MediaQuery.paddingOf(context).bottom + 28,
                  ),
                  itemCount: loading ? 4 : count + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return LoadedContentItem(
                        index: 0,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              sectionHeader(
                                context,
                                '本地存储',
                                formatCacheBytes(widget.repository.cache.bytes),
                              ),
                              const SizedBox(height: 12),
                              const AppText(
                                '已缓存正文与插图可离线阅读。清理缓存不会移出书架，也不会删除阅读进度。',
                                style: TextStyle(fontSize: 13, height: 1.7),
                              ),
                              if (snapshot.hasError ||
                                  widget.repository.cacheError != null) ...[
                                const SizedBox(height: 12),
                                const AppText('缓存读取或写入失败，请释放存储后重试。'),
                                GlassTextButton(
                                  onPressed: () => setState(
                                    () =>
                                        _loaded = widget.repository.loadCache(),
                                  ),
                                  child: const AppText('重试'),
                                ),
                              ] else if (!loading && count == 0)
                                const Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: AppText('暂无离线缓存，在图书详情中缓存章节。'),
                                ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (loading) return const BookRowSkeleton(label: '正在读取缓存');
                    final novel = index <= books.length
                        ? books[index - 1].novel
                        : pending[index - books.length - 1].novel;
                    return LoadedContentItem(
                      key: ValueKey('offline-book-${novel.id}'),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ContentPanel(
                          onTap: novel.chapters.isEmpty
                              ? null
                              : () => widget.onOpen(context, novel),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      novel.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    OfflineBookStatus(
                                      repository: widget.repository,
                                      novel: novel,
                                      reduceMotion: widget.reduceMotion,
                                    ),
                                    const SizedBox(height: 4),
                                    AppText(
                                      formatCacheBytes(
                                        widget.repository.cache
                                                .book(novel.id)
                                                ?.bytes ??
                                            0,
                                      ),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              OfflineBookMenu(
                                repository: widget.repository,
                                novel: novel,
                                reduceMotion: widget.reduceMotion,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _clear(BuildContext context) async {
    if (!await _confirmClear(
      context,
      '清空全部缓存',
      reduceMotion: widget.reduceMotion,
    )) {
      return;
    }
    try {
      await widget.repository.clearCache();
    } catch (_) {
      if (context.mounted) _storageFailure(context);
    }
  }
}
