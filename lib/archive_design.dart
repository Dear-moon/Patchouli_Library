import 'sources/source_declarations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_language.dart';
import 'book_identity.dart';

import 'archive_icons.dart';
import 'archive_motion.dart';
import 'motion_ui.dart' show NovelMotion;
import 'performance_preferences.dart';
import 'library_reflow.dart';

/// The archive vocabulary is foreground geometry, not another filter layer.
/// Codes, rules and registration marks are static and carry no idle ticker.
abstract final class ArchiveDesign {
  static const background = Color(0xFFF4F3EF);
  static const surface = Color(0xFFFDFCFA);
  static const milk = Color(0xFFFEFDF8);
  static const darkBackground = Color(0xFF191919);
  static const darkSurface = Color(0xFF242424);
  static const darkRaised = Color(0xFF2D2D2D);
  static const darkRaisedHigh = Color(0xFF3A3A3A);
  static const darkOutline = Color(0xFF3C3C3C);
  static const darkInk = Color(0xFFF2F2F2);
  static const darkMuted = Color(0xFFB7B7B7);
  static const darkMilk = Color(0xFFF6F6F6);
  static const panelRadius = 4.0;
  static const coverRadius = 3.0;

  /// A thin neutral milk layer, not a white opaque sheet or another blur pass.
  static Color glassTint(Brightness brightness, {required double opacity}) =>
      brightness == Brightness.dark
      // Keep white labels legible even at the user's opaque endpoint.
      ? Color.lerp(darkMilk, darkSurface, opacity.clamp(0.0, 1.0))!
      : milk;

  static TextStyle codeStyle(BuildContext context, {Color? color}) => TextStyle(
    fontFamily: 'monospace',
    fontSize: 9,
    height: 1.35,
    letterSpacing: 1.05,
    fontWeight: FontWeight.w500,
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static String fileCode(int id, {String? sourceId}) {
    final prefix = isLocalBook(id)
        ? 'LOCAL'
        : SourceDeclarations.mark(sourceId);
    return '$prefix-${id.toString().padLeft(5, '0')}';
  }
}

class ArchiveMasthead extends StatelessWidget {
  const ArchiveMasthead({
    super.key,
    required this.title,
    required this.code,
    this.brand = false,
  });
  final String title;
  final String code;
  final bool brand;

