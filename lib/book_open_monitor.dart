import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_book_importer.dart';
import 'local_import_batch.dart';
import 'local_import_review.dart';

/// Cold and warm system file opens use the same importer as the local library.
/// The inbox is consumed after the first frame, not while routes are building.
class BookOpenMonitor extends StatefulWidget {
  const BookOpenMonitor({
    super.key,
    required this.books,
    required this.library,
    required this.onOpen,
    required this.child,
    this.documents,
    this.onInitialInboxSettled,
    this.onOpenRequested,
  });
  final LocalBookStore books;
  final LibraryState library;
  final Future<void> Function(Novel) onOpen;
  final Widget child;
  final BookDocuments? documents;
  final ValueChanged<bool>? onInitialInboxSettled;
  final VoidCallback? onOpenRequested;

  @override
  State<BookOpenMonitor> createState() => _BookOpenMonitorState();
}

class _BookOpenMonitorState extends State<BookOpenMonitor>
    with WidgetsBindingObserver {
  late final documents = widget.documents ?? BookDocuments();
  late final importer = LocalBookImporter(
    books: widget.books,
    library: widget.library,
    documents: documents,
  );
  bool _draining = false, _requested = false;
  bool _reportedInitialInbox = false;
  String? _opening;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<({BookDocumentSelection selection, bool copy, bool move})?> _resolve(
    BookOpenRequest request,
  ) async {
    var copy = !widget.library.organization.linkLocalBooks;
    var move = false;
    var authorizationFailed = false;
    while (!copy && !request.canLink) {
      final choice = await showJellySheet<String>(
        context: context,
        reduceMotion: widget.library.reduceMotion,
        builder: (sheet) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppText(
                '保存到本地书库',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              AppText(
                request.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (request.sourceName case final source?) ...[
                const SizedBox(height: 6),
                AppText('文件来源：$source'),
              ],
              if (request.sourceLocation case final location?) ...[
                const SizedBox(height: 6),
                AppText('来源内位置：$location'),
              ],
              const SizedBox(height: 14),
              AppText(
                authorizationFailed
                    ? '未获得长期读取权限。仍可保存一份到书库，不必重新找文件。'
                    : request.canLocate
                    ? '关联会尝试在系统文件选择器中定位原文件，仍需确认授权。'
                    : '来源未提供可定位的文档位置。关联需手动选择；保存到书库则无需再找文件。',
              ),
              const SizedBox(height: 8),
              AppText(
                request.canMove
                    ? '移动会在完整保存后删除原文件；复制会保留原文件。'
                    : '复制会保存一份到应用，不修改原文件。此来源不支持直接移动。',
              ),
              const SizedBox(height: 24),
              if (request.canMove) ...[
                GlassTextButton(
                  key: const ValueKey('book-open-move'),
                  onPressed: () => Navigator.pop(sheet, 'move'),
                  child: const AppText('移动到书库'),
                ),
                const SizedBox(height: 10),
              ],
              GlassTextButton(
                key: const ValueKey('book-open-authorize'),
                onPressed: () => Navigator.pop(sheet, 'authorize'),
                child: const AppText('关联原文件'),
              ),
              const SizedBox(height: 10),
              GlassTextButton(
                key: const ValueKey('book-open-copy'),
                onPressed: () => Navigator.pop(sheet, 'copy'),
                child: const AppText('复制到书库'),
              ),
              const SizedBox(height: 8),
              GlassTextButton(
                key: const ValueKey('book-open-cancel'),
                onPressed: () => Navigator.pop(sheet),
                child: const AppText('取消'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return null;
      if (choice == 'authorize') {
        try {
          final selection = await documents.authorizeOpen(request.id);
          if (!mounted || selection == null) return null;
          return (selection: selection, copy: false, move: false);
        } on PlatformException {
          if (!mounted) return null;
          authorizationFailed = true;
          continue;
        }
      }
      move = choice == 'move';
      copy = true;
    }
    final selection = await documents.resolveOpen(request.id, copy: copy);
    return (selection: selection, copy: copy, move: move);
  }

  Future<LocalImportReport> _finishMove(
    BookOpenRequest request,
    LocalImportReport report,
  ) async {
    String? notice;
    if (report.bookIds.length != 1 ||
        report.failures.isNotEmpty ||
        report.notices.isNotEmpty) {
      notice = '未完成移动，原文件未删除。请先处理下面的导入提示。';
    } else {
      String? path;
      try {
        path = await widget.books.verifiedMoveCopy(report.bookIds.single);
      } catch (_) {
        notice = '已复制到书库，原文件未删除。原文件的权限、内容或书库副本未通过删除前核对。';
      }
      if (path != null) {
        try {
          await documents.deleteOpenSource(request.id, path);
        } catch (error) {
          notice =
              error is PlatformException &&
                  {'move_not_deleted', 'move_unavailable'}.contains(error.code)
              ? '已复制到书库，原文件未删除。来源未允许删除，或原文件内容已变化。'
              : '已导入书库，但未能确认原文件是否删除。书库副本已保留，请在来源应用中核对。';
        }
      }
    }
    if (notice == null) return report;
    return LocalImportReport(
      bookIds: report.bookIds,
      added: report.added,
      existing: report.existing,
      failures: report.failures,
      notices: [...report.notices, (name: request.name, message: notice)],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BookDocuments.channel.setMethodCallHandler((call) async {
      if (call.method == 'bookOpenAvailable') unawaited(_drain());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_drain());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  Future<void> _drain() async {
    _requested = true;
    if (_draining || !mounted || !_foreground) return;
    _draining = true;
    var sawRequest = false;
    try {
      do {
        _requested = false;
        while (mounted && _foreground) {
          final request = await documents.pendingOpen();
          if (request == null || !mounted) break;
          sawRequest = true;
          widget.onOpenRequested?.call();
          try {
            if (request.error case final error?) throw FormatException(error);
            final resolved = await _resolve(request);
            if (!mounted) break;
            if (resolved == null) continue;
            final selected = resolved.selection;
            setState(() => _opening = selected.name);
            await importer.run(
              context,
              copyLocal: resolved.copy,
              selectedBooks: [selected],
              onImported: (report) async {
                if (!mounted) return;
                final completed = resolved.move
                    ? await _finishMove(request, report)
                    : report;
                if (!mounted) return;
                if (completed.bookIds.length == 1 &&
                    completed.failures.isEmpty &&
                    (!resolved.move || completed.notices.isEmpty)) {
                  final book = widget.books.book(completed.bookIds.single);
                  if (book != null) await widget.onOpen(book);
                } else {
                  await pushNovelPage<void>(
                    context,
                    LocalImportReview(
                      books: widget.books,
                      library: widget.library,
                      report: completed,
                    ),
                    reduceMotion: widget.library.reduceMotion,
                  );
                }
              },
            );
          } catch (error) {
            if (mounted) {
              showNovelFeedback(context, linkedTextFailureMessage(error));
            }
          } finally {
            await documents.finishOpen(request.id);
            if (mounted) setState(() => _opening = null);
          }
        }
      } while (_requested && mounted && _foreground);
    } on MissingPluginException {
      // Other platforms do not expose Android's file-association inbox.
    } on PlatformException catch (error) {
      if (mounted && error.code != 'NO_ACTIVITY') {
        showNovelFeedback(context, linkedTextFailureMessage(error));
      }
    } finally {
      _draining = false;
      if (!_reportedInitialInbox && mounted) {
        _reportedInitialInbox = true;
        widget.onInitialInboxSettled?.call(sawRequest);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BookDocuments.channel.setMethodCallHandler(null);
    importer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      if (_opening != null)
        Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 96,
          child: IgnorePointer(
            child: ContentPanel(
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppText(
                      '正在打开《$_opening》',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
