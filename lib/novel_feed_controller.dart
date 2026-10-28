import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'catalog.dart';
import 'book_tag_catalog.dart';
import 'book_search.dart';
import 'tag_catalogue.dart';
import 'blocked_tags.dart';
import 'publication_catalog.dart';
import 'web_publication_catalog.dart' show PublicationConnectionRequired;

/// Owns page cursors, stale-result isolation and explicit recovery. A failed
/// page never advances the cursor or loops automatically against the service.
class NovelFeedController extends ChangeNotifier {
  NovelFeedController(
    this.repository, {
    this.search = false,
    this.groupAllSearch = false,
    this.initialItems = 0,
  }) : assert(initialItems >= 0);
  final NovelRepository repository;
  final bool search;

  /// The shared search page keeps each real field's cursor and result state.
  /// Other feed callers retain their existing single-list contract.
  final bool groupAllSearch;
  static const _groupFields = [
    BookSearchField.title,
    BookSearchField.author,
    BookSearchField.tags,
    BookSearchField.id,
  ];
  List<NovelFeedController>? _searchGroups;
  bool _acceptGroupChanges = false;
  bool get _usesSearchGroups =>
      search &&
      groupAllSearch &&
      searchField == BookSearchField.all &&
      query.isNotEmpty;
  List<NovelFeedController> get searchGroups =>
      _usesSearchGroups &&
          _searchGroups?.every((group) => group.query == query) == true
      ? _searchGroups!
      : const [];

  List<NovelFeedController> _ensureSearchGroups() => _searchGroups ??= [
    for (final field in _groupFields)
      NovelFeedController(repository, search: true)
        ..searchField = field
        ..setBlockedTags(_blockedTags.tags)
        ..addListener(_searchGroupChanged),
  ];

  /// Discovery can warm a useful list below the ten featured files. Service
  /// page sizes/cursors stay unchanged; search remains one page at a time.
  final int initialItems;
  List<Novel> _items = const [];
  BlockedTags _blockedTags = BlockedTags.empty;
  List<Novel>? _visibleItems;
  int _visibleResultStartIndex = 0;
  int _blockedItemCount = 0;
  NovelSort sort = NovelSort.lastUpdate;
  PublicationLibrary? _publication;
  PublicationCatalog? _publicationCatalog;

  /// An explicit publication category replaces, rather than combines with,
  /// ranking and tag requests because its service has its own ordered cursor.
  PublicationLibrary? get publication => _publication;
  String query = '';
  BookSearchField searchField = BookSearchField.all;
  List<String> tags = const [];
  final _tagSuggestions = <String>{};
  Set<String> get tagSuggestions => Set.unmodifiable(_tagSuggestions);
  int page = 0;
  int? totalItems;
  Set<BookSearchField> incompleteSearchFields = const {};
  String? get searchNotice {
    if (incompleteSearchFields.isEmpty) return null;
    final fields = incompleteSearchFields.map((field) => field.label).join('、');
    return items.isEmpty
        ? '$fields搜索暂未完成，目前没有可显示的结果。'
        : '$fields搜索暂未完成，已保留其他搜索结果。';
  }

  bool hasMore = true;
  bool loading = false;
  TagSearchProgress? _tagProgress;
  String? get tagProgressLabel {
    final progress = _tagProgress;
    if (!loading || progress == null) return null;
    final total = progress.totalPages;
    return total == null
        ? '正在筛选标签 · 已检查 ${progress.scannedPages} 页'
        : '正在筛选标签 · 已检查 ${progress.scannedPages} / $total 页';
  }

  Object? error;
  String get failureMessage {
    final failure = error;
    if (failure is PublicationConnectionRequired) {
      return '此出版文库需要官网账号连接，请到账号页确认后重试。';
    }
    if (failure is FormatException && failure.message.toString().isNotEmpty) {
      return failure.message.toString();
    }
    if (failure is PlatformException && failure.details is Map) {
      return switch ((failure.details as Map)['httpStatus']) {
        429 => '当前请求较多，请稍后重试；已保存的书籍与阅读记录仍保留。',
        401 || 403 => '当前连接需要登录或访问验证，请在账号页确认后重试。',
        451 => '当前服务未提供此内容，已保存的书籍与阅读记录仍保留。',
        _ => '检查网络后重试，已保存的书籍与阅读记录仍保留。',
      };
    }
    return '检查网络后重试，已保存的书籍与阅读记录仍保留。';
  }

