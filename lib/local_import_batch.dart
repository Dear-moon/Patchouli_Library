import 'book_documents.dart';
import 'catalog.dart';
import 'cloud_sources.dart' show cloudFailureMessage;
import 'local_books.dart';
import 'local_book_series.dart';

typedef LocalImportFailure = ({String name, String message});
typedef LocalImportNotice = ({String name, String message});

class LocalImportReport {
  const LocalImportReport({
    required this.bookIds,
    required this.added,
    required this.existing,
    this.failures = const [],
    this.notices = const [],
  });
  final List<int> bookIds;
  final int added, existing;
  final List<LocalImportFailure> failures;
  final List<LocalImportNotice> notices;
  String get summary => [
    if (added > 0) '已导入 $added 本',
    if (existing > 0) '$existing 本已在书库',
    if (failures.isNotEmpty) '${failures.length} 本未导入',
    if (notices.isNotEmpty)
      '${notices.map((n) => n.name).toSet().length} 本有导入提示',
  ].join(' · ');
}

/// Read/parse one source at a time. A bad document must not discard the rest
/// of a user-selected batch, and no merge prompt interrupts this operation.
Future<LocalImportReport> importLocalBatch({
  required List<BookDocumentSelection> selections,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  Future<Novel> Function(String name, String reference)? importReference,
  Future<Novel> Function(BookDocumentSelection selection)? importSelection,
  void Function(int completed, int total)? onProgress,
  Future<void> Function(BookDocumentSelection selected)? onConsumed,
}) async {
  final ids = <int>{};
  final failures = <LocalImportFailure>[];
  final notices = <LocalImportNotice>[];
  var added = 0, existing = 0;
  for (final (index, selected) in selections.indexed) {
    try {
      if (selected.error case final error?) throw FormatException(error);
      final before = books.originals.length;
      final book = importSelection != null
          ? await importSelection(selected)
          : selected.reference == null
          ? await importFile(selected.name, selected.path!)
          : await (importReference ??
                ((_, _) async => throw const FormatException('此入口不支持关联原文件')))(
              selected.name,
              selected.reference!,
            );
      ids.add(book.id);
      notices.addAll(
        books
            .importWarnings(book.id)
            .map((message) => (name: selected.name, message: message)),
      );
      if (books.originals.length > before) {
        added++;
      } else {
        existing++;
      }
    } catch (error) {
      if (selected.error != null) {}
      failures.add((name: selected.name, message: cloudFailureMessage(error)));
    } finally {
      await onConsumed?.call(selected);
    }
    onProgress?.call(index + 1, selections.length);
  }
  return LocalImportReport(
    bookIds: ids.toList(),
    added: added,
    existing: existing,
    failures: failures,
    notices: notices,
  );
}

/// The next selected original is copied only after the previous one has been
/// imported and released. Scanner/cloud callers keep ownership of their input;
/// this operation owns only files it stages or converts itself.
Future<LocalImportReport> importLocalDocuments({
  required List<BookDocumentSelection> selections,
  required BookDocuments documents,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  Future<Novel> Function(String name, String reference)? importReference,
  Future<Novel> Function(BookDocumentSelection selection)? importSelection,
  bool releaseSources = false,
  void Function(int completed, int total)? onProgress,
  void Function(Iterable<BookDocumentSelection> remaining)? onCleanupFailed,
}) async {
  final ids = <int>{};
  final failures = <LocalImportFailure>[];
  final notices = <LocalImportNotice>[];
  var added = 0, existing = 0, done = 0, total = selections.length;
  onProgress?.call(done, total);
  for (final selected in selections) {
    final owned = <BookDocumentSelection>[];
    if (releaseSources || selected.token != null) owned.add(selected);
    Future<void> release(Iterable<BookDocumentSelection> items) async {
      final ready = items.toList();
      if (ready.isEmpty) return;
      try {
        await documents.releaseBooks(ready);
        owned.removeWhere(ready.contains);
      } catch (_) {
        // The book is durable already. Retry cleanup after the batch rather
        // than turn a successful import into a failed/duplicate book.
      }
    }

    try {
      final source = await documents.stageForImport(selected);
      if (selected.token != null && source.path != null) owned.add(source);
      final prepared = source.error != null
          ? [source]
          : await documents.prepareBook(source);
      if (prepared.isEmpty) throw const FormatException('文件中没有可导入的书籍');
      for (final item in prepared) {
        if (item.path != null && item.path != source.path) owned.add(item);
      }
      total += prepared.length - 1;
      final report = await importLocalBatch(
        selections: prepared,
        books: books,
        importFile: importFile,
        importReference: importReference,
        importSelection: importSelection,
        onConsumed: (item) async {
          if (owned.contains(item)) await release([item]);
        },
        onProgress: (count, _) => onProgress?.call(done + count, total),
      );
      done += prepared.length;
      ids.addAll(report.bookIds);
      added += report.added;
      existing += report.existing;
      failures.addAll(report.failures);
      notices.addAll(report.notices);
    } catch (error) {
      done++;
      failures.add((name: selected.name, message: cloudFailureMessage(error)));
      onProgress?.call(done, total);
    } finally {
      await release(owned.toList());
      if (owned.isNotEmpty) onCleanupFailed?.call(owned);
    }
  }
  return LocalImportReport(
    bookIds: ids.toList(),
    added: added,
    existing: existing,
    failures: failures,
    notices: notices,
  );
}

class LocalImportGroup {
  const LocalImportGroup({
    required this.seed,
    required this.title,
    required this.volumes,
    this.targetId,
    this.needsTarget = false,
  });
  final int seed;
  final String title;
  final int? targetId;
  final bool needsTarget;
  final List<({int bookId, String title})> volumes;
}

/// Suggestions only. The caller presents all groups after the batch finishes;
/// durable originals and reading records are changed only on confirmation.
List<LocalImportGroup> localImportGroups(
  LocalBookStore books,
  Iterable<int> ids,
) {
  final groups = <LocalImportGroup>[];
  final claimed = <int>{};
  for (final id in ids) {
    if (claimed.contains(id) || books.seriesFor(id) != null) continue;
    final related = books.relatedVolumes(id);
    if (related.isEmpty) continue;
    final targets = related
        .map((b) => books.seriesFor(b.id))
        .whereType<LocalBookSeries>()
        .toList();
    final target = targets.firstOrNull;
    final order = <({int bookId, String title})>[
      ...?target?.volumes.map((v) => (bookId: v.bookId, title: v.title)),
    ];
    final originals =
        [
          books.book(id)!,
          ...related,
        ].where((b) => books.seriesFor(b.id) == null).toList()..sort(
          (a, b) => (books.seriesHint(a.id)?.number ?? double.infinity)
              .compareTo(books.seriesHint(b.id)?.number ?? double.infinity),
        );
    for (final book in originals) {
      claimed.add(book.id);
      final hint = books.seriesHint(book.id);
      final before = hint == null
          ? -1
          : order.indexWhere((v) {
              final other = books.seriesHint(v.bookId);
              return other?.key == hint.key && other!.number > hint.number;
            });
      final entry = (bookId: book.id, title: hint?.volumeTitle ?? book.title);
      if (before < 0) {
        order.add(entry);
      } else {
        order.insert(before, entry);
      }
    }
    groups.add(
      LocalImportGroup(
        seed: id,
        title: target?.title ?? books.seriesHint(id)!.title,
        volumes: order,
        targetId: target?.id,
        needsTarget: targets.length > 1,
      ),
    );
  }
  return groups;
}
