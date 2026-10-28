import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'app_ui.dart';
import 'book_collection_layout.dart';
import 'catalog.dart';
import 'book_search.dart';
import 'blocked_tags_controls.dart';
import 'feature_pages.dart' show ArchiveFeaturePage;
import 'library_state.dart';
import 'novel_feed_controller.dart';
import 'offline_repository.dart';
import 'tag_catalogue.dart';
import 'pages.dart' show NovelRow, FeedRefresh, FeedFooter, openDetail;

class AuthorWorksRepository extends NovelRepository {
  const AuthorWorksRepository(
    this.source,
    this.author, {
    this.localOnly = false,
    this.tagSearch = false,
    this.current,
  });
  final NovelRepository source;
  final String author;
  final bool localOnly;
  final bool tagSearch;
  final bool Function()? current;
  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) async {
    if (localOnly) {
      final local = source is OfflineNovelRepository
          ? (source as OfflineNovelRepository).local?.books ?? const <Novel>[]
          : const <Novel>[];
      return NovelPage.fromItems(
        local.where((b) => sameNovelAuthor(b.author, author)).toList(),
        page,
      );
    }
    if (tagSearch && source is ProgressiveTagCatalogue) {
      return (source as ProgressiveTagCatalogue).tagPage(
        author,
        page: page,
        refresh: refresh,
        current: current,
      );
    }
    return tagSearch
        ? source.searchFilteredPage(
            author,
            field: BookSearchField.tags,
            page: page,
            refresh: refresh,
          )
        : source.authorPage(author, page: page, refresh: refresh);
  }

  @override
  Future<List<Novel>> list() async => (await browse()).items;
  @override
  Future<Novel?> find(int id) => source.find(id);
  @override
  Future<List<Novel>> search(String query) => source.search(query);
  @override
  Future<Novel> detail(Novel novel) => source.detail(novel);
  @override
  Future<List<NovelChapter>> chapters(int id) => source.chapters(id);
  @override
  Future<String> chapterContent(int id, NovelChapter chapter) =>
      source.chapterContent(id, chapter);
}

class AuthorWorksPage extends StatefulWidget {
  const AuthorWorksPage({
    super.key,
    required this.author,
    required this.repository,
    required this.state,
    this.localOnly = false,
    this.tagSearch = false,
  });
  final String author;
  final NovelRepository repository;
  final LibraryState state;
  final bool localOnly;
  final bool tagSearch;
  @override
  State<AuthorWorksPage> createState() => _AuthorWorksPageState();
}

class _AuthorWorksPageState extends State<AuthorWorksPage> {
  late final _feed = NovelFeedController(
    widget.tagSearch
        ? widget.repository
        : AuthorWorksRepository(
            widget.repository,
            widget.author,
            localOnly: widget.localOnly,
          ),
    search: widget.tagSearch,
    initialItems: 20,
  );
  @override
  void initState() {
    super.initState();
    if (widget.tagSearch) {
      _feed.query = widget.author;
      _feed.searchField = BookSearchField.tags;
    }
    if (!widget.localOnly) {
      widget.state.blockedTagsChanges.addListener(_blockedTagsChanged);
      _blockedTagsChanged();
    }
    unawaited(_feed.loadInitial());
  }

  void _blockedTagsChanged() => _feed.setBlockedTags(widget.state.blockedTags);

  @override
  void dispose() {
    if (!widget.localOnly) {
      widget.state.blockedTagsChanges.removeListener(_blockedTagsChanged);
    }
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.tagSearch ? '标签书单' : '作者作品',
    code: widget.tagSearch
        ? 'TAGS / CATALOGUE'
        : widget.localOnly
        ? 'AUTHOR / LOCAL WORKS'
        : 'AUTHOR / WORKS',
    child: AnimatedBuilder(
      animation: _feed,
      builder: (context, _) {
        if (_feed.items.isEmpty && _feed.error != null) {
          return ContentNotice(
            icon: CupertinoIcons.wifi_exclamationmark,
            title: '作品加载失败',
            message: _feed.failureMessage,
            onRetry: _feed.retry,
            secondaryAction: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.localOnly)
                  BlockedTagsButton(state: widget.state, feed: _feed),
              ],
            ),
          );
        }
        return LoadedContentSequence(
          generation: _feed.resultReplacesRetained
              ? null
              : _feed.resultRevision,
          firstIndex: _feed.resultStartIndex == 0
              ? 0
              : _feed.resultStartIndex + 1,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notice) {
              if (notice.depth == 0 &&
                  _feed.items.isNotEmpty &&
                  notice.metrics.extentAfter < 400 &&
                  !_feed.loading &&
                  _feed.hasMore &&
                  _feed.error == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _feed.loadMore();
                });
              }
              return false;
            },
            child: FeedRefresh(
              feed: _feed,
              child: CustomScrollView(
                key: PageStorageKey(
                  'related-works-${widget.author}-${widget.localOnly}-${widget.tagSearch}',
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.paddingOf(context).top +
                          FrostedHeader.toolbarHeight +
                          20,
                      24,
                      18,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          sectionHeader(
                            context,
                            widget.author,
                            _feed.tagProgressLabel ??
                                (_feed.hasBlockedTags ||
                                        _feed.totalItems == null
                                    ? '已显示 ${_feed.items.length} 部作品'
                                    : '${_feed.totalItems} 部作品'),
                          ),
                          if (!widget.localOnly)
                            BlockedTagsButton(
                              key: const ValueKey(
                                'related-blocked-tags-manage',
                              ),
                              state: widget.state,
                              feed: _feed,
                              compact: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_feed.items.isEmpty && _feed.loading)
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      sliver: SliverToBoxAdapter(
                        child: BookCollectionSkeleton(rows: 5),
                      ),
                    ),
                  if (_feed.items.isEmpty && !_feed.loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ContentNotice(
                        icon: CupertinoIcons.book,
                        title: _feed.blockedItemCount > 0
                            ? '当前作品已被标签屏蔽'
                            : widget.tagSearch
                            ? '暂未找到这个标签的书籍'
                            : '暂未找到此作者的作品',
                        secondaryAction: _feed.blockedItemCount == 0
                            ? null
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  BlockedTagsButton(
                                    state: widget.state,
                                    feed: _feed,
                                    label: '管理屏蔽标签',
                                  ),
                                  if (_feed.hasMore)
                                    GlassTextButton(
                                      key: const ValueKey(
                                        'related-blocked-tags-more',
                                      ),
                                      onPressed: _feed.loadMore,
                                      child: const AppText('继续加载'),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: BookCollectionSliver(
                      itemCount: _feed.items.length,
                      itemBuilder: (context, i) {
                        final book = _feed.items[i],
                            tag = CoverHeroTag(context, _feed.items[i].id);
                        return LoadedContentItem(
                          key: ValueKey(book.id),
                          index: i + 1,
                          placeholder: const BookRowSkeleton(),
                          child: NovelRow(
                            novel: book,
                            coverHeroTag: tag,
                            onTap: () => openDetail(
                              context,
                              book,
                              widget.state,
                              widget.repository,
                              coverHeroTag: tag,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _feed.items.isEmpty && _feed.blockedItemCount > 0
                          ? const SizedBox.shrink()
                          : FeedFooter(feed: _feed),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class TagWorksPage extends StatelessWidget {
  const TagWorksPage({
    super.key,
    required this.tag,
    required this.repository,
    required this.state,
  });
  final String tag;
  final NovelRepository repository;
  final LibraryState state;
  @override
  Widget build(BuildContext context) => AuthorWorksPage(
    author: tag,
    repository: repository,
    state: state,
    tagSearch: true,
  );
}
