import 'package:flutter/material.dart';
import '../app_search_field.dart';
import '../app_ui.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../pages.dart' show NovelRow;
import 'source_repository.dart';

class SourceLinkPage extends StatefulWidget {
  const SourceLinkPage({
    super.key,
    required this.oldBook,
    required this.repository,
    this.reduceMotion = false,
  });
  final Novel oldBook;
  final SourceNovelRepository repository;
  final bool reduceMotion;
  @override
  State<SourceLinkPage> createState() => _SourceLinkPageState();
}

class _SourceLinkPageState extends State<SourceLinkPage> {
  late final _searchRepository = SourceNovelRepository(
    store: widget.repository.store,
    platform: widget.repository.platform,
    legacyBook: widget.repository.legacyBook,
  );
  late final _query = TextEditingController(text: widget.oldBook.title);
  List<Novel> _books = const [];
  int _page = 0;
  bool _loading = false, _hasMore = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _books = [];
        _page = 0;
      }
    });
    try {
      final page = await _searchRepository.searchPage(
        _query.text,
        page: _page + 1,
        refresh: !more,
      );
      if (mounted) {
        setState(() {
          _books = [..._books, ...page.items];
          _page = page.page;
          _hasMore = page.hasMore;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = sourceErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bind(Novel target) async {
    if (_loading) return;
    if (!await confirmNovelAction(
      context,
      title: '关联「${target.title}」？',
      message: '保留旧书架位置、缓存与书签。新旧章节仅按唯一同名匹配；目录不一致时不会更改旧书。请确认作者及版本一致。',
      confirmLabel: '检查目录并关联',
      reduceMotion: widget.reduceMotion,
    )) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.detail(target);
      final chapters = await widget.repository.chapters(target.id);
      final bound = await widget.repository.store.bindLegacy(
        widget.oldBook,
        detail,
        chapters,
      );
      if (mounted) Navigator.pop(context, bound);
    } catch (e) {
      if (mounted) setState(() => _error = sourceErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchRepository.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '关联书源',
    code: 'SOURCES / PRESERVE YOUR PLACE',
    child: ListView(
      padding: featurePadding(context),
      children: [
        AppSearchField(
          controller: _query,
          hint: '搜索同一本书',
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        const AppText(
          '选择同作者、同版本的作品，关联后继续使用原书的缓存、进度和书签。',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          AppText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_loading) const LoadingSkeleton(layout: SkeletonLayout.actions),
        for (final book in _books)
          NovelRow(
            novel: book,
            sourceLabel: widget.repository.store.source(book.sourceId)?.name,
            onTap: () => _bind(book),
          ),
        if (_hasMore && !_loading)
          GlassTextButton(
            onPressed: () => _search(more: true),
            child: const AppText('继续查找'),
          ),
        if (_books.isEmpty && !_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: AppText('未找到作品，请先导入对应书源')),
          ),
      ],
    ),
  );
}