  bool refreshFailed = false;
  int _generation = 0;
  // Accepted data batches, not request attempts. Failed/stale requests must not
  // restart presentation, and appended pages must leave the old rows alone.
  int _resultRevision = 0;
  int _resultStartIndex = 0;
  bool _resultReplacesRetained = false;
  bool refreshing = false;
  bool _disposed = false;
  Timer? _searchDelay;

  List<Novel> get allItems => _items;
  List<Novel> get items {
    if (_blockedTags.isEmpty) return _items;
    _projectVisibleItems();
    return _visibleItems!;
  }

  bool get hasBlockedTags => _blockedTags.isNotEmpty;
  int get blockedItemCount {
    if (_blockedTags.isEmpty) return 0;
    _projectVisibleItems();
    return _blockedItemCount;
  }

  bool get hasLoaded => page > 0;
  int get resultRevision => _resultRevision;
  int get resultStartIndex {
    if (_blockedTags.isEmpty) return _resultStartIndex;
    _projectVisibleItems();
    return _visibleResultStartIndex;
  }

  void _projectVisibleItems() {
    if (_visibleItems != null) return;
    final visible = <Novel>[];
    var first = 0;
    for (var index = 0; index < _items.length; index++) {
      final book = _items[index];
      if (_blockedTags.blocks(book)) continue;
      visible.add(book);
      if (index < _resultStartIndex) first++;
    }
    _visibleItems = List.unmodifiable(visible);
    _visibleResultStartIndex = first;
    _blockedItemCount = _items.length - visible.length;
  }

  /// Filter the already accepted pages, without touching service cursors or
  /// starting a request. Clearing a rule restores the retained original rows.
  void setBlockedTags(Iterable<String> values) {
    if (_disposed) return;
    final next = BlockedTags(values);
    if (_blockedTags.sameAs(next)) return;
    _blockedTags = next;
    _visibleItems = null;
    _resultStartIndex = 0;
    _resultReplacesRetained = true;
    _resultRevision++;
    final accepting = _acceptGroupChanges;
    _acceptGroupChanges = false;
    for (final group in _searchGroups ?? const <NovelFeedController>[]) {
      group.setBlockedTags(next.tags);
    }
    _acceptGroupChanges = accepting;
    if (accepting && _usesSearchGroups) {
      _searchGroupChanged();
    } else {
      notifyListeners();
    }
  }

  /// A refresh updates the existing view; it is not an initial loading scene.
  bool get resultReplacesRetained => _resultReplacesRetained;

  Future<void> refresh() {
    _searchDelay?.cancel();
    _searchDelay = null;
    return _load(replace: true, force: true);
  }

  Future<void> loadInitial() => _load(replace: true);
  Future<void> loadMore() async {
    if (loading || !hasMore || error != null) return;
    await _load(replace: false);
  }

  Future<void> retry() => loading
      ? Future.value()
      : _load(replace: page == 0 || refreshFailed, force: true);

  Future<void> selectSort(NovelSort value) async {
    if (sort == value && tags.isEmpty && _publication == null) return;
    sort = value;
    tags = const [];
    _publication = null;
    _publicationCatalog = null;
    _reset();
    await _load(replace: true);
  }

  Future<void> selectTags(Iterable<String> values) async {
    final next = tagSearchTerms(values.join(' '));
    if (listEquals(tags, next) && _publication == null) return;
    tags = List.unmodifiable(next);
    _publication = null;
    _publicationCatalog = null;
    _reset();
    await _load(replace: true);
  }

  /// Browse a publication through the same paging, refresh and stale-response
  /// isolation as discovery. The caller restores the existing account first.
  Future<void> selectPublication(
    PublicationLibrary value, {
    required PublicationCatalog catalog,
    bool force = false,
  }) async {
    if (_disposed || search) return;
    if (!force &&
        _publication?.id == value.id &&
        identical(_publicationCatalog, catalog)) {
      return;
    }
    _publication = value;
    _publicationCatalog = catalog;
    tags = const [];
    _reset();
    await _load(replace: true, force: force);
  }

  /// A changed identity must not retain another account's visible book list.
  /// A refreshed connection for the same identity preserves resolved content.
  Future<void> refreshPublicationSession({required bool retain}) async {
    if (_disposed || _publication == null) return;
    if (!retain) _reset();
    await _load(replace: true, force: true);
  }

  Future<void> searchFor(String value) async {
    if (_disposed) return;
    final term = value.trim();
    if (query == term &&
        ((loading && _searchDelay == null) || (page > 0 && error == null))) {
      return;
    }
    _searchDelay?.cancel();
    _searchDelay = null;
    query = term;
    _reset();
    await _load(replace: true);
  }

