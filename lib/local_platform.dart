import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_haptics.dart';
import 'library_state.dart';
import 'reader_preferences.dart';

/// Host capabilities are separate from the network contract. Only explicit
/// file actions open a picker; reader changes are restored when it leaves.
abstract final class LocalPlatform {
  static const channel = MethodChannel('org.mewx.wenku8/local_tools');
  static bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  // Flutter-OH adds this enum value; the stable Android/iOS SDK does not.
  static bool get harmony => !kIsWeb && defaultTargetPlatform.name == 'ohos';
  static bool get website => ios || harmony;
  static bool get readerAppearance => android || ios || harmony;
  static bool get listening => android || ios || harmony;
  static bool get nearbyReading => android || ios || harmony;
  static bool get fileActions => android || ios || harmony;
  static bool get storageDiagnostics => android || ios || harmony;
  static bool get volumePaging => android || harmony;
  static Future<bool> exportBackup(String text, String name) async =>
      await channel.invokeMethod<bool>('exportBackup', {
        'text': text,
        'name': name,
      }) ??
      false;
  static Future<String?> importBackup() =>
      channel.invokeMethod<String>('importBackup');
  static Future<Map<Object?, Object?>?> importLegacyData() =>
      channel.invokeMapMethod<Object?, Object?>('importLegacyData');
  static Future<void> shareText(String text) =>
      channel.invokeMethod<void>('shareText', {'text': text});
  static Future<bool> saveBookImage(
    Uint8List bytes,
    String name, {
    String? authorizationToken,
  }) => _saveGalleryImage(
    'saveBookImage',
    bytes,
    name,
    authorizationToken: authorizationToken,
  );
  static Future<void> shareImage(Uint8List bytes, String name) =>
      channel.invokeMethod<void>('shareImage', {'bytes': bytes, 'name': name});

  /// Saves app-rendered PNG bytes to Photos/Gallery, never a file picker.
  /// Harmony receives its one-use authorization from GallerySaveButton.
  static Future<void> saveImageToGallery(
    Uint8List bytes,
    String name, {
    String? authorizationToken,
  }) async {
    await _saveGalleryImage(
      'saveImageToGallery',
      bytes,
      name,
      authorizationToken: authorizationToken,
    );
  }

  /// Compatibility entry for image callers; backups keep exportBackup.
  static Future<bool> exportImage(
    Uint8List bytes,
    String name, {
    String? authorizationToken,
  }) => _saveGalleryImage(
    'exportImage',
    bytes,
    name,
    authorizationToken: authorizationToken,
  );

  static Future<bool> _saveGalleryImage(
    String method,
    Uint8List bytes,
    String name, {
    String? authorizationToken,
  }) async {
    final saved = await channel.invokeMethod<bool>(method, {
      'bytes': bytes,
      'name': name,
      'authorizationToken': ?authorizationToken,
    });
    if (saved != true) {
      throw PlatformException(code: 'gallery_save', message: '图片未保存到相册，请重试');
    }
    return true;
  }

  static final Set<Object> _awakeOwners = {};
  static const readerControls = MethodChannel(
    'org.mewx.wenku8/reader_controls',
  );
  static Object? _readerOwner;
  static ValueChanged<int>? _onPage;
  static bool? _iosStatusHidden;
  static void reader(
    Object owner, {
    required bool active,
    required LibraryState state,
    ValueChanged<int>? onPage,
    bool pageKeysActive = true,
  }) {
    if (!readerAppearance) return;
    if (active) {
      _readerOwner = owner;
      _onPage = pageKeysActive ? onPage : null;
      readerControls.setMethodCallHandler((call) async {
        if (call.method == 'page' && call.arguments is int) {
          _onPage?.call(call.arguments as int);
        }
      });
    } else if (identical(_readerOwner, owner)) {
      _readerOwner = null;
      _onPage = null;
    } else {
      return;
    }
    if (ios || harmony) {
      final hidden = active && state.readerPreferences.hideSystemStatus;
      if (hidden != _iosStatusHidden) {
        _iosStatusHidden = hidden;
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: hidden
              ? (harmony ? const [SystemUiOverlay.bottom] : const [])
              : SystemUiOverlay.values,
        );
      }
    }
    readerControls
        .invokeMethod<void>('apply', {
          'volumePaging':
              volumePaging &&
              active &&
              pageKeysActive &&
              state.readerPreferences.volumePaging,
          'brightness': active ? state.readerPreferences.brightness : null,
          'hideStatusBar': active && state.readerPreferences.hideSystemStatus,
        })
        .catchError((Object _) {});
  }

  static bool _requestedAwake = false;

  static void keepScreen(Object owner, bool enabled) {
    if (!readerAppearance) return;
    if (enabled) {
      _awakeOwners.add(owner);
    } else {
      _awakeOwners.remove(owner);
    }
    final awake = _awakeOwners.isNotEmpty;
    if (awake == _requestedAwake) return;
    _requestedAwake = awake;
    // No polling, permanent ticker, global timeout change or wake lock.
    channel.invokeMethod<void>('keepScreenOn', awake).catchError((Object _) {});
  }
}

/// Route/lifecycle notifications rebuild only this zero-size binding, not the
/// article. Reader-owned sheets retain its window appearance but suspend page
/// keys; another page or backgrounding releases the window.
class ReaderScreenBinding extends StatefulWidget {
  const ReaderScreenBinding({
    super.key,
    required this.state,
    this.onPage,
    this.readerOverlayOpen,
  });
  final LibraryState state;
  final ValueChanged<int>? onPage;
  // Read at route/lifecycle changes: opening a sheet need not rebuild the book.
  final ValueGetter<bool>? readerOverlayOpen;
  @override
  State<ReaderScreenBinding> createState() => _ReaderScreenBindingState();
}

