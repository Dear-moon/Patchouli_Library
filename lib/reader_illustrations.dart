import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'local_platform.dart';
import 'legacy_transport.dart';
import 'local_book_media.dart';
import 'local_image_layout.dart';
import 'gallery_save_button.dart';

typedef IllustrationRequest = Future<Uint8List> Function(String url);

class _IllustrationSource {
  _IllustrationSource(this.epoch, this.revision, {required this.retain});
  final int epoch, revision;
  bool retain, active = true;
}

typedef _IllustrationRead = ({
  Future<Uint8List> future,
  _IllustrationSource source,
});

typedef _IllustrationImage = ({
  Uint8List? bytes,
  Size? size,
  Object? error,
  _IllustrationSource? source,
});

class _IllustrationDecodes {
  _IllustrationDecodes(this.source);
  final _IllustrationSource source;
  final entries = <int, ({ResizeImage provider, ResizeImageKey key})>{};
}

/// Decoded images are bounded by Flutter's image cache; encoded images by bytes,
/// not by chapter count. Completed futures are not retained after eviction.
class ReaderIllustrationCache {
  ReaderIllustrationCache({
    IllustrationRequest? request,
    this.offlineReader,
    this.maxBytes = 16 * 1024 * 1024,
  }) : _request = request ?? LegacyTransport.illustration;
  static final shared = ReaderIllustrationCache();
  final IllustrationRequest _request;

  /// The application binds its explicit book cache once at startup. Viewing
  /// cache eviction never deletes these durable, book-owned illustrations.
  Future<Uint8List?> Function(String url)? offlineReader;
  final int maxBytes;
  final _pending = <String, _IllustrationRead>{};
  final _cache = <String, ({Uint8List bytes, _IllustrationSource source})>{};
  final _dimensions = <String, ({Size size, _IllustrationSource source})>{};
  // Header inspection is shared by the inline view and gallery. Weak byte keys
  // follow the encoded cache, without retaining another copy of an illustration.
  static final _sizes = Expando<Size>('illustration-size');
  static final _sizeRequests = Expando<Future<Size>>('illustration-size-read');
  // Only standard provider keys, never pixel frames or another encoded cache.
  // Weak byte identities follow the source/cache lifetime.
  var _decodes = Expando<_IllustrationDecodes>('illustration-decodes');
  int _bytes = 0;
  int _epoch = 0;
  int get encodedBytes => _bytes;
  int _revision(String url) =>
      url.startsWith('wenku-local:') ? LocalBookMedia.revisionOf(url) : 0;
  bool _current(String url, _IllustrationSource source) =>
      source.active &&
      source.epoch == _epoch &&
      source.revision == _revision(url);

  Uint8List? peek(String url) {
    final cached = _cache[url];
    if (cached == null) return null;
    if (_current(url, cached.source)) return cached.bytes;
    _cache.remove(url);
    _bytes -= cached.bytes.length;
    return null;
  }

  Size? sizeOf(String url) {
    if (_dimensions[url] case final entry?) {
      if (_current(url, entry.source)) return entry.size;
      _dimensions.remove(url);
    }
    final bytes = peek(url);
    return bytes == null ? null : _sizes[bytes];
  }

  Future<Size> dimensions(String url) async {
    if (sizeOf(url) case final size?) return size;
    final request = _requestFor(url);
    return _rememberSize(url, await request.future, request.source);
  }

  Future<Size> _rememberSize(
    String url,
    Uint8List bytes,
    _IllustrationSource source,
  ) async {
    final size = await _size(bytes);
    if (_current(url, source)) {
      if (_dimensions.length >= 256 && !_dimensions.containsKey(url)) {
        _dimensions.remove(_dimensions.keys.first);
      }
      _dimensions[url] = (size: size, source: source);
    }
    return size;
  }