  Future<void> selectSearchField(BookSearchField value) async {
    if (_disposed || searchField == value) return;
    _searchDelay?.cancel();
    _searchDelay = null;
    searchField = value;
    _reset();
    await _load(replace: true);
  }

  /// Invalidate old results immediately, but request only the final input after
  /// a short quiet period. Pagination cannot start during the debounce window.
  void scheduleSearch(
    String value, {
    Duration delay = const Duration(milliseconds: 280),
  }) {
    if (_disposed || !search) return;
    final term = value.trim();
    if (query == term &&
        (_searchDelay != null || loading || (page > 0 && error == null))) {
      return;
    }
    _searchDelay?.cancel();
    query = term;
    _reset();
    loading = true;
    notifyListeners();
    _searchDelay = Timer(delay, () {
      _searchDelay = null;
      unawaited(_load(replace: true));
    });
  }

  /// A closed search keeps its last result/query, without launching a request
  /// which the user can no longer see. Reopening can explicitly resume it.
  void cancelScheduledSearch() {
    if (_disposed || _searchDelay == null && !loading) return;
    _cancelSearchGroups();
    _searchDelay?.cancel();
    _searchDelay = null;
    _generation++;
    loading = false;
    refreshing = false;
    _tagProgress = null;
    // Existing rows stay interactive after reopening a search whose in-flight
    // page was cancelled. Each child has already invalidated that old request.
    _acceptGroupChanges = _usesSearchGroups;
    notifyListeners();
  }

  void _reset() {
    _cancelSearchGroups();
    _generation++;
    _items = const [];
    _visibleItems = null;
    page = 0;
    totalItems = null;
    incompleteSearchFields = const {};
    _tagProgress = null;
    hasMore = true;
    error = null;
    refreshFailed = false;
    loading = false;
    refreshing = false;
  }

