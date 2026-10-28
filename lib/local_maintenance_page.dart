import 'package:flutter/cupertino.dart';
import 'app_ui.dart';
import 'archive_progress.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_coordinate_upgrade.dart';
import 'offline_cache.dart' show formatCacheBytes;

class LocalMaintenancePage extends StatefulWidget {
  const LocalMaintenancePage({
    super.key,
    required this.books,
    required this.library,
    required this.selected,
  });
  final LocalBookStore books;
  final LibraryState library;
  final Set<int> selected;
  @override
  State<LocalMaintenancePage> createState() => _LocalMaintenancePageState();
}

class _LocalMaintenancePageState extends State<LocalMaintenancePage> {
  final _tasks = {...LocalMaintenanceTask.values};
  final _results = <({String title, String message, bool failed})>[];
  bool _busy = false, _stop = false;
  int _done = 0, _total = 0, _freed = 0;
  String? _current;
  static const _labels = {
    LocalMaintenanceTask.layout: '升级排版',
    LocalMaintenanceTask.covers: '重建封面',
    LocalMaintenanceTask.storage: '整理存储',
  };
  static const _descriptions = {
    LocalMaintenanceTask.layout: '补回原书注音、注释与样式，保留目录、书签和阅读位置。',
    LocalMaintenanceTask.covers: '从原书恢复缺失封面，不覆盖你选过的封面。',
    LocalMaintenanceTask.storage: '压缩 TXT 阅读副本，清理 EPUB 重复资源；原书与阅读记录保留。',
  };
  Future<void> _run() async {
    if (_busy || _tasks.isEmpty) return;
    final ids = widget.books.maintenanceOriginals(widget.selected);
    final tasks = LocalMaintenanceTask.values.where(_tasks.contains).toList();
    setState(() {
      _busy = true;
      _stop = false;
      _done = 0;
      _freed = 0;
      _total = ids.length * tasks.length;
      _results.clear();
    });
    try {
      for (final id in ids) {
        var layoutFailed = false;
        for (final task in tasks) {
          if (_stop || !mounted) return;
          final title = widget.books.book(id)?.title ?? '本地书籍';
          setState(() => _current = title);
          try {
            if (layoutFailed && task == LocalMaintenanceTask.storage) {
              _results.add((
                title: title,
                message: '排版未升级，暂不清理旧资源',
                failed: false,
              ));
            } else {
              final result = await widget.books.maintain(id, task);
              _freed += result.freedBytes;
              _results.add((
                title: title,
                message: result.message,
                failed: false,
              ));
            }
          } catch (error) {
            layoutFailed |= task == LocalMaintenanceTask.layout;
            _results.add((
              title: title,
              message: error is FormatException
                  ? error.message.toString()
                  : '未完成，原书与阅读记录保留，可重试',
              failed: true,
            ));
          }
          if (mounted) setState(() => _done++);
        }
      }
    } finally {
      // Stopping after the current operation must still persist the anchors
      // of completed upgrades before the page can close or a backup is made.
      try {
        await normalizeLocalReadingRecords(widget.books, widget.library);
      } catch (_) {
        if (mounted) {
          _results.add((
            title: '阅读记录',
            message: '定位信息暂未保存，旧定位仍可读取，可再次整理',
            failed: true,
          ));
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _current = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ArchiveFeaturePage(
      title: '修复与整理',
      code: 'LOCAL / MAINTENANCE',
      canPop: !_busy,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: featurePadding(context).copyWith(bottom: 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ArchiveSection(
                    title: '${widget.selected.length} 本书',
                    code: '保留原书与阅读记录',
                  ),
                  const SizedBox(height: 16),
                  for (final task in LocalMaintenanceTask.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ContentPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AppText(
                                    _labels[task]!,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                AppControls.toggle(
                                  context,
                                  value: _tasks.contains(task),
                                  onChanged: _busy
                                      ? null
                                      : (enabled) => setState(() {
                                          enabled
                                              ? _tasks.add(task)
                                              : _tasks.remove(task);
                                        }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AppText(
                              _descriptions[task]!,
                              style: const TextStyle(fontSize: 12, height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ArchiveTransferButton(
                        key: const ValueKey('local-maintenance-run'),
                        icon: CupertinoIcons.wand_stars,
                        label: _busy ? '停止整理' : '开始整理',
                        working: _busy,
                        value: _total == 0 ? null : _done / _total,
                        reduceMotion: widget.library.reduceMotion,
                        onPressed: _busy
                            ? () => setState(() => _stop = true)
                            : _tasks.isEmpty
                            ? null
                            : _run,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              _busy ? (_stop ? '正在停止' : '正在整理') : '开始整理',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AppText(
                              _busy
                                  ? '${_stop ? '完成当前操作后停止' : _current ?? '正在整理'} · $_done/$_total'
                                  : _results.isEmpty
                                  ? '支持 TXT 与 EPUB，合订本按原卷处理。'
                                  : '${_stop
                                        ? '已停止'
                                        : _results.any((r) => r.failed)
                                        ? '${_results.where((r) => r.failed).length} 项未完成'
                                        : '已完成'} · 释放 ${formatCacheBytes(_freed)}',
                              style: const TextStyle(fontSize: 12, height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const ArchiveSection(title: '处理结果', code: 'RESULTS'),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            sliver: SliverList.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final result = _results[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ContentPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          result.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        AppText(
                          result.message,
                          style: const TextStyle(fontSize: 12, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
