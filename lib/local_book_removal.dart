import 'package:flutter/cupertino.dart';

import 'catalog.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'listening/widgets.dart';
import 'local_books.dart';
import 'local_series_actions.dart';

enum LocalBookRemoval { shelfOnly, files }

Future<LocalBookRemoval?> chooseLocalBookRemoval(
  BuildContext context, {
  required Novel book,
  required LocalBookStore books,
  required LibraryState library,
}) async {
  const choice = LocalBookRemoval.files;
  final series = books.seriesFor(book.id);
  if (!await confirmNovelAction(
    context,
    title: series?.id == book.id ? '删除整部书的本机文件？' : '删除本机文件？',
    message:
        '《${book.title}》${series?.id == book.id ? '的 ${series!.volumes.length} 卷' : ''}将移出书架，并删除 App 内的原书、正文与插图。阅读进度和书签保留。',
    confirmLabel: '删除本机文件',
    reduceMotion: library.reduceMotion,
  )) {
    return null;
  }
  if (!context.mounted) return null;
  final listening = ListeningScope.maybeOf(context);
  final activeId = listening?.snapshot.value.novel?.id;
  if (activeId == book.id ||
      series?.volumes.any((v) => v.bookId == activeId) == true) {
    await listening!.stop();
  }
  await removeLocalBook(books: books, library: library, id: book.id);
  return choice;
}

typedef LocalBooksRemovalResult = ({
  LocalBookRemoval choice,
  Set<int> removed,
  Set<int> failed,
});

/// Bounded file removal. A failed book remains selected and keeps its records.
Future<LocalBooksRemovalResult> removeLocalBooks({
  required Iterable<int> ids,
  required LocalBookRemoval choice,
  required LocalBookStore books,
  required LibraryState library,
  void Function(int completed, int total)? onProgress,
}) async {
  if (choice == LocalBookRemoval.shelfOnly) {
    throw const FormatException('仅移出功能已取消，书籍和文件未变动');
  }
  final selected = ids.where(isLocalBook).where(books.contains).toSet();
  final targets = selected
      .where((id) {
        final owner = books.seriesFor(id);
        return owner == null || owner.id == id || !selected.contains(owner.id);
      })
      .toList(growable: false);
  final removed = <int>{}, failed = <int>{};
  for (final (index, id) in targets.indexed) {
    try {
      await removeLocalBook(books: books, library: library, id: id);
      removed.add(id);
    } catch (_) {
      failed.add(id);
    }
    onProgress?.call(index + 1, targets.length);
  }
  return (choice: choice, removed: removed, failed: failed);
}

Future<LocalBooksRemovalResult?> chooseLocalBooksRemoval(
  BuildContext context, {
  required Iterable<int> ids,
  required LocalBookStore books,
  required LibraryState library,
  void Function(int completed, int total)? onProgress,
}) async {
  final targets = ids.where(isLocalBook).where(books.contains).toSet();
  if (targets.isEmpty) return null;
  const choice = LocalBookRemoval.files;
  if (choice == LocalBookRemoval.files) {
    if (!await confirmNovelAction(
      context,
      title: '删除 ${targets.length} 本书的本机文件？',
      message: '合订本包含的所有分卷也会删除。仅删除 App 内的原书、正文与插图；下载目录和网盘原文件、阅读进度与书签保留。',
      confirmLabel: '删除本机文件',
      reduceMotion: library.reduceMotion,
    )) {
      return null;
    }
    if (!context.mounted) return null;
    final listening = ListeningScope.maybeOf(context);
    final activeId = listening?.snapshot.value.novel?.id;
    if (activeId != null &&
        targets.any(
          (id) =>
              id == activeId ||
              books.seriesFor(id)?.volumes.any((v) => v.bookId == activeId) ==
                  true,
        )) {
      await listening!.stop();
    }
  }
  return removeLocalBooks(
    ids: targets,
    choice: choice,
    books: books,
    library: library,
    onProgress: onProgress,
  );
}