  /// Pagination needs header dimensions, not decoded pixels. Repeated note
  /// icons share one request; canceled layouts stop scheduling further reads.
  Future<Map<String, Size>> measureLocalImages(
    Iterable<String> urls, {
    required bool Function() current,
    Iterable<String> prioritize = const [],
    bool retainPriority = false,
  }) async {
    final local = urls.where((u) => u.startsWith('wenku-local:')).toSet();
    final preferred = <String>[];
    for (final url in prioritize) {
      if (local.remove(url)) preferred.add(url);
      if (preferred.length == 4) break;
    }
    final ordered = [...preferred, ...local];
    final result = <String, Size>{};
    for (var start = 0; start < ordered.length && current(); start += 4) {
      final batch = ordered.skip(start).take(4).toList();
      final reads = LocalBookMedia.loadBatch([
        for (final url in batch)
          if (sizeOf(url) == null &&
              peek(url) == null &&
              _pendingFor(url) == null)
            url,
      ]);
      final measured =
          <
            String,
            ({Uint8List bytes, Size size, _IllustrationSource source})
          >{};
      await Future.wait(
        batch.map((url) async {
          try {
            if (sizeOf(url) case final size?) {
              result[url] = size;
              return;
            }
            final request = _requestFor(url, input: reads[url], retain: false);
            final bytes = await request.future;
            final size = await _rememberSize(url, bytes, request.source);
            measured[url] = (bytes: bytes, size: size, source: request.source);
          } catch (_) {
            /* A broken image retains its reader retry, not a broken chapter. */
          }
        }),
      );
      // Header inspection must not let later art evict the visible image. Commit
      // one bounded batch in reading priority, rather than completion order.
      for (final url in batch) {
        final image = measured[url];
        if (image == null) continue;
        result[url] = image.size;
        if (current()) {
          _rememberBytes(
            url,
            image.bytes,
            image.source,
            allowEviction:
                retainPriority &&
                preferred.isNotEmpty &&
                preferred.first == url,
          );
        }
      }
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
    _dimensions.remove(url)?.source.active = false;
    final cached = _cache.remove(url);
    if (cached != null) {
      cached.source.active = false;
      _bytes -= cached.bytes.length;
    }
    _pending.remove(url)?.source.active = false;
  }

  _IllustrationRead? _pendingFor(String url) {
    final request = _pending[url];
    if (request == null || _current(url, request.source)) return request;
    _pending.remove(url);
    return null;
  }

  Future<Uint8List> load(String url) => _requestFor(url).future;

  _IllustrationRead _requestFor(
    String url, {
    Future<Uint8List>? input,
    bool retain = true,
  }) {
    final bytes = peek(url);
    final cached = bytes == null ? null : _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return (future: Future.value(cached.bytes), source: cached.source);
    }
    if (_pendingFor(url) case final request?) {
      if (retain) request.source.retain = true;
      return request;
    }
    final source = _IllustrationSource(_epoch, _revision(url), retain: retain);
    Uint8List? received;
    late final Future<Uint8List> future;
    future = _receive(url, input)
        .then((bytes) {
          received = bytes;
          return bytes;
        })
        .whenComplete(() {
          if (identical(_pending[url]?.source, source)) {
            final bytes = received;
            if (source.retain && bytes != null) {
              _rememberBytes(url, bytes, source, allowEviction: true);
            }
            _pending.remove(url);
          }
        });
    final request = (future: future, source: source);
    _pending[url] = request;
    return request;
  }

