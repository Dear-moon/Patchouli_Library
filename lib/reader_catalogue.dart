import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'app_search_field.dart';
import 'catalog.dart';
import 'offline_cache.dart';
import 'library_state.dart' show ReadingPosition;
import 'library_reflow.dart';

/// A bounded, lazy chapter picker using the existing glass drawer. The current
/// chapter is the scroll origin, so locating it never lays out earlier rows.
class ReaderCatalogue extends StatefulWidget {
  const ReaderCatalogue({
    super.key,
    required this.novel,
    required this.currentChapter,
    this.cache,
    this.position,
    this.onProgressPreview,
    this.onProgressCommitted,
    this.onPreviewChanged,
    this.canHandoff = false,
    this.initialReversed = false,
    this.onOrderChanged,
    this.reduceMotion = false,
  });
  final Novel novel;
  final int currentChapter;
  final OfflineCacheStore? cache;
  final ReadingPosition? position;
  final ValueChanged<double>? onProgressPreview, onProgressCommitted;
  final ValueChanged<bool>? onPreviewChanged;
  final bool canHandoff;
  final bool initialReversed;
  final ValueChanged<bool>? onOrderChanged;
  final bool reduceMotion;

  @override
  State<ReaderCatalogue> createState() => _ReaderCatalogueState();
}

