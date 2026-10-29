import 'dart:convert';
import 'library_state.dart';
import 'local_books.dart';
import 'reader_rich_content.dart';

/// Reconcile lazy legacy anchors before exporting/syncing them. The persisted
/// revision makes this idempotent; an active reader saves its own current anchor.
Future<void> normalizeLocalReadingRecords(
  LocalBookStore books,
  LibraryState state,
) async {
  final ids = <int>{
    ...state.readingPositions.keys,
    ...state.bookmarkEntries.map((e) => e.novelId),
  };
  for (final id in ids.where((id) => isLocalBook(id) && books.contains(id))) {
    final positions = [
      ?state.positionFor(id),
      ...state.bookmarksFor(id).map((m) => m.position),
    ];
    if (!positions.any((p) => books.canResolveCoordinates(id, p.toJson()))) {
      continue;
    }
    final chapters = <int, Future<ReaderRichBody>>{};
    final resolved = <String, Future<Map<String, dynamic>>>{};
    await state.remapBookCoordinates(
      id,
      (position) => resolved.putIfAbsent(
        jsonEncode(position),
        () => books.resolveReadingCoordinates(
          id,
          position,
          chapterCache: chapters,
        ),
      ),
    );
  }
}
