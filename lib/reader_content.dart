import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'local_book_media.dart';
import 'local_image_layout.dart';
import 'app_language.dart';
import 'sources/source_image_locator.dart';
import 'reader_rich_content.dart';
import 'reader_coordinate_map.dart';
import 'reader_languages.dart';
import 'reader_source_fonts.dart';

final _markdownWrappedImage = RegExp(
  r'''!\[[^\]\n]{0,128}\]\(\s*(<!--image-->[^\n]*?<!--image-->)(?:\s*(?:"[^"\n]{0,256}"|'[^'\n]{0,256}')?\s*\))?''',
);
final _legacyMarkdownImageQuery = RegExp(
  r'''!\[[^\]\n]{0,128}\]\(\s*(<!--image-->([^\n]*?)<!--image-->)\s*(\?[^\s<>"']{1,4096})\)(?=[ \t]*(?:\r?\n|$))''',
);

String? _restoreImageQuery(String locator, String query) {
  if (readerIllustrationUrl('<!--image-->$locator<!--image-->') == null) {
    return null;
  }
  final outer = Uri.tryParse(locator)!;
  final remote = outer.scheme == 'source-image'
      ? outer.queryParameters['url']!
      : locator;
  final uri = Uri.tryParse(remote);
  // Only repair the unambiguous old extension-only conversion. Do not rewrite
  // request-option locators, local files, or an already complete image URL.
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      remote.contains(RegExp(r'\s*,\s*\{'))) {
    return null;
  }
  final restored = '$remote$query';
  if (!validSourceImageLocator(restored)) return null;
  return outer.scheme == 'source-image'
      ? outer
            .replace(
              queryParameters: {...outer.queryParameters, 'url': restored},
            )
            .toString()
      : restored;
}

String _imageReplacementKeepingLines(String raw, String image, String result) {
  final start = raw.indexOf(image);
  String newlines(String value) => value.replaceAll(RegExp(r'[^\n]'), '');
  return '${newlines(raw.substring(0, start))}$result${newlines(raw.substring(start + image.length))}';
}

/// Repair old cached Markdown wrappers at the display boundary. Retain every
/// newline so paragraph IDs and saved positions continue to name the same prose.
String normalizeReaderImageBoundaries(String source) {
  if (!source.contains('![') || !source.contains('<!--image-->')) return source;
  final repaired = source.replaceAllMapped(_legacyMarkdownImageQuery, (match) {
    final locator = _restoreImageQuery(match[2]!, match[3]!);
    return locator == null
        ? match[0]!
        : _imageReplacementKeepingLines(
            match[0]!,
            match[1]!,
            '<!--image-->$locator<!--image-->',
          );
  });
  return repaired.replaceAllMapped(_markdownWrappedImage, (match) {
    final image = match[1]!;
    return _imageReplacementKeepingLines(match[0]!, image, image);
  });
}

ReaderRichBody _splitParagraphs(String source) =>
    ReaderRichBody.decode(normalizeReaderImageBoundaries(source));

class ReaderContent {
  const ReaderContent(
    this.paragraphs, {
    this.readingOrder,
    this.inlineOwners = const {},
    this.placementIds = const {},
    this.formats = const {},
    this.notes = const {},
    this.revision = '',
    this.coordinateMap,
    this.languageFilter = '',
  });
  final List<String> paragraphs;
  final List<int>? readingOrder;
  final Map<int, int> inlineOwners;
  final Map<int, String> placementIds;
  final Map<int, ReaderRichParagraph> formats;
  final Map<String, String> notes;
  final String revision;
  final ReaderCoordinateMap? coordinateMap;
  final String languageFilter;
  String? get sourceFontFamily => formats.values
      .map((format) => format.fontFamily)
      .whereType<String>()
      .firstOrNull;
  bool get hasSourceFont => sourceFontFamily != null;
  Set<String> get languages => {
    for (final f in formats.values)
      if (f.language.isNotEmpty) f.language,
  };
  Iterable<int> get order =>
      readingOrder ?? Iterable.generate(paragraphs.length);

  /// Display-only exclusion. Keep the source paragraphs and their IDs so
  /// bookmarks, speech and the volume gallery still refer to the original text.
  ReaderContent withoutUnavailableIllustrations(Set<String> unavailable) {
    if (unavailable.isEmpty) return this;
    final before = order.toList();
    final visible = before.where((index) {
      final url = readerIllustrationUrl(paragraphs[index]);
      return url == null ||
          url.startsWith('wenku-local:') ||
          !unavailable.contains(url);
    }).toList();
    if (visible.length == before.length) return this;
    return ReaderContent(
      paragraphs,
      readingOrder: List.unmodifiable(visible),
      inlineOwners: inlineOwners,
      placementIds: placementIds,
      formats: formats,
      notes: notes,
      revision: revision,
      coordinateMap: coordinateMap,
      languageFilter: languageFilter,
    );
  }

