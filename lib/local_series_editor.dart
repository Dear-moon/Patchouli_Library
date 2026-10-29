import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app_ui.dart';
import 'app_interactions.dart' show showNovelFeedback;
import 'app_search_field.dart';
import 'catalog.dart';
import 'feature_pages.dart'
    show confirmNovelAction, FeatureError, featurePadding;
import 'library_state.dart';
import 'local_books.dart';
import 'local_book_series.dart';
import 'local_book_edit_widgets.dart';
import 'local_series_actions.dart';
import 'listening/widgets.dart';

class LocalSeriesEditResult {
  const LocalSeriesEditResult({this.bookId, this.dissolved = false});
  final int? bookId;
  final bool dissolved;
}

class LocalSeriesEditor extends StatefulWidget {
  const LocalSeriesEditor({
    super.key,
    required this.book,
    required this.books,
    required this.library,
    this.suggested = false,
  });
  final Novel book;
  final LocalBookStore books;
  final LibraryState library;
  final bool suggested;
  @override
  State<LocalSeriesEditor> createState() => _LocalSeriesEditorState();
}

class _LocalSeriesEditorState extends State<LocalSeriesEditor> {
  final _title = TextEditingController();
  final _labels = <int, String>{};
  final _order = <int>[];
  LocalBookSeries? _series;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.books.seriesFor(widget.book.id);
    final related = widget.books.relatedVolumes(widget.book.id);
    final suggested = widget.suggested
        ? related
              .map((b) => widget.books.seriesFor(b.id))
              .whereType<LocalBookSeries>()
              .firstOrNull
        : null;
    _configure(current ?? suggested, related: related);
  }

  String _label(int id) => _labels.putIfAbsent(
    id,
    () =>
        widget.books.seriesHint(id)?.volumeTitle ??
        widget.books.book(id)!.title,
  );

  void _configure(LocalBookSeries? series, {List<Novel> related = const []}) {
    _series = series;
    _order.clear();
    if (series != null) {
      for (final volume in series.volumes) {
        _order.add(volume.bookId);
        _labels[volume.bookId] = volume.title;
      }
    }
    void add(int id) {
      if (_order.contains(id)) return;
      final hint = widget.books.seriesHint(id);
      final before = hint == null
          ? -1
          : _order.indexWhere((other) {
              final h = widget.books.seriesHint(other);
              return h?.key == hint.key && h!.number > hint.number;
            });
      before < 0 ? _order.add(id) : _order.insert(before, id);
    }

    final initial = widget.books.originals
        .where((b) => b.id == widget.book.id)
        .firstOrNull;
    if (initial != null) add(initial.id);
    for (final book in related) {
      if (widget.books.seriesFor(book.id) == null) add(book.id);
    }
    if (series == null) {
      _order.sort(
        (a, b) => (widget.books.seriesHint(a)?.number ?? double.infinity)
            .compareTo(widget.books.seriesHint(b)?.number ?? double.infinity),
      );
    }
    _title.text =
        series?.title ??
        widget.books.seriesHint(widget.book.id)?.title ??
        widget.book.title;
    _error = null;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _chooseTarget() async {
    final selected = await showJellySheet<int>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      heightFactor: .68,
      builder: (sheet) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const ArchiveSection(title: '合并到', code: 'LOCAL / COLLECTION'),
          const SizedBox(height: 16),
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, 0),
            child: const AppText('新建合订本'),
          ),
          for (final series in widget.books.series)
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, series.id),
              child: AppText('${series.title} · ${series.volumes.length} 卷'),
            ),
        ],
      ),
    );
    if (mounted && selected != null) {
      setState(
        () =>
            _configure(selected == 0 ? null : widget.books.seriesFor(selected)),
      );
    }
  }

  Future<void> _stopReading() async {
    final listening = ListeningScope.maybeOf(context);
    final id = listening?.snapshot.value.novel?.id;
    if (id != null && (id == _series?.id || _order.contains(id))) {
      await listening!.stop();
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_series != null && _order.length < 2) {
      if (!await confirmNovelAction(
            context,
            title: '恢复为独立书籍？',
            message: '合订本不足两卷。保存后各卷会独立显示，原文件、阅读进度与书签保留。',
            confirmLabel: '恢复独立书籍',
            reduceMotion: widget.library.reduceMotion,
          ) ||
          !mounted) {
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopReading();
      final volumes = [
        for (final id in _order) (bookId: id, title: _label(id)),
      ];
      final book = _series == null
          ? await saveLocalSeries(
              books: widget.books,
              library: widget.library,
              title: _title.text,
              volumes: volumes,
            )
          : await updateLocalSeries(
              books: widget.books,
              library: widget.library,
              id: _series!.id,
              title: _title.text,
              volumes: volumes,
            );
      if (book != null && _series == null && _order.isNotEmpty) {
        final groups = widget.library.organization;
        await groups.assign(book.id, groups.groupOf(_order.first));
      }
      if (mounted) {
        Navigator.pop(
          context,
          LocalSeriesEditResult(bookId: book?.id, dissolved: book == null),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e is FormatException ? e.message : '分卷保存未完成，原书仍保留，请重试';
        setState(() {
          _busy = false;
          _error = message;
          _series ??= widget.books.seriesFor(widget.book.id);
        });
        showNovelFeedback(context, message);
      }
    }
  }

  Future<void> _dissolve() async {
    final series = _series;
    if (_busy ||
        series == null ||
        !await confirmNovelAction(
          context,
          title: '恢复为独立书籍？',
          message: '各卷会重新显示在本地书库，阅读进度与书签按原章节保留。',
          confirmLabel: '恢复独立书籍',
          reduceMotion: widget.library.reduceMotion,
        ) ||
        !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopReading();
      await dissolveLocalSeries(
        books: widget.books,
        library: widget.library,
        series: series,
      );
      if (mounted) {
        Navigator.pop(context, const LocalSeriesEditResult(dissolved: true));
      }
    } catch (e) {
      if (mounted) {
        final message = e is FormatException ? e.message : '恢复未完成，原书仍保留，请重试';
        setState(() {
          _busy = false;
          _error = message;
        });
        showNovelFeedback(context, message);
      }
    }
  }

  Future<void> _rename(int id) async {
    final text = TextEditingController(text: _label(id));
    final value = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ArchiveSection(title: '修改卷名', code: 'LOCAL / VOLUME'),
            const SizedBox(height: 20),
            LocalBookEditField(
              label: '分卷名称',
              controller: text,
              inputKey: ValueKey('series-label-$id'),
              autofocus: true,
              onSubmitted: (_) {
                if (text.text.trim().isNotEmpty) {
                  Navigator.pop(sheet, text.text.trim());
                }
              },
            ),
            const SizedBox(height: 20),
            GlassPillButton(
              icon: CupertinoIcons.checkmark,
              label: '完成',
              onPressed: () {
                if (text.text.trim().isNotEmpty) {
                  Navigator.pop(sheet, text.text.trim());
                }
              },
            ),
          ],
        ),
      ),
    );
    text.dispose();
    if (mounted && value != null) setState(() => _labels[id] = value);
  }

  Future<void> _addVolumes() async {
    final candidates = widget.books.originals.where((book) {
      final owner = widget.books.seriesFor(book.id);
      return !_order.contains(book.id) &&
          (owner == null || owner.id == _series?.id);
    }).toList();
    final added = await showJellySheet<List<int>>(
      context: context,
      reduceMotion: widget.library.reduceMotion,
      heightFactor: .82,
      builder: (_) => _AddVolumesSheet(books: candidates),
    );
    if (mounted && added != null) {
      setState(() => _order.addAll(added.where((id) => !_order.contains(id))));
    }
  }

  void _move(int from, int to) {
    if (_busy || from == to) return;
    AppHaptics.play(context, HapticCue.selection);
    setState(() => _order.insert(to, _order.removeAt(from)));
  }

  Widget _volume(BuildContext context, int index) {
    final id = _order[index], book = widget.books.book(_order[index])!;
    return Padding(
      key: ValueKey('series-volume-$id'),
      padding: const EdgeInsets.only(bottom: 12),
      child: ContentPanel(
        child: ArchivePart(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  NovelCover(book, width: 44, height: 62),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          _label(id),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AppText(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ReorderableDragStartListener(
                    key: ValueKey('series-reorder-$id'),
                    index: index,
                    enabled: !_busy,
                    child: Semantics(
                      label: '拖动调整 ${book.title} 的顺序',
                      customSemanticsActions: {
                        if (index > 0)
                          CustomSemanticsAction(label: '向前移动'): () =>
                              _move(index, index - 1),
                        if (index + 1 < _order.length)
                          CustomSemanticsAction(label: '向后移动'): () =>
                              _move(index, index + 1),
                      },
                      child: const SizedBox(
                        width: 44,
                        height: 48,
                        child: Center(
                          child: ArchiveIcon(
                            CupertinoIcons.line_horizontal_3,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  AppText(
                    '${index + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        GlassTextButton(
                          key: ValueKey('series-rename-$id'),
                          compact: true,
                          onPressed: _busy ? null : () => _rename(id),
                          child: const AppText('修改卷名'),
                        ),
                        GlassTextButton(
                          key: ValueKey('series-remove-$id'),
                          compact: true,
                          onPressed: _busy
                              ? null
                              : () => setState(() => _order.remove(id)),
                          child: const AppText('移出'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introduction() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.suggested) ...[
        const AppText(
          '已找到同系列书籍，确认卷名与阅读顺序后即可合并。',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 20),
      ],
      if (widget.books.seriesFor(widget.book.id) == null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: GlassTextButton(
            key: const ValueKey('series-target'),
            compact: true,
            onPressed: _busy ? null : _chooseTarget,
            child: AppText('合并到：${_series?.title ?? '新建合订本'}'),
          ),
        ),
        const SizedBox(height: 18),
      ],
      LocalBookEditField(
        label: '合订本书名',
        controller: _title,
        inputKey: const ValueKey('series-title'),
        enabled: !_busy,
      ),
      const SizedBox(height: 28),
      ArchiveSection(
        title: '阅读顺序 · ${_order.length} 卷',
        code: '01 / VOLUMES',
        subtitle: '拖动右侧横线排序，移出的书会恢复独立显示。',
      ),
      const SizedBox(height: 18),
      if (_series != null && _order.length < 2) ...[
        ContentPanel(
          child: const AppText(
            '合订本不足两卷。保存后各卷会恢复为独立书籍。',
            style: TextStyle(height: 1.6),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (_order.isEmpty)
        ContentPanel(
          child: const AppText(
            '还没有分卷，点下方“添加分卷”选择本地书籍。',
            style: TextStyle(height: 1.6),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope<LocalSeriesEditResult>(
    canPop: !_busy,
    child: LocalBookEditLayout(
      title: _series == null ? '合并分卷' : '管理分卷',
      code: 'LOCAL / VOLUMES',
      onBack: _busy ? null : () => Navigator.maybePop(context),
      primaryKey: const ValueKey('series-save'),
      primaryLabel: _busy
          ? '正在保存'
          : _series == null
          ? '合并为一本书'
          : _order.length < 2
          ? '恢复独立书籍'
          : '保存分卷',
      primaryIcon: CupertinoIcons.checkmark,
      onPrimary: _busy || (_series == null && _order.length < 2) ? null : _save,
      secondaryKey: const ValueKey('series-add-volumes'),
      secondaryLabel: '添加分卷',
      secondaryIcon: CupertinoIcons.plus,
      onSecondary: _busy ? null : _addVolumes,
      slivers: [
        SliverPadding(
          padding: featurePadding(context).copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(child: _introduction()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverReorderableList(
            itemCount: _order.length,
            itemBuilder: _volume,
            onReorderStart: (_) => AppHaptics.play(context, HapticCue.action),
            onReorder: (from, to) => _move(from, to > from ? to - 1 : to),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FeatureError(_error),
                if (_series != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GlassTextButton(
                      key: const ValueKey('series-dissolve'),
                      compact: true,
                      onPressed: _busy ? null : _dissolve,
                      child: const AppText('全部恢复为独立书籍'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _AddVolumesSheet extends StatefulWidget {
  const _AddVolumesSheet({required this.books});
  final List<Novel> books;
  @override
  State<_AddVolumesSheet> createState() => _AddVolumesSheetState();
}

class _AddVolumesSheetState extends State<_AddVolumesSheet> {
  final _search = TextEditingController();
  final _selected = <int>{};
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final candidates = widget.books
        .where((b) => '${b.title} ${b.author}'.toLowerCase().contains(query))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ArchiveSection(title: '添加分卷', code: 'LOCAL / ORIGINALS'),
          const SizedBox(height: 16),
          AppSearchField(
            controller: _search,
            hint: '搜索书名、作者',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: candidates.isEmpty
                ? Center(
                    child: AppText(
                      widget.books.isEmpty ? '没有可添加的独立书籍' : '没有找到符合的书籍',
                    ),
                  )
                : ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final book = candidates[index],
                          selected = _selected.contains(candidates[index].id);
                      return ContentPanel(
                        key: ValueKey('series-add-${book.id}'),
                        onTap: () => setState(
                          () => selected
                              ? _selected.remove(book.id)
                              : _selected.add(book.id),
                        ),
                        child: Row(
                          children: [
                            NovelCover(book, width: 38, height: 54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    book.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  AppText(
                                    book.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ArchiveIcon(
                              selected
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              size: 22,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          GlassPillButton(
            key: const ValueKey('series-add-confirm'),
            icon: CupertinoIcons.plus,
            label: _selected.isEmpty ? '选择要添加的分卷' : '添加 ${_selected.length} 卷',
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
          ),
        ],
      ),
    );
  }
}
