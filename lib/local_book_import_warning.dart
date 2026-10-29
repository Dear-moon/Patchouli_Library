import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'book_identity.dart';
import 'catalog.dart';
import 'local_book_import_issues.dart';
import 'local_book_media.dart';

Future<void> showLocalBookImportIssues(
  BuildContext context, {
  required Novel book,
  required LocalBookImportWarningAccess books,
  bool reduceMotion = false,
}) => showJellySheet<void>(
  context: context,
  reduceMotion: reduceMotion,
  heightFactor: .86,
  maxWidth: 640,
  guardDragDismiss: true,
  builder: (_) => LocalBookImportIssuesSheet(book: book, books: books),
);

/// Healthy covers keep their original widget and do not subscribe to the store.
class LocalBookImportWarningCover extends StatelessWidget {
  const LocalBookImportWarningCover({
    super.key,
    required this.book,
    required this.width,
    required this.child,
  });
  final Novel book;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLocalBook(book.id)) return child;
    final books = LocalBookMedia.importWarnings;
    if (books == null || books.importIssues(book.id).isEmpty) return child;
    return AnimatedBuilder(
      animation: books.importWarningChanges,
      child: child,
      builder: (context, cover) => Stack(
        clipBehavior: Clip.none,
        children: [
          cover!,
          if (books.shouldShowImportWarning(book.id))
            Positioned(
              top: 0,
              left: 0,
              child: _ImportWarningBadge(
                book: book,
                books: books,
                size: math.min(40, math.max(32, width * .4)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportWarningBadge extends StatelessWidget {
  const _ImportWarningBadge({
    required this.book,
    required this.books,
    required this.size,
  });
  final Novel book;
  final LocalBookImportWarningAccess books;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = '查看《${book.title}》的导入问题';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          key: ValueKey('local-import-warning-${book.id}'),
          width: size,
          height: size,
          child: JellyTapSurface(
            haptic: HapticCue.selection,
            onTap: () => showLocalBookImportIssues(
              context,
              book: book,
              books: books,
              reduceMotion: MediaQuery.disableAnimationsOf(context),
            ),
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.onErrorContainer.withValues(alpha: .25),
                  ),
                ),
                child: ArchiveIcon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 16,
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LocalBookImportIssuesSheet extends StatefulWidget {
  const LocalBookImportIssuesSheet({
    super.key,
    required this.book,
    required this.books,
  });
  final Novel book;
  final LocalBookImportWarningAccess books;

  @override
  State<LocalBookImportIssuesSheet> createState() =>
      _LocalBookImportIssuesSheetState();
}

class _LocalBookImportIssuesSheetState
    extends State<LocalBookImportIssuesSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _toggleWarning() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.books.setImportWarningHidden(
        widget.book.id,
        widget.books.shouldShowImportWarning(widget.book.id),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '警告显示设置未保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _groupTitle(LocalBookImportIssueKind kind) => switch (kind) {
    LocalBookImportIssueKind.chapter => '章节',
    LocalBookImportIssueKind.image => '插图',
    LocalBookImportIssueKind.resource => '其他资源',
  };

  Widget _issue(LocalBookImportIssue issue, int index) {
    final titles = issue.chapterTitles
        .where((title) => title.trim().isNotEmpty)
        .toList();
    final title = titles.isEmpty
        ? '${_groupTitle(issue.kind)} ${index + 1}'
        : titles.join('、');
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      key: ValueKey((
        'local-import-issue',
        issue.bookId,
        issue.path,
        issue.kind,
      )),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText(
            title,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AppText(
            issue.reason,
            style: const TextStyle(fontSize: 13, height: 1.65),
          ),
          const SizedBox(height: 8),
          SelectableText(
            issue.path,
            style: TextStyle(fontSize: 12, height: 1.6, color: secondary),
          ),
          if (issue.bookId != widget.book.id)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppText(
                '来源书籍 #${issue.bookId}',
                style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.books.importWarningChanges,
    builder: (context, _) {
      final issues = widget.books.importIssues(widget.book.id);
      final visible = widget.books.shouldShowImportWarning(widget.book.id);
      return Padding(
        key: const ValueKey('local-import-issues-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: AppText(
                    '导入问题',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                ),
                GlassTextButton(
                  key: const ValueKey('local-import-warning-toggle'),
                  compact: true,
                  onPressed: _saving ? null : _toggleWarning,
                  child: AppText(
                    _saving
                        ? '正在保存'
                        : visible
                        ? '不再显示警告'
                        : '恢复警告',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppText(
              widget.book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 8),
            AppText(
              '已发现的问题 · ${issues.length} 项',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('local-import-issues-list'),
                slivers: [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: AppText(
                        '如需补齐缺失内容，请获取完整文件后重新导入。',
                        style: TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ),
                  ),
                  for (final kind in LocalBookImportIssueKind.values)
                    if (issues.where((issue) => issue.kind == kind).toList()
                        case final group when group.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ArchiveSection(
                            title: '${_groupTitle(kind)} · ${group.length}',
                            code: 'IMPORT / ISSUES',
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: group.length,
                        itemBuilder: (_, index) => _issue(group[index], index),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