  static final _imageLists = Expando<List<String>>('chapter-illustrations');
  static final _publisherSpacing = Expando<bool>('publisher-spacing');
  String layoutKey(String base) {
    final layout =
        (_publisherSpacing[this] ??= formats.values.any(
          (format) => !format.spacing.empty,
        ))
        ? 'publisher-spacing-v1|$base'
        : base;
    final family = sourceFontFamily;
    final typography = family == null ? layout : '$layout|source-font=$family';
    return languageFilter.isEmpty
        ? typography
        : '$typography|languages=$languageFilter';
  }

  ReaderContent withHiddenLanguages(
    Set<String> hidden, {
    String? onlyLanguage,
  }) {
    final excluded = onlyLanguage == null
        ? languages.intersection(hidden)
        : languages.difference({onlyLanguage});
    if (excluded.isEmpty) return this;
    final names = excluded.toList()..sort();
    return ReaderContent(
      paragraphs,
      readingOrder: List.unmodifiable(
        order.where((index) => !excluded.contains(formats[index]?.language)),
      ),
      inlineOwners: inlineOwners,
      placementIds: placementIds,
      formats: formats,
      notes: notes,
      revision: revision,
      coordinateMap: coordinateMap,
      languageFilter: names.join(','),
    );
  }

  List<String> get illustrations => _imageLists[this] ??= List.unmodifiable([
    for (final index in order) ?readerIllustrationUrl(paragraphs[index]),
  ]);
  ReaderContent localized(Locale locale) {
    if (hasSourceFont) return this;
    if (chineseLocale(locale).countryCode == 'CN') return this;
    return ReaderContent(
      List.unmodifiable([
        for (final (index, text) in paragraphs.indexed)
          readerIllustrationUrl(text) != null ||
                  text.trim() == '[插图]' ||
                  formats[index]?.language.isNotEmpty == true &&
                      formats[index]!.language != 'zh'
              ? text
              : ChineseText.convert(text, locale, reader: true),
      ]),
      readingOrder: readingOrder,
      inlineOwners: inlineOwners,
      placementIds: placementIds,
      formats: formats,
      notes: notes,
      revision: revision,
      coordinateMap: coordinateMap,
      languageFilter: languageFilter,
    );
  }

  static Future<ReaderContent> parse(String source) async {
    if (source.trim().isEmpty) throw const FormatException('章节正文为空');
    final rich = source.length > 64 * 1024
        ? await compute(_splitParagraphs, source)
        : _splitParagraphs(source);
    final family = rich.sourceFont == null
        ? null
        : await ReaderSourceFonts.load(rich.sourceFont!);
    return ReaderContent(
      List.unmodifiable(rich.paragraphs),
      formats: family == null
          ? rich.formats
          : {
              for (var index = 0; index < rich.paragraphs.length; index++)
                index: (rich.formats[index] ?? const ReaderRichParagraph())
                    .withFontFamily(family),
            },
      notes: rich.notes,
      revision: rich.revision,
      coordinateMap: rich.coordinateMap,
    );
  }

  Future<ReaderContent> localizedAsync(Locale locale) async {
    if (hasSourceFont) return this;
    if (chineseLocale(locale).countryCode == 'CN') return this;
    // A Chinese UI preference must not rewrite Japanese kanji in bilingual books.
    final eligible = [
      for (var i = 0; i < paragraphs.length; i++)
        if (formats[i]?.language.isNotEmpty != true ||
            readerLanguageCode(formats[i]!.language) == 'zh')
          i,
    ];
    final translated = await ChineseText.readerParagraphs([
      for (final i in eligible) paragraphs[i],
    ], locale);
    final localized = List<String>.of(paragraphs);
    for (var i = 0; i < eligible.length; i++) {
      localized[eligible[i]] = translated[i];
    }
    return ReaderContent(
      List.unmodifiable(localized),
      readingOrder: readingOrder,
      inlineOwners: inlineOwners,
      placementIds: placementIds,
      formats: formats,
      notes: notes,
      revision: revision,
      coordinateMap: coordinateMap,
      languageFilter: languageFilter,
    );
  }
}

