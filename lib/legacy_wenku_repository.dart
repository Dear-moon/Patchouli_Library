import 'catalog.dart';
import 'online_component.dart';
import 'publication_catalog.dart';
import 'tag_catalogue.dart';

/// Source-preview boundary. Online implementations are supplied separately.
/// Existing book/chapter models remain shared with local reading and caches.
class LegacyWenkuRepository extends NovelRepository
    implements PublicationCatalog, ProgressiveTagCatalogue {
  const LegacyWenkuRepository();
  @override
  Future<List<Novel>> list() => unavailableOnline();
  @override
  Future<Novel?> find(int id) => unavailableOnline();
  @override
  Future<List<Novel>> search(String query) => unavailableOnline();
  @override
  Future<Novel> detail(Novel novel) => unavailableOnline();
  @override
  Future<List<NovelChapter>> chapters(int id) => unavailableOnline();
  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) =>
      unavailableOnline();
  @override
  Future<List<PublicationLibrary>> publicationLibraries({
    bool refresh = false,
  }) => unavailableOnline();
  @override
  Future<NovelPage> browsePublication(
    int libraryId, {
    int page = 1,
    bool refresh = false,
  }) => unavailableOnline();
  @override
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
  }) => unavailableOnline();
}
