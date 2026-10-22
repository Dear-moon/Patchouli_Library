import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

typedef EpubNavigationLink = ({String key, String title, int depth});
typedef EpubNavigationTarget = ({String path, String fragment});

/// Authored navigation is independent of spine chapter boundaries. EPUB3 TOC
/// wins over NCX; page-list/landmarks never become a substitute table of contents.
List<EpubNavigationLink> readEpubNavigation({
  required String? navPath,
  required String? ncxPath,
  required String Function(String) read,
  required EpubNavigationTarget Function(String, String) resolve,
  required bool Function(String) contains,
  required List<String> warnings,
}) {
  final result = <EpubNavigationLink>[];
  void add(String base, String? href, String title, int depth) {
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (href == null || title.isEmpty || result.length >= 10000) return;
    try {
      final target = resolve(base, href);
      if (contains(target.path)) {
        if (title.length > 2048) {
          final last = title.codeUnitAt(2047);
          title = title.substring(
            0,
            last >= 0xD800 && last <= 0xDBFF ? 2047 : 2048,
          );
        }
        result.add((
          key: '${target.path}#${target.fragment}',
          title: title,
          depth: depth.clamp(0, 32),
        ));
      }
    } on FormatException {
      /* External links are not reading destinations. */
    }
  }

  if (navPath != null) {
    try {
      final doc = html.parse(read(navPath));
      final nav = doc
          .querySelectorAll('nav')
          .where(
            (n) =>
                (n.attributes['epub:type'] ?? '')
                    .split(RegExp(r'\s+'))
                    .contains('toc') ||
                n.attributes['role'] == 'doc-toc',
          )
          .firstOrNull;
      void walk(html.Element root, int depth) {
        for (final li in root.children.where((e) => e.localName == 'li')) {
          final a = li.children.where((e) => e.localName == 'a').firstOrNull;
          add(navPath, a?.attributes['href'], a?.text ?? '', depth);
          final ol = li.children.where((e) => e.localName == 'ol').firstOrNull;
          if (ol != null && depth < 32) walk(ol, depth + 1);
        }
      }

      final ol = nav?.querySelector('ol');
      if (ol != null) walk(ol, 0);
    } on FormatException {
      warnings.add('原书 NAV 无法读取，已尝试 NCX 目录。');
    }
  }
  if (result.isNotEmpty || ncxPath == null) return result;
  try {
    final doc = XmlDocument.parse(read(ncxPath));
    void walk(XmlElement root, int depth) {
      for (final point in root.childElements.where(
        (e) => e.name.local == 'navPoint',
      )) {
        final label =
            point.childElements
                .where((e) => e.name.local == 'navLabel')
                .firstOrNull
                ?.innerText ??
            '';
        final href = point.childElements
            .where((e) => e.name.local == 'content')
            .firstOrNull
            ?.getAttribute('src');
        add(ncxPath, href, label, depth);
        if (depth < 32) walk(point, depth + 1);
      }
    }

    for (final map in doc.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'navMap',
    )) {
      walk(map, 0);
    }
  } on FormatException {
    warnings.add('原书 NCX 无法读取，已保留阅读顺序和正文标题。');
  }
  return result;
}
