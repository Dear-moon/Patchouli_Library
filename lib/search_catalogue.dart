import 'book_search.dart';
import 'catalog.dart';

class PlatformSearchProgress {
  const PlatformSearchProgress({
    required this.items,
    required this.completed,
    required this.total,
    this.failures = const {},
  });
  final List<Novel> items;
  final int completed, total;
  final Map<String, String> failures;
}

typedef PlatformSearchProgressCallback =
    void Function(PlatformSearchProgress progress);

abstract interface class ProgressiveSearchCatalogue {
  Future<NovelPage> searchProgressPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
    bool allPlatforms = false,
    bool Function()? current,
    PlatformSearchProgressCallback? onProgress,
  });
  Future<void> cancelSearch();
}
