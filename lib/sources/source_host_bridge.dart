import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_interactions.dart';
import '../app_ui.dart';
import '../library_state.dart';
import 'source_platform.dart';
import 'book_source.dart';
import 'book_platform.dart';
import 'source_pages.dart';
import 'source_repository.dart';
import 'source_fields.dart';

/// Script UI uses existing app notices/sheets, never a separate design system.
class SourceHostBridge extends NavigatorObserver with WidgetsBindingObserver {
  SourceHostBridge(this.state, {this.repository});
  final LibraryState state;
  final SourceNovelRepository? repository;
  final navigatorKey = GlobalKey<NavigatorState>();
  final _routes = <Route<dynamic>>[];
  Future<void> _queue = Future.value();
  final _cancelled = <String>{};
  final _pending = <String>{};
  final _open = <String, BuildContext>{};
  Completer<bool>? _resumed;
  bool _attached = false;
  String? _accountSource;

  Future<bool> _foreground() async {
    if (!_attached) return false;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return true;
    }
    final waiter = _resumed ??= Completer<bool>();
    try {
      // A native verification window can finish before Flutter's onResume.
      // Wait for that handoff, never bring the app to the foreground ourselves.
      return await waiter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
    } finally {
      if (identical(_resumed, waiter)) _resumed = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumed?.complete(true);
      _resumed = null;
      unawaited(_verifyAccounts());
    } else if (state == AppLifecycleState.paused) {
      unawaited(repository?.platform.pauseConnections());
    } else if (state == AppLifecycleState.detached) {
      _resumed?.complete(false);
      _resumed = null;
    }
  }

  void _accountSourceChanged() {
    final source = repository?.discoverySource;
    if (_accountSource == source?.key) return;
    _accountSource = source?.key;
    unawaited(_verifyAccounts());
  }

  Future<void> _verifyAccounts() async {
    final repo = repository;
    if (repo == null) return;
    final selected = repo.discoverySource;
    final sources = [
      ?selected,
      for (final platform in bookPlatforms(repo.enabled, includeWenku: false))
        if (platform.key != bookPlatformKey(selected?.key))
          platform.sources.first,
    ];
    for (final source in sources) {
      try {
        await repo.ensureAccount(source);
      } on SourceFailure catch (failure) {
        // One unavailable platform must not prevent other saved accounts from restoring.
        debugPrint('Source account verification: ${failure.message}');
      }
    }
  }

  void _dismissCancelled() {
    for (final entry in _open.entries) {
      final context = entry.value;
      if (_cancelled.contains(entry.key) &&
          context.mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
        break;
      }
    }
  }

  BuildContext? get _context => _routes.reversed
      .whereType<ModalRoute<dynamic>>()
      .where((r) => r.isCurrent)
      .map((r) => r.subtreeContext)
      .whereType<BuildContext>()
      .firstOrNull;

  void attach() {
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    SourcePlatform.environmentProvider = environment;
    SourcePlatform.channel.setMethodCallHandler(_handle);
    repository?.addListener(_accountSourceChanged);
    _accountSource = repository?.discoverySource?.key;
    unawaited(_verifyAccounts());
  }

  void dispose() {
    _attached = false;
    repository?.removeListener(_accountSourceChanged);
    WidgetsBinding.instance.removeObserver(this);
    _resumed?.complete(false);
    _resumed = null;
    SourcePlatform.environmentProvider = null;
    SourcePlatform.channel.setMethodCallHandler(null);
  }

  Map<String, dynamic> environment() {
    final dark =
        state.theme == ThemeMode.dark ||
        state.theme == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark;
    final reader = state.readerPreferences;
    final context = _context;
    final theme = context != null && context.mounted
        ? Theme.of(context)
        : novelTheme(
            dark ? Brightness.dark : Brightness.light,
            fontFamily: state.appFontFamily,
          );
    return {
      'themeMode': switch (state.theme) {
        ThemeMode.system => '0',
        ThemeMode.light => '1',
        ThemeMode.dark => '2',
      },
      'reader': {
        ...reader.toJson(),
        'textSize': state.fontSize,
        'lineSpacingExtra': (state.lineHeight - 1) * state.fontSize,
        'lineSpacingMultiplier': state.lineHeight,
        'textIndent': reader.indent ? 2 : 0,
        'textJustify': reader.justify,
        'paddingLeft': reader.leftMargin,
        'paddingRight': reader.rightMargin,
        'paddingTop': reader.marginTop,
        'paddingBottom': reader.marginBottom,
        'paragraphSpacing': reader.paragraphGap,
        'fontName': state.readerFontId,
        'hideStatusBar': reader.hideSystemStatus,
      },
      'theme': {
        'isNight': dark,
        'backgroundColor': theme.scaffoldBackgroundColor.toARGB32(),
        'primaryColor': theme.colorScheme.primary.toARGB32(),
        'accentColor': theme.colorScheme.primary.toARGB32(),
        'textColor': theme.colorScheme.onSurface.toARGB32(),
        'glassOpacity': state.glassOpacity,
      },
    };
  }

  Future<dynamic> _handle(MethodCall call) async {
    final data = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
    final id = data['id']?.toString() ?? '';
    if (call.method == 'downloadProgress') {
      SourcePlatform.reportDownloadProgress(data);
      return null;
    }
    if (call.method == 'accountChanged') {
      repository?.refreshAccount(data['source'] as String);
      return null;
    }
    if (call.method == 'sessionUpdated') {
      final source = repository?.store.source(data['source']?.toString());
      if (source != null && source.enabled) {
        unawaited(repository!.loginFinished(source));
      } else {
        repository?.sessionChanged();
      }
      return null;
    }
    if (call.method == 'cancelPrompt') {
      if (!_pending.contains(id)) return null;
      _cancelled.add(id);
      _dismissCancelled();
      return null;
    }
    final context = _context;
    if (call.method == 'notice') {
      if (context?.mounted == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        showNovelFeedback(context!, data['message']?.toString() ?? '');
      }
      return null;
    }
    if (call.method != 'captcha' && call.method != 'confirmOpenUrl') {
      throw MissingPluginException();
    }
    _pending.add(id);
    final result = Completer<dynamic>();
    _queue = _queue.catchError((Object _) {}).then((_) async {
      try {
        if (_cancelled.remove(id)) {
          result.complete(null);
          return;
        }
        final foreground = await _foreground();
        if (_cancelled.remove(id)) {
          result.complete(null);
          return;
        }
        final context = _context;
        if (context == null ||
            !context.mounted ||
            !foreground ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          result.completeError(
            PlatformException(code: 'NO_FOREGROUND', message: '请在应用前台完成书源验证'),
          );
          return;
        }
        if (call.method == 'captcha') {
          final bytes = data['image'];
          if (bytes is! Uint8List || bytes.isEmpty) {
            throw const FormatException('验证码图片为空');
          }
          final code = await showJellySheet<String>(
            context: context,
            reduceMotion: state.effectiveReduceMotion,
            builder: (sheet) {
              _open[id] = sheet;
              return SourceCaptchaInput(
                image: bytes,
                sourceName: data['source']?.toString() ?? '书源',
              );
            },
          );
          result.complete(code);
        } else {
          final source = data['source']?.toString() ?? '书源';
          final url = data['url']?.toString() ?? '';
          final uri = Uri.tryParse(url);
          final importUrl =
              uri != null &&
                  const ['legado', 'yuedu'].contains(uri.scheme) &&
                  (uri.host == 'booksource' ||
                      uri.path.toLowerCase().endsWith('/booksource'))
              ? uri.queryParameters['src']
              : null;
          // Keep this sheet's context for request cancellation as well.
          final confirmed = await showJellySheet<bool>(
            context: context,
            reduceMotion: state.effectiveReduceMotion,
            builder: (sheet) {
              _open[id] = sheet;
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppText(
                      '打开外部应用？',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppText('「$source」请求打开以下地址：'),
                    const SizedBox(height: 8),
                    AppText(url, maxLines: 5, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 24),
                    GlassTextButton(
                      onPressed: () => Navigator.pop(sheet, true),
                      child: const AppText('继续打开'),
                    ),
                    const SizedBox(height: 8),
                    GlassTextButton(
                      onPressed: () => Navigator.pop(sheet, false),
                      child: const AppText('取消'),
                    ),
                  ],
                ),
              );
            },
          );
          if (confirmed == true && importUrl != null && repository != null) {
            final target = Uri.tryParse(importUrl);
            if (target == null ||
                !const ['https', 'http'].contains(target.scheme)) {
              throw const FormatException('书源导入地址必须为 HTTP 或 HTTPS');
            }
            final text = await repository!.platform.fetchImport(importUrl);
            if (context.mounted) {
              await previewSourceRules(
                context,
                repository!,
                text,
                reduceMotion: state.effectiveReduceMotion,
              );
            }
            result.complete(false); // Handled inside this app, not ACTION_VIEW.
          } else {
            result.complete(confirmed == true);
          }
        }
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _open.remove(id);
        _cancelled.remove(id);
        _pending.remove(id);
      }
    });
    return result.future;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    WidgetsBinding.instance.addPostFrameCallback((_) => _dismissCancelled());
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) return;
    final index = _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

class SourceCaptchaInput extends StatefulWidget {
  const SourceCaptchaInput({
    super.key,
    required this.image,
    required this.sourceName,
  });
  final Uint8List image;
  final String sourceName;
  @override
  State<SourceCaptchaInput> createState() => _SourceCaptchaInputState();
}

class _SourceCaptchaInputState extends State<SourceCaptchaInput> {
  final _text = TextEditingController();
  void _submit() {
    final value = _text.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppText(
            '图片验证',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          AppText(
            widget.sourceName,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Image.memory(
              widget.image,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Center(child: AppText('验证码图片无法读取，请返回后重试')),
            ),
          ),
          const SizedBox(height: 20),
          sourceField(
            context,
            '验证码',
            _text,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          GlassTextButton(onPressed: _submit, child: const AppText('确认')),
          const SizedBox(height: 8),
          GlassTextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('取消'),
          ),
        ],
      ),
    ),
  );
}
