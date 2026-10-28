import 'package:wenku8_flutter/catalog.dart';

class SourceFixtureRepository extends DemoNovelRepository {
  final fixture = demoNovels.first.withChapters([
    for (final (index, chapter) in demoNovels.first.chapters.indexed)
      NovelChapter(chapter.title, chapter.content, id: index + 1),
  ]);
  @override
  Future<List<Novel>> list() async => [fixture];
  @override
  Future<Novel?> find(int id) async => id == fixture.id ? fixture : null;
  @override
  Future<List<NovelChapter>> chapters(int id) async => fixture.chapters;
}
