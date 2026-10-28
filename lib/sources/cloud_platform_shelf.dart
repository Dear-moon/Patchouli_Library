import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_ui.dart';
import '../app_interactions.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../library_state.dart';
import '../pages.dart' show openDetail;
import '../wenku_features.dart';
import 'book_platform.dart';
import 'platform_account_page.dart';
import 'source_repository.dart';
import 'book_source.dart';
import 'shelf_platform_controls.dart';

class CloudPlatformShelf extends StatefulWidget {
  const CloudPlatformShelf({
    super.key,
    required this.repository,
    required this.state,
    required this.header,
    required this.showHeader,
    required this.offline,
  });
  final NovelRepository repository;
  final LibraryState state;
  final Widget header;
  final bool showHeader, offline;
  @override
  State<CloudPlatformShelf> createState() => _CloudPlatformShelfState();
}

class _CloudPlatformShelfState extends State<CloudPlatformShelf> {
  static int _next = 0;
  final _items = <({Novel book, bool external})>[];
  final _seen = <int>{};
  final _pages = <String>{};
  late final _request = 'cloud-shelf-${++_next}';
  bool _started = false, _busy = false, _more = true;
  int _page = 0;
  String? _nextUrl, _error;
  SourceNovelRepository? get _sources => sourceRepositoryOf(widget.repository);
  LibraryState get state => widget.state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!widget.offline && !['all', 'local'].contains(state.shelfPlatform)) {
        unawaited(_load());
      }
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = refresh ? 1 : _page + 1;
      final rows = <({Novel book, bool external})>[];
      var more = false;
      String? next;
      if (state.shelfPlatform == wenkuPlatformKey) {
        final account = WenkuFeaturesScope.maybeOf(context)?.account;
        if (account?.authenticated != true) {
          throw const SourceFailure('请先登录文库账号');
        }
        final books = await account!.readCloudBooks();
        for (final entry in books) {
          rows.add((
            book:
                state.cachedNovel(entry.id) ??
                Novel(
                  id: entry.id,
                  title: entry.title.isEmpty ? '书籍 ${entry.id}' : entry.title,
                  author: '',
                  genre: '',
                  summary: '',
                  colors: const [Color(0xFF353A42), Color(0xFF555961)],
                ),
            external: false,
          ));
        }
      } else {
        final repo = _sources!;
        final group = bookPlatforms(
          repo.store.sources,
          includeWenku: false,
        ).where((p) => p.key == state.shelfPlatform).firstOrNull;
        if (group == null) throw const SourceFailure('此平台书源已移除，请先在书源管理中恢复');
        final selected = repo.discoverySource;
        final source =
            group.sources
                .where((s) => s.enabled && s.key == selected?.key)
                .firstOrNull ??
            group.sources.where((s) => s.enabled).firstOrNull ??
            group.sources.first;
        if (!source.enabled) throw const SourceFailure('请先启用此平台书源');
        final status = await repo.ensureAccount(source);
        if (status.status == 'none' || status.status == 'signedOut') {
          throw SourceFailure('请先登录${group.name}');
        }
        final operation = source.data['cloudShelf'] == true
            ? 'cloudShelf'
            : (source.data['ruleAccount'] as Map?)?['shelf'] != null
            ? 'accountShelf'
            : null;
        if (operation == null) throw const SourceFailure('此书源未提供云收藏读取能力');
        final result = Map<String, dynamic>.from(
          await repo.platform.run(
                source,
                operation,
                page: page,
                url: refresh ? null : _nextUrl,
                requestId: _request,
              )
              as Map,
        );
        if (!mounted) return;
        final pageUrl = result['pageUrl'] as String?;
        if (!refresh && pageUrl != null && !_pages.add(pageUrl)) {
          throw const SourceFailure('云书架分页重复');
        }
        for (final raw in result['items'] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          rows.add((
            book: repo.store.remember(source, row),
            external: row['externalOnly'] == true,
          ));
        }
        await repo.store.flush();
        more = result['hasMore'] == true || result['nextUrl'] != null;
        next = result['nextUrl'] as String?;
      }
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items.clear();
          _seen.clear();
          _pages.clear();
        }
        _items.addAll(rows.where((row) => _seen.add(row.book.id)));
        _page = page;
        _more = more;
        _nextUrl = next;
      });
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accounts() async {
    await pushNovelPage<void>(
      context,
      PlatformAccountPage(repository: widget.repository, state: state),
      reduceMotion: state.reduceMotion,
    );
    if (mounted) await _load(refresh: true);
  }

  Future<void> _open(({Novel book, bool external}) entry) async {
    try {
      if (entry.external) {
        if (!await launchUrl(
          Uri.parse(entry.book.bookUrl!),
          mode: LaunchMode.externalApplication,
        )) {
          throw const SourceFailure('无法打开原站阅读页面');
        }
      } else {
        final book = await widget.repository.find(entry.book.id);
        if (book == null) throw const SourceFailure('书籍详情暂不可用');
        if (mounted) openDetail(context, book, state, widget.repository);
      }
    } catch (error) {
      if (mounted) showNovelFeedback(context, sourceErrorMessage(error));
    }
  }

  @override
  void dispose() {
    unawaited(_sources?.platform.cancel(_request));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassHeaderLayout(
    showHeader: widget.showHeader,
    header: widget.header,
    body: ListView(
      key: ValueKey('cloud-shelf-${state.shelfPlatform}'),
      padding: featurePadding(context),
      children: [
        ShelfPlatformControls(
          state: state,
          repository: widget.repository,
          offline: widget.offline,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: AppText(
                '云端收藏',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            GlassIconButton(
              icon: CupertinoIcons.refresh,
              label: '刷新云收藏',
              onPressed:
                  _busy ||
                      widget.offline ||
                      ['all', 'local'].contains(state.shelfPlatform)
                  ? null
                  : () => _load(refresh: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.offline)
          const AppText('离线模式下请切换到本机收藏。')
        else if (['all', 'local'].contains(state.shelfPlatform))
          const AppText('选择一个平台查看其云端收藏。')
        else ...[
          if (_error != null) ...[
            ContentNotice(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: '云收藏读取未完成',
              message: _error!,
              onRetry: () => _load(refresh: _items.isEmpty),
            ),
            GlassTextButton(
              onPressed: _accounts,
              child: const AppText('账号与登录'),
            ),
          ],
          for (final entry in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ContentPanel(
                onTap: () => _open(entry),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 74,
                      child: NovelCover(entry.book, width: 52, height: 74),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            entry.book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (entry.book.author.isNotEmpty)
                            AppText(
                              entry.book.author,
                              style: const TextStyle(fontSize: 12),
                            ),
                          if (entry.external)
                            const AppText(
                              '文库 · 原站阅读',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    const ArchiveIcon(CupertinoIcons.chevron_right, size: 14),
                  ],
                ),
              ),
            ),
          if (_busy) const InlineSkeleton(label: '正在读取云收藏'),
          if (!_busy && _error == null && _items.isEmpty)
            const AppText('此平台暂无云端收藏。'),
          if (!_busy && _more && _error == null && _items.isNotEmpty)
            GlassTextButton(onPressed: _load, child: const AppText('加载更多')),
          const SizedBox(height: 16),
          const AppText(
            '云端收藏独立展示，不会自动加入本机收藏。',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ],
    ),
  );
}
