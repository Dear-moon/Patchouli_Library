/// Source identity of one row in the continuous reader. A null row is an
/// unloaded chapter; -1 is its heading and rowCount is its separator.
typedef ReaderScrollRow = ({int chapter, int? row});

typedef ReaderScrollChapterRows = ({int chapter, int? rows});

/// A lazy index over chapter intervals, in display order.
///
/// Historical chapters keep their row slots after their prose is evicted. Store
/// only a chapter's prefix and count, rather than materializing every source row
/// and a second reverse-index entry for every paragraph.
class ReaderScrollRowIndex {
  ReaderScrollRowIndex(
    Iterable<ReaderScrollChapterRows> chapters, {
    this.backwards = false,
  }) {
    var start = 0;
    for (final chapter in chapters) {
      assert(chapter.rows == null || chapter.rows! >= 0);
      assert(!_byChapter.containsKey(chapter.chapter));
      final range = _ChapterRange(
        chapter: chapter.chapter,
        rows: chapter.rows,
        start: start,
      );
      _ranges.add(range);
      _byChapter[chapter.chapter] = range;
      start += range.length;
    }
    length = start;
  }

  final bool backwards;
  final _ranges = <_ChapterRange>[];
  final _byChapter = <int, _ChapterRange>{};
  late final int length;
  int get chapterCount => _ranges.length;

  ReaderScrollRow operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    var low = 0, high = _ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      final range = _ranges[middle];
      if (index < range.start) {
        high = middle;
      } else if (index >= range.start + range.length) {
        low = middle + 1;
      } else {
        final rows = range.rows;
        return (
          chapter: range.chapter,
          row: rows == null
              ? null
              : backwards
              ? rows - (index - range.start)
              : index - range.start - 1,
        );
      }
    }
    throw StateError('Missing chapter interval for row $index');
  }

  int? indexOf(ReaderScrollRow row) {
    final range = _byChapter[row.chapter];
    if (range == null) return null;
    final rows = range.rows, sourceRow = row.row;
    if (rows == null) return sourceRow == null ? range.start : null;
    if (sourceRow == null || sourceRow < -1 || sourceRow > rows) return null;
    return range.start + (backwards ? rows - sourceRow : sourceRow + 1);
  }
}

class _ChapterRange {
  const _ChapterRange({
    required this.chapter,
    required this.rows,
    required this.start,
  });
  final int chapter, start;
  final int? rows;
  int get length => rows == null ? 1 : rows! + 2;
}

/// Measured row geometry with a constant-time chapter extent estimate.
class ReaderScrollRowHeights {
  final _heights = <int, double>{};
  int _rows = 0, _bodyCount = 0;
  double _bodyHeight = 0;

  int get rows => _rows;
  set rows(int value) {
    if (value == _rows) return;
    _rows = value;
    _bodyCount = 0;
    _bodyHeight = 0;
    for (final entry in _heights.entries) {
      if (entry.key >= 0 && entry.key < _rows) {
        _bodyCount++;
        _bodyHeight += entry.value;
      }
    }
  }

  bool record(int row, double height) {
    final previous = _heights[row];
    if (previous == height) return false;
    _heights[row] = height;
    if (row >= 0 && row < _rows) {
      if (previous == null) _bodyCount++;
      _bodyHeight += height - (previous ?? 0);
    }
    return true;
  }

  double get _bodyEstimate => _bodyCount == 0 ? 100 : _bodyHeight / _bodyCount;
  double get extent =>
      (_heights[-1] ?? 80) +
      (_heights[_rows] ?? 24) +
      _bodyHeight +
      (_rows - _bodyCount) * _bodyEstimate;

  double heightOf(int row, {double? retainedExtent}) =>
      _heights[row] ??
      (row < 0
          ? 80
          : row == _rows
          ? 24
          : retainedExtent == null
          ? _bodyEstimate
          : (retainedExtent - (_heights[-1] ?? 80) - (_heights[_rows] ?? 24)) /
                _rows);
}
