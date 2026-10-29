import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'app_search_field.dart';
import 'archive_carousel.dart';
import 'book_collection_layout.dart';
import 'book_collection_grid.dart';
import 'book_collection_view_options.dart';
import 'book_collection_region_toolbar.dart';
import 'book_shelf_content_preferences.dart';
import 'book_grid_density.dart';
import 'book_categories.dart';
import 'book_documents.dart';
import 'book_sync.dart';
import 'catalog.dart';
import 'cloud_sources.dart';
import 'dock_layout.dart';
import 'glass_choices.dart';
import 'library_state.dart';
import 'library_toolbar.dart';
import 'library_reflow.dart';
import 'local_books.dart';
import 'local_book_importer.dart';
import 'local_library_preferences.dart';
import 'local_series_editor.dart';
import 'local_book_removal.dart';
import 'local_book_batch_page.dart';
import 'pages.dart' show NovelRow;
import 'ui_notifiers.dart';

export 'cloud_book_sync_panel.dart' show CloudBookSyncPanel;

// A single-factor profile baseline; ordinary builds retain the toolbar paint.
Widget _localToolbarPaint(Widget child) =>
    const bool.fromEnvironment(
      'LOCAL_TOOLBAR_REPAINT_BOUNDARY',
      defaultValue: true,
    )
    ? RepaintBoundary(child: child)
    : child;

// Dense rows use a painted action: tablet profiling found that per-row live
// refraction dominates scrolling. Keep the old surface as a diagnostic baseline.
const _localRowGlassAction = bool.fromEnvironment(
  'LOCAL_ROW_GLASS_ACTION',
  defaultValue: false,
);

class LocalLibraryController extends ChangeNotifier {
  void Function(BuildContext)? importMenu;
  VoidCallback? search, refresh;
  bool importing = false;
  void changed() => notifyListeners();
}

Widget _localLibraryHeader(
  BuildContext context,
  LocalLibraryController? controller, {
  bool back = false,
}) {
  Widget header() => Row(
    children: [
      if (back)
        GlassIconButton(
          icon: CupertinoIcons.back,
          label: '返回',
          onPressed: () => Navigator.pop(context),
        ),
      const Expanded(
        child: ArchiveMasthead(title: '本地', code: '03 / LOCAL ARCHIVE'),
      ),
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('local-import-book'),
            icon: CupertinoIcons.arrow_down_doc,
            label: '本地书籍操作',
            onPressed: controller?.importMenu == null
                ? null
                : () => controller!.importMenu!(anchor),
          ),
        ),
      ),
      GlassIconButton(
        key: const ValueKey('local-search'),
        icon: CupertinoIcons.search,
        label: '搜索本地书籍',
        onPressed: controller?.search,
      ),
    ],
  );
  return controller == null
      ? header()
      : AnimatedBuilder(animation: controller, builder: (_, _) => header());
}

class LocalLibraryPage extends StatefulWidget {
  const LocalLibraryPage({
    super.key,
    required this.books,
    required this.state,
    required this.onOpen,
    this.onOpenWithCover,
    this.showHeader = true,
    this.compactMainPageControls = false,
    this.controller,
    this.documents,
    this.cloudSettings,
    this.onSearch,
  });
  final LocalBookStore books;
  final LibraryState state;
  final void Function(BuildContext, Novel) onOpen;
  final void Function(BuildContext, Novel, Object)? onOpenWithCover;
  final bool showHeader;
  final bool compactMainPageControls;
  final LocalLibraryController? controller;
  final BookDocuments? documents;
  final CloudSourceSettings? cloudSettings;
  final VoidCallback? onSearch;
  Widget buildHeader(BuildContext context) =>
      _localLibraryHeader(context, controller, back: showHeader);

  @override
  State<LocalLibraryPage> createState() => _LocalLibraryPageState();
}