/// Standalone paired markers in persisted reader content. Images keep their
/// paragraph index, so bookmarks and lazy restoration share one coordinate map.
String? readerIllustrationUrl(String paragraph) {
  const marker = '<!--image-->';
  final text = paragraph.trim();
  if (!text.startsWith(marker) || text.length <= marker.length * 2) {
    return null;
  }
  final end = text.indexOf(marker, marker.length);
  if (end < 0) return null;
  final tail = text.substring(end + marker.length).trim();
  final raw = text.substring(marker.length, end).trim();
  final uri = Uri.tryParse(raw);
  if (uri?.scheme == 'source-image') {
    final remote = uri!.queryParameters['url'] ?? '';
    return (tail.isEmpty ||
                remote.startsWith('source-epub:') &&
                    LocalImageLayout.parseSuffix(tail) != null) &&
            uri.userInfo.isEmpty &&
            !uri.hasPort &&
            (int.tryParse(uri.host) ?? 0) > 0 &&
            validSourceImageLocator(remote)
        ? uri.toString()
        : null;
  }
  if (uri != null && LocalBookMedia.valid(uri)) {
    return LocalImageLayout.parseSuffix(tail) == null ? null : uri.toString();
  }
  if (tail.isNotEmpty) return null;
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && ![80, 443].contains(uri.port)) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.replace(scheme: 'https', port: 443).toString();
}

final _missingIllustration = RegExp(r'(^|\n)[ \t]*\[插图\][ \t]*(\n|$)');

/// Old bodies lost the URL at these stand-alone image paragraphs. Ordinary
/// prose containing the same words does not trigger a network refresh.
bool readerHasMissingIllustrations(String body) =>
    body.contains('[插图]') && _missingIllustration.hasMatch(body);

typedef ParagraphPosition = ({int index, double fraction});
typedef ParagraphTarget = ({double offset, bool exact});
typedef _MeasuredParagraph = ({int index, double top, double height});

/// Only laid-out paragraphs are registered: no global key or upfront text
/// layout per paragraph, and no work on each scroll tick. Capture occurs when
/// saving or explicitly changing the reading layout.
class ReaderParagraphRegistry {
  final Map<int, _ReaderParagraphRender> _rows = {};
  @visibleForTesting
  int debugParagraphMounts = 0;

  List<_MeasuredParagraph> _measure() {
    final result = <_MeasuredParagraph>[];
    for (final entry in _rows.entries) {
      final row = entry.value;
      if (!row.attached || !row.hasSize || row.size.height <= 0) continue;
      final viewport = RenderAbstractViewport.maybeOf(row);
      if (viewport == null) continue;
      final top = viewport.getOffsetToReveal(row, 0).offset;
      if (top.isFinite) {
        result.add((index: entry.key, top: top, height: row.size.height));
      }
    }
    result.sort((a, b) => a.index.compareTo(b.index));
    return result;
  }

  ParagraphPosition? capture(double readingOffset, {bool clampToLast = false}) {
    final rows = _measure();
    for (final row in rows) {
      if (readingOffset >= row.top && readingOffset < row.top + row.height) {
        return (
          index: row.index,
          fraction: (readingOffset - row.top) / row.height,
        );
      }
      if (readingOffset < row.top) return (index: row.index, fraction: 0);
    }
    return clampToLast && rows.isNotEmpty
        ? (index: rows.last.index, fraction: 1)
        : null;
  }

  int? captureTextOffset(int index, double readingOffset) {
    final row = _rows[index];
    if (row == null || !row.attached || !row.hasSize) return null;
    RenderParagraph? paragraph;
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        paragraph ??= node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(row);
    final text = paragraph;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (text == null || viewport == null) return null;
    final top = viewport.getOffsetToReveal(row, 0).offset;
    final textOrigin = text.localToGlobal(Offset.zero, ancestor: row);
    final position = text.getPositionForOffset(
      Offset(
        0,
        (readingOffset - top - textOrigin.dy).clamp(0.0, text.size.height),
      ),
    );
    return (position.offset - row.textOffset).clamp(
      0,
      text.text.toPlainText().length - row.textOffset,
    );
  }

