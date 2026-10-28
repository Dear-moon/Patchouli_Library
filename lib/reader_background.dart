import 'dart:io';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'personal_images.dart';
import 'reader_preferences.dart';

/// Kept behind the whole article. Scrolling, pagination and chrome ticks never
/// reopen the file or decode a screen capture. Only changing the image id does.
class ReaderBackground extends StatefulWidget {
  const ReaderBackground({
    super.key,
    required this.store,
    required this.preferences,
    required this.paper,
    required this.child,
    this.reduceMotion = false,
  });
  final ReaderBackgroundStore store;
  final ReaderPreferences preferences;
  final Color paper;
  final Widget child;
  final bool reduceMotion;
  @override
  State<ReaderBackground> createState() => _ReaderBackgroundState();
}

class _ReaderBackgroundState extends State<ReaderBackground> {
  Future<File?>? _file;
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    _file = widget.store.file(widget.preferences.backgroundImage);
  }

  @override
  void didUpdateWidget(ReaderBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.preferences.backgroundImage !=
            widget.preferences.backgroundImage) {
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.paper,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                key: const ValueKey('reader-background-layer'),
                child: FutureBuilder<File?>(
                  future: _file,
                  initialData: widget.store.resolvedFile(
                    widget.preferences.backgroundImage,
                  ),
                  builder: (context, snapshot) => AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : NovelMotion.enter,
                    switchInCurve: NovelMotion.ease,
                    switchOutCurve: NovelMotion.retract,
                    child: snapshot.data == null
                        ? const SizedBox.expand()
                        : Image.file(
                            snapshot.data!,
                            key: ValueKey(snapshot.data!.path),
                            width: double.infinity,
                            height: double.infinity,
                            fit: widget.preferences.backgroundFit,
                            color: widget.paper.withValues(
                              alpha:
                                  widget.preferences.darkPaper(
                                    Theme.of(context).brightness ==
                                        Brightness.dark,
                                  )
                                  ? (1 - widget.preferences.backgroundOpacity)
                                        .clamp(.55, 1.0)
                                  : 1 - widget.preferences.backgroundOpacity,
                            ),
                            colorBlendMode: BlendMode.srcOver,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const SizedBox.expand(),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    ),
  );
}