class _LocalLibraryPageState extends State<LocalLibraryPage>
    with WidgetsBindingObserver {
  late final _documents = widget.documents ?? BookDocuments();
  late final _controller = widget.controller ?? LocalLibraryController();
  late final _cloudSources = widget.cloudSettings ?? CloudSourceSettings();
  late final _importer = LocalBookImporter(
    books: widget.books,
    library: widget.state,
    documents: _documents,
    cloudSettings: _cloudSources,
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'local-library-search');
  bool _searchOpen = false;
  BookSync? _sync;
  LocalLibraryPreferences? _organization;
  final _gridViewport = ValueNotifier<BookGridViewport?>(null);
  String? _error;
  bool _importing = false;
  (int, int)? _importProgress;
  bool? _routeCurrent;
  bool _scanActive = false;
  late final _bookChanges = Listenable.merge([
    widget.books,
    widget.state.historyChanges,
    widget.state.shelfViewChanges,
  ]);
  Listenable? _viewChanges;
  List<Novel>? _visibleBooks;
  String? _visibleQuery;
  List<Novel>? _membershipBooks;
  List<Novel>? _shelfBooks;
  Map<String, String>? _shelfCategories;

  void _invalidateBooks() {
    _visibleBooks = null;
    _membershipBooks = null;
    _shelfBooks = null;
    _shelfCategories = null;
  }

  List<Novel> _localMembership() => _membershipBooks ??= widget.books.books
      .where((book) => widget.state.localBookVisible(book.id))
      .toList(growable: false);

  Map<String, String> _shelfCategoryOptions(
    LocalLibraryPreferences organization,
  ) {
    if (_shelfCategories != null) return _shelfCategories!;
    final categories = {
      LocalLibraryPreferences.all: '全部书籍',
      LocalLibraryPreferences.unfiled: '未分类',
      ...organization.groups,
      for (final author
          in (_localMembership()
              .map((book) => LocalLibraryPreferences.authorName(book.author))
              .toSet()
              .toList()
            ..sort()))
        LocalLibraryPreferences.authorCategory(author): '作者 · $author',
    };
    final selected = organization.shelfContent.category;
    final selectedAuthor = LocalLibraryPreferences.categoryAuthor(selected);
    if (selectedAuthor != null && !categories.containsKey(selected)) {
      categories[selected] = '作者 · $selectedAuthor（暂无匹配）';
    }
    return _shelfCategories = categories;
  }

  String _shelfCategory(LocalLibraryPreferences organization) {
    final requested = organization.shelfContent.category;
    // An author is a query, not a named category that can be deleted. Keep its
    // condition when no visible book matches instead of broadening to all books.
    if (LocalLibraryPreferences.categoryAuthor(requested) != null) {
      return requested;
    }
    return _shelfCategoryOptions(organization).containsKey(requested)
        ? requested
        : LocalLibraryPreferences.all;
  }

  List<Novel> _featuredBooks(
    LocalLibraryPreferences? organization,
    List<Novel> collection,
  ) {
    if (organization == null) return const [];
    final preferences = organization.shelfContent;
    if (preferences.followCollection) return collection;
    if (_shelfBooks != null) return _shelfBooks!;
    final category = _shelfCategory(organization);
    final result = _localMembership().where((book) {
      if (!organization.matchesCategory(book, category)) return false;
      return switch (preferences.readingFilter) {
        'recent' => widget.state.hasRead(book.id),
        'unread' => !widget.state.hasRead(book.id),
        'reading' =>
          widget.state.hasRead(book.id) && !widget.state.finishedReading(book),
        'finished' => widget.state.finishedReading(book),
        _ => true,
      };
    }).toList();
    // The independent shelf shares membership, not the index's active query or
    // category. Resolve sort keys once and retain this projection until data changes.
    if (preferences.sort != BookShelfContentSort.original) {
      final readTimes = preferences.sort == BookShelfContentSort.recentRead
          ? {
              for (final book in result)
                book.id: widget.state.lastReadAt(book.id),
            }
          : const <int, int>{};
      final addedTimes = preferences.sort == BookShelfContentSort.recentAdded
          ? {
              for (final book in result)
                book.id: widget.books.importedAt(book.id),
            }
          : const <int, int>{};
      result.sort((a, b) {
        final order = switch (preferences.sort) {
          BookShelfContentSort.recentRead => readTimes[b.id]!.compareTo(
            readTimes[a.id]!,
          ),
          BookShelfContentSort.recentAdded => addedTimes[b.id]!.compareTo(
            addedTimes[a.id]!,
          ),
          BookShelfContentSort.title => a.title.compareTo(b.title),
          BookShelfContentSort.original => 0,
        };
        return order != 0 ? order : a.title.compareTo(b.title);
      });
    }
    return _shelfBooks = result;
  }

  List<Novel> _filteredBooks(LocalLibraryPreferences? organization) {
    if (organization == null) return const [];
    final query = _search.text;
    if (_visibleBooks != null && _visibleQuery == query) return _visibleBooks!;
    _visibleQuery = query;
    final addedTimes = <int, int>{};
    final readTimes = <int, int>{};
    // A combined volume may derive its import date from hundreds of originals.
    // Each sort key is read at most once, even when many comparisons tie.
    int addedAt(int id) => addedTimes[id] ??= widget.books.importedAt(id);
    int readAt(int id) =>
        readTimes[id] ??= widget.state.positionFor(id)?.updatedAt ?? 0;
    return _visibleBooks = organization
        .filter(
          _localMembership(),
          query: query,
          addedAt: addedAt,
          readAt: readAt,
        )
        .where(
          (book) => switch (organization.readingFilter) {
            'unread' => !widget.state.hasRead(book.id),
            'reading' =>
              widget.state.hasRead(book.id) &&
                  !widget.state.finishedReading(book),
            'finished' => widget.state.finishedReading(book),
            _ => true,
          },
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.refresh = _reload;
    _controller.search = widget.onSearch ?? _toggleSearch;
    _controller.importMenu = _importMenu;
    _importer.addListener(_importChanged);
    // Keep data invalidation cheap even while this retained tab is offstage.
    // Import progress, keyboard and viewport changes reuse the ordered books.
    _bookChanges.addListener(_invalidateBooks);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _importer.scanOnEntry(context, resumed: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context);
    final scanActive = current != false && TickerMode.valuesOf(context).enabled;
    if (scanActive && !_scanActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _importer.scanOnEntry(context);
      });
    }
    _scanActive = scanActive;
    if (current == true && _routeCurrent == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.isCurrentOf(context) == true) _reload();
      });
    }
    _routeCurrent = current;
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchFocus.unfocus();
        _search.clear();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _searchOpen &&
            _searchFocus.canRequestFocus &&
            ModalRoute.isCurrentOf(context) != false) {
          _searchFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _importMenu(BuildContext anchor) async {
    _searchFocus.unfocus();
    await _importer.showMenu(
      anchor,
      sync: _sync,
      onBatch: () => openLocalBookBatch(
        context,
        books: widget.books,
        library: widget.state,
      ),
    );
    if (mounted) _reload();
  }

  void _importChanged() {
    if (!mounted) return;
    setState(() {
      _importing = _importer.busy;
      _importProgress = _importer.progress;
      _error = _importer.error;
    });
    _controller
      ..importing = _importing
      ..importMenu = _importing ? null : _importMenu
      ..changed();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final organization = widget.state.organization;
      if (_organization != organization) {
        _organization?.removeListener(_invalidateBooks);
        organization.addListener(_invalidateBooks);
      }
      final sync = BookSync(
        books: widget.books,
        state: widget.state,
        preferences: prefs,
        documents: _documents,
        organization: organization,
        cloudSources: _cloudSources,
      );
      setState(() {
        _invalidateBooks();
        _organization = organization;
        _viewChanges = Listenable.merge([_bookChanges, organization]);
        _sync = sync;
      });
      _controller.changed();
      await Future.wait([sync.load(), _cloudSources.load()]);
    } catch (_) {
      if (mounted) setState(() => _error = '本地书库设置读取失败，请重试');
    }
  }

  void _reload() {
    try {
      _organization?.refresh();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '本地分类读取失败，请重试');
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showNovelFeedback(
          context,
          e is FormatException ? e.message : '设置保存失败，请重试',
        );
      }
    }
  }

  Future<void> _volumes(Novel book, {bool suggested = false}) async {
    final result = await pushNovelPage<LocalSeriesEditResult>(
      context,
      LocalSeriesEditor(
        book: book,
        books: widget.books,
        library: widget.state,
        suggested: suggested,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (!mounted || result == null) return;
    _organization?.refresh();
    showNovelFeedback(
      context,
      result.dissolved
          ? '已恢复为独立书籍'
          : '已保存《${widget.books.book(result.bookId!)!.title}》的分卷',
    );
  }

  Future<void> _remove(Novel book) async {
    await _save(() async {
      await chooseLocalBookRemoval(
        context,
        book: book,
        books: widget.books,
        library: widget.state,
      );
    });
  }

  Future<void> _bookMenu(Novel book) async {
    final organization = _organization!;
    final currentCategory = organization.groupOf(book.id);
    final seriesLabel = widget.books.seriesFor(book.id) == null
        ? '合并分卷'
        : '管理分卷';
    final value = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      builder: (sheet) {
        Widget action(
          String value,
          String label,
          IconData icon, {
          bool destructive = false,
        }) {
          final color = destructive ? Theme.of(sheet).colorScheme.error : null;
          return GlassTextButton(
            key: ValueKey('local-book-action-$value'),
            onPressed: () => Navigator.pop(sheet, value),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ArchiveIcon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: AppText(label, style: TextStyle(color: color)),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArchiveSection(title: book.title, code: 'LOCAL / ORGANIZE'),
              GlassChoiceGroup<String>(
                name: 'local-book-category',
                label: '移至分类',
                value: currentCategory,
                options: {
                  LocalLibraryPreferences.unfiled: '未分类',
                  ...organization.groups,
                },
                leading: (category) => ArchiveIcon(
                  category == currentCategory
                      ? CupertinoIcons.check_mark
                      : CupertinoIcons.folder,
                  size: 16,
                ),
                onChanged: (category) => Navigator.pop(sheet, category),
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: Theme.of(sheet).dividerColor),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: action(
                      '_series',
                      seriesLabel,
                      CupertinoIcons.rectangle_stack,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: action(
                      '_batch',
                      '批量选择',
                      CupertinoIcons.checkmark_circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              action(
                '_delete',
                '移除书籍',
                CupertinoIcons.trash,
                destructive: true,
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || value == null) return;
    if (value == '_series') {
      await _volumes(book);
    } else if (value == '_delete') {
      await _remove(book);
    } else if (value == '_batch') {
      await openLocalBookBatch(
        context,
        books: widget.books,
        library: widget.state,
        selected: {book.id},
      );
    } else {
      await _save(() => organization.assign(book.id, value));
    }
  }

  Future<void> _categories() => showBookCategories(
    context,
    _organization!,
    books: widget.books.books.where(
      (book) => widget.state.localBookVisible(book.id),
    ),
    reduceMotion: widget.state.reduceMotion,
  );

  Future<void> _display({
    BookCollectionViewTarget target = BookCollectionViewTarget.all,
  }) async {
    final organization = _organization!;
    final layout = await showJellySheet<bool>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .82,
      builder: (_) => AnimatedBuilder(
        animation: Listenable.merge([organization, _gridViewport]),
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: BookCollectionViewOptions(
            target: target,
            mode: organization.viewMode,
            onModeChanged: (mode) =>
                _save(() => organization.setViewMode(mode)),
            gridDensity: organization.gridDensity,
            shelfPreferences: organization.shelfPreferences,
            shelfContent: organization.shelfContent,
            shelfCategoryOptions: _shelfCategoryOptions(organization),
            shelfSortOptions: const {
              BookShelfContentSort.original: '原始顺序',
              BookShelfContentSort.recentRead: '最近阅读',
              BookShelfContentSort.recentAdded: '最近导入',
              BookShelfContentSort.title: '书名',
            },
            shelfContentHint: '上方立体书架可独立展示本地分类与阅读状态；下方仍按页面筛选。',
            reduceMotion: widget.state.reduceMotion,
            onShelfPreferencesChanged: (preferences) =>
                _save(() => organization.setShelfPreferences(preferences)),
            gridViewport: _gridViewport.value,
            onGridDensityChanged: (density) =>
                _save(() => organization.setGridDensity(density)),
            onShowLayoutOptions: target == BookCollectionViewTarget.all
                ? null
                : () => Navigator.pop(context, true),
          ),
        ),
      ),
    );
    if (mounted && layout == true) await _display();
  }

  Future<void> _shelfFilters() => showJellySheet<void>(
    context: context,
    reduceMotion: widget.state.reduceMotion,
    heightFactor: .82,
    builder: (_) => AnimatedBuilder(
      animation: _organization!,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: BookShelfContentOptions(
          value: _organization!.shelfContent,
          categoryOptions: _shelfCategoryOptions(_organization!),
          sortOptions: const {
            BookShelfContentSort.original: '原始顺序',
            BookShelfContentSort.recentRead: '最近阅读',
            BookShelfContentSort.recentAdded: '最近导入',
            BookShelfContentSort.title: '书名',
          },
          reduceMotion: widget.state.reduceMotion,
          onChanged: (value) =>
              _save(() => _organization!.setShelfContent(value)),
        ),
      ),
    ),
  );

  Future<void> _chooseShelfCategory() async {
    final organization = _organization!;
    final category = await chooseBookCollectionRegionCategory(
      context,
      options: _shelfCategoryOptions(organization),
      selected: organization.shelfContent.followCollection
          ? organization.selected
          : _shelfCategory(organization),
      reduceMotion: widget.state.reduceMotion,
    );
    if (category != null && mounted) {
      await _save(
        () => organization.setShelfContent(
          organization.shelfContent.copyWith(
            followCollection: false,
            category: category,
          ),
        ),
      );
    }
  }

  Widget _collectionToolbar(
    LocalLibraryPreferences? organization,
    int count, {
    bool region = false,
  }) {
    final category = organization?.nameOf(organization.selected) ?? '全部书籍';
    if (region) {
      return BookCollectionRegionToolbar(
        key: const ValueKey('local-collection-region-toolbar'),
        title: '本地书籍',
        category: category,
        count: count,
        loading: organization == null,
        activeFilters: organization?.readingFilter == 'all' ? 0 : 1,
        categoryKey: const ValueKey('local-category'),
        filterKey: const ValueKey('local-filter'),
        viewKey: const ValueKey('local-display'),
        onCategory: organization == null ? null : _categories,
        onFilter: organization == null ? null : _filters,
        onView: organization == null
            ? null
            : () => _display(target: BookCollectionViewTarget.collection),
      );
    }
    return LibraryToolbar(
      categoryKey: const ValueKey('local-category'),
      optionsKey: const ValueKey('local-filter'),
      viewKey: const ValueKey('local-display'),
      category: category,
      count: count,
      loading: organization == null,
      activeFilters: organization?.readingFilter == 'all' ? 0 : 1,
      onCategory: organization == null ? null : _categories,
      onOptions: organization == null ? null : _filters,
      onView: organization == null ? null : () => _display(),
    );
  }

  Widget _searchField() => AnimatedOptionSection(
    expanded: _searchOpen,
    child: Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppSearchField(
        controller: _search,
        focusNode: _searchFocus,
        hint: '搜索本地书名、作者',
        onChanged: (_) => setState(() {}),
      ),
    ),
  );

  Widget _shelfToolbar(LocalLibraryPreferences organization, int count) =>
      BookCollectionRegionToolbar(
        key: const ValueKey('local-shelf-region-heading'),
        title: '立体书架',
        category: organization.shelfContent.followCollection
            ? organization.nameOf(organization.selected)
            : organization.nameOf(_shelfCategory(organization)),
        count: count,
        categoryKey: const ValueKey('local-shelf-category'),
        filterKey: const ValueKey('local-shelf-filter'),
        viewKey: const ValueKey('local-shelf-display'),
        onCategory: _chooseShelfCategory,
        onFilter: _shelfFilters,
        onView: () => _display(target: BookCollectionViewTarget.shelf),
      );

  Future<void> _filters() async {
    final organization = _organization!;
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .72,
      builder: (_) => AnimatedBuilder(
        animation: organization,
        builder: (_, _) => LibraryViewOptions(
          showView: false,
          shelf: organization.viewMode.hasShelf,
          reading: organization.readingFilter,
          sort: organization.sort.name,
          onView: (v) => _save(
            () => organization.setView(
              v ? LocalLibraryView.shelf : LocalLibraryView.list,
            ),
          ),
          onReading: (v) => _save(() => organization.setReadingFilter(v)),
          onSort: (v) => _save(
            () => organization.setSort(LocalLibrarySort.values.byName(v)),
          ),
        ),
      ),
    );
  }

  void _open(Novel book, Object tag) {
    if (widget.onOpenWithCover case final open?) {
      open(context, book, tag);
    } else {
      widget.onOpen(context, book);
    }
  }

  String _gridProgress(Novel book) => !widget.state.hasRead(book.id)
      ? '未读'
      : widget.state.finishedReading(book)
      ? '已读完'
      : (book.chapters.isNotEmpty || book.chapterCount > 0)
      ? '${widget.state.chapterForNovel(book) + 1}/${book.chapters.isNotEmpty ? book.chapters.length : book.chapterCount}'
      : '第 ${widget.state.chapterFor(book.id) + 1} 章';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..importMenu = null
      ..search = null
      ..refresh = null;
    if (widget.controller == null) _controller.dispose();
    _sync?.dispose();
    _importer.removeListener(_importChanged);
    _importer.dispose();
    _bookChanges.removeListener(_invalidateBooks);
    _organization?.removeListener(_invalidateBooks);
    if (widget.cloudSettings == null) _cloudSources.dispose();
    _search.dispose();
    _gridViewport.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _header(BuildContext context) =>
      _localLibraryHeader(context, _controller, back: true);
  @override
  Widget build(BuildContext context) {
    final organization = _organization;
    final body = GlassHeaderLayout(
      showHeader: widget.showHeader,
      header: _header(context),
      body: CompactMainPageControls(
        enabled: widget.compactMainPageControls,
        child: ActiveListenableBuilder(
          listenable: _viewChanges ?? _bookChanges,
          builder: (context) {
            final books = _filteredBooks(organization);
            final featured = organization?.viewMode.hasShelf == true
                ? _featuredBooks(organization, books)
                : const <Novel>[];
            final shelf = organization?.showsShelf(featured.length) == true;
            final mixed = organization?.viewMode.hasShelf == true;
            final grid = organization?.viewMode.isGrid == true;
            final independent =
                organization?.viewMode.hasShelf == true &&
                organization?.shelfContent.followCollection == false;
            // A carousel is a featured view, not a replacement for the index.
            // Every filtered book remains reachable in the same complete list.
            final rows = books;
            return LoadedContentSequence(
              generation: (
                organization?.selected,
                organization?.readingFilter,
                organization?.sort,
                organization?.shelfContent.record,
                _search.text,
                shelf,
                grid,
              ),
              child: CustomScrollView(
                key: const PageStorageKey('local-library'),
                clipBehavior: LibraryReflowScope.clipOf(context),
                cacheExtent: BookCollectionLayout.cacheExtentFor(
                  MediaQuery.sizeOf(context).width - 48,
                  base: 250,
                  grid: grid,
                ),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.paddingOf(context).top +
                          FrostedHeader.toolbarHeight +
                          20,
                      24,
                      14,
                    ),
                    sliver: SliverToBoxAdapter(
                      // SliverToBoxAdapter does not retain its child's picture
                      // like SliverList does. Keep the toolbar/labels out of the
                      // scroll repaint path; glass still resolves its transform
                      // and live backdrop when the retained layers composite.
                      child: _localToolbarPaint(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (mixed)
                              _shelfToolbar(organization!, featured.length)
                            else ...[
                              _collectionToolbar(organization, books.length),
                              _searchField(),
                            ],
                            const SizedBox(height: 14),
                            if (widget.books.books.isEmpty &&
                                organization != null) ...[
                              const AppText(
                                '还没有本地书籍，点击右上角导入按钮添加。',
                                style: TextStyle(height: 1.7),
                              ),
                            ],
                            if (organization == null)
                              BookCollectionSkeleton(
                                rows: 2,
                                grid: grid,
                                gridDensity:
                                    organization?.gridDensity ??
                                    const BookGridDensity.auto(),
                                label: _importProgress == null
                                    ? '正在整理本地书库'
                                    : '正在导入 ${_importProgress!.$1} / ${_importProgress!.$2} 本',
                              )
                            else if (_importing) ...[
                              AppText(
                                _importProgress == null
                                    ? '正在导入书籍'
                                    : '正在导入 ${_importProgress!.$1} / ${_importProgress!.$2} 本',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(
                                height: 8,
                                child: RefreshProgress(label: '正在导入书籍'),
                              ),
                            ],
                            if ((_error ?? widget.books.seriesError) !=
                                null) ...[
                              AppText(
                                (_error ?? widget.books.seriesError)!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              if (organization == null)
                                GlassTextButton(
                                  onPressed: _load,
                                  child: const AppText('重试'),
                                ),
                            ],
                            if (organization != null &&
                                books.isEmpty &&
                                widget.books.books.isNotEmpty &&
                                !mixed)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: AppText('没有符合条件的书籍，换个分类或关键词试试。'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (mixed && featured.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                      sliver: SliverToBoxAdapter(
                        child: AppText('立体书架暂无符合条件的书籍'),
                      ),
                    ),
                  if (mixed && featured.isNotEmpty && !shelf)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      sliver: SliverToBoxAdapter(
                        child: AppText(
                          '当前范围共 ${featured.length} 本，达到 ${organization!.shelfPreferences.minimumBooks} 本时显示立体书架。',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  if (shelf)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ArchiveFileCarousel(
                          key: ValueKey((
                            'local-shelf',
                            independent
                                ? organization!.shelfContent.record
                                : (
                                    organization!.selected,
                                    organization.readingFilter,
                                    organization.sort,
                                    _search.text,
                                  ),
                            independent ? _shelfCategory(organization) : null,
                          )),
                          books: featured
                              .take(
                                organization.shelfPreferences.featuredCount(
                                  featured.length,
                                ),
                              )
                              .toList(),
                          repeatFill: organization.shelfPreferences.repeatFill,
                          library: widget.state,
                          entry: ReadingEntry.local,
                          reduceMotion: widget.state.reduceMotion,
                          animateEntrance: true,
                          onOpen: _open,
                        ),
                      ),
                    ),
                  if (mixed)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      sliver: SliverToBoxAdapter(
                        child: _localToolbarPaint(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _collectionToolbar(
                                organization,
                                books.length,
                                region: true,
                              ),
                              _searchField(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (mixed && books.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
                      sliver: SliverToBoxAdapter(
                        child: AppText('下方暂无符合条件的书籍，换个分类或关键词试试。'),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: BookCollectionSliver(
                      shareRowGlass: !grid,
                      grid: grid,
                      gridDensity:
                          organization?.gridDensity ??
                          const BookGridDensity.auto(),
                      gridBottomInset: widget.showHeader
                          ? MediaQuery.paddingOf(context).bottom + 32
                          : DockLayout.scrollPaddingOf(context),
                      onGridViewport: (v) => _gridViewport.value = v,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final book = rows[index],
                            tag = ValueKey('local-cover-${rows[index].id}');
                        return LoadedContentItem(
                          key: ValueKey(book.id),
                          index: index,
                          placeholder: grid
                              ? const BookGridSkeleton()
                              : const BookRowSkeleton(),
                          child: grid
                              ? BookGridTile(
                                  key: ValueKey('local-grid-book-${book.id}'),
                                  book: book,
                                  coverHeroTag: tag,
                                  onTap: () => _open(book, tag),
                                  progress: _gridProgress(book),
                                  trailing: GlassIconButton.custom(
                                    label: '整理 ${book.title}',
                                    onPressed: () => _bookMenu(book),
                                    liveGlass: false,
                                    transparent: true,
                                    child: const ArchiveIcon(
                                      CupertinoIcons.ellipsis,
                                      size: 18,
                                    ),
                                  ),
                                )
                              : NovelRow(
                                  novel: book,
                                  coverHeroTag: tag,
                                  onTap: () => _open(book, tag),
                                  trailing: GlassIconButton(
                                    icon: CupertinoIcons.ellipsis,
                                    label: '整理 ${book.title}',
                                    onPressed: () => _bookMenu(book),
                                    liveGlass: _localRowGlassAction,
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: widget.showHeader
                          ? MediaQuery.paddingOf(context).bottom + 32
                          : DockLayout.scrollPaddingOf(context),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return widget.showHeader ? Scaffold(body: Atmosphere(child: body)) : body;
  }
}
