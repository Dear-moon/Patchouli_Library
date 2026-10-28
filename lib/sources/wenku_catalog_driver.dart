import '../book_search.dart';
import '../catalog.dart';

class WenkuCatalogDriver {
  const WenkuCatalogDriver(this.repository);
  final NovelRepository repository;
  static const operations = {
    'explores',
    'explore',
    'search',
    'detail',
    'toc',
    'content',
  };

  static Map<String, dynamic> book(Novel novel) => {
    ...novel.toSnapshot(),
    'id': novel.id,
    'name': novel.title,
    'kind': novel.genre,
    'intro': novel.summary,
    'bookUrl': 'wenku8:${novel.id}',
    'tocUrl': 'wenku8:${novel.id}',
    'lastChapter': novel.lastUpdate,
    'complete': novel.isComplete,
  };

  Future<dynamic> run(
    String operation, {
    String? url,
    String key = '',
    int page = 1,
    Map<String, dynamic>? inputBook,
    Map<String, dynamic>? chapter,
  }) async {
    if (operation == 'explores') {
      return [
        for (final sort in NovelSort.values)
          {'title': sort.label, 'url': sort.name},
      ];
    }
    if (operation == 'search' || operation == 'explore') {
      final result = operation == 'search'
          ? await repository.searchFilteredPage(
              key,
              field: BookSearchField.values.byName(
                inputBook?['searchField'] as String? ?? 'all',
              ),
              page: page,
            )
          : await repository.browse(
              sort: NovelSort.values.byName(url ?? 'lastUpdate'),
              page: page,
            );
      return {
        'items': [for (final novel in result.items) book(novel)],
        'hasMore': result.hasMore,
        'totalPages': result.totalPages,
        'totalItems': result.totalItems,
        'pageUrl': '${operation == 'search' ? key : url}/$page',
      };
    }
    final id = inputBook?['id'] as int? ?? int.parse(url!.split(':').last);
    final novel = await repository.find(id);
    if (novel == null) throw StateError('Native Wenku book was not found');
    if (operation == 'detail') return book(await repository.detail(novel));
    if (operation == 'toc') {
      return [
        for (final item in await repository.chapters(id))
          {
            'id': item.id,
            'name': item.title,
            'url': item.url ?? 'wenku8:$id/${item.id}',
            'volumeTitle': item.volumeTitle,
            'volumeId': item.volumeId,
          },
      ];
    }
    if (operation == 'content') {
      return repository.chapterContent(
        id,
        NovelChapter(
          chapter!['title'] as String,
          '',
          id: chapter['id'] as int,
          url: chapter['url'] as String?,
        ),
      );
    }
    throw StateError('Native Wenku catalogue operation is not registered');
  }
}
