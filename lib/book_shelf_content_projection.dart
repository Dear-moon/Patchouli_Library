import 'book_shelf_content_preferences.dart';
import 'catalog.dart';
import 'library_state.dart';

/// Region filtering uses durable reading identity, not an item's visible slot.
bool shelfContentMatchesReading(
  int id,
  Novel? book,
  LibraryState state,
  String filter,
) {
  final read = state.hasRead(id);
  final finished = book != null && state.finishedReading(book);
  return switch (filter) {
    'recent' => read,
    'unread' => !read,
    'reading' => read && !finished,
    'finished' => finished,
    _ => true,
  };
}

/// Materialize sort keys once so an independent shelf stays cheap on large libraries.
void sortShelfContentIds(
  List<int> ids,
  BookShelfContentSort sort, {
  required int Function(int) readAt,
  required int Function(int) addedAt,
  required String Function(int) title,
}) {
  if (sort == BookShelfContentSort.original) return;
  final times = switch (sort) {
    BookShelfContentSort.recentRead => {for (final id in ids) id: readAt(id)},
    BookShelfContentSort.recentAdded => {for (final id in ids) id: addedAt(id)},
    _ => const <int, int>{},
  };
  final titles = sort == BookShelfContentSort.title
      ? {for (final id in ids) id: title(id)}
      : const <int, String>{};
  ids.sort((a, b) {
    final order = sort == BookShelfContentSort.title
        ? titles[a]!.compareTo(titles[b]!)
        : times[b]!.compareTo(times[a]!);
    return order != 0 ? order : a.compareTo(b);
  });
}
