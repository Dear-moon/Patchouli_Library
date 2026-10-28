import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_ui.dart';
import 'app_window_insets.dart';
import 'app_licenses.dart';
import 'catalog.dart';
import 'legacy_cover.dart';
import 'reader_illustrations.dart';
import 'sources/source_repository.dart';
import 'sources/source_store.dart';
import 'sources/source_host_bridge.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_series_actions.dart';
import 'listening/audio_output.dart';
import 'listening/cache.dart';
import 'listening/controller.dart';
import 'listening/store.dart';
import 'listening/custom_tts.dart';
import 'listening/widgets.dart';
import 'native_effects.dart';
import 'network_status.dart';
import 'offline_cache.dart';
import 'offline_repository.dart';
import 'pages.dart';
import 'performance_preferences.dart';
import 'haptic_preferences.dart';
import 'touch_sampling.dart';
import 'updates/app_updates.dart';
import 'updates/update_page.dart';
import 'wenku_features.dart';
import 'lan_reading_sync.dart';
import 'lan_handoff_widgets.dart';
import 'reader_handoff_navigation.dart';
import 'reader_appearance.dart';
import 'app_palette.dart';
import 'book_open_monitor.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  TouchSamplingPolicy(binding);
  // Do not hold the first frame while Android is applying window insets.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final state = await LibraryState.load();
  if (state.appPalette.source == AppPaletteSource.system ||
      !state.appPalette.themedIcon) {
    await state.refreshSystemPalette();
  }
  if (chineseLocale(
        state.language.locale ?? binding.platformDispatcher.locale,
      ).countryCode !=
      'CN') {
    await ChineseText.prepare();
  }
  await state.loadFonts();
  final network = NetworkStatus();
  await network.start();
  if (state.performance.needsRuntimeEffects) await NativeEffects.prepare();
  final brightness = switch (state.theme) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };
  SystemChrome.setSystemUIOverlayStyle(novelSystemUiStyle(brightness));
  final cache = await OfflineCacheStore.forApp();
  final store = await SourceStore.forApp();
  await store.load();
  store.reserveBooks(state.knownNovels);
  final remote = SourceNovelRepository(
    store: store,
    legacyBook: state.cachedNovel,
  );
  LegacyCover.useResolver(remote.cover);
  ReaderIllustrationCache.shared.useResolver(remote.illustration);
  final repository = defaultTargetPlatform == TargetPlatform.android
      ? OfflineNovelRepository(
          remote: remote,
          illustrationRequest: remote.illustration,
          cache: cache,
          local: await LocalBookStore.forApp(),
          network: network,
        )
      : const DemoNovelRepository();
  if (repository is OfflineNovelRepository) {
    ReaderIllustrationCache.shared.offlineReader =
        repository.cache.readIllustration;
  }
  if (repository is OfflineNovelRepository && repository.local != null) {
    await reconcileLocalSeries(repository.local!, state);
  }
  final WenkuFeatures? features = null;
  final customSpeech = defaultTargetPlatform == TargetPlatform.android
      ? CustomSpeechSettings()
      : null;
  await customSpeech?.load();
  final listening = defaultTargetPlatform == TargetPlatform.android
      ? ListeningController(
          repository: repository,
          audio: await SpeechAudioCache.forApp(
            customSpeech: customSpeech,
            network: network,
          ),
          customSpeech: customSpeech,
          store: ListeningStore(await SharedPreferences.getInstance()),
          outputFactory: createListeningOutput,
        )
      : null;
  runApp(
    NovelApp(
      state: state,
      repository: repository,
      features: features,
      listening: listening,
      network: network,
      updates: defaultTargetPlatform == TargetPlatform.android
          ? AppUpdates(preferences: await SharedPreferences.getInstance())
          : null,
    ),
  );
  if (listening != null) {
    // Register media commands without allocating a player or blocking the first
    // frame. A service-created engine also gets a handler, with no auto-play.
    unawaited(prepareListeningService(listening).catchError((Object _) {}));
  }
  if (features != null) unawaited(features.account.initialize());
}

class NovelApp extends StatefulWidget {
  const NovelApp({
    super.key,
    required this.state,
    required this.repository,
    this.features,
    this.listening,
    this.updates,
    this.network,
  });

