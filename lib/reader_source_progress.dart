import 'reader_content.dart';

/// UI progress follows source text, not a changing lazy-list extent estimate.
/// Pixel offsets in saved reading positions keep their existing meaning.
class ReaderSourceProgress {
  ReaderSourceProgress(ReaderContent content) {
    for (final index in content.order) {
      final text = content.paragraphs[index];
      final weight = readerIllustrationUrl(text) != null
          ? 1
          : text.length.clamp(1, 0x7fffffff);
      _ends.add(_ends.last + weight);
    }
  }
  final _ends = <int>[0];
  static final _indexes = Expando<ReaderSourceProgress>();
  static ReaderSourceProgress of(ReaderContent content) =>
      _indexes[content] ??= ReaderSourceProgress(content);

  double fraction(({int row, double fraction}) anchor) {
    if (_ends.length == 1) return 0;
    final row = anchor.row.clamp(0, _ends.length - 2);
    final within = anchor.fraction.clamp(0.0, 1.0);
    return (_ends[row] + (_ends[row + 1] - _ends[row]) * within) / _ends.last;
  }

  /// Inverts source progress into a display-order row, not a paragraph index.
  /// Shared row boundaries use the next row's start; the final endpoint remains
  /// the last row's end. No lazy viewport measurement participates in this map.
  ({int row, double fraction})? anchor(double value) {
    final rows = _ends.length - 1;
    if (rows == 0) return null;
    final bounded = value.clamp(0.0, 1.0).toDouble();
    if (bounded == 0) return (row: 0, fraction: 0.0);
    if (bounded == 1) return (row: rows - 1, fraction: 1.0);

    // Compare the same normalized boundaries used by fraction(). Multiplying
    // first can put an exact boundary such as .29 just below its source weight.
    var lower = 0, upper = rows;
    final total = _ends.last;
    while (lower + 1 < upper) {
      final middle = (lower + upper) >> 1;
      if (bounded < _ends[middle] / total) {
        upper = middle;
      } else {
        lower = middle;
      }
    }
    final start = _ends[lower] / total;
    final end = _ends[lower + 1] / total;
    return (
      row: lower,
      fraction: ((bounded - start) / (end - start)).clamp(0.0, 1.0).toDouble(),
    );
  }
}
