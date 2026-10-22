import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'reader_rich_content.dart';
import 'app_ui.dart';

class ReaderAnnotations extends SingleChildRenderObjectWidget {
  const ReaderAnnotations({
    super.key,
    required this.format,
    required this.style,
    required this.scaler,
    required this.prefix,
    required this.onNote,
    required super.child,
  });
  final ReaderRichParagraph format;
  final TextStyle style;
  final TextScaler scaler;
  final int prefix;
  final ValueChanged<String> onNote;
  @override
  RenderReaderAnnotations createRenderObject(BuildContext context) =>
      RenderReaderAnnotations(this);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderAnnotations renderObject,
  ) => renderObject.update(this);
}

class RenderReaderAnnotations extends RenderProxyBox {
  RenderReaderAnnotations(this.config) {
    _tap.onTap = () {
      if (_pressed case final id?) config.onNote(id);
    };
  }
  ReaderAnnotations config;
  final _tap = TapGestureRecognizer();
  final _labels = <({TextPainter text, Rect rect, double scale})>[];
  final _links = <({Rect rect, String id})>[];
  String? _pressed;
  void update(ReaderAnnotations value) {
    final layoutChanged =
        value.format != config.format ||
        value.style != config.style ||
        value.scaler != config.scaler ||
        value.prefix != config.prefix;
    config = value;
    if (layoutChanged) markNeedsLayout();
  }

  void _clear() {
    for (final p in _labels) {
      p.text.dispose();
    }
    _labels.clear();
    _links.clear();
  }

  @visibleForTesting
  List<Rect> get debugRubyRects => _labels.map((p) => p.rect).toList();
  List<Rect> get debugNoteRects => _links.map((p) => p.rect).toList();
  @override
  void performLayout() {
    super.performLayout();
    _clear();
    RenderParagraph? text;
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        text ??= node;
        return;
      }
      node.visitChildren(visit);
    }

    if (child != null) visit(child!);
    final paragraph = text;
    if (paragraph == null) return;
    final origin = paragraph.localToGlobal(Offset.zero, ancestor: this);
    List<Rect> boxes(int start, int end) => paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: start + config.prefix,
            extentOffset: end + config.prefix,
          ),
        )
        .map((r) => r.toRect().shift(origin))
        .toList();
    for (final ruby in config.format.ruby) {
      final rects = boxes(ruby.start, ruby.end);
      final total = rects.fold<double>(0, (sum, r) => sum + r.width);
      var used = 0.0;
      final letters = ruby.text.characters.toList();
      for (final box in rects) {
        if (total <= 0) continue;
        final start = (used / total * letters.length).floor();
        used += box.width;
        final end = (used / total * letters.length + 1e-8).floor().clamp(
          start,
          letters.length,
        );
        if (end == start) continue;
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: config.scaler,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
          text: TextSpan(
            text: letters.sublist(start, end).join(),
            style: config.style.copyWith(
              fontSize: (config.style.fontSize ?? 19) * .48,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
        )..layout();
        final scale = math.min(
          1.0,
          (box.width + 4) / painter.width.clamp(1, double.infinity),
        );
        _labels.add((
          text: painter,
          rect: Rect.fromLTWH(
            box.center.dx - painter.width * scale / 2,
            box.top - painter.height * scale - 1,
            painter.width * scale,
            painter.height * scale,
          ),
          scale: scale,
        ));
      }
    }
    for (final link in config.format.references) {
      for (final rect in boxes(link.start, link.end)) {
        _links.add((rect: rect, id: link.id));
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final canvas = context.canvas;
    for (final item in _labels) {
      canvas.save();
      canvas.translate(offset.dx + item.rect.left, offset.dy + item.rect.top);
      canvas.scale(item.scale);
      item.text.paint(canvas, Offset.zero);
      canvas.restore();
    }
    final paint = Paint()
      ..color = (config.style.color ?? Colors.grey).withValues(alpha: .55)
      ..strokeWidth = 1;
    for (final link in _links) {
      canvas.drawLine(
        offset + Offset(link.rect.left, link.rect.bottom - 3),
        offset + Offset(link.rect.right, link.rect.bottom - 3),
        paint,
      );
    }
  }

  @override
  bool hitTestSelf(Offset position) =>
      _links.any((v) => v.rect.inflate(3).contains(position));
  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerDownEvent) {
      final link = _links
          .where((v) => v.rect.inflate(3).contains(event.localPosition))
          .firstOrNull;
      if (link != null) {
        _pressed = link.id;
        _tap.addPointer(event);
      }
    }
  }

  @override
  void dispose() {
    _clear();
    _tap.dispose();
    super.dispose();
  }
}

Future<void> showReaderNote(
  BuildContext context,
  String text, {
  required bool reduceMotion,
  Widget Function(Widget)? surfaceWrapper,
}) => showJellySheet<void>(
  context: context,
  reduceMotion: reduceMotion,
  surfaceWrapper: surfaceWrapper,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArchiveSection(title: '注释', code: 'READER / NOTE'),
        const SizedBox(height: 18),
        SelectableText(text, style: const TextStyle(fontSize: 16, height: 1.8)),
        const SizedBox(height: 20),
        GlassTextButton(
          onPressed: () => Navigator.pop(sheet),
          child: const AppText('回到正文'),
        ),
      ],
    ),
  ),
);