  final LibraryState state;
  final NovelRepository repository;
  final WenkuFeatures? features;
  final ListeningController? listening;
  final AppUpdates? updates;
  final NetworkStatus? network;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> with WidgetsBindingObserver {
  LibraryState get state => widget.state;
  NovelRepository get repository => widget.repository;
  WenkuFeatures? get features => widget.features;
  ListeningController? get listening => widget.listening;
  AppUpdates? get updates => widget.updates;
  final _updateNavigation = AppUpdateNavigation();
  late final _sourceHost = SourceHostBridge(
    state,
    repository: sourceRepositoryOf(repository),
  );
  GlobalKey<NavigatorState> get _navigator => _sourceHost.navigatorKey;
  final _readerHandoff = ReaderHandoffNavigation();
  late String _lastTypeface = state.appFontId;
  Locale _systemLocale = chineseLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (sourceRepositoryOf(repository) != null) _sourceHost.attach();
    state.settingsChanges.addListener(_orientationChanged);
    _orientationChanged();
    unawaited(_prepareLanSync());
  }

  bool? _portraitApplied;
  void _orientationChanged() {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    final force = state.forcePortrait;
    if (_portraitApplied == force) return;
    _portraitApplied = force;
    unawaited(
      SystemChrome.setPreferredOrientations(
        force ? [DeviceOrientation.portraitUp] : [],
      ),
    );
  }

