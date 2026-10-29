import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'reader_content.dart';
import 'reader_scroll_index.dart';
import 'reader_scroll_sliver.dart';

/// Keeps source anchors separate from the continuous viewport's signed pixels.
class ReaderScrollStreamController<T> {
  _ReaderScrollStreamState<T>? _state;
  bool get attached => _state?.mounted == true;
  int? get originChapter => _state?._origin;
  ReaderParagraphRegistry? registryFor(int chapter) =>
      _state?._chapters[chapter]?.registry;
  double originOf(int chapter) => _state?._chapterOrigin(chapter) ?? 0;
  double? extentOf(int chapter) => _state?._chapters[chapter]?.extent;
  T? dataFor(int chapter) => _state?._chapters[chapter]?.data;
  void prepareAdjacent() => _state?._prepareAdjacent(enable: true);

  bool restoreParagraph(int chapter, int row, double fraction, double inset) {
    final state = _state;
    if (state == null) return false;
    final backwards = chapter < state._origin;
    final rows = backwards ? state._before : state._after;
    final at = rows.indexOf((chapter: chapter, row: row));
    if (at == null) return false;
    (backwards ? state._backAnchor : state._frontAnchor).restore(
      row: at,
      fraction: backwards ? 1 - fraction : fraction,
      inset: backwards
          ? state.widget.scroll.position.viewportDimension - inset
          : inset,
    );
    return true;
  }
}

class _StreamChapter<T> {
  _StreamChapter(this.index);
  final int index;
  final registry = ReaderParagraphRegistry();
  final heights = ReaderScrollRowHeights();
  T? data;
  Object? error;
  bool loading = false;
  bool known = false;
  bool foreground = false;
  int get rows => heights.rows;
  set rows(int value) => heights.rows = value;
  double? leading, retainedExtent;
  double heightOf(int row) => heights.heightOf(
    row,
    retainedExtent: data == null ? retainedExtent : null,
  );
  double get extent {
    if (data == null && retainedExtent != null) return retainedExtent!;
    return heights.extent;
  }
}

typedef _StreamRow = ReaderScrollRow;

/// Two native lazy lists grow away from a fixed origin. Appending the next or
/// previous chapter never replaces the current scroll activity or its pixels.
class ReaderScrollStream<T> extends StatefulWidget {
  const ReaderScrollStream({
    super.key,
    required this.controller,
    required this.scroll,
    required this.identity,
    required this.geometry,
    required this.chapter,
    required this.data,
    required this.chapterCount,
    required this.rowCount,
    required this.load,
    required this.itemBuilder,
    required this.pendingBuilder,
    required this.onChapterChanged,
    this.readingInset = 0,
    this.canAdopt,
    this.deferPreparation = false,
    this.continuous = true,
  });
  final ReaderScrollStreamController<T> controller;
  final ScrollController scroll;
  final Object identity, geometry;
  final int chapter, chapterCount;
  final T data;
  final int Function(T data) rowCount;
  final Future<T> Function(int chapter) load;

  /// Row -1 is the heading; rowCount is the chapter separator.
  final Widget Function(BuildContext context, int chapter, T data, int row)
  itemBuilder;
  final Widget Function(
    BuildContext context,
    int chapter,
    Object? error,
    VoidCallback retry,
  )
  pendingBuilder;
  final void Function(int chapter, T data) onChapterChanged;
  final double readingInset;
  final bool Function()? canAdopt;
  final bool deferPreparation;
  final bool continuous;
  @override
  State<ReaderScrollStream<T>> createState() => _ReaderScrollStreamState<T>();
}

