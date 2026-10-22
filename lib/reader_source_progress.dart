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
}
