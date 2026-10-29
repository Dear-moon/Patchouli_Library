import 'package:flutter/cupertino.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'book_documents.dart';
import 'local_books.dart';

class LocalTextRecovery extends StatefulWidget {
  const LocalTextRecovery({
    super.key,
    required this.books,
    required this.bookId,
    this.documents,
    this.allowCopy = false,
    this.onChanged,
  });
  final LocalBookStore books;
  final int bookId;
  final BookDocuments? documents;
  final bool allowCopy;
  final VoidCallback? onChanged;
  @override
  State<LocalTextRecovery> createState() => _LocalTextRecoveryState();
}

class _LocalTextRecoveryState extends State<LocalTextRecovery> {
  bool busy = false;
  Future<void> perform({bool copy = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (copy) {
        await widget.books.saveOriginalCopy(widget.bookId);
      } else {
        final documents = widget.documents ?? BookDocuments();
        final selected = await (widget.books.isLinkedText(widget.bookId)
            ? documents.pickTextReference()
            : documents.pickOriginalReference());
        if (selected == null) return;
        await widget.books.relinkOriginal(widget.bookId, selected.reference!);
      }
      if (mounted) {
        showNovelFeedback(context, copy ? '已保存副本，可独立阅读' : '原文件已重新关联，阅读位置保留');
        widget.onChanged?.call();
      }
    } catch (error) {
      if (mounted) showNovelFeedback(context, linkedTextFailureMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      GlassTextButton(
        key: ValueKey('local-relink-${widget.bookId}'),
        onPressed: busy ? null : () => perform(),
        child: AppText(busy ? '正在处理' : '重新定位原文件'),
      ),
      if (widget.allowCopy)
        GlassTextButton(
          key: ValueKey('local-save-copy-${widget.bookId}'),
          onPressed: busy ? null : () => perform(copy: true),
          child: const AppText('保存副本到应用'),
        ),
    ],
  );
}