  Future<void> _load({required bool replace, bool force = false}) async {
    if (_disposed) return;
    if (!replace && loading) return;
    if (_usesSearchGroups) {
      await _loadSearchGroups(replace: replace, force: force);
      return;
    }
    final generation = replace ? ++_generation : _generation;
    var requestedPage = replace ? 1 : page + 1;
    var replacing = replace;
    final requestedSort = sort;
    final requestedPublication = _publication;
    final publicationCatalog = _publicationCatalog;
    final filteringTags = !search && tags.isNotEmpty;
    final requestedQuery = filteringTags ? tags.join(' ') : query;
    final requestedField = filteringTags ? BookSearchField.tags : searchField;
    final retaining = replace && (hasLoaded || _items.isNotEmpty);
    final retainedCount = _items.length;
    final retainedPage = page;
    var pending = replace ? <Novel>[] : _items;
    final pendingIncompleteFields = replace
        ? <BookSearchField>{}
        : {...incompleteSearchFields};
    loading = true;
    _tagProgress = null;
    refreshing = retaining;
    error = null;
    refreshFailed = false;
    notifyListeners();
    try {
      while (true) {
        void acceptTagProgress(TagSearchProgress progress) {
          if (_disposed || generation != _generation) return;
          _tagProgress = progress;
          if (!retaining && progress.items.isNotEmpty) {
            final oldCount = pending.length;
            final merged = <int, Novel>{
              if (!replacing)
                for (final item in pending) item.id: item,
              for (final item in progress.items) item.id: item,
            };
            final first = replacing ? 0 : oldCount;
            pending = List.unmodifiable(merged.values);
            replacing = false;
            _items = pending;
            _visibleItems = null;
            _tagSuggestions.addAll(pending.expand((book) => book.tags));
            BookTagCatalog.shared.observe(_tagSuggestions);
            if (first < pending.length) {
              _resultStartIndex = first;
              _resultReplacesRetained = false;
              _resultRevision++;
            }
          }
          notifyListeners();
        }

        final tagOnly =
            requestedField == BookSearchField.tags ||
            requestedField == BookSearchField.all &&
                requestedQuery.trim().startsWith('#');
        final result =
            requestedPublication != null && publicationCatalog != null
            ? await publicationCatalog.browsePublication(
                requestedPublication.id,
                page: requestedPage,
                refresh: force,
              )
            : (search || filteringTags) &&
                  tagOnly &&
                  repository is ProgressiveTagCatalogue
            ? await (repository as ProgressiveTagCatalogue).tagPage(
                requestedQuery,
                page: requestedPage,
                refresh: force,
                current: () => !_disposed && generation == _generation,
                onProgress: acceptTagProgress,
              )
            : search || filteringTags
            ? await repository.searchFilteredPage(
                requestedQuery,
                field: requestedField,
                page: requestedPage,
                refresh: force,
              )
            : await repository.browse(
                sort: requestedSort,
                page: requestedPage,
                refresh: force,
              );
        if (_disposed || generation != _generation) return;
        if (result.page != requestedPage) {
          throw const FormatException('分页游标不匹配');
        }
        pendingIncompleteFields.addAll(result.searchFailures.keys);
        final oldCount = pending.length;
        final merged = <int, Novel>{
          if (!replacing)
            for (final item in pending) item.id: item,
          for (final item in result.items) item.id: item,
        };
        pending = List.unmodifiable(merged.values);
        final first = replacing ? 0 : oldCount;
        replacing = false;
        // Refresh the pages already visible as one transaction. Never shrink a
        // long list to page one while its remaining pages are still in flight.
        // A failed later page leaves the old content and cursor intact.
        final complete =
            !result.hasMore ||
            result.items.isEmpty ||
            pending.length <= oldCount ||
            (retaining
                ? requestedPage >= retainedPage &&
                      (search ||
                          filteringTags ||
                          pending.length >= initialItems ||
                          requestedPage >= 3) &&
                      pending.length >= retainedCount
                : search ||
                      filteringTags ||
                      pending.length >= initialItems ||
                      requestedPage >= 3);
        if (!retaining || complete) {
          _items = pending;
          _visibleItems = null;
          _tagSuggestions.addAll(pending.expand((book) => book.tags));
          BookTagCatalog.shared.observe(_tagSuggestions);
          if (first < _items.length || retaining) {
            _resultStartIndex = retaining ? 0 : first;
            _resultReplacesRetained = retaining;
            _resultRevision++;
          }
          page = requestedPage;
          hasMore = result.hasMore;
          totalItems = result.totalItems;
          incompleteSearchFields = Set.unmodifiable(pendingIncompleteFields);
        }
        if (complete) break;
        if (!retaining) notifyListeners();
        if (_disposed || generation != _generation) return;
        requestedPage++;
      }
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
      refreshFailed = retaining;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        refreshing = false;
        _tagProgress = null;
        notifyListeners();
      }
    }
  }

  void _cancelSearchGroups() {
    _acceptGroupChanges = false;
    for (final group in _searchGroups ?? const <NovelFeedController>[]) {
      group.cancelScheduledSearch();
    }
  }

  Future<void> _loadSearchGroups({
    required bool replace,
    required bool force,
  }) async {
    final generation = replace ? ++_generation : _generation;
    final groups = _ensureSearchGroups();
    // Start every field before accepting notifications, so a new query cannot
    // briefly display another field's retained results from the previous query.
    _acceptGroupChanges = false;
    final work = [
      for (final group in groups)
        if (!replace && force)
          group.error != null ? group.retry() : Future<void>.value()
        else if (!replace)
          group.loadMore()
        else if (force && group.query == query)
          group.refresh()
        else
          group.searchFor(query),
    ];
    _acceptGroupChanges = true;
    _searchGroupChanged();
    await Future.wait(work);
    if (!_disposed && generation == _generation) _searchGroupChanged();
  }

  void _searchGroupChanged() {
    if (_disposed || !_acceptGroupChanges || !_usesSearchGroups) return;
    final groups = _searchGroups!;
    final items = [for (final group in groups) ...group.allItems];
    if (!listEquals(_items, items)) {
      _items = List.unmodifiable(items);
      _visibleItems = null;
      _resultStartIndex = 0;
      _resultReplacesRetained = groups.any((group) => group.refreshing);
      _resultRevision++;
    }
    _tagSuggestions.addAll(groups.expand((group) => group.tagSuggestions));
    loading = groups.any((group) => group.loading);
    refreshing = groups.any((group) => group.refreshing);
    refreshFailed = groups.any((group) => group.refreshFailed);
    // A cancelled initial field must resume when the search reopens, even if a
    // faster field already produced rows. Failed fields remain explicitly retryable.
    page = groups.every((group) => group.hasLoaded || group.error != null)
        ? 1
        : 0;
    hasMore = groups.any((group) => group.hasMore);
    totalItems = groups.every((group) => group.totalItems != null)
        ? groups.fold<int>(0, (total, group) => total + group.totalItems!)
        : null;
    incompleteSearchFields = Set.unmodifiable({
      for (final group in groups) ...[
        if (group.error != null) group.searchField,
        ...group.incompleteSearchFields,
      ],
    });
    error = groups.every((group) => group.error != null)
        ? groups.first.error
        : null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDelay?.cancel();
    _generation++;
    for (final group in _searchGroups ?? const <NovelFeedController>[]) {
      group.dispose();
    }
    super.dispose();
  }
}
