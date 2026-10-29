import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The reader's existing repaint boundary, with assert-only workload counters.
/// Release painting and compositing keep the same RenderRepaintBoundary path.
class ReaderArticleBoundary extends SingleChildRenderObjectWidget {
  const ReaderArticleBoundary({super.key, required super.child});

  @override
  ReaderArticleRenderBoundary createRenderObject(BuildContext context) =>
      ReaderArticleRenderBoundary();
}

/// Records container work in assertions without changing release rendering.
class ReaderArticleRenderBoundary extends RenderRepaintBoundary {
  int debugLayouts = 0, debugPaints = 0;

  @override
  void performLayout() {
    assert(() {
      debugLayouts++;
      return true;
    }());
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      debugPaints++;
      return true;
    }());
    super.paint(context, offset);
  }
}