  /// A visible anchor can be restored exactly. Otherwise use the nearest lazy
  /// row to bring it into view, then refine on the next layout; bounded by the
  /// caller so damaged/changed chapter content cannot cause a frame loop.
  ParagraphTarget? target(
    ParagraphPosition anchor,
    double inset, {
    double? viewportBottom,
    double trailingSpace = 0,
  }) {
    final rows = _measure();
    if (rows.isEmpty) return null;
    final landing = viewportBottom == null
        ? inset
        : (inset + viewportBottom) / 2;
    double fraction(double height) {
      final contentHeight = (height - trailingSpace).clamp(0.0, height);
      return viewportBottom != null && contentHeight <= viewportBottom - inset
          ? contentHeight / height / 2
          : anchor.fraction.clamp(0.0, 1.0);
    }

    var nearest = rows.first;
    var totalHeight = 0.0;
    for (final row in rows) {
      totalHeight += row.height;
      if (row.index == anchor.index) {
        return (
          // Short bookmarked paragraphs sit in the middle of the unobscured
          // article. For a screen-long paragraph keep its bookmarked portion
          // visible instead of jumping to a different part of the paragraph.
          offset: row.top + fraction(row.height) * row.height - landing,
          exact: true,
        );
      }
      if ((row.index - anchor.index).abs() <
          (nearest.index - anchor.index).abs()) {
        nearest = row;
      }
    }
    final estimate = totalHeight / rows.length;
    return (
      offset:
          nearest.top +
          (anchor.index - nearest.index + fraction(estimate)) * estimate -
          landing,
      exact: false,
    );
  }

  /// Short paragraphs stay centered as a whole. For a screen-long paragraph,
  /// follow the spoken fragment's glyph range rather than its unchanged index.
  ParagraphTarget? speechTarget(
    int index,
    int start,
    int end,
    double inset, {
    required double viewportBottom,
    double trailingSpace = 0,
  }) {
    final anchor = target(
      (index: index, fraction: 0),
      inset,
      viewportBottom: viewportBottom,
      trailingSpace: trailingSpace,
    );
    final row = _rows[index];
    if (anchor == null ||
        !anchor.exact ||
        row == null ||
        row.size.height - trailingSpace <= viewportBottom - inset) {
      return anchor;
    }
    final offset = matchOffset(
      index,
      start,
      end,
      inset,
      viewportBottom: viewportBottom,
    );
    return offset == null ? anchor : (offset: offset, exact: true);
  }

  /// Use laid-out glyph boxes to land on the occurrence, not merely the start
  /// of a long paragraph. No upfront layout of offscreen text is required.
  double? matchOffset(
    int index,
    int start,
    int end,
    double inset, {
    double? viewportBottom,
  }) {
    final row = _rows[index];
    if (row == null || !row.attached || !row.hasSize) return null;
    RenderParagraph? text;
    void visit(RenderObject node) {
      if (text != null) return;
      if (node is RenderParagraph) {
        text = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(row);
    final paragraph = text;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (paragraph == null || viewport == null) return null;
    final length = paragraph.text.toPlainText().length;
    start += row.textOffset;
    end += row.textOffset;
    if (start < 0 || start >= length || end <= start) return null;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end.clamp(start, length)),
    );
    if (boxes.isEmpty) return null;
    final local = paragraph.localToGlobal(
      Offset(0, boxes.first.top),
      ancestor: row,
    );
    final top = viewport.getOffsetToReveal(row, 0).offset + local.dy;
    if (viewportBottom == null) return top - inset;
    var bottom = boxes.first.bottom;
    for (final box in boxes.skip(1)) {
      if (box.bottom > bottom) bottom = box.bottom;
    }
    final height = bottom - boxes.first.top;
    return height <= viewportBottom - inset
        ? top + height / 2 - (inset + viewportBottom) / 2
        : top - inset;
  }
}

class ReaderParagraph extends SingleChildRenderObjectWidget {
  const ReaderParagraph({
    super.key,
    required this.registry,
    required this.index,
    this.textOffset = 0,
    required super.child,
  });
  final ReaderParagraphRegistry registry;
  final int index;
  final int textOffset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ReaderParagraphRender(registry, index, textOffset);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _ReaderParagraphRender).update(
      registry,
      index,
      textOffset,
    );
  }
}

class _ReaderParagraphRender extends RenderProxyBox {
  _ReaderParagraphRender(this.registry, this.index, this.textOffset);
  ReaderParagraphRegistry registry;
  int index;
  int textOffset;

  void _remove() {
    if (identical(registry._rows[index], this)) registry._rows.remove(index);
  }

  void update(ReaderParagraphRegistry value, int number, int prefix) {
    textOffset = prefix;
    if (registry == value && index == number) return;
    _remove();
    registry = value;
    index = number;
    if (attached) registry._rows[index] = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    registry._rows[index] = this;
    assert(() {
      registry.debugParagraphMounts++;
      return true;
    }());
  }

  @override
  void detach() {
    _remove();
    super.detach();
  }
}
