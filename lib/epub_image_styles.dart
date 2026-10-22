import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as ast;
import 'package:html/dom.dart';
import 'local_image_layout.dart';
import 'reader_block_spacing.dart';

/// Only image dimensions are carried into the text reader, not a second HTML
/// renderer. csslib and html handle declarations and matching selectors.
Map<Element, LocalImageLayout> epubImageStyles(
  Document document,
  String? Function(String) readStylesheet,
) {
  final properties = epubStyleProperties(document, readStylesheet);
  return {
    for (final image in document.querySelectorAll('img, image'))
      image: LocalImageLayout.fromProperties(properties[image] ?? {}),
  };
}

Map<Element, Map<String, String>> epubStyleProperties(
  Document document,
  String? Function(String) readStylesheet,
) {
  const supportedProperties = {
    'width',
    'height',
    'max-width',
    'max-height',
    'text-align',
    'writing-mode',
    '-epub-writing-mode',
    'font-weight',
    'font-style',
    'text-decoration',
    'opacity',
    'display',
    'break-before',
    'break-after',
    'page-break-before',
    'page-break-after',
    'margin',
    'margin-top',
    'margin-right',
    'margin-bottom',
    'margin-left',
    'margin-block',
    'margin-block-start',
    'margin-block-end',
    'padding',
    'padding-top',
    'padding-right',
    'padding-bottom',
    'padding-left',
    'padding-block',
    'padding-block-start',
    'padding-block-end',
  };
  final images = document.querySelectorAll('*');
  final values =
      <Element, Map<String, ({String value, bool important, int specificity})>>{
        for (final image in images)
          image: {
            for (final name in ['width', 'height'])
              if (image.attributes[name] case final value?)
                name: (value: value, important: false, specificity: -1),
          },
      };
  void apply(Element image, ast.DeclarationGroup group, int specificity) {
    for (final declaration in group.declarations.whereType<ast.Declaration>()) {
      final name = declaration.property.toLowerCase();
      if (!supportedProperties.contains(name)) {
        continue;
      }
      final expression = declaration.expression;
      if (expression == null) continue;
      final printer = ast.CssPrinter();
      expression.visit(printer);
      final value = printer.toString().trim().toLowerCase();
      if ((['width', 'height', 'max-width', 'max-height'].contains(name) &&
          value != 'auto' &&
          value != 'none' &&
          LocalImageLayout.length(value) == null)) {
        continue;
      }
      final expanded = <String, String>{};
      if (name == 'margin' || name == 'padding') {
        final parts = value.split(RegExp(r'\s+'));
        if (parts.isEmpty ||
            parts.length > 4 ||
            parts.any(
              (p) =>
                  ReaderBlockSpacing.length(p) == null &&
                  !(name == 'margin' && p == 'auto'),
            )) {
          continue;
        }
        expanded.addAll({
          '$name-top': parts[0],
          '$name-right': parts.length > 1 ? parts[1] : parts[0],
          '$name-bottom': parts.length > 2 ? parts[2] : parts[0],
          '$name-left': parts.length > 3
              ? parts[3]
              : parts.length > 1
              ? parts[1]
              : parts[0],
        });
      } else if (name == 'margin-block' || name == 'padding-block') {
        final parts = value.split(RegExp(r'\s+'));
        if (parts.isEmpty ||
            parts.length > 2 ||
            parts.any((p) => ReaderBlockSpacing.length(p) == null)) {
          continue;
        }
        expanded.addAll({'$name-start': parts.first, '$name-end': parts.last});
      } else {
        expanded[name] = value;
      }
      for (final entry in expanded.entries) {
        final old = values[image]![entry.key];
        if (old != null &&
            (old.important && !declaration.important ||
                old.important == declaration.important &&
                    old.specificity > specificity)) {
          continue;
        }
        values[image]![entry.key] = (
          value: entry.value,
          important: declaration.important,
          specificity: specificity,
        );
      }
    }
  }

  for (final source in document.querySelectorAll(
    'style, link[rel~="stylesheet"]',
  )) {
    final text = source.localName == 'style'
        ? source.text
        : readStylesheet(source.attributes['href'] ?? '');
    if (text == null || text.isEmpty) continue;
    final sheet = css.parse(text);
    for (final rule in sheet.topLevels.whereType<ast.RuleSet>()) {
      if (!rule.declarationGroup.declarations.whereType<ast.Declaration>().any(
        (d) => supportedProperties.contains(d.property.toLowerCase()),
      )) {
        continue;
      }
      for (final selector
          in rule.selectorGroup?.selectors ?? <ast.Selector>[]) {
        final query = selector.span?.text;
        if (query == null) continue;
        final specificity = selector.simpleSelectorSequences.fold<int>(
          0,
          (sum, s) =>
              sum +
              switch (s.simpleSelector) {
                ast.IdSelector() => 1000000,
                ast.ClassSelector() ||
                ast.AttributeSelector() ||
                ast.PseudoClassSelector() => 1000,
                ast.ElementSelector() => 1,
                _ => 0,
              },
        );
        try {
          for (final image
              in document.querySelectorAll(query).where(values.containsKey)) {
            apply(image, rule.declarationGroup, specificity);
          }
        } on FormatException {
          /* An unsupported selector does not discard the chapter. */
        } on UnimplementedError {
          // html's selector evaluator throws this for valid CSS it cannot
          // match, such as :hover, :target, :nth-of-type and ::marker.
          // Keep processing the remaining selectors and declarations.
        }
      }
    }
  }
  for (final image in images) {
    final inline = image.attributes['style'];
    if (inline == null) continue;
    for (final rule
        in css.parse('img{$inline}').topLevels.whereType<ast.RuleSet>()) {
      apply(image, rule.declarationGroup, 1000000000);
    }
  }
  return {
    for (final image in images)
      image: values[image]!.map((key, value) => MapEntry(key, value.value)),
  };
}
