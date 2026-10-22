import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_ui.dart';

/// Listen to pixels locally, but rebuild only when the displayed percentage
/// changes. Source progress uses only mounted row geometry after layout, never
/// eager paragraph layout, disk writes or article rebuilds on a fling.
class ReaderScrollLocation extends StatefulWidget {
  const ReaderScrollLocation({
    super.key,
    required this.controller,
    required this.title,
    required this.margin,
    required this.ink,
    required this.paper,
    this.sourceFraction,
  });
  final ScrollController controller;
  final String title;
  final EdgeInsets margin;
  final Color ink, paper;
  final double? Function(double viewportOffset)? sourceFraction;
  static double extentOf(BuildContext context) =>
      math.max(22, MediaQuery.textScalerOf(context).scale(11) * 1.3 + 4);

  @override
  State<ReaderScrollLocation> createState() => _ReaderScrollLocationState();
}

class _ReaderScrollLocationState extends State<ReaderScrollLocation> {
  int _percent = 0;
  bool _updateQueued = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateAfterLayout);
    _updateAfterLayout();
  }

  void _updateAfterLayout() {
    if (_updateQueued) return;
    _updateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateQueued = false;
      if (mounted) _update();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _update() {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return;
    }
    final maximum = controller.position.maxScrollExtent;
    final source = widget.sourceFraction;
    final fraction = source == null
        ? (maximum > 0 ? controller.offset / maximum : 0.0)
        : controller.offset <= .5
        ? 0.0
        : controller.position.extentAfter <= .5
        ? 1.0
        : source(controller.offset);
    // A layout/restore can temporarily have no mounted source row. Keep the
    // last verified location instead of substituting an unrelated estimate.
    if (fraction == null) return;
    final percent = (fraction * 100).clamp(0, 100).round();
    if (_percent != percent) setState(() => _percent = percent);
  }

  @override
  void didUpdateWidget(ReaderScrollLocation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateAfterLayout);
      widget.controller.addListener(_updateAfterLayout);
    }
    // Font, margins or viewport changes can update maxScrollExtent without
    // changing pixels, so a scroll listener alone leaves the label stale.
    _updateAfterLayout();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateAfterLayout);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: ColoredBox(
      color: widget.paper,
      child: Padding(
        padding: widget.margin,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 11,
            height: 1.3,
            color: widget.ink.withValues(alpha: .65),
          ),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              AppText(
                '$_percent%',
                key: const ValueKey('reader-scroll-percent'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