  @override
  void didUpdateWidget(NovelApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != state) {
      oldWidget.state.settingsChanges.removeListener(_orientationChanged);
      state.settingsChanges.addListener(_orientationChanged);
      _portraitApplied = null;
      _orientationChanged();
    }
  }

  LanReadingSync? _lanSync;
  Future<void> _openLocalBook(Novel book) async {
    final position =
        state.positionFor(book.id) ??
        ReadingPosition(
          chapter: 0,
          chapterId: book.chapters.firstOrNull?.id ?? 0,
          offset: 0,
          fraction: 0,
          fontSize: state.readerFontSizeFor(book.id),
          width: 0,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
    await _readerHandoff.open(
      bookId: book.id,
      position: position,
      page: ReaderPage(
        novel: book,
        state: state,
        repository: repository,
        initialChapter: position.chapter,
        initialPosition: position,
        directEntry: true,
      ),
      reduceMotion: state.reduceMotion,
    );
  }

  Future<void> _continueNearbyBook(LanHandoffReceipt receipt) async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null || !context.mounted) {
      throw const FormatException('阅读器暂未准备好，请重试');
    }
    final book = _lanSync?.books?.book(receipt.book.id);
    if (book == null) {
      throw const FormatException('这本书已从本机移除，请重新接收');
    }
    await _readerHandoff.open(
      bookId: book.id,
      position: receipt.position,
      page: ReaderPage(
        novel: book,
        state: state,
        repository: repository,
        initialChapter: receipt.position.chapter,
        initialPosition: receipt.position,
        directEntry: true,
      ),
      reduceMotion: state.reduceMotion,
    );
    if (identical(_lanSync?.handoff.received, receipt)) {
      _lanSync?.handoff.dismissReceipt();
    }
  }

  Widget _nearbyNotice(Widget notice) => AnimatedBuilder(
    animation: _readerHandoff,
    child: notice,
    builder: (context, child) {
      final id = _readerHandoff.currentBookId;
      return id == null
          ? child!
          : ReaderAppearance(
              state: state,
              appTheme: Theme.of(context),
              bookId: id,
              child: child!,
            );
    },
  );

  Future<void> _prepareLanSync() async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        repository is! OfflineNovelRepository) {
      return;
    }
    final sync = LanReadingSync(
      state: state,
      preferences: await SharedPreferences.getInstance(),
      books: (repository as OfflineNovelRepository).local,
    );
    if (!mounted) {
      sync.dispose();
      return;
    }
    setState(() => _lanSync = sync);
    await sync.initialize();
  }

  @override
  Future<void> didChangeLocales(List<Locale>? locales) async {
    final ticket = ++_localeRequest;
    final next = chineseLocale(locales?.firstOrNull);
    if (state.language == AppLanguage.system && next.countryCode != 'CN') {
      await ChineseText.prepare();
    }
    if (mounted && ticket == _localeRequest) {
      setState(() => _systemLocale = next);
    }
  }

  int _localeRequest = 0;

  Object? _themeKey;
  final _themes = <Brightness, ThemeData>{};
  ThemeData _theme(Brightness brightness) {
    final key = (
      defaultTargetPlatform,
      state.appFontId,
      state.appPalette.source,
      state.appPalette.seed,
      state.systemTonalColors?.signature,
    );
    if (_themeKey != key) {
      _themeKey = key;
      _themes.clear();
    }
    return _themes.putIfAbsent(
      brightness,
      () => novelTheme(
        brightness,
        fontFamily: state.appFontFamily,
        palette: state.appPalette,
        systemColors: state.systemTonalColors,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed &&
        state.appPalette.source == AppPaletteSource.system) {
      unawaited(state.refreshSystemPalette());
    }
  }

  @override
  void dispose() {
    state.settingsChanges.removeListener(_orientationChanged);
    WidgetsBinding.instance.removeObserver(this);
    features?.shelfSync?.dispose();
    _updateNavigation.dispose();
    if (sourceRepositoryOf(repository) != null) _sourceHost.dispose();
    _readerHandoff.dispose();
    _lanSync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state.applicationChanges,
      builder: (context, child) {
        final typefaceChanged = _lastTypeface != state.appFontId;
        _lastTypeface = state.appFontId;
        return MaterialApp(
          navigatorKey: _navigator,
          title: '帕秋莉图书馆',
          locale: state.language.locale ?? _systemLocale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'HK'),
            Locale('zh', 'TW'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          localeResolutionCallback: (locale, _) =>
              chineseLocale(state.language.locale ?? locale),
          navigatorObservers: [_updateNavigation, _sourceHost, _readerHandoff],
          debugShowCheckedModeBanner: false,
          scrollBehavior: const NovelScrollBehavior(),
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: state.theme,
          themeAnimationDuration:
              typefaceChanged ||
                  state.effectiveReduceMotion ||
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
              ? Duration.zero
              : NovelMotion.enter,
          themeAnimationCurve: NovelMotion.ease,
          builder: (context, child) => AppWindowInsets(
            child: Builder(
              builder: (context) {
                final media = MediaQuery.of(context);
                final content = PerformanceScope(
                  preferences: state.performance,
                  explicitReduceMotion:
                      media.disableAnimations || state.reduceMotion,
                  child: MediaQuery(
                    data: media.copyWith(
                      disableAnimations:
                          media.disableAnimations ||
                          state.effectiveReduceMotion,
                    ),
                    child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: novelSystemUiStyle(Theme.of(context).brightness),
                      child: AnimatedBuilder(
                        animation: state.glassChanges,
                        child: child,
                        builder: (context, child) => GlassAppearance(
                          blur: state.glassBlur,
                          opacity: state.glassOpacity,
                          child: ListeningScope(
                            controller: listening,
                            child: LanSyncScope(
                              sync: _lanSync,
                              child: WenkuFeaturesScope(
                                features: features,
                                child: ReaderHandoffScope(
                                  navigation: _readerHandoff,
                                  child: LanHandoffMonitor(
                                    handoff: _lanSync?.handoff,
                                    onContinue: _continueNearbyBook,
                                    reduceMotion: state.effectiveReduceMotion,
                                    noticeWrapper: _nearbyNotice,
                                    child: child!,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                return HapticScope(
                  preferences: state.haptics,
                  child: updates == null
                      ? content
                      : AppUpdateMonitor(
                          updates: updates!,
                          navigation: _updateNavigation,
                          child: content,
                        ),
                );
              },
            ),
          ),
          home: Builder(
            builder: (context) {
              // A newly attached Android surface can report a zero-sized view.
              // Do not create a glass geometry texture until metrics are ready.
              if (MediaQuery.sizeOf(context).isEmpty) {
                return const SizedBox.shrink();
              }
              final home = RepaintBoundary(
                child: HomeShell(
                  state: state,
                  repository: repository,
                  network: widget.network,
                ),
              );
              final repo = repository;
              return defaultTargetPlatform == TargetPlatform.android &&
                      repo is OfflineNovelRepository &&
                      repo.local != null
                  ? BookOpenMonitor(
                      books: repo.local!,
                      library: state,
                      onOpen: _openLocalBook,
                      child: home,
                    )
                  : home;
            },
          ),
        );
      },
    );
  }
}