  Future<Uint8List> _receive(String url, Future<Uint8List>? input) async {
    try {
      final bytes = input != null
          ? await input
          : url.startsWith('wenku-local:')
          ? await LocalBookMedia.load(url)
          : await offlineReader?.call(url) ?? await _request(url);
      if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
        throw const FormatException('插图大小无效');
      }
      return bytes;
    } catch (error) {
      rethrow;
    }
  }

  void _rememberBytes(
    String url,
    Uint8List bytes,
    _IllustrationSource source, {
    required bool allowEviction,
  }) {
    if (!_current(url, source) || bytes.length > maxBytes) return;
    final existing = _cache[url];
    if (existing != null && identical(existing.bytes, bytes)) return;
    if (!allowEviction && _bytes + bytes.length > maxBytes) return;
    final previous = _cache.remove(url);
    if (previous != null) _bytes -= previous.bytes.length;
    while (_bytes + bytes.length > maxBytes && _cache.isNotEmpty) {
      _bytes -= _cache.remove(_cache.keys.first)!.bytes.length;
    }
    _cache[url] = (bytes: bytes, source: source);
    _bytes += bytes.length;
  }

  void clearMemory() {
    _epoch++;
    _decodes = Expando<_IllustrationDecodes>('illustration-decodes');
    _cache.clear();
    _pending.clear();
    _dimensions.clear();
    _bytes = 0;
  }

  ResizeImage _decodeProvider(
    String url,
    Uint8List bytes,
    _IllustrationSource source,
    int width,
  ) {
    final known = _decodes[bytes];
    if (_current(url, source) && identical(known?.source, source)) {
      ResizeImage? reusable;
      final cache = PaintingBinding.instance.imageCache;
      for (final entry in known!.entries.entries) {
        if (entry.key < width) continue;
        final status = cache.statusForKey(entry.value.key);
        if (!status.pending && (status.live || status.keepAlive)) {
          // Prefer the retained detail tier after zoom, even when a reader
          // underneath still has a live lower-resolution frame.
          if (reusable == null || entry.key > reusable.width!) {
            reusable = entry.value.provider;
          }
        }
      }
      if (reusable != null) return reusable;
    }
    return ResizeImage(MemoryImage(bytes), width: width);
  }

  void _decoded(
    String url,
    Uint8List bytes,
    _IllustrationSource source,
    ResizeImage provider,
  ) {
    provider.obtainKey(ImageConfiguration.empty).then((key) {
      if (!_current(url, source)) return;
      var known = _decodes[bytes];
      if (!identical(known?.source, source)) {
        _decodes[bytes] = known = _IllustrationDecodes(source);
      }
      final entries = known!.entries;
      final width = provider.width!;
      entries[width] = (provider: provider, key: key);
      final cache = PaintingBinding.instance.imageCache;
      for (final entry in entries.entries) {
        if (entry.key < width &&
            cache.statusForKey(entry.value.key).keepAlive) {
          // A real higher-resolution frame has reached the tree. Drop only
          // obsolete cache residency; a reader's live image stays reusable.
          cache.evict(entry.value.key, includeLive: false);
        }
      }
      if (entries.length > 8) {
        entries.removeWhere(
          (width, entry) =>
              entry.key != key && !cache.statusForKey(entry.key).tracked,
        );
        while (entries.length > 8) {
          entries.remove(entries.keys.first);
        }
      }
    });
  }
}