class _ReaderCatalogueState extends State<ReaderCatalogue>
    with SingleTickerProviderStateMixin {
  final _rowReflow = LibraryReflowController();
  late final _orderMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _center = GlobalKey();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;
  late bool _reversed = widget.initialReversed;
  late List<int> _matches = _filter('');
  late final _entries = widget.novel.directory;
  late final _directoryChapters = widget.novel.directoryChapters;
  late final _current = widget.novel.directoryIndexFor(
    widget.currentChapter,
    paragraph: widget.position?.paragraphIndex ?? 0,
    offset: widget.position?.textOffset ?? 0,
  );
  late final _volumes = NovelVolume.of(_directoryChapters);
  late final Set<String> _expanded = {
    for (final volume in _volumes)
      if (_current >= volume.start && _current < volume.end) volume.key,
  };

  @override
  void initState() {
    super.initState();
    _orderMotion.addStatusListener((status) {
      if (status == AnimationStatus.completed && _rowReflow.active && mounted) {
        setState(_rowReflow.finish);
      }
    });
  }

  void _changeRows(VoidCallback change) {
    final motion =
        !widget.reduceMotion && !MediaQuery.disableAnimationsOf(context);
    if (motion) _rowReflow.begin(_orderMotion);
    setState(change);
    if (motion) _orderMotion.forward(from: 0);
  }

  List<int> _filter(String query) {
    final chapters = _directoryChapters;
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return List.generate(chapters.length, (index) => index);
    final number = int.tryParse(text);
    if (number != null) {
      return number > 0 && number <= chapters.length ? [number - 1] : [];
    }
    return [
      for (var index = 0; index < chapters.length; index++)
        if (chapters[index].title.toLowerCase().contains(text) ||
            chapters[index].volumeTitle.toLowerCase().contains(text))
          index,
    ];
  }

  void _filterChanged(String query) {
    setState(() => _matches = _filter(query));
    _resetScrollAfterFrame();
  }

  void _toggleOrder() {
    _changeRows(() => _reversed = !_reversed);
    widget.onOrderChanged?.call(_reversed);
    _resetScrollAfterFrame();
  }

  void _resetScrollAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _rowReflow.dispose();
    _orderMotion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = math.max(
      0.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom - 40,
    );
    final height = math.min(media.size.height * .64, available);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Small landscape/keyboard viewports can scroll the header as well;
          // the chapter list still has its own finite lazy viewport.
          if (constraints.maxHeight < 210) {
            return SingleChildScrollView(
              child: SizedBox(height: 300, child: _contents(context)),
            );
          }
          return _contents(context);
        },
      ),
    );
  }

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchOpen) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
      _search.clear();
      _filterChanged('');
    }
  }

  Widget _contents(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: AppText(
                '目录',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            GlassIconButton(
              key: const ValueKey('reader-catalogue-search-toggle'),
              icon: CupertinoIcons.search,
              label: _searchOpen ? '收起搜索' : '搜索目录',
              onPressed: _toggleSearch,
            ),
            GlassTextButton(
              key: const ValueKey('reader-catalogue-order'),
              compact: true,
              selected: _reversed,
              onPressed: _toggleOrder,
              child: AppText(_reversed ? '倒序' : '正序'),
            ),
            GlassIconButton(
              icon: CupertinoIcons.xmark,
              label: '关闭目录',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _searchOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppSearchField(
                    inputKey: const ValueKey('reader-chapter-search'),
                    controller: _search,
                    focusNode: _searchFocus,
                    hint: '搜索章节名或输入章序',
                    onChanged: _filterChanged,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        Expanded(child: _chapters(context)),
      ],
    ),
  );

  Widget _chapters(BuildContext context) {
    if (_matches.isEmpty) {
      return const Center(child: AppText('没有匹配的章节'));
    }
    final matches = _matches.toSet();
    // Reorder only the display projection; row indices remain source addresses.
    final rows = <({NovelVolume? volume, int? chapter})>[
      for (final volume in _reversed ? _volumes.reversed : _volumes)
        if (Iterable.generate(
          volume.length,
          (i) => volume.start + i,
        ).any(matches.contains)) ...[
          if (volume.title.isNotEmpty) (volume: volume, chapter: null),
          if (volume.title.isEmpty ||
              _expanded.contains(volume.key) ||
              _search.text.trim().isNotEmpty)
            for (final i in Iterable.generate(
              volume.length,
              (i) => _reversed ? volume.end - i - 1 : volume.start + i,
            ))
              if (matches.contains(i)) (volume: null, chapter: i),
        ],
    ];
    Widget row(int index) => LibraryReflowPart(
      id: rows[index].volume != null
          ? ('volume', rows[index].volume!.key)
          : ('chapter', rows[index].chapter!),
      child: rows[index].volume != null
          ? _volumeRow(context, rows[index].volume!)
          : _row(context, rows[index].chapter!),
    );
    final current = rows.indexWhere((row) => row.chapter == _current);
    final origin = current < 0 ? 0 : current;
    return LibraryReflowScope(
      controller: _rowReflow,
      enabled: !widget.reduceMotion && !MediaQuery.disableAnimationsOf(context),
      generation: _rowReflow.generation,
      active: _rowReflow.active,
      child: LibraryReflowClip(
        controller: _rowReflow,
        child: CustomScrollView(
          key: const ValueKey('reader-catalogue-scroll'),
          clipBehavior: _rowReflow.active ? Clip.none : Clip.hardEdge,
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          center: _center,
          anchor: current > 0 ? .22 : 0,
          slivers: [
            SliverList.builder(
              itemCount: origin,
              itemBuilder: (context, index) => row(origin - index - 1),
            ),
            SliverList.builder(
              key: _center,
              itemCount: rows.length - origin,
              itemBuilder: (context, index) => row(origin + index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _volumeRow(BuildContext context, NovelVolume volume) {
    final expanded =
        _expanded.contains(volume.key) || _search.text.trim().isNotEmpty;
    return Semantics(
      expanded: expanded,
      child: JellyTapSurface(
        key: ValueKey('reader-volume-${volume.key}'),
        onTap: _search.text.trim().isNotEmpty
            ? null
            : () => _changeRows(() {
                if (!_expanded.add(volume.key)) _expanded.remove(volume.key);
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  volume.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppText(
                '${volume.length} 章',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 10),
              AnimatedRotation(
                turns: expanded ? .25 : 0,
                duration:
                    widget.reduceMotion ||
                        MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : NovelMotion.enter,
                curve: NovelMotion.ease,
                child: const ArchiveIcon(
                  CupertinoIcons.chevron_right,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index) {
    final entry = _entries[index];
    final chapter = widget.novel.chapters[entry.chapter];
    final current = index == _current;
    return Semantics(
      selected: current,
      child: JellyTapSurface(
        key: ValueKey('reader-chapter-$index'),
        onTap: () {
          FocusScope.of(context).unfocus();
          Navigator.pop(
            context,
            widget.novel.navigation?.entries.isNotEmpty == true
                ? entry.target
                : entry.chapter,
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: EdgeInsets.fromLTRB(
            10 + entry.depth.clamp(0, 6) * 12.0,
            12,
            10,
            12,
          ),
          decoration: BoxDecoration(
            color: current
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .06)
                : null,
            borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppText(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: AppText(
                  entry.title,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (current)
                    const AppText('正在阅读', style: TextStyle(fontSize: 10)),
                  if (widget.cache case final OfflineCacheStore cache)
                    AnimatedBuilder(
                      animation: cache.bookChanges(widget.novel.id),
                      builder: (context, _) =>
                          cache
                                  .book(widget.novel.id)
                                  ?.chapterBytes
                                  .containsKey(chapter.id) ==
                              true
                          ? const AppText('已缓存', style: TextStyle(fontSize: 10))
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
