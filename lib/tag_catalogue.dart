import 'catalog.dart';

/// Canonical tag terms share a cursor regardless of selection order, spacing or
/// optional # markers. Language conversion remains with the source adapter.
List<String> tagSearchTerms(String query) =>
    query
        .replaceAll('＃', '#')
        .split(RegExp(r'[\s\u3000,，、;；]+'))
        .map((term) => term.replaceFirst(RegExp(r'^#+'), '').trim())
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

class TagSearchProgress {
  const TagSearchProgress({
    required this.items,
    required this.scannedPages,
    this.totalPages,
  });
  final List<Novel> items;
  final int scannedPages;
  final int? totalPages;
}

typedef TagProgressCallback = void Function(TagSearchProgress progress);

/// A tag query can continue through catalogue pages while its owner is alive.
/// Other repository/search callers keep their original one-Future contract.
abstract interface class ProgressiveTagCatalogue {
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
    TagProgressCallback? onProgress,
  });
}
