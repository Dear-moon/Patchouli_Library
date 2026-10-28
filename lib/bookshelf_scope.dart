import 'library_state.dart';
import 'sources/book_platform.dart';
import 'sources/source_repository.dart';
import 'offline_repository.dart';
import 'local_library_preferences.dart';
import 'catalog.dart';

/// The shelf contains saved books and, when merged, imported originals.
/// Cached trial chapters provide offline availability, never membership.
Set<int> bookshelfIds(
  LibraryState state,
  OfflineNovelRepository? offline, {
  bool readableOnly = false,
  bool filterSource = true,
  bool filterCategory = true,
}) =>
    {
          for (final id in state.shelf)
            if (!readableOnly || offline?.availableOffline(id) == true) id,
          if (state.combinedShelf)
            ...?offline?.local?.books.map((book) => book.id),
        }
        .where(
          (id) =>
              state.localBookVisible(id) &&
              bookshelfMatchesPlatform(id, state, offline) &&
              (!filterSource || bookshelfMatchesSource(id, state, offline)) &&
              (!filterCategory ||
                  bookshelfMatchesCategory(
                    id,
                    state,
                    book:
                        offline?.local?.book(id) ??
                        offline?.cache.book(id)?.novel,
                  )),
        )
        .toSet();

bool bookshelfMatchesCategory(int id, LibraryState state, {Novel? book}) {
  final selected = state.organization.shelfSelected;
  if (LocalLibraryPreferences.categoryAuthor(selected) case final author?) {
    return LocalLibraryPreferences.authorName(
          (book ?? state.cachedNovel(id))?.author ?? '',
        ) ==
        author;
  }
  return selected == LocalLibraryPreferences.all ||
      state.organization.groupOf(id) == selected;
}

bool bookshelfMatchesSource(
  int id,
  LibraryState state,
  OfflineNovelRepository? offline,
) {
  if (!state.combinedShelf) return true;
  final local = offline?.local?.book(id) != null;
  return switch (state.shelfSourceFilter) {
    'local' => local,
    'cached' => !local && offline?.availableOffline(id) == true,
    'online' => !local && state.contains(id),
    _ => true,
  };
}

String bookshelfSourceLabel(String source) => switch (source) {
  'local' => '本地导入',
  'cached' => '已缓存',
  'online' => '在线收藏',
  _ => '全部来源',
};

String bookshelfSource(int id, OfflineNovelRepository? offline) {
  if (offline?.local?.book(id) != null) return '本地';
  return offline?.availableOffline(id) == true ? '缓存' : '在线';
}

bool bookshelfMatchesPlatform(
  int id,
  LibraryState state,
  OfflineNovelRepository? offline,
) {
  if (state.shelfPlatform == 'all') return true;
  if (offline?.local?.book(id) != null) return state.shelfPlatform == 'local';
  if (state.shelfPlatform == 'local') return false;
  final book =
      state.cachedNovel(id) ??
      offline?.cache.book(id)?.novel ??
      sourceRepositoryOf(offline)?.store.book(id);
  return bookPlatformKey(book?.sourceId) == state.shelfPlatform;
}
