import 'package:flutter/cupertino.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'feature_pages.dart';
import 'library_incremental_sync.dart';

class LibrarySyncConflictsPage extends StatefulWidget {
  const LibrarySyncConflictsPage({super.key, required this.sync});
  final LibraryIncrementalSync sync;
  @override
  State<LibrarySyncConflictsPage> createState() =>
      _LibrarySyncConflictsPageState();
}

class _LibrarySyncConflictsPageState extends State<LibrarySyncConflictsPage> {
  bool _busy = false;
  Future<void> _choose(String id, LibraryVariant variant) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.sync.resolve(id, variant);
    } catch (e) {
      if (mounted) {
        showNovelFeedback(
          context,
          e is FormatException ? e.message : '选择未保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '同步冲突',
    code: 'LIBRARY / REVIEW',
    child: AnimatedBuilder(
      animation: widget.sync,
      builder: (context, _) {
        final conflicts = widget.sync.conflicts;
        return ListView.builder(
          padding: featurePadding(context),
          itemCount: conflicts.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: AppText(
                  conflicts.isEmpty
                      ? '没有待处理的冲突。'
                      : '两台设备分别修改了同一条记录。所有版本都已保留，选择要继续使用的一项；删除与修改冲突时暂按删除处理，避免旧记录重新出现。',
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
              );
            }
            final id = conflicts[index - 1];
            final variants = widget.sync.alternatives(id);
            final current = widget.sync.current(id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ContentPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      widget.sync.title(id),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final variant in variants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppText(
                              widget.sync.describe(variant),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.6),
                            ),
                            const SizedBox(height: 6),
                            GlassTextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _choose(id, variant),
                              child: AppText(
                                variant.deleted
                                    ? '保留删除'
                                    : variant.version == current?.version
                                    ? '保留当前项'
                                    : '改用这一项',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
