import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const epubMarkupVersion = 1;

/// EPUB XHTML permits empty script/style elements. HTML5's raw-text tokenizer
/// ignores their closing slash and otherwise consumes the following book body.
/// Normalize only these empty elements, retaining the existing lenient HTML DOM.
Document parseLocalEpubMarkup(
  String source, {
  bool normalizeEmptyRawText = true,
}) => html.parse(normalizeEmptyRawText ? _closeEmptyRawText(source) : source);

String _closeEmptyRawText(String source) {
  final lower = source.toLowerCase();
  final out = StringBuffer();
  var cursor = 0, copied = 0;
  while (cursor < source.length) {
    final start = source.indexOf('<', cursor);
    if (start < 0) break;
    if (source.startsWith('<!--', start)) {
      final end = source.indexOf('-->', start + 4);
      cursor = end < 0 ? source.length : end + 3;
      continue;
    }
    if (source.startsWith('<![CDATA[', start)) {
      final end = source.indexOf(']]>', start + 9);
      cursor = end < 0 ? source.length : end + 3;
      continue;
    }
    var end = start + 1, quote = 0;
    for (; end < source.length; end++) {
      final c = source.codeUnitAt(end);
      if (quote != 0) {
        if (c == quote) quote = 0;
      } else if (c == 34 || c == 39) {
        quote = c;
      } else if (c == 62) {
        break;
      }
    }
    if (end == source.length) break;
    cursor = end + 1;
    var nameEnd = start + 1;
    while (nameEnd < end &&
        ((lower.codeUnitAt(nameEnd) >= 97 &&
                lower.codeUnitAt(nameEnd) <= 122) ||
            (lower.codeUnitAt(nameEnd) >= 48 &&
                lower.codeUnitAt(nameEnd) <= 57))) {
      nameEnd++;
    }
    final name = lower.substring(start + 1, nameEnd);
    if (!const {
      'script',
      'style',
      'textarea',
      'title',
      'xmp',
      'iframe',
      'noembed',
      'noframes',
      'plaintext',
    }.contains(name)) {
      continue;
    }
    // Namespaced/longer names are not HTML raw-text elements.
    if (nameEnd < end && !' \t\r\n\f/'.contains(source[nameEnd])) continue;
    if ((name == 'script' || name == 'style') &&
        source.codeUnitAt(end - 1) == 47) {
      out.write(source.substring(copied, end + 1));
      out.write('</$name>');
      copied = end + 1;
    } else {
      // Do not reinterpret text or '<script/>' strings inside real scripts.
      final close = RegExp(
        '</$name(?=[\\s/>])',
      ).firstMatch(lower.substring(cursor));
      cursor = close == null ? source.length : cursor + close.start;
    }
  }
  if (copied == 0) return source;
  out.write(source.substring(copied));
  return out.toString();
}