  @override
  Widget build(BuildContext context) => LibraryReflowPart(
    child: Row(
      children: [
        if (brand) ...[
          ExcludeSemantics(
            child: SizedBox(
              width: 30,
              height: 34,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    'assets/branding/app-icon.png',
                    key: const ValueKey('discovery-app-icon'),
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                    cacheWidth: (30 * MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          // Keep the fixed 56 px toolbar usable with large system text, without
          // shrinking any reading content or enlarging its pinned hitbox plane.
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Keep the navigation landmark immediately readable; the
                  // archive address below it performs the terminal assembly.
                  AppText(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                      shadows: [],
                    ),
                  ),
                  const SizedBox(height: 3),
                  ArchivePart(start: .16, end: .88, child: ArchiveCode(code)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class ArchiveCode extends StatelessWidget {
  const ArchiveCode(this.text, {super.key, this.inverse = false, this.color});
  final String text;
  final bool inverse;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = AppText(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: ArchiveDesign.codeStyle(
        context,
        color: color ?? (inverse ? scheme.surface : null),
      ),
    );
    return ExcludeSemantics(
      child: inverse
          ? ColoredBox(
              color: scheme.onSurface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: label,
              ),
            )
          : label,
    );
  }
}

class ArchiveSection extends StatelessWidget {
  const ArchiveSection({
    super.key,
    required this.title,
    required this.code,
    this.subtitle = '',
    this.onMore,
    this.moreKey,
  });
  final String title;
  final String code;
  final String subtitle;
  final VoidCallback? onMore;
  final Key? moreKey;

  @override
  Widget build(BuildContext context) => LibraryReflowPart(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    0,
                    constraints.maxWidth - (onMore == null ? 17 : 62),
                  ),
                ),
                child: ArchivePart(
                  start: .1,
                  end: .68,
                  child: ArchiveCode(code),
                ),
              ),
              const SizedBox(width: 9),
              if (onMore != null)
                Expanded(
                  child: _ArchiveMoreAction(
                    actionKey: moreKey,
                    onMore: onMore!,
                  ),
                )
              else ...[
                Expanded(
                  child: const ArchivePart(
                    start: 0,
                    end: .46,
                    child: ExcludeSemantics(
                      child: Divider(height: 1, thickness: .6),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                ExcludeSemantics(
                  child: SizedBox(
                    width: 3,
                    height: 3,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 7),
        ArchivePart(
          start: .16,
          end: .82,
          child: AppText(
            title,
            style: const TextStyle(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 5),
          AppText(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ArchiveMoreAction extends StatefulWidget {
  const _ArchiveMoreAction({this.actionKey, required this.onMore});
  final Key? actionKey;
  final VoidCallback onMore;

  @override
  State<_ArchiveMoreAction> createState() => _ArchiveMoreActionState();
}

class _ArchiveMoreActionState extends State<_ArchiveMoreAction>
    with SingleTickerProviderStateMixin {
  bool _revealed = false;
  bool _awaitingReturn = false;
  ModalRoute<dynamic>? _route;
  Animation<double>? _secondary;
  late final _controller = AnimationController(
    vsync: this,
    duration: NovelMotion.enter,
    reverseDuration: NovelMotion.exit,
  );

  bool get _reduced =>
      PerformanceScope.reduceMotionOf(context) ||
      !PerformanceScope.of(context).motion;

  void _collapse() {
    if (!_revealed || _awaitingReturn) return;
    setState(() => _revealed = false);
    if (_reduced) {
      _controller.value = 0;
    } else {
      _controller.reverse();
    }
  }

  void _activate() {
    if (_revealed) {
      _awaitingReturn = true;
      _controller.value = 1;
      widget.onMore();
    } else {
      setState(() => _revealed = true);
      if (_reduced) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  void _returned(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        _awaitingReturn &&
        _route?.isCurrent == true) {
      _awaitingReturn = false;
      _collapse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      _secondary?.removeStatusListener(_returned);
      _route = route;
      _secondary = route?.secondaryAnimation;
      _secondary?.addStatusListener(_returned);
    }
  }

  @override
  void dispose() {
    _secondary?.removeStatusListener(_returned);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => CustomPaint(
      key: const ValueKey('section-more-morph'),
      painter: _ArchiveMorePainter(
        progress: _controller.value,
        color: Theme.of(context).colorScheme.onSurface,
        ruleColor:
            DividerTheme.of(context).color ?? Theme.of(context).dividerColor,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: TapRegion(
          onTapOutside: (_) => _collapse(),
          child: Focus(
            onFocusChange: (focused) {
              if (!focused) _collapse();
            },
            child: Semantics(
              label: _revealed ? '查看更多' : '展开更多入口',
              child: ArchiveIconButton(
                key: widget.actionKey,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                style: const ButtonStyle(
                  overlayColor: WidgetStatePropertyAll(Colors.transparent),
                  splashFactory: NoSplash.splashFactory,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _activate,
                icon: SizedBox.square(
                  key: ValueKey(
                    _revealed ? 'section-more-arrow' : 'section-more-dot',
                  ),
                  dimension: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ArchiveMorePainter extends CustomPainter {
  const _ArchiveMorePainter({
    required this.progress,
    required this.color,
    required this.ruleColor,
  });
  final double progress;
  final Color color, ruleColor;

  static final _arrowPaths = ArchiveIconArt.paths(ArchiveSymbol.external);
  static final _segments = [
    (_point(_arrowPaths[0], 0), _point(_arrowPaths[0], 1)),
    (_point(_arrowPaths[1], 0), _point(_arrowPaths[1], .5)),
    (_point(_arrowPaths[1], .5), _point(_arrowPaths[1], 1)),
  ];

  static Offset _point(Path path, double fraction) {
    final metric = path.computeMetrics().single;
    return metric.getTangentForOffset(metric.length * fraction)!.position;
  }

  double get shaftProgress =>
      NovelMotion.ease.transform((progress / .6).clamp(0.0, 1.0));
  double get headProgress =>
      NovelMotion.ease.transform(((progress - .6) / .4).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    const scale = 20 / 24;
    const stroke = 1.72 * scale;
    final anchor = Offset(size.width - 10, size.height / 2);
    final (start, end) = _segments[0];
    final center = (start + end) / 2;
    final tail = (start - center) * scale;
    final tip = (end - center) * scale;
    final delta = tip - tail;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance * (stroke / 2);
    final shaft = shaftProgress;
    final head = headProgress;
    final radius = 1.5 + (stroke / 2 - 1.5) * shaft;
    final from = [
      const Offset(-1.5, 1.5),
      const Offset(-1.5, -1.5),
      const Offset(1.5, -1.5),
      const Offset(1.5, 1.5),
    ];
    final to = [tail + normal, tail - normal, tip - normal, tip + normal];
    final paths = [
      Path()
        ..addPolygon([
          for (var i = 0; i < 4; i++)
            anchor + Offset.lerp(from[i], to[i], shaft)!,
        ], true)
        ..addOval(
          Rect.fromCircle(center: anchor + tail * shaft, radius: radius),
        )
        ..addOval(
          Rect.fromCircle(center: anchor + tip * shaft, radius: radius),
        ),
      if (head > 0)
        for (final outer in [_segments[1].$1, _segments[2].$2])
          (Path()..addRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(
                    center: Offset.zero,
                    width: ((outer - end) * scale).distance * head + stroke,
                    height: stroke,
                  ),
                  const Radius.circular(stroke / 2),
                ),
              ))
              .transform(
                (Matrix4.translationValues(
                      anchor.dx +
                          tip.dx +
                          (outer.dx - end.dx) * scale * head / 2,
                      anchor.dy +
                          tip.dy +
                          (outer.dy - end.dy) * scale * head / 2,
                      0,
                    )..rotateZ(
                      math.atan2(outer.dy - end.dy, outer.dx - end.dx),
                    ))
                    .storage,
              ),
    ];
    final left = paths.map((path) => path.getBounds().left).reduce(math.min);
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(math.max(0, left - 8), size.height / 2),
      Paint()
        ..color = ruleColor
        ..strokeWidth = .6,
    );
    final ink = Paint()..color = color;
    for (final path in paths) {
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_ArchiveMorePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      ruleColor != oldDelegate.ruleColor;
}

/// Readable route title plus a restrained archive address below it.
class ArchiveRouteTitle extends StatelessWidget {
  const ArchiveRouteTitle({super.key, required this.title, required this.code});
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: constraints.maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 3),
            ArchiveCode(code),
          ],
        ),
      ),
    ),
  );
}

class ArchiveRegistration extends StatelessWidget {
  const ArchiveRegistration({super.key, required this.child, this.inset = 0});
  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _RegistrationPainter(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
      inset: inset,
    ),
    child: child,
  );
}

class _RegistrationPainter extends CustomPainter {
  const _RegistrationPainter({required this.color, required this.inset});
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    final r = (Offset.zero & size).deflate(inset + .5);
    final length = math.min(7.0, math.min(r.width, r.height) / 3);
    if (length <= 0) return;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx + dx * length, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RegistrationPainter oldDelegate) =>
      color != oldDelegate.color || inset != oldDelegate.inset;
}

/// The diagram is limited to the header margin. The reading canvas stays plain.
class ArchiveBackdrop extends StatelessWidget {
  const ArchiveBackdrop({super.key, this.filmColor = ArchiveDesign.milk});
  final Color filmColor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.topCenter,
        // Bound the raster-cache candidate to the diagram itself, rather than
        // allocating a full-screen layer for an almost empty static painter.
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.viewPaddingOf(context).top + 240,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ArchiveBackdropPainter(
                color: Theme.of(context).colorScheme.onSurface,
                filmColor: filmColor,
                top: MediaQuery.viewPaddingOf(context).top,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ArchiveBackdropPainter extends CustomPainter {
  const _ArchiveBackdropPainter({
    required this.color,
    required this.top,
    required this.filmColor,
  });
  final Color color;
  final Color filmColor;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = math.min(size.height, top + 240);
    final dark = color.computeLuminance() > .5;
    final film = Paint()
      ..color = filmColor.withValues(alpha: dark ? .018 : .42);
    // Two restrained frosted file planes in the existing small header raster.
    // They are paint geometry: no backdrop filter, full-screen layer or ticker.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .42, top)
        ..lineTo(size.width, top)
        ..lineTo(size.width, bottom * .82)
        ..lineTo(size.width * .78, bottom * .82)
        ..close(),
      film,
    );
    film.color = filmColor.withValues(alpha: dark ? .012 : .28);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .60, top + 18)
        ..lineTo(size.width, top + 18)
        ..lineTo(size.width, bottom)
        ..lineTo(size.width * .92, bottom)
        ..close(),
      film,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .045)
      ..strokeWidth = .5;
    for (var x = 24.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, bottom), paint);
    }
    for (var y = top + 4; y < bottom; y += 48) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), paint);
    }
    paint.color = color.withValues(alpha: .15);
    final y = top + 60;
    for (final x in [24.0, size.width - 24]) {
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), paint);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_ArchiveBackdropPainter oldDelegate) =>
      color != oldDelegate.color ||
      top != oldDelegate.top ||
      filmColor != oldDelegate.filmColor;
}
