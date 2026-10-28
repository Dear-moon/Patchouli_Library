import 'reader_content.dart';

final _headingWhitespace = RegExp(r'[\s\u00a0\u3000\ufeff]+');
final _chapterNumber = RegExp(
  r'^(?:第\s*[〇零一二三四五六七八九十百千万两0-9０-９]+\s*[章节節卷部篇回]|(?:chapter|volume|part|book)\s+[0-9ivxlcdm]+)$',
  caseSensitive: false,
);

String _headingText(String value) =>
    value.replaceAll(_headingWhitespace, ' ').trim().toLowerCase();

/// The source already supplies this heading, as one block or a chapter number
/// followed by its title. Only the reader's extra display heading is omitted;
/// the original paragraphs and their UTF-16 coordinates are never rewritten.
bool readerHasLeadingChapterTitle(ReaderContent content, String title) {
  final wanted = _headingText(title);
  if (wanted.isEmpty) return false;
  String? number;
  for (final index in content.order) {
    final source = content.paragraphs[index];
    final text = _headingText(source);
    if (text.isEmpty) continue;
    if (readerIllustrationUrl(source) != null ||
        text == '[插图]' ||
        content.formats[index]?.rule == true) {
      return false;
    }
    if (number != null) return '$number $text' == wanted;
    if (text == wanted) return true;
    if (!_chapterNumber.hasMatch(text)) return false;
    number = text;
  }
  return false;
}
