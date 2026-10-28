import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'reading_touch_store.dart';

/// A passive observer around the article, below selection controls and reader
/// chrome. It adds no gesture recognizer and never consumes or follows a drag.
class ReaderTouchSurface extends StatefulWidget {
  const ReaderTouchSurface({
    super.key,
    required this.canRecord,
    required this.child,
    this.store,
  });
  final bool Function() canRecord;
  final Widget child;
  final ReadingTouchStore? store;

  @override
  State<ReaderTouchSurface> createState() => _ReaderTouchSurfaceState();
}

class _ReaderTouchSurfaceState extends State<ReaderTouchSurface>
    with WidgetsBindingObserver {
  ReadingTouchStore get _store => widget.store ?? ReadingTouchStore.shared;
  bool _foreground = true, _attached = true, _routeCurrent = true;
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    unawaited(_store.ensureLoaded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) != false;
    _keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!_routeCurrent || _keyboardVisible) unawaited(_store.flush());
  }

  @override
  void didUpdateWidget(covariant ReaderTouchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      unawaited((oldWidget.store ?? ReadingTouchStore.shared).flush());
      unawaited(_store.ensureLoaded());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_store.flush());
  }

  void _pointerDown(PointerDownEvent event) {
    if (!_store.canRecord ||
        !_attached ||
        !_foreground ||
        !_routeCurrent ||
        _keyboardVisible ||
        !widget.canRecord() ||
        (event.kind != PointerDeviceKind.touch &&
            event.kind != PointerDeviceKind.stylus &&
            event.kind != PointerDeviceKind.invertedStylus)) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final size = box.size;
    _store.record(
      x: event.localPosition.dx / size.width,
      y: event.localPosition.dy / size.height,
      orientation: size.width > size.height
          ? ReadingTouchOrientation.landscape
          : ReadingTouchOrientation.portrait,
    );
  }

  @override
  void deactivate() {
    _attached = false;
    unawaited(_store.flush());
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerDown: _pointerDown, child: widget.child);
}
