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
  });
  final LocalBookStore books;
  final LibraryState library;
  final Future<void> Function(Novel) onOpen;
  final Widget child;
  final BookDocuments? documents;

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
  String? _opening;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

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
    try {
      do {
        _requested = false;
        while (mounted && _foreground) {
          final request = await documents.pendingOpen();
          if (request == null || !mounted) break;
          try {
            if (request.error case final error?) throw FormatException(error);
            final copy = !widget.library.organization.linkLocalBooks;
            final selected = await documents.resolveOpen(
              request.id,
              copy: copy,
            );
            if (!mounted) break;
            setState(() => _opening = selected.name);
            await importer.run(
              context,
              copyLocal: copy,
              selectedBooks: [selected],
              onImported: (report) async {
                if (!mounted) return;
                if (report.bookIds.length == 1 && report.failures.isEmpty) {
                  final book = widget.books.book(report.bookIds.single);
                  if (book != null) await widget.onOpen(book);
                } else {
                  await pushNovelPage<void>(
                    context,
                    LocalImportReview(
                      books: widget.books,
                      library: widget.library,
                      report: report,
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