class _ReaderScrollStreamState<T> extends State<ReaderScrollStream<T>> {
  final _chapters = <int, _StreamChapter<T>>{};
  final _mountedRows = <_StreamRow, _StreamExtentRender>{};
  final _frontAnchor = ReaderScrollAnchor(), _backAnchor = ReaderScrollAnchor();
  final _originKey = GlobalKey();
  var _before = ReaderScrollRowIndex(const []);
  var _after = ReaderScrollRowIndex(const []);
  bool _rowsDirty = true;
  int _origin = 0, _active = 0, _epoch = 0;
  bool _frameQueued = false;
  bool _preparationEnabled = false;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    widget.scroll.addListener(_queueMeasure);
    _reset();
  }

  void _reset({bool retainPreparation = false}) {
    _epoch++;
    if (!retainPreparation) _preparationEnabled = !widget.deferPreparation;
    _origin = _active = widget.chapter;
    _rowsDirty = true;
    _chapters.clear();
    _chapters[_active] = _StreamChapter<T>(_active)
      ..data = widget.data
      ..known = true
      ..rows = widget.rowCount(widget.data)
      ..leading = 0;
    // Reserve space without starting network work during route entry. In
    // particular, a saved line near a chapter's tail must be alignable before
    // the next chapter finishes loading; otherwise the viewport clamps it up.
    for (final index in [_active - 1, _active + 1]) {
      if (widget.continuous && index >= 0 && index < widget.chapterCount) {
        _chapters[index] = _StreamChapter<T>(index);
      }
    }
    _queueMeasure();
  }

  @override
  void didUpdateWidget(ReaderScrollStream<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.geometry != widget.geometry ||
        oldWidget.continuous != widget.continuous) {
      _reset(retainPreparation: oldWidget.identity == widget.identity);
    } else if (_chapters[widget.chapter] case final entry?) {
      final rows = widget.rowCount(widget.data);
      _rowsDirty |= !entry.known || entry.rows != rows;
      entry.data = widget.data;
      entry.known = true;
      entry.rows = rows;
    }
    _queueMeasure();
  }

  void _prepareAdjacent({
    bool enable = false,
    int? viewportNext,
    int? viewportPrevious,
  }) {
    if (enable) _preparationEnabled = true;
    if (!mounted ||
        !widget.continuous ||
        !_preparationEnabled ||
        ModalRoute.isCurrentOf(context) == false ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    // A short loaded neighbour can end inside the viewport while its heading
    // still cannot reach the reading line. Continue from that visible boundary
    // rather than waiting for reading adoption to advance _active. Each layout
    // adds at most one new chapter at either end; its real geometry determines
    // whether another is needed on a later frame.
    final visible = <int>{
      if (viewportNext != null && viewportNext > _active) viewportNext,
      if (viewportPrevious != null && viewportPrevious < _active - 1)
        viewportPrevious,
    };
    var added = false;
    for (final index in {...visible, _active + 1, _active - 1}) {
      if (index >= 0 && index < widget.chapterCount) {
        added |= !_chapters.containsKey(index);
        _load(index, foreground: visible.contains(index));
      }
    }
    if (added) setState(() {});
  }

  void _load(int index, {bool retry = false, bool foreground = false}) {
    final entry = _chapters.putIfAbsent(index, () {
      _rowsDirty = true;
      return _StreamChapter<T>(index);
    });
    if (foreground) {
      entry.foreground = true;
    }
    if (entry.data != null || entry.loading || entry.error != null && !retry) {
      return;
    }
    final epoch = _epoch;
    entry.loading = true;
    entry.error = null;
    entry.foreground = foreground;
    final request = widget.load(index);
    unawaited(
      request.then<void>(
        (data) {
          if (!mounted || epoch != _epoch) return;
          setState(() {
            entry.loading = false;
            if (entry.foreground || (index - _active).abs() <= 1) {
              final rows = widget.rowCount(data);
              _rowsDirty |= !entry.known || entry.rows != rows;
              entry.data = data;
              entry.known = true;
              entry.rows = rows;
            }
          });
          _queueMeasure();
        },
        onError: (Object error) {
          if (!mounted || epoch != _epoch) return;
          setState(() {
            entry.loading = false;
            entry.error = error;
          });
        },
      ),
    );
  }

  void _queueMeasure() {
    if (!mounted || _frameQueued) return;
    _frameQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameQueued = false;
      if (!mounted || !widget.scroll.hasClients) return;
      _measure();
    });
  }

  double _chapterOrigin(int chapter) {
    if (_chapters[chapter]?.leading case final leading?) return leading;
    if (chapter >= _origin) {
      return _chapters.values
          .where((entry) => entry.index >= _origin && entry.index < chapter)
          .fold(0, (sum, entry) => sum + entry.extent);
    }
    return -_chapters.values
        .where((entry) => entry.index >= chapter && entry.index < _origin)
        .fold(0.0, (sum, entry) => sum + entry.extent);
  }

  void _measure() {
    final position = widget.scroll.position;
    final reading = position.pixels + widget.readingInset;
    final viewportEnd = position.pixels + position.viewportDimension;
    _StreamRow? visible;
    var nextTop = double.infinity;
    int? viewportNext, viewportPrevious;
    final near = <int>{};
    for (final entry in _mountedRows.entries) {
      final render = entry.value;
      if (!render.attached || !render.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(render);
      if (viewport == null) continue;
      final top = viewport.getOffsetToReveal(render, 0).offset;
      final bottom = top + render.size.height;
      if (entry.key.row == -1) _chapters[entry.key.chapter]?.leading = top;
      final chapter = _chapters[entry.key.chapter];
      if (chapter != null && chapter.data != null) {
        if (entry.key.row == chapter.rows &&
            top <= viewportEnd &&
            bottom >= position.pixels) {
          final next = chapter.index + 1;
          if (viewportNext == null || next > viewportNext) viewportNext = next;
        }
        if (entry.key.row == -1 &&
            top >= position.pixels &&
            top <= viewportEnd) {
          final previous = chapter.index - 1;
          if (viewportPrevious == null || previous < viewportPrevious) {
            viewportPrevious = previous;
          }
        }
      }
      if (bottom >= position.pixels - position.viewportDimension * 2 &&
          top <= position.pixels + position.viewportDimension * 3) {
        near.add(entry.key.chapter);
      }
      if (top <= reading && reading < bottom) {
        visible = entry.key;
        nextTop = double.negativeInfinity;
      } else if (top >= reading && top < nextTop) {
        visible = entry.key;
        nextTop = top;
      }
    }
    final selected = visible == null ? null : _chapters[visible.chapter];
    final canAdopt = widget.canAdopt?.call() ?? true;
    if (canAdopt && selected != null && selected.data == null) {
      _load(selected.index, foreground: true);
    }
    if (canAdopt && selected?.data != null && selected!.index != _active) {
      _active = selected.index;
      widget.onChapterChanged(_active, selected.data as T);
    }
    var pruned = false;
    for (final entry in _chapters.values) {
      if ((entry.index - _active).abs() <= 1 ||
          near.contains(entry.index) ||
          entry.data == null) {
        continue;
      }
      entry.retainedExtent = entry.extent;
      entry.data = null;
      pruned = true;
    }
    _prepareAdjacent(
      viewportNext: canAdopt ? viewportNext : null,
      viewportPrevious: canAdopt ? viewportPrevious : null,
    );
    if (pruned) setState(() {});
  }

  void _ensureRowIndices() {
    if (!_rowsDirty) return;
    final ordered = _chapters.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    ReaderScrollChapterRows range(_StreamChapter<T> entry) =>
        (chapter: entry.index, rows: entry.known ? entry.rows : null);
    _before = ReaderScrollRowIndex(
      ordered
          .where((entry) => entry.index < _origin)
          .toList()
          .reversed
          .map(range),
      backwards: true,
    );
    _after = ReaderScrollRowIndex(
      ordered.where((entry) => entry.index >= _origin).map(range),
    );
    _rowsDirty = false;
  }

  Widget _list(ReaderScrollRowIndex rows, ReaderScrollAnchor anchor) {
    return ReaderScrollSliver(
      anchor: anchor,
      itemCount: rows.length,
      findChildIndexCallback: (key) =>
          key is ValueKey<_StreamRow> ? rows.indexOf(key.value) : null,
      itemBuilder: (context, index) {
        final row = rows[index], chapter = _chapters[row.chapter]!;
        final data = chapter.data;
        final Widget child;
        if (row.row != null && data == null) {
          // Keep the source row slots and their measured geometry when prose
          // leaves the window. Renumbering a lazy list's surviving rows moves
          // their layout offsets underneath an active drag.
          child = SizedBox(height: chapter.heightOf(row.row!));
        } else if (row.row == null) {
          child = ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  chapter.retainedExtent ?? MediaQuery.sizeOf(context).height,
            ),
            child: Align(
              alignment: row.chapter < _active
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: widget.pendingBuilder(
                context,
                chapter.index,
                chapter.error,
                () {
                  setState(
                    () => _load(chapter.index, retry: true, foreground: true),
                  );
                },
              ),
            ),
          );
        } else {
          child = widget.itemBuilder(
            context,
            chapter.index,
            data as T,
            row.row!,
          );
        }
        return _StreamExtent(
          key: ValueKey(row),
          mountedRows: _mountedRows,
          row: row,
          onHeight: (height) {
            if (row.row != null) {
              chapter.heights.record(row.row!, height);
            } else {
              chapter.retainedExtent = height;
            }
            _queueMeasure();
          },
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureRowIndices();
    return CustomScrollView(
      key: const ValueKey('reader-scroll'),
      controller: widget.scroll,
      center: _originKey,
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      cacheExtent: (MediaQuery.sizeOf(context).height * .75).clamp(
        250.0,
        900.0,
      ),
      slivers: [
        _list(_before, _backAnchor),
        SliverToBoxAdapter(key: _originKey, child: const SizedBox.shrink()),
        _list(_after, _frontAnchor),
      ],
    );
  }

  @override
  void dispose() {
    _epoch++;
    widget.scroll.removeListener(_queueMeasure);
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    super.dispose();
  }
}

class _StreamExtent extends SingleChildRenderObjectWidget {
  const _StreamExtent({
    super.key,
    required this.mountedRows,
    required this.row,
    required this.onHeight,
    required super.child,
  });
  final Map<_StreamRow, _StreamExtentRender> mountedRows;
  final _StreamRow row;
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _StreamExtentRender(mountedRows, row, onHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _StreamExtentRender renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _StreamExtentRender extends RenderProxyBox {
  _StreamExtentRender(this.rows, this.row, this.onHeight);
  final Map<_StreamRow, _StreamExtentRender> rows;
  final _StreamRow row;
  ValueChanged<double> onHeight;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    rows[row] = this;
  }

  @override
  void detach() {
    if (identical(rows[row], this)) rows.remove(row);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
