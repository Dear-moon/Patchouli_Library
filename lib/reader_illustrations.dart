import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'local_platform.dart';
import 'cover_arrival.dart';
import 'legacy_transport.dart';
import 'local_book_media.dart';
import 'local_image_layout.dart';

typedef IllustrationRequest = Future<Uint8List> Function(String url);

/// Decoded images are bounded by Flutter's image cache; encoded images by bytes,
/// not by chapter count. Completed futures are not retained after eviction.
class ReaderIllustrationCache {
  ReaderIllustrationCache({
    IllustrationRequest? request,
    this.offlineReader,
    this.maxBytes = 16 * 1024 * 1024,
  }) : _request = request ?? LegacyTransport.illustration;
  static final shared = ReaderIllustrationCache();
  IllustrationRequest _request;
  void useResolver(IllustrationRequest request) {
    clearMemory();
    _request = request;
  }

  /// The application binds its explicit book cache once at startup. Viewing
  /// cache eviction never deletes these durable, book-owned illustrations.
  Future<Uint8List?> Function(String url)? offlineReader;
  final int maxBytes;
  final _pending = <String, Future<Uint8List>>{};
  final _cache = <String, Uint8List>{};
  final _dimensions = <String, Size>{};
  // Header inspection is shared by the inline view and gallery. Weak byte keys
  // follow the encoded cache, without retaining another copy of an illustration.
  static final _sizes = Expando<Size>('illustration-size');
  static final _sizeRequests = Expando<Future<Size>>('illustration-size-read');
  int _bytes = 0;
  int _epoch = 0;
  int get encodedBytes => _bytes;
  Uint8List? peek(String url) => _cache[url];
  Size? sizeOf(String url) {
    if (_dimensions[url] case final size?) return size;
    final bytes = peek(url);
    return bytes == null ? null : _sizes[bytes];
  }

  Future<Size> dimensions(String url) async {
    if (sizeOf(url) case final size?) return size;
    return _rememberSize(url, await load(url));
  }

  Future<Size> _rememberSize(String url, Uint8List bytes) async {
    final epoch = _epoch;
    final size = await _size(bytes);
    if (epoch == _epoch) {
      if (_dimensions.length >= 256) _dimensions.remove(_dimensions.keys.first);
      _dimensions[url] = size;
    }
    return size;
  }

  /// Pagination needs header dimensions, not decoded pixels. Repeated note
  /// icons share one request; canceled layouts stop scheduling further reads.
  Future<Map<String, Size>> measureLocalImages(
    Iterable<String> urls, {
    required bool Function() current,
  }) async {
    final local = urls
        .where((u) => u.startsWith('wenku-local:'))
        .toSet()
        .toList();
    final result = <String, Size>{};
    for (var start = 0; start < local.length && current(); start += 4) {
      await Future.wait(
        local.skip(start).take(4).map((url) async {
          try {
            result[url] = await dimensions(url);
          } catch (_) {
            /* A broken image retains its reader retry, not a broken chapter. */
          }
        }),
      );
    }
    return result;
  }

  Future<Size> _size(Uint8List bytes) => _sizeRequests[bytes] ??= () async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final size = Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
        if (size.isEmpty) throw const FormatException('插图尺寸无效');
        _sizes[bytes] = size;
        return size;
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }();

  void evict(String url) {
    _dimensions.remove(url);
    final bytes = _cache.remove(url);
    if (bytes != null) _bytes -= bytes.length;
  }

  Future<Uint8List> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(url, () async {
      final epoch = _epoch;
      try {
        final bytes = url.startsWith('wenku-local:')
            ? await LocalBookMedia.load(url)
            : await offlineReader?.call(url) ?? await _request(url);
        if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('插图大小无效');
        }
        if (epoch == _epoch && bytes.length <= maxBytes) {
          while (_bytes + bytes.length > maxBytes && _cache.isNotEmpty) {
            _bytes -= _cache.remove(_cache.keys.first)!.length;
          }
          _cache[url] = bytes;
          _bytes += bytes.length;
        }
        return bytes;
      } catch (error) {
        rethrow;
      } finally {
        if (epoch == _epoch) _pending.remove(url);
      }
    });
  }

  void clearMemory() {
    _epoch++;
    _cache.clear();
    _pending.clear();
    _dimensions.clear();
    _bytes = 0;
  }
}

