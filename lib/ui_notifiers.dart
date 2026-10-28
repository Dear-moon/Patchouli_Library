import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// An inactive retained page keeps its last layout and media constraints. It
/// catches up once when shown, not whenever a neighbouring pane changes width.
class RetainedPane extends StatefulWidget {
  const RetainedPane({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;
  @override
  State<RetainedPane> createState() => _RetainedPaneState();
}

class _RetainedPaneState extends State<RetainedPane> {
  MediaQueryData? _media;
  Size? _size;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.active || _media == null) {
          _media = media;
          _size = constraints.biggest;
        }
        return Offstage(
          offstage: !widget.active,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: _size!.width,
            maxWidth: _size!.width,
            minHeight: _size!.height,
            maxHeight: _size!.height,
            child: MediaQuery(data: _media!, child: widget.child),
          ),
        );
      },
    );
  }
}

/// Listen to a small immutable projection rather than rebuilding for unrelated
/// changes (for example, every audio clip's preparation/position updates).
class SelectedValueBuilder<T, S> extends StatefulWidget {
  const SelectedValueBuilder({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
    this.child,
    this.pauseWhenCovered = false,
  });
  final ValueListenable<T> listenable;
  final S Function(T value) select;
  final Widget Function(BuildContext context, S value, Widget? child) builder;
  final Widget? child;

  /// Covered routes retain their last UI and catch up once when revealed.
  /// This does not infer visibility from TickerMode, which may only disable
  /// animation on a still-visible page, and never pauses the data source.
  final bool pauseWhenCovered;

  @override
  State<SelectedValueBuilder<T, S>> createState() =>
      _SelectedValueBuilderState<T, S>();
}

class _SelectedValueBuilderState<T, S>
    extends State<SelectedValueBuilder<T, S>> {
  late S _value;
  ValueListenable<T>? _subscribedTo;
  bool _routeCurrent = true;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.listenable.value);
    _subscribe();
  }

  void _subscribe() {
    final target = _routeCurrent ? widget.listenable : null;
    if (_subscribedTo == target) return;
    _subscribedTo?.removeListener(_changed);
    _subscribedTo = target;
    target?.addListener(_changed);
  }

  void _readActivity() {
    final wasCurrent = _routeCurrent;
    _routeCurrent =
        !widget.pauseWhenCovered || ModalRoute.isCurrentOf(context) != false;
    _subscribe();
    if (_routeCurrent && !wasCurrent) {
      _value = widget.select(widget.listenable.value);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readActivity();
  }

  void _changed() {
    if (!_routeCurrent) return;
    final value = widget.select(widget.listenable.value);
    if (value != _value) setState(() => _value = value);
  }

  @override
  void didUpdateWidget(SelectedValueBuilder<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _readActivity();
    // A new projection can refer to a different paragraph or book even when
    // its source is unchanged. The parent already scheduled this build.
    if (_routeCurrent) _value = widget.select(widget.listenable.value);
  }

  @override
  void dispose() {
    _subscribedTo?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}

/// Data changes remain synchronous; visual observers receive at most one
/// notification per frame, outside layout. No idle timer or permanent ticker.
class FrameChangeNotifier extends ChangeNotifier {
  bool _queued = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed || _queued || !hasListeners) return;
    _queued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _queued = false;
      if (!_disposed) super.notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Retained home tabs do not rebuild for background data updates. Reactivation
/// reads the latest data once, so their scroll positions/elements stay alive.
class ActiveListenableBuilder extends StatefulWidget {
  const ActiveListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });
  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<ActiveListenableBuilder> createState() =>
      _ActiveListenableBuilderState();
}

class _ActiveListenableBuilderState extends State<ActiveListenableBuilder> {
  bool _active = false;
  bool _dirty = false;
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  void _changed() {
    _dirty = true;
    if (_active) setState(() {});
  }

  void _modeChanged() {
    final active = _tickerMode!.value.enabled;
    if (_active == active) return;
    _active = active;
    if (active && _dirty) setState(() {});
  }

  void _updateTickerMode() {
    // Route coverage and retained-tab visibility change this notifier without
    // changing the page's data. Do not turn hiding/showing into a full rebuild.
    final mode = TickerMode.getValuesNotifier(context);
    if (_tickerMode == mode) return;
    _tickerMode?.removeListener(_modeChanged);
    _tickerMode = mode..addListener(_modeChanged);
    _modeChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTickerMode();
  }

  @override
  void activate() {
    super.activate();
    _updateTickerMode();
  }

  @override
  void didUpdateWidget(ActiveListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_modeChanged);
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dirty = false;
    return widget.builder(context);
  }
}