class _ReaderScreenBindingState extends State<ReaderScreenBinding>
    with WidgetsBindingObserver {
  bool _foreground = true;
  bool _current = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.readerBehaviorChanges.addListener(_update);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  void _update() {
    final active =
        mounted &&
        _foreground &&
        (_current || widget.readerOverlayOpen?.call() == true);
    LocalPlatform.keepScreen(this, active && widget.state.keepScreenOn);
    LocalPlatform.reader(
      this,
      active: active,
      state: widget.state,
      onPage: widget.onPage,
      pageKeysActive: _current,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _current = ModalRoute.isCurrentOf(context) ?? true;
    _update();
  }

  @override
  void didUpdateWidget(ReaderScreenBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.readerBehaviorChanges.removeListener(_update);
      widget.state.readerBehaviorChanges.addListener(_update);
      _update();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  @override
  void dispose() {
    widget.state.readerBehaviorChanges.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    LocalPlatform.keepScreen(this, false);
    LocalPlatform.reader(this, active: false, state: widget.state);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class ReaderBrightnessGesture extends StatefulWidget {
  const ReaderBrightnessGesture({
    super.key,
    required this.state,
    required this.onChanged,
    this.onExitSwipe,
  });
  final LibraryState state;
  final void Function(ReaderPreferences value, bool persist) onChanged;
  final VoidCallback? onExitSwipe;
  @override
  State<ReaderBrightnessGesture> createState() =>
      _ReaderBrightnessGestureState();
}

class _ReaderBrightnessGestureState extends State<ReaderBrightnessGesture> {
  double? _base;
  double _delta = 0;
  double _horizontal = 0;
  int _ticket = 0;
  int? _lastHapticStep;
  double? _lastHapticValue;
  bool _hasHapticStep = false;
  bool _fineAdjustmentPending = false;
  bool _pointerReleased = false;
  void _apply(bool persist) {
    final base = _base;
    if (base == null || !mounted) return;
    final height = MediaQuery.sizeOf(context).height;
    final brightness = (base - _delta / height).clamp(0.0, 1.0);
    final step = (brightness * 20).round();
    final previous = _lastHapticStep ?? (base * 20).round();
    final boundary =
        (brightness == 0 || brightness == 1) &&
        brightness != (_lastHapticValue ?? base);
    if (step != previous || boundary) {
      _hasHapticStep = true;
      AppHaptics.play(
        context,
        boundary ? HapticCue.boundary : HapticCue.detent,
      );
    }
    _lastHapticStep = step;
    _lastHapticValue = brightness;
    widget.onChanged(
      widget.state.readerPreferences.copyWith(brightness: brightness),
      persist,
    );
  }

  Future<void> _start() async {
    final ticket = ++_ticket;
    _delta = 0;
    _lastHapticStep = null;
    _lastHapticValue = null;
    _hasHapticStep = false;
    _fineAdjustmentPending = false;
    _pointerReleased = false;
    _base = widget.state.readerPreferences.brightness;
    if (_base == null) {
      try {
        final value = await LocalPlatform.readerControls.invokeMethod<double>(
          'brightness',
        );
        if (mounted && ticket == _ticket) {
          _base = value;
          _apply(false);
        }
      } catch (_) {
        /* Without a brightness value, leave the window untouched. */
      }
    }
  }

  void _end({bool cancelled = false}) {
    _fineAdjustmentPending =
        !cancelled &&
        !_hasHapticStep &&
        _base != null &&
        _lastHapticValue != null &&
        _lastHapticValue != _base;
    _apply(true);
    _confirmFineAdjustment();
    _ticket++;
    _base = null;
  }

  void _confirmFineAdjustment() {
    if (!_pointerReleased || !_fineAdjustmentPending) return;
    _fineAdjustmentPending = false;
    AppHaptics.play(context, HapticCue.selection);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, _) {
      final brightness = widget.state.readerPreferences.edgeBrightness;
      final exit = widget.onExitSwipe;
      if (!brightness && exit == null) return const SizedBox.shrink();
      return Listener(
        behavior: HitTestBehavior.translucent,
        // Flutter ends an already-accepted drag on pointer cancellation;
        // keep that path distinct from a deliberate fine-adjust release.
        onPointerCancel: (_) {
          _pointerReleased = false;
          _fineAdjustmentPending = false;
        },
        onPointerUp: (_) {
          _pointerReleased = true;
          _confirmFineAdjustment();
        },
        child: GestureDetector(
          key: const ValueKey('reader-edge-brightness'),
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: brightness ? (_) => _start() : null,
          onVerticalDragUpdate: brightness
              ? (details) {
                  _delta += details.delta.dy;
                  _apply(false);
                }
              : null,
          onVerticalDragEnd: brightness ? (_) => _end() : null,
          onVerticalDragCancel: brightness ? () => _end(cancelled: true) : null,
          onHorizontalDragStart: exit == null ? null : (_) => _horizontal = 0,
          onHorizontalDragUpdate: exit == null
              ? null
              : (details) => _horizontal += details.delta.dx,
          onHorizontalDragEnd: exit == null
              ? null
              : (_) {
                  final accepted = _horizontal >= 36;
                  _horizontal = 0;
                  if (accepted) exit();
                },
          onHorizontalDragCancel: exit == null ? null : () => _horizontal = 0,
        ),
      );
    },
  );
}
