import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'app_search_field.dart';
import 'catalog.dart';
import 'offline_repository.dart';
import 'local_books.dart';
import 'reader_content.dart';
import 'reader_find.dart';

class ReaderFindWholeBook {
  const ReaderFindWholeBook();
}

class BookTextMatch {
  const BookTextMatch(this.location, this.preview);
  final ReaderMatch location;
  final String preview;
}

class BookTextSearchResult {
  const BookTextSearchResult(
    this.matches,
    this.scanned,
    this.missing,
    this.failed, {
    this.truncated = false,
  });
  final List<BookTextMatch> matches;
  final int scanned, missing, failed;
  final bool truncated;
}

/// Reads one chapter at a time. Cancelling/closing never starts another request;
/// the default pass does not fetch un-cached text from the website.
Stream<BookTextSearchResult> findInBook(
  Novel novel,
  NovelRepository repository,
  String query, {
  bool network = false,
  Locale? locale,
  required bool Function() current,
}) async* {
  final matches = <BookTextMatch>[];
  if (query.trim().isEmpty || query.trim().length > 120) {
    yield const BookTextSearchResult([], 0, 0, 0);
    return;
  }
  var scanned = 0, missing = 0, failed = 0;
  for (var index = 0; index < novel.chapters.length; index++) {
    if (!current()) return;
    try {
      String? body;
      if (repository is OfflineNovelRepository && !isLocalBook(novel.id)) {
        body = await repository.cache.readChapter(
          novel.id,
          novel.chapters[index].id,
        );
        if (body == null && network && current()) {
          body = await repository.chapterContent(
            novel.id,
            novel.chapters[index],
          );
        }
      } else if (network || isLocalBook(novel.id)) {
        body = await repository.chapterContent(novel.id, novel.chapters[index]);
      }
      if (!current()) return;
      if (body == null) {
        missing++;
      } else {
        var content = await ReaderContent.parse(body);
        if (locale != null) content = await content.localizedAsync(locale);
        final found = await findInReader(content, query);
        if (!current()) return;
        scanned++;
        for (final match in found.matches) {
          final text = content.paragraphs[match.paragraph];
          final start = (match.start - 24).clamp(0, text.length);
          final end = (match.end + 60).clamp(start, text.length);
          matches.add(
            BookTextMatch(
              ReaderMatch(
                match.paragraph,
                match.start,
                match.end,
                chapter: index,
              ),
              '${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}',
            ),
          );
          if (matches.length >= 500) {
            yield BookTextSearchResult(
              List.unmodifiable(matches),
              scanned,
              missing,
              failed,
              truncated: true,
            );
            return;
          }
        }
      }
    } catch (_) {
      if (!current()) return;
      failed++;
    }
    yield BookTextSearchResult(
      List.unmodifiable(matches),
      scanned,
      missing,
      failed,
    );
    await Future<void>.delayed(Duration.zero);
  }
}

/// Both scopes stay in one drawer; switching a tab retains its query/results.
class ReaderSearchPanel extends StatefulWidget {
  const ReaderSearchPanel({
    super.key,
    required this.content,
    required this.novel,
    required this.repository,
    this.locale,
    this.wholeBook = false,
  });
  final ReaderContent content;
  final Novel novel;
  final NovelRepository repository;
  final Locale? locale;
  final bool wholeBook;

  @override
  State<ReaderSearchPanel> createState() => _ReaderSearchPanelState();
}

class _ReaderSearchPanelState extends State<ReaderSearchPanel> {
  late int _tab = widget.wholeBook ? 1 : 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(600, MediaQuery.sizeOf(context).height * .72),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 14, 8),
          child: Row(
            children: [
              const Expanded(
                child: AppText(
                  '查找',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              GlassIconButton(
                icon: CupertinoIcons.xmark,
                label: '关闭查找',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: AppControls.segments<int>(
            context,
            key: const ValueKey('reader-find-tabs'),
            groupValue: _tab,
            children: const {0: AppText('章内查找'), 1: AppText('整书查找')},
            onValueChanged: (value) {
              if (value == null || value == _tab) return;
              FocusScope.of(context).unfocus();
              setState(() => _tab = value);
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              ReaderFindPanel(content: widget.content, embedded: true),
              ReaderBookFindPanel(
                novel: widget.novel,
                repository: widget.repository,
                locale: widget.locale,
                embedded: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ReaderBookFindPanel extends StatefulWidget {
  const ReaderBookFindPanel({
    super.key,
    required this.novel,
    required this.repository,
    this.locale,
    this.embedded = false,
  });
  final Novel novel;
  final NovelRepository repository;
  final Locale? locale;
  final bool embedded;
  @override
  State<ReaderBookFindPanel> createState() => _ReaderBookFindPanelState();
}

class _ReaderBookFindPanelState extends State<ReaderBookFindPanel> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _busy = false;
  String _editedText = '';
  bool _wasComposing = false;
  BookTextSearchResult _result = const BookTextSearchResult([], 0, 0, 0);

  @override
  void initState() {
    super.initState();
    _query.addListener(_edited);
  }

  void _edited() {
    final value = _query.value;
    final composing = !value.composing.isCollapsed;
    if (value.text == _editedText && composing == _wasComposing) return;
    _editedText = value.text;
    _wasComposing = composing;
    _generation++;
    _debounce?.cancel();
    if (composing) return;
    // An IME may commit the same characters by changing only its composing
    // range. The controller observes that commit; onChanged does not.
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search({bool network = false}) async {
    _debounce?.cancel();
    final term = _query.text.trim(), generation = ++_generation;
    if (term.isEmpty || term.length > 120) {
      setState(() {
        _busy = false;
        _result = const BookTextSearchResult([], 0, 0, 0);
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = const BookTextSearchResult([], 0, 0, 0);
    });
    await for (final result in findInBook(
      widget.novel,
      widget.repository,
      term,
      network: network,
      locale: widget.locale,
      current: () => mounted && generation == _generation,
    )) {
      if (!mounted || generation != _generation) return;
      setState(() => _result = result);
    }
    if (mounted && generation == _generation) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _query.removeListener(_edited);
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .64,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: ArchiveSection(
                    title: '整书查找',
                    code: 'READER / BOOK QUERY',
                  ),
                ),
                GlassIconButton(
                  icon: CupertinoIcons.xmark,
                  label: '关闭整书查找',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AppSearchField(
            inputKey: const ValueKey('reader-book-find-field'),
            controller: _query,
            hint: '查找整本书的文字',
            onSubmitted: (_) => _search(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: AppText(
            _query.text.trim().length > 120
                ? '查找文字请控制在 120 字以内'
                : _query.text.isEmpty
                ? '查找本地原书和已缓存正文；不会自动缓存整本在线书。'
                : '${_busy ? '正在查找 · ' : ''}${_result.matches.length} 处 · 已查 ${_result.scanned}/${widget.novel.chapters.length} 章${_result.failed > 0 ? ' · ${_result.failed} 章读取失败' : ''}${_result.truncated ? ' · 显示前 500 处' : ''}',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_result.missing > 0 && !_busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassTextButton(
              onPressed: () => _search(network: true),
              child: AppText('联网查找未缓存章节（${_result.missing} 章）'),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            itemCount: _result.matches.length,
            itemBuilder: (context, index) {
              final match = _result.matches[index];
              return JellyTapSurface(
                key: ValueKey('book-find-result-$index'),
                onTap: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context, match.location);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        widget.novel.chapters[match.location.chapter!].title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        match.preview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
