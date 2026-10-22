import 'package:html/dom.dart';
import 'reader_rich_content.dart';
import 'reader_languages.dart';

String epubSemantic(Element node) =>
    '${node.attributes['epub:type'] ?? ''} ${node.attributes['role'] ?? ''}';
bool epubNoteElement(Element node) => epubSemantic(node)
    .split(RegExp(r'\s+'))
    .any(
      {
        'footnote',
        'endnote',
        'rearnote',
        'doc-footnote',
        'doc-endnote',
      }.contains,
    );

class EpubRichText {
  EpubRichText(this.styles, this.baseWriting, {this.baseLanguage = ''});
  final Map<Element, Map<String, String>> styles;
  final String baseWriting;
  final String baseLanguage;
  final _text = StringBuffer();
  final _ruby = <ReaderRuby>[];
  final _refs = <ReaderNoteReference>[];
  final _emphasis = <ReaderEmphasis>[];
  bool _space = false;
  String _align = '', _writing = '';
  String _language = '';
  double _opacity = 1;
  bool get isNotEmpty => _text.isNotEmpty;
  int get length => _text.length;
  String inherited(Element? node, String name) {
    for (var at = node; at != null; at = at.parent) {
      final value =
          styles[at]?[name] ??
          (name == 'text-align' ? at.attributes['align'] : null);
      if (value != null && value.isNotEmpty && value != 'inherit') return value;
    }
    return '';
  }

  void begin(Element node) {
    _language = readerLanguageCode(baseLanguage);
    _opacity = 1;
    var languageFound = false;
    for (Element? at = node; at != null; at = at.parent) {
      final language = at.attributes['lang'] ?? at.attributes['xml:lang'];
      if (!languageFound && language != null) {
        _language = readerLanguageCode(language);
        languageFound = true;
      }
      final raw = styles[at]?['opacity'] ?? '';
      final amount = raw.endsWith('%')
          ? (double.tryParse(raw.substring(0, raw.length - 1)) ?? 100) / 100
          : double.tryParse(raw);
      if (amount != null && amount.isFinite) _opacity *= amount.clamp(0.0, 1.0);
    }
    _align = inherited(node, 'text-align');
    final writing = inherited(node, 'writing-mode').isNotEmpty
        ? inherited(node, 'writing-mode')
        : inherited(node, '-epub-writing-mode');
    _writing = writing.isEmpty || writing == baseWriting
        ? ''
        : writing.startsWith('vertical')
        ? 'vertical'
        : 'horizontal';
  }

  int _mask(Element? node) {
    var mask = 0;
    final weight = inherited(node, 'font-weight');
    if (weight == 'bold' ||
        weight == 'bolder' ||
        (int.tryParse(weight) ?? 0) >= 600) {
      mask |= 1;
    }
    if (inherited(node, 'font-style').contains('italic') ||
        inherited(node, 'font-style') == 'oblique') {
      mask |= 2;
    }
    if (inherited(node, 'text-decoration').contains('underline')) mask |= 4;
    for (var at = node; at != null; at = at.parent) {
      if ({'b', 'strong'}.contains(at.localName)) mask |= 1;
      if ({'i', 'em'}.contains(at.localName)) mask |= 2;
      if (at.localName == 'u') mask |= 4;
    }
    return mask;
  }

  void _mark(int start, int end, int mask) {
    if (end <= start || mask == 0) return;
    if (_emphasis.isNotEmpty &&
        _emphasis.last.end == start &&
        _emphasis.last.mask == mask) {
      final old = _emphasis.removeLast();
      _emphasis.add(ReaderEmphasis(old.start, end, mask));
    } else {
      _emphasis.add(ReaderEmphasis(start, end, mask));
    }
  }

  void appendStyled(String value, Element? node) {
    final range = append(value);
    _mark(range.start, range.end, _mask(node));
  }

  ({int start, int end}) append(String value) {
    var start = -1;
    for (final token in RegExp(r'\s+|\S+').allMatches(value)) {
      final text = token.group(0)!;
      if (text.trim().isEmpty) {
        _space = _text.isNotEmpty;
        continue;
      }
      if (_space && _text.isNotEmpty) _text.write(' ');
      _space = false;
      if (start < 0) start = _text.length;
      _text.write(text);
    }
    return (start: start < 0 ? _text.length : start, end: _text.length);
  }

  void ruby(Element node) {
    final start = _text.length;
    String baseText(Element element) {
      final copy = element.clone(true);
      for (final child in copy.querySelectorAll('rt, rp, rtc')) {
        child.remove();
      }
      return copy.text;
    }

    void annotate(({int start, int end}) range, String reading) {
      if (range.end > range.start && reading.trim().isNotEmpty) {
        _ruby.add(ReaderRuby(range.start, range.end, reading.trim()));
      }
    }

    final bases = node.children.where((e) => e.localName == 'rb').toList();
    final readings = node.children.where((e) => e.localName == 'rt').toList();
    if (bases.length > 1 && bases.length == readings.length) {
      // Grouped rb/rt preserves unequal readings such as 御/お + 主人/しゅじん.
      var index = 0;
      for (final child in node.nodes) {
        if (child is Element && child.localName == 'rb') {
          annotate(append(baseText(child)), readings[index++].text);
        } else if (child is Text) {
          append(child.text);
        }
      }
    } else if (readings.isNotEmpty) {
      ({int start, int end})? base;
      for (final child in node.nodes) {
        if (child is Element && child.localName == 'rt') {
          if (base != null) annotate(base, child.text);
          base = null;
        } else if (child is Text ||
            child is Element && !{'rp', 'rtc'}.contains(child.localName)) {
          final range = append(
            child is Text ? child.text : baseText(child as Element),
          );
          if (range.end > range.start) {
            base = (start: base?.start ?? range.start, end: range.end);
          }
        }
      }
    } else {
      // Use the first annotation layer; phonetics never enter copied/spoken prose.
      final layer = node.querySelector('rtc');
      annotate(append(baseText(node)), layer?.text ?? '');
    }
    _mark(start, _text.length, _mask(node));
  }

  void reference(Element node, String id) {
    final text = node.text.trim();
    final range = append(text.isEmpty ? '〔注〕' : text);
    _mark(range.start, range.end, _mask(node));
    if (range.end > range.start) {
      _refs.add(ReaderNoteReference(range.start, range.end, id));
    }
  }

  void markReference(int start, String id) {
    if (_text.length > start) {
      _refs.add(ReaderNoteReference(start, _text.length, id));
    }
  }

  ({String text, ReaderRichParagraph format})? take() {
    if (_text.isEmpty) return null;
    final result = (
      text: _text.toString(),
      format: ReaderRichParagraph(
        alignment: _align,
        writing: _writing,
        language: _language,
        opacity: _opacity,
        ruby: List.unmodifiable(_ruby),
        references: List.unmodifiable(_refs),
        emphasis: List.unmodifiable(_emphasis),
      ),
    );
    _text.clear();
    _ruby.clear();
    _refs.clear();
    _emphasis.clear();
    _space = false;
    return result;
  }
}