/// Scrolling illustrations use their own aspect ratio and the actual text
/// column width. Page illustrations instead use the whole leaf without cropping.
class ReaderIllustrationFrame extends StatelessWidget {
  const ReaderIllustrationFrame({
    super.key,
    required this.child,
    this.imageSize,
    this.fitPage = false,
    this.preserveSize = false,
    this.localLayout = const LocalImageLayout(),
    this.fontSize = 19,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final Size? imageSize;
  final bool fitPage;
  final bool preserveSize;
  final LocalImageLayout localLayout;
  final double fontSize;
  final Alignment alignment;

  Widget _resize(BuildContext context, Widget child) {
    // Zero-duration AnimatedSize can synchronously dirty its own layout when
    // decoded dimensions arrive. Reduced motion needs no animation controller.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: alignment,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (preserveSize) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final available = Size(
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : double.infinity,
          );
          final target = localLayout.resolve(
            natural: imageSize ?? const Size(32, 32),
            available: available,
            fontSize: fontSize,
          );
          return _resize(
            context,
            Align(
              alignment: Alignment(alignment.x, fitPage ? 0 : -1),
              heightFactor: fitPage ? null : 1,
              child: SizedBox(
                width: target.width,
                height: target.height,
                child: child,
              ),
            ),
          );
        },
      );
    }
    if (fitPage) return SizedBox.expand(child: child);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return _resize(
          context,
          SizedBox(
            width: width,
            height: width / (imageSize?.aspectRatio ?? .75),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class ReaderIllustration extends StatefulWidget {
  const ReaderIllustration({
    super.key,
    required this.url,
    this.onOpen,
    this.onUnavailable,
    this.cache,
    this.fullScreen = false,
    this.fitPage = false,
    this.localLayout = const LocalImageLayout(),
    this.fontSize = 19,
    this.sizedFrame = false,
    this.alignment = Alignment.topCenter,
  });
  final String url;
  final VoidCallback? onOpen;

  /// Inline readers can omit unavailable remote images from their reading
  /// order. Galleries leave this unset and retain the explicit retry control.
  final ValueChanged<String>? onUnavailable;
  final ReaderIllustrationCache? cache;
  final bool fullScreen;
  final bool fitPage;
  final LocalImageLayout localLayout;
  final double fontSize;

  /// Pagination has already resolved percentages against the whole leaf.
  final bool sizedFrame;
  final Alignment alignment;
  @override
  State<ReaderIllustration> createState() => _ReaderIllustrationState();
}

class _ReaderIllustrationState extends State<ReaderIllustration> {
  String? _reportedUnavailable;
  ReaderIllustrationCache get _cache =>
      widget.cache ?? ReaderIllustrationCache.shared;
  late Future<({Uint8List? bytes, Size? size, Object? error})> _future =
      _load();
  Future<({Uint8List? bytes, Size? size, Object? error})> _load() async {
    final cache = _cache, url = widget.url;
    try {
      final bytes = await cache.load(url);
      final size = await cache._rememberSize(url, bytes);
      return (bytes: bytes, size: size, error: null);
    } catch (error) {
      _notifyUnavailable(url);
      return (bytes: null, size: null, error: error);
    }
  }

  bool _notifyUnavailable(String url) {
    if (widget.onUnavailable == null || url.startsWith('wenku-local:')) {
      return false;
    }
    if (_reportedUnavailable != url) {
      _reportedUnavailable = url;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.url == url) widget.onUnavailable?.call(url);
      });
    }
    return true;
  }

  @override
  void didUpdateWidget(ReaderIllustration old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.cache != widget.cache) _future = _load();
  }

  String _failureLabel(Object? error) {
    final status = error is PlatformException && error.details is Map
        ? (error.details as Map)['httpStatus']
        : null;
    return switch (status) {
      401 || 403 => '图片服务暂未提供这张插图',
      404 || 410 => '原始插图已失效',
      429 => '图片请求较多，请稍后重试',
      _ => '插图加载失败',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cache.peek(widget.url), size = _cache.sizeOf(widget.url);
    return RepaintBoundary(
      child: FutureBuilder<({Uint8List? bytes, Size? size, Object? error})>(
        key: ObjectKey(_future),
        future: _future,
        initialData: cached != null && size != null
            ? (bytes: cached, size: size, error: null)
            : null,
        builder: (context, snapshot) {
          final bytes = snapshot.data?.bytes;
          Widget frame(Widget child) => widget.sizedFrame
              ? SizedBox.expand(child: child)
              : ReaderIllustrationFrame(
                  imageSize: snapshot.data?.size,
                  fitPage: widget.fullScreen || widget.fitPage,
                  preserveSize:
                      !widget.fullScreen &&
                      widget.url.startsWith('wenku-local:'),
                  localLayout: widget.localLayout,
                  fontSize: widget.fontSize,
                  alignment: widget.alignment,
                  child: child,
                );
          Widget localRetry() => Semantics(
            button: true,
            label: '图片加载失败，点按重试',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.play(context, HapticCue.action);
                _cache.evict(widget.url);
                setState(() {
                  _future = _load();
                });
              },
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: ArchiveIcon(
                    CupertinoIcons.arrow_clockwise,
                    size: 24,
                    ambient: true,
                  ),
                ),
              ),
            ),
          );
          if (snapshot.data?.error != null) {
            if (widget.onUnavailable != null &&
                !widget.url.startsWith('wenku-local:')) {
              return const SizedBox.shrink();
            }
            if (widget.url.startsWith('wenku-local:')) {
              return frame(localRetry());
            }
            final failure = Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ArchiveIcon(
                    CupertinoIcons.photo,
                    size: 28,
                    ambient: true,
                  ),
                  const SizedBox(height: 12),
                  AppText(_failureLabel(snapshot.data?.error)),
                  GlassTextButton(
                    onPressed: () {
                      _cache.evict(widget.url);
                      setState(() {
                        _future = _load();
                      });
                    },
                    child: const AppText('重试插图'),
                  ),
                ],
              ),
            );
            // A missing remote file must not leave a page-sized blank hole in
            // scrolling prose. Paged leaves keep their established geometry.
            return widget.fullScreen || widget.fitPage || widget.sizedFrame
                ? frame(failure)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: failure,
                  );
          }
          if (bytes == null) {
            return frame(
              const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在载入插图',
              ),
            );
          }
          return frame(
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTap: widget.onOpen == null
                    ? null
                    : () {
                        AppHaptics.play(context, HapticCue.action);
                        widget.onOpen!();
                      },
                child: Semantics(
                  label: '章节插图，点击查看大图',
                  image: true,
                  child: Image.memory(
                    bytes,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    fit: BoxFit.contain,
                    cacheWidth:
                        (widget.fullScreen
                                ? 2400
                                : (constraints.maxWidth *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round()
                                      .clamp(1, 1600))
                            .clamp(
                              1,
                              snapshot.data!.size!.width.round().clamp(1, 2400),
                            ),
                    frameBuilder: (context, child, frame, sync) => CoverArrival(
                      bytes: bytes,
                      ready: frame != null,
                      placeholder: const LoadingSkeleton(
                        layout: SkeletonLayout.cover,
                        label: '正在解码插图',
                      ),
                      child: child,
                    ),
                    errorBuilder: (context, error, stack) =>
                        _notifyUnavailable(widget.url)
                        ? const SizedBox.shrink()
                        : widget.url.startsWith('wenku-local:')
                        ? localRetry()
                        : Center(
                            child: GlassTextButton(
                              onPressed: () {
                                _cache.evict(widget.url);
                                setState(() {
                                  _future = _load();
                                });
                              },
                              child: const AppText('重新读取插图'),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReaderIllustrationGallery extends StatefulWidget {
  const ReaderIllustrationGallery({
    super.key,
    required this.urls,
    required this.initialUrl,
    this.cache,
    this.title = '章节插图',
    this.fileNamePrefix = '文库插图',
  }) : assert(urls.length > 0);
  final List<String> urls;
  final String initialUrl;
  final ReaderIllustrationCache? cache;
  final String title, fileNamePrefix;
  @override
  State<ReaderIllustrationGallery> createState() =>
      _ReaderIllustrationGalleryState();
}

class _ReaderIllustrationGalleryState extends State<ReaderIllustrationGallery> {
  late int _page = widget.urls
      .indexOf(widget.initialUrl)
      .clamp(0, widget.urls.length - 1);
  late final _pages = PageController(initialPage: _page);
  bool _saving = false;
  int? _dragPage;
  void _dragStart(ScaleStartDetails details) {
    _dragCancel();
    _dragPage = _pages.page!.round();
    _pages.jumpTo(_pages.offset);
  }

  void _dragUpdate(ScaleUpdateDetails details) {
    if (_dragPage == null) return;
    final position = _pages.position;
    _pages.jumpTo(
      (position.pixels - details.focalPointDelta.dx).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _dragEnd(ScaleEndDetails details) {
    final origin = _dragPage;
    _dragPage = null;
    if (origin == null) return;
    final distance = _pages.page! - origin;
    final velocity = -details.velocity.pixelsPerSecond.dx;
    final step = velocity.abs() > 350
        ? velocity.sign.toInt()
        : distance.abs() > .2
        ? distance.sign.toInt()
        : 0;
    final target = (origin + step).clamp(0, widget.urls.length - 1);
    if (target != origin || step != 0) {
      AppHaptics.play(
        context,
        target != origin ? HapticCue.pageTurn : HapticCue.boundary,
      );
    }
    _pages.animateToPage(
      target,
      duration: NovelMotion.contact,
      curve: NovelMotion.ease,
    );
  }

  void _dragCancel() {
    final origin = _dragPage;
    _dragPage = null;
    if (origin != null) _pages.jumpToPage(origin);
  }

  void _closeFromCanvas() {
    AppHaptics.play(context, HapticCue.action);
    Navigator.maybePop(context);
  }

  Future<void> _save() async {
    if (_saving) return;
    final page = _page;
    setState(() => _saving = true);
    try {
      final bytes = await (widget.cache ?? ReaderIllustrationCache.shared).load(
        widget.urls[page],
      );
      final saved = await LocalPlatform.saveBookImage(
        bytes,
        '${widget.fileNamePrefix}-${page + 1}',
      );
      if (mounted && saved) showNovelFeedback(context, '图片已保存');
    } catch (_) {
      if (mounted) showNovelFeedback(context, '图片保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _dragPage = null;
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回',
            onPressed: () => Navigator.pop(context),
          ),
          title: ArchiveRouteTitle(
            title: widget.title,
            code: 'IMAGE / ${_page + 1} OF ${widget.urls.length}',
          ),
          actions: [
            GlassIconButton(
              key: const ValueKey('book-image-save'),
              icon: CupertinoIcons.arrow_down_to_line,
              label: _saving ? '正在保存图片' : '保存图片',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeFromCanvas,
          child: PageView.builder(
            key: const ValueKey('book-image-canvas'),
            controller: _pages,
            // InteractiveViewer owns both contacts from the first finger.
            // Its one-finger callbacks drive this PageView, so a small drift
            // before the second finger arrives cannot steal the pinch arena.
            physics: const NeverScrollableScrollPhysics(),
            // A drag activity ignores new pointers in its child subtree. Keep
            // paging under the image's recognizer so a second finger can land.
            pageSnapping: false,
            itemCount: widget.urls.length,
            onPageChanged: (page) => setState(() {
              _page = page;
            }),
            itemBuilder: (context, index) => _ZoomableBookImage(
              key: ValueKey((widget.urls[index], index)),
              onDragStart: _dragStart,
              onDragUpdate: _dragUpdate,
              onDragEnd: _dragEnd,
              onDragCancel: _dragCancel,
              onClose: _closeFromCanvas,
              child: SizedBox.expand(
                child: ReaderIllustration(
                  url: widget.urls[index],
                  cache: widget.cache,
                  fullScreen: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ZoomableBookImage extends StatefulWidget {
  const _ZoomableBookImage({
    super.key,
    required this.child,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onClose,
  });
  final Widget child;
  final ValueChanged<ScaleStartDetails> onDragStart;
  final ValueChanged<ScaleUpdateDetails> onDragUpdate;
  final ValueChanged<ScaleEndDetails> onDragEnd;
  final VoidCallback onDragCancel;
  final VoidCallback onClose;
  @override
  State<_ZoomableBookImage> createState() => _ZoomableBookImageState();
}

class _ZoomableBookImageState extends State<_ZoomableBookImage>
    with SingleTickerProviderStateMixin {
  static const _initialScale = .9;
  final _transform = TransformationController();
  Size? _viewport;
  late final AnimationController _settle;
  void _applySettle() {
    if (_target != null) {
      _transform.value = _target!.lerp(
        NovelMotion.ease.transform(_settle.value),
      );
    }
  }

  Matrix4Tween? _target;
  // Keep the unused Z scale in step as InteractiveViewer uses the maximum
  // axis scale internally, including when the image is smaller than its fit.
  double get _scale => _transform.value.entry(0, 0).abs();
  Offset _tap = Offset.zero;
  final _contacts = <int>{};
  bool _multiple = false, _paging = false, _zoomed = false;
  bool _interactionFeedback = false;
  double _startScale = _initialScale;
  Offset _startTranslation = Offset.zero;
  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: NovelMotion.contact)
      ..addListener(_applySettle);
    _transform.addListener(_changed);
  }

  void _changed() {
    final zoomed = (_scale - _initialScale).abs() > .01;
    if (mounted && zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _animateTo(Matrix4 target) {
    _settle.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _transform.value = target;
    } else {
      _target = Matrix4Tween(begin: _transform.value.clone(), end: target);
      _settle.forward(from: 0);
    }
  }

  Matrix4 _bounded(Size size, double scale, double x, double y) =>
      Matrix4.identity()
        ..translateByDouble(
          scale < 1
              ? size.width * (1 - scale) / 2
              : x.clamp(size.width * (1 - scale), 0),
          scale < 1
              ? size.height * (1 - scale) / 2
              : y.clamp(size.height * (1 - scale), 0),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1);
  @override
  void dispose() {
    _settle.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (_viewport != size) {
        final scale = _viewport == null ? _initialScale : _scale;
        final translation = _transform.value.getTranslation();
        _viewport = size;
        _transform.value = _bounded(size, scale, translation.x, translation.y);
      }
      return Listener(
        onPointerDown: (event) {
          _contacts.add(event.pointer);
          if (_contacts.length > 1) {
            _multiple = true;
            _paging = false;
            widget.onDragCancel();
          }
        },
        onPointerUp: (event) => _contacts.remove(event.pointer),
        onPointerCancel: (event) {
          _contacts.remove(event.pointer);
          // ScaleRecognizer still ends a cancelled drag. Restore its source
          // page now, before that end callback can commit a turn or feedback.
          _paging = false;
          widget.onDragCancel();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          onDoubleTapDown: (details) => _tap = details.localPosition,
          onDoubleTap: () {
            AppHaptics.play(context, HapticCue.action);
            _animateTo(
              (_scale - _initialScale).abs() > .01
                  ? _bounded(size, _initialScale, 0, 0)
                  : _bounded(size, 2, -_tap.dx, -_tap.dy),
            );
          },
          child: InteractiveViewer(
            transformationController: _transform,
            panEnabled: _zoomed,
            minScale: .25,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            onInteractionStart: (details) {
              _settle.stop();
              _interactionFeedback = false;
              _startScale = _scale;
              final translation = _transform.value.getTranslation();
              _startTranslation = Offset(translation.x, translation.y);
              _multiple = _contacts.length > 1 || details.pointerCount > 1;
              _paging = !_multiple && !_zoomed;
              if (_paging) widget.onDragStart(details);
            },
            onInteractionUpdate: (details) {
              if (details.pointerCount > 1) {
                _multiple = true;
                _paging = false;
                widget.onDragCancel();
              } else if (_paging && !_multiple) {
                widget.onDragUpdate(details);
              }
              if (!_paging && !_interactionFeedback) {
                final translation = _transform.value.getTranslation();
                final moved =
                    (Offset(translation.x, translation.y) - _startTranslation)
                        .distance;
                if ((_scale - _startScale).abs() > .01 || moved > .5) {
                  _interactionFeedback = true;
                  AppHaptics.play(context, HapticCue.action);
                }
              }
            },
            onInteractionEnd: (details) {
              if (_paging && !_multiple) widget.onDragEnd(details);
              _paging = false;
              final scale = _scale.clamp(.25, 5.0);
              final translation = _transform.value.getTranslation();
              _animateTo(_bounded(size, scale, translation.x, translation.y));
            },
            child: widget.child,
          ),
        ),
      );
    },
  );
}
