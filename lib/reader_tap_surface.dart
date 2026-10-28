import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Inline book controls can retain sole ownership of their precise hit region.
abstract interface class ReaderTapPreviewPolicy {
  /// Whether a body preview may share this exact local hit region.
  bool allowsReaderTapPreview(Offset localPosition);
}

/// Confirms an already-visible reader preview before another chrome action.
/// The gesture arena may still be waiting to distinguish its first body tap
/// from a listening double tap; confirmation must not run that action twice.
class ReaderTapSurfaceController {
  _PreviewTapGestureRecognizer? _recognizer;

  /// Returns true if the pending single tap was confirmed exactly once.
  bool commitPreview() => _recognizer?.commitPreview() ?? false;
}

/// Uses Flutter's normal tap arbitration while showing reversible feedback at
/// pointer-up. Selection, scrolling, links and listening double taps still win
/// their original arenas; only the centre chrome animation may be previewed.
class ReaderTapSurface extends StatefulWidget {
  const ReaderTapSurface({
    super.key,
    required this.controller,
    required this.onTapUp,
    required this.onPreview,
    required this.child,
  });

  final ReaderTapSurfaceController controller;
  final GestureTapUpCallback onTapUp;

  /// Returns the rollback for a visual-only preview, or null for other intents.
  /// The callback must not seek, persist preferences or produce haptics.
  final VoidCallback? Function(TapUpDetails details) onPreview;
  final Widget child;

  @override
  State<ReaderTapSurface> createState() => _ReaderTapSurfaceState();
}

class _ReaderTapSurfaceState extends State<ReaderTapSurface> {
  bool _active = true;

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    // Descendant double-tap disposal can release a held arena while this
    // surface is leaving the tree. It must not commit a stale body action.
    _active = false;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      _PreviewTapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<_PreviewTapGestureRecognizer>(
            () => _PreviewTapGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..bind(widget.controller)
              ..onConfirmed = (details) {
                if (_active) widget.onTapUp(details);
              }
              ..onPreview = (details) {
                if (!_active) return null;
                final rollback = widget.onPreview(details);
                return rollback == null
                    ? null
                    : () {
                        if (_active) rollback();
                      };
              },
          ),
    },
    child: widget.child,
  );
}

class _TapPreview {
  const _TapPreview(this.pointer, this.details, this.rollback);
  final int pointer;
  final TapUpDetails details;
  final VoidCallback rollback;
}

class _PreviewTapGestureRecognizer extends TapGestureRecognizer {
  _PreviewTapGestureRecognizer({super.debugOwner}) {
    // A non-null primary callback keeps the standard TapGestureRecognizer in
    // the arena. The overrides below retain pointer identity for deduplication.
    onTapUp = (_) {};
  }

  GestureTapUpCallback? onConfirmed;
  VoidCallback? Function(TapUpDetails details)? onPreview;
  ReaderTapSurfaceController? _controller;
  int? _eligiblePointer;
  int? _confirmedPointer, _forcedPointer;
  _TapPreview? _preview;

  void bind(ReaderTapSurfaceController controller) {
    if (_controller == controller) return;
    if (_controller?._recognizer == this) _controller?._recognizer = null;
    _controller = controller;
    controller._recognizer = this;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Tap tracks secondary pointers too, but only dispatches primary events to
    // handlePrimaryPointer. Secondary arenas can be accepted without rejection,
    // so they must never enter the preview's primary-only bookkeeping.
    if (state == GestureRecognizerState.ready) {
      _confirmedPointer = null;
      _eligiblePointer = event.pointer;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    super.handlePrimaryPointer(event);
    if (event is! PointerUpEvent ||
        _eligiblePointer != event.pointer ||
        _confirmedPointer == event.pointer ||
        _preview != null ||
        !_allowsPreview(event)) {
      return;
    }
    _eligiblePointer = null;
    final details = TapUpDetails(
      kind: event.kind,
      globalPosition: event.position,
      localPosition: event.localPosition,
    );
    final rollback = onPreview?.call(details);
    if (rollback != null) {
      _preview = _TapPreview(event.pointer, details, rollback);
    }
  }

  bool _allowsPreview(PointerUpEvent event) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, event.position, event.viewId);
    for (final entry in result.path) {
      if (entry is! BoxHitTestEntry) continue;
      final target = entry.target;
      if (target is ReaderTapPreviewPolicy &&
          !(target as ReaderTapPreviewPolicy).allowsReaderTapPreview(
            entry.localPosition,
          )) {
        return false;
      }
      if (target is RenderParagraph) {
        final span = target.text.getSpanForPosition(
          target.getPositionForOffset(entry.localPosition),
        );
        if (span is TextSpan && span.recognizer != null) return false;
      }
    }
    return true;
  }

  @override
  void handleTapUp({
    required PointerDownEvent down,
    required PointerUpEvent up,
  }) {
    _confirmedPointer = down.pointer;
    if (_eligiblePointer == down.pointer) _eligiblePointer = null;
    if (_preview?.pointer == down.pointer) _preview = null;
    if (_forcedPointer == down.pointer) {
      _forcedPointer = null;
      return;
    }
    onConfirmed?.call(
      TapUpDetails(
        kind: up.kind,
        globalPosition: up.position,
        localPosition: up.localPosition,
      ),
    );
  }

  void _reject(int pointer) {
    if (_eligiblePointer == pointer) _eligiblePointer = null;
    if (_forcedPointer == pointer) _forcedPointer = null;
    if (_preview case final preview? when preview.pointer == pointer) {
      _preview = null;
      preview.rollback();
    }
  }

  @override
  void rejectGesture(int pointer) {
    _reject(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void handleTapCancel({
    required PointerDownEvent down,
    PointerCancelEvent? cancel,
    required String reason,
  }) {
    _reject(down.pointer);
    super.handleTapCancel(down: down, cancel: cancel, reason: reason);
  }

  bool commitPreview() {
    final preview = _preview;
    if (preview == null) return false;
    _preview = null;
    _forcedPointer = preview.pointer;
    onConfirmed?.call(preview.details);
    return true;
  }

  @override
  void dispose() {
    // The parent may already have disposed its animation controller. A removed
    // surface abandons a preview rather than invoking UI rollback after exit.
    _preview = null;
    _eligiblePointer = null;
    if (_controller?._recognizer == this) _controller?._recognizer = null;
    _controller = null;
    super.dispose();
  }
}
