import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'catalog.dart';
import 'book_search.dart';
import 'tag_catalogue.dart';

/// Owns page cursors, stale-result isolation and explicit recovery. A failed
/// page never advances the cursor or loops automatically against the service.
class NovelFeedController extends ChangeNotifier {
  NovelFeedController(
    this.repository, {
    this.search = false,
    this.initialItems = 0,
  }) : assert(initialItems >= 0);
  final NovelRepository repository;
  final bool search;

  /// Discovery can warm a useful list below the ten featured files. Service
  /// page sizes/cursors stay unchanged; search remains one page at a time.
  final int initialItems;
  List<Novel> _items = const [];
  NovelSort sort = NovelSort.lastUpdate;
  String query = '';
  BookSearchField searchField = BookSearchField.all;
  List<String> tags = const [];
  final _tagSuggestions = <String>{};
  Set<String> get tagSuggestions => Set.unmodifiable(_tagSuggestions);
  int page = 0;
  int? totalItems;
  bool hasMore = true;
  bool loading = false;
  Object? error;
  String get failureMessage {
    final failure = error;
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

  List<Novel> get items => _items;
  bool get hasLoaded => page > 0;
  int get resultRevision => _resultRevision;
  int get resultStartIndex => _resultStartIndex;

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
    if (sort == value && tags.isEmpty) return;
    sort = value;
    tags = const [];
    _reset();
    await _load(replace: true);
  }

  Future<void> selectTags(Iterable<String> values) async {
    final next =
        values.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList()
          ..sort();
    if (listEquals(tags, next)) return;
    tags = List.unmodifiable(next);
    _reset();
    await _load(replace: true);
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
    if (_searchDelay == null) return;
    _searchDelay!.cancel();
    _searchDelay = null;
    loading = false;
    refreshing = false;
    notifyListeners();
  }

  void _reset() {
    _generation++;
    _items = const [];
    page = 0;
    totalItems = null;
    hasMore = true;
    error = null;
    refreshFailed = false;
    loading = false;
    refreshing = false;
  }

  Future<void> _load({required bool replace, bool force = false}) async {
    if (_disposed) return;
    if (!replace && loading) return;
    final generation = replace ? ++_generation : _generation;
    var requestedPage = replace ? 1 : page + 1;
    var replacing = replace;
    final requestedSort = sort;
    final filteringTags = !search && tags.isNotEmpty;
    final requestedQuery = filteringTags ? tags.join(' ') : query;
    final requestedField = filteringTags ? BookSearchField.tags : searchField;
    final retaining = replace && hasLoaded;
    final retainedCount = _items.length;
    final retainedPage = page;
    var pending = replace ? <Novel>[] : _items;
    loading = true;
    refreshing = retaining;
    error = null;
    refreshFailed = false;
    notifyListeners();
    try {
      while (true) {
        final tagOnly =
            requestedField == BookSearchField.tags ||
            requestedField == BookSearchField.all &&
                requestedQuery.trim().startsWith('#');
        final result =
            (search || filteringTags) &&
                tagOnly &&
                repository is ProgressiveTagCatalogue
            ? await (repository as ProgressiveTagCatalogue).tagPage(
                requestedQuery,
                page: requestedPage,
                refresh: force,
                current: () => !_disposed && generation == _generation,
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
          _resultStartIndex = retaining ? 0 : first;
          _resultReplacesRetained = retaining;
          _items = pending;
          _tagSuggestions.addAll(pending.expand((book) => book.tags));
          if (_resultStartIndex < _items.length || retaining) _resultRevision++;
          page = requestedPage;
          hasMore = result.hasMore;
          totalItems = result.totalItems;
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
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDelay?.cancel();
    _generation++;
    super.dispose();
  }
}
