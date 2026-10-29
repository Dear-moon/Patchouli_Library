import 'package:flutter/material.dart';

/// Selectable prose that leaves ordinary vertical drags to its page.
///
/// Unlike [SelectableText], this has no EditableText or private Scrollable.
/// Selection is handled by the platform's normal long-press/drag selection UI.
class ReadOnlyText extends StatelessWidget {
  const ReadOnlyText(
    String this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textKey,
  }) : textSpan = null;

  const ReadOnlyText.rich(
    TextSpan this.textSpan, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textKey,
  }) : data = null;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: data != null
        ? Text(
            data!,
            key: textKey,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          )
        : Text.rich(
            textSpan!,
            key: textKey,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          ),
  );
}