/// Decode the pixels that can actually be drawn, then retain the established
/// full-screen detail ceiling when the user magnifies the image.
int readerIllustrationDecodeWidth({
  required Size imageSize,
  required Size available,
  required double devicePixelRatio,
  bool fullScreen = false,
  bool detailResolution = false,
}) {
  final maximum = (fullScreen ? 2400 : 1600).clamp(
    1,
    imageSize.width.round().clamp(1, 2400),
  );
  if (fullScreen && detailResolution) return maximum;
  final width = available.width.isFinite ? available.width : imageSize.width;
  final fittedWidth = available.height.isFinite
      ? math.min(width, available.height * imageSize.aspectRatio)
      : width;
  return (fittedWidth * devicePixelRatio).ceil().clamp(1, maximum);
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
          return AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: alignment,
            child: Align(
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
        return AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
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
    this.cache,
    this.fullScreen = false,
    this.detailResolution = false,
    this.fitPage = false,
    this.localLayout = const LocalImageLayout(),
    this.fontSize = 19,
    this.sizedFrame = false,
    this.alignment = Alignment.topCenter,
  });
  final String url;
  final VoidCallback? onOpen;
  final ReaderIllustrationCache? cache;
  final bool fullScreen;
  final bool detailResolution;
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
  ReaderIllustrationCache get _cache =>
      widget.cache ?? ReaderIllustrationCache.shared;
  int _sourceRevision = 0;
  late Future<_IllustrationImage> _future = _load();
  Future<_IllustrationImage> _load() async {
    try {
      final cache = _cache, url = widget.url;
      _sourceRevision = cache._revision(url);
      final request = cache._requestFor(url);
      final bytes = await request.future;
      final size = await cache._rememberSize(url, bytes, request.source);
      return (bytes: bytes, size: size, error: null, source: request.source);
    } catch (error) {
      return (bytes: null, size: null, error: error, source: null);
    }
  }

  @override
  void didUpdateWidget(ReaderIllustration old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.cache != widget.cache ||
        _sourceRevision != _cache._revision(widget.url)) {
      _future = _load();
    }
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
      child: FutureBuilder<_IllustrationImage>(
        key: ObjectKey(_future),
        future: _future,
        initialData: cached != null && size != null
            ? (
                bytes: cached,
                size: size,
                error: null,
                source: _cache._cache[widget.url]!.source,
              )
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
                  child: _IllustrationPixels(
                    cache: _cache,
                    url: widget.url,
                    bytes: bytes,
                    source: snapshot.data!.source!,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    cacheWidth: readerIllustrationDecodeWidth(
                      imageSize: snapshot.data!.size!,
                      available: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                      fullScreen: widget.fullScreen,
                      detailResolution: widget.detailResolution,
                    ),
                    errorBuilder: (context, error, stack) =>
                        widget.url.startsWith('wenku-local:')
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

/// Retain the presented frame while a zoom requests a higher-resolution codec.
/// Replacing the source bytes still starts its own normal arrival.
class _IllustrationPixels extends StatefulWidget {
  const _IllustrationPixels({
    required this.cache,
    required this.url,
    required this.bytes,
    required this.source,
    required this.width,
    required this.height,
    required this.cacheWidth,
    required this.errorBuilder,
  });
  final ReaderIllustrationCache cache;
  final String url;
  final Uint8List bytes;
  final _IllustrationSource source;
  final double width, height;
  final int cacheWidth;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  State<_IllustrationPixels> createState() => _IllustrationPixelsState();
}

class _IllustrationPixelsState extends State<_IllustrationPixels> {
  bool _decoded = false;
  ResizeImage? _recorded;

  @override
  void didUpdateWidget(_IllustrationPixels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        !identical(oldWidget.source, widget.source) ||
        oldWidget.cache != widget.cache) {
      _decoded = false;
      _recorded = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.cache._decodeProvider(
      widget.url,
      widget.bytes,
      widget.source,
      widget.cacheWidth,
    );
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) {
        if (frame != null) {
          _decoded = true;
          if (_recorded != provider) {
            _recorded = provider;
            final image = widget;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                image.cache._decoded(
                  image.url,
                  image.bytes,
                  image.source,
                  provider,
                );
              }
            });
          }
        }
        // Article art is content, not a shelf-cover entrance. A ready local or
        // cached frame must not wait for the route and another cover reveal.
        // Keep gapless pixels while the same image upgrades its decode size.
        return _decoded
            ? child
            : const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在解码插图',
              );
      },
      errorBuilder: widget.errorBuilder,
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

  Future<void> _save(String? authorizationToken) async {
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
        authorizationToken: authorizationToken,
      );
      if (mounted && saved) showNovelFeedback(context, '已保存到相册');
    } catch (error) {
      if (mounted) {
        showNovelFeedback(context, gallerySaveFailureMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _saveButton(BuildContext context) => GallerySaveButton(
    key: const ValueKey('book-image-save'),
    enabled: !_saving,
    foreground: Theme.of(context).colorScheme.onSurface,
    background: Theme.of(context).colorScheme.surface,
    onSave: _save,
    onError: (error) {
      if (mounted) {
        showNovelFeedback(context, gallerySaveFailureMessage(error));
      }
    },
    builder: (onPressed) => GlassIconButton(
      icon: CupertinoIcons.arrow_down_to_line,
      label: _saving ? '正在保存图片' : '保存图片',
      onPressed: onPressed,
    ),
  );

  @override
  void dispose() {
    _dragPage = null;
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: LocalPlatform.harmony
        ? ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(12),
              child: Center(
                heightFactor: 1,
                child: SizedBox(width: 160, child: _saveButton(context)),
              ),
            ),
          )
        : null,
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
          actions: [if (!LocalPlatform.harmony) _saveButton(context)],
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
              builder: (detailResolution) => SizedBox.expand(
                child: ReaderIllustration(
                  url: widget.urls[index],
                  cache: widget.cache,
                  fullScreen: true,
                  detailResolution: detailResolution,
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
    required this.builder,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onClose,
  });
  final Widget Function(bool detailResolution) builder;
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
  bool _detailResolution = false;
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
    final detail = _detailResolution || _scale > _initialScale + .01;
    if (mounted && (zoomed != _zoomed || detail != _detailResolution)) {
      setState(() {
        _zoomed = zoomed;
        _detailResolution = detail;
      });
    }
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
            child: widget.builder(_detailResolution),
          ),
        ),
      );
    },
  );
}
