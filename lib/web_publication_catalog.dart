import 'catalog.dart';
import 'publication_catalog.dart';

class PublicationConnectionRequired implements Exception {
  const PublicationConnectionRequired();
}

/// Presentation-level adapter; concrete connectivity is not part of this checkout.
class WebPublicationCatalog implements PublicationCatalog {
  WebPublicationCatalog({required this.categories, required this.books});
  final PublicationCatalog categories;
  final NovelRepository books;
  @override
  Future<List<PublicationLibrary>> publicationLibraries({
    bool refresh = false,
  }) => categories.publicationLibraries(refresh: refresh);
  @override
  Future<NovelPage> browsePublication(
    int libraryId, {
    int page = 1,
    bool refresh = false,
  }) => categories.browsePublication(libraryId, page: page, refresh: refresh);
}
