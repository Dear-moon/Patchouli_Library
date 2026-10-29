import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

class ReviewTextPart {
  const ReviewTextPart(this.text, [this.link]);
  final String text;
  final Uri? link;
}

/// Forum HTML is data, never executable markup. Keep prose, paragraph breaks
/// and the actual destination of anchors, including anchors with a short label.
class ReviewDocument {
  ReviewDocument._(this.parts);
  final List<ReviewTextPart> parts;
  String get text => parts.map((p) => p.text).join();
  List<Uri> get links =>
      parts.map((p) => p.link).whereType<Uri>().toSet().toList();

  factory ReviewDocument.parse(String source) {
    final fragment = html.parseFragment(source.replaceAll('\r\n', '\n'));
    final markup = RegExp(
      r'(?:<|&(?:amp;){0,3}(?:lt|#0*60|#x0*3c);)\s*/?\s*(a|p|div|br|span|b|strong|i|em|u|s|ul|ol|li|code|pre|font|blockquote|h[1-6]|table|thead|tbody|tr|td|th|img|script|style|iframe|object|template)\b',
      caseSensitive: false,
    );
    final parts = <ReviewTextPart>[];
    void append(String text, [Uri? link]) {
      if (text.isEmpty) return;
      if (parts.isNotEmpty && parts.last.link == link) {
        final old = parts.removeLast();
        parts.add(ReviewTextPart(old.text + text, link));
      } else {
        parts.add(ReviewTextPart(text, link));
      }
    }

    void newline() {
      if (parts.isNotEmpty && !parts.last.text.endsWith('\n')) append('\n');
    }

    void visit(dom.Node node, [Uri? link, int depth = 0]) {
      if (node is dom.Text) {
        // Rich forum posts can mix real tags with escaped tags inside pre/code.
        // Decode each such island, not just an entirely escaped response.
        if (depth < 4 && markup.hasMatch(node.data)) {
          for (final child in html.parseFragment(node.data).nodes) {
            visit(child, link, depth + 1);
          }
          return;
        }
        append(node.data.replaceAll('\u00a0', ' '), link);
      } else if (node is dom.Element) {
        if (const {
          'script',
          'style',
          'iframe',
          'object',
          'head',
          'template',
        }.contains(node.localName)) {
          return;
        }
        if (node.localName == 'br') {
          append('\n');
          return;
        }
        final block = const {
          'p',
          'div',
          'li',
          'blockquote',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
          'pre',
          'tr',
        }.contains(node.localName);
        if (block) newline();
        final target = node.localName == 'a'
            ? reviewLinkUri(node.attributes['href'])
            : link;
        if (node.localName == 'img') {
          append(node.attributes['alt'] ?? '');
        } else {
          for (final child in node.nodes) {
            visit(child, target, depth);
          }
          if (node.localName == 'a' &&
              node.text.trim().isEmpty &&
              target != null) {
            append(target.toString(), target);
          }
        }
        if (block) newline();
      }
    }

    for (final node in fragment.nodes) {
      visit(node);
    }
    final linked = <ReviewTextPart>[];
    final urls = RegExp(
      r'''(?:https?://|www\.)[^\s<>"'，。；！？、：”’《》「」『』\u0000-\u001f]+''',
      caseSensitive: false,
    );
    for (final part in parts) {
      if (part.link != null) {
        linked.add(part);
        continue;
      }
      var offset = 0;
      for (final match in urls.allMatches(part.text)) {
        var raw = match.group(0)!;
        while (raw.isNotEmpty) {
          final end = raw.substring(raw.length - 1);
          final punctuation = '.,;!?，。；！？、：”’》」』'.contains(end);
          final closing = {
            ')': '(',
            ']': '[',
            '}': '{',
            '）': '（',
            '】': '【',
          }[end];
          if (!punctuation &&
              (closing == null ||
                  end.allMatches(raw).length <=
                      closing.allMatches(raw).length)) {
            break;
          }
          raw = raw.substring(0, raw.length - 1);
        }
        final uri = reviewLinkUri(raw);
        if (uri == null) continue;
        if (match.start > offset) {
          linked.add(ReviewTextPart(part.text.substring(offset, match.start)));
        }
        linked.add(ReviewTextPart(raw, uri));
        offset = match.start + raw.length;
      }
      if (offset < part.text.length) {
        linked.add(ReviewTextPart(part.text.substring(offset)));
      }
    }
    while (linked.isNotEmpty && linked.first.text.trimLeft().isEmpty) {
      linked.removeAt(0);
    }
    while (linked.isNotEmpty && linked.last.text.trimRight().isEmpty) {
      linked.removeLast();
    }
    if (linked.isNotEmpty) {
      linked[0] = ReviewTextPart(
        linked.first.text.trimLeft(),
        linked.first.link,
      );
      final last = linked.length - 1;
      linked[last] = ReviewTextPart(
        linked.last.text.trimRight(),
        linked.last.link,
      );
    }
    return ReviewDocument._(List.unmodifiable(linked));
  }
}

/// Untrusted comments cannot invoke intent:, javascript:, file: or arbitrary
/// application schemes. HTTPS App Links/Universal Links still open native apps.
Uri? reviewLinkUri(String? source) {
  if (source == null) return null;
  var value = source.trim();
  if (value.startsWith('//')) value = 'https:$value';
  if (value.toLowerCase().startsWith('www.')) value = 'https://$value';
  if (RegExp(r'[\s\u0000-\u001f\u007f]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
