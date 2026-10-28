import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_ui.dart';
import 'app_interactions.dart';
import 'app_window_insets.dart';
import 'app_licenses.dart';
import 'app_repository.dart';
import 'catalog.dart';
import 'legacy_wenku_repository.dart';
import 'library_state.dart';
import 'local_platform.dart';
import 'local_series_actions.dart';
import 'listening/audio_output.dart';
import 'listening/cache.dart';
import 'listening/controller.dart';
import 'listening/store.dart';
import 'listening/custom_tts.dart';
import 'listening/widgets.dart';
import 'native_effects.dart';
import 'network_status.dart';
import 'offline_repository.dart';
import 'pages.dart';
import 'performance_preferences.dart';
import 'haptic_preferences.dart';
import 'touch_sampling.dart';
import 'updates/app_updates.dart';
import 'updates/ios_update_platform.dart';
import 'updates/harmony_update_platform.dart';
import 'updates/update_page.dart';
import 'wenku_account.dart';
import 'wenku_features.dart';
import 'wenku_shelf_sync.dart';
import 'publication_catalog.dart';
import 'lan_reading_sync.dart';
import 'lan_handoff_widgets.dart';
import 'reader_handoff_navigation.dart';
import 'reader_appearance.dart';
import 'reader_illustrations.dart';
import 'app_palette.dart';
import 'book_open_monitor.dart';
import 'reading_widget_controller.dart';
import 'reading_widget_cards.dart';
import 'reading_widget_settings_page.dart';
import 'bookmark_library_page.dart';
import 'reading_statistics_page.dart';
import 'reading_moments_ui.dart';

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
  final WenkuAccount? account = LocalPlatform.fileActions
      ? WenkuAccount()
      : null;
  const remote = LegacyWenkuRepository();
  final repository = LocalPlatform.fileActions
      ? await openApplicationLibrary(remote: remote, network: network)
      : const DemoNovelRepository();
  if (repository is OfflineNovelRepository) {
    ReaderIllustrationCache.shared.offlineReader =
        repository.cache.readIllustration;
  }
  if (repository is OfflineNovelRepository && repository.local != null) {
    await reconcileLocalSeries(repository.local!, state);
  }
  final features = account != null
      ? WenkuFeatures(
          account: account,
          // The authenticated novellist response already contains book metadata.
          // Reuse its adapter, pagination and the existing account session.
          publications: remote as PublicationCatalog,
          shelfSync: WenkuShelfSync(
            account: account,
            library: state,
            preferences: await SharedPreferences.getInstance(),
            network: network,
          )..start(),
        )
      : null;
  final customSpeech = LocalPlatform.listening ? CustomSpeechSettings() : null;
  await customSpeech?.load();
  final listening = LocalPlatform.listening
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
          : LocalPlatform.ios
          ? AppUpdates(
              preferences: await SharedPreferences.getInstance(),
              platform: IOSUpdatePlatform(),
              packageUpdates: false,
            )
          : LocalPlatform.harmony
          ? AppUpdates(
              preferences: await SharedPreferences.getInstance(),
              platform: HarmonyUpdatePlatform(),
              packageUpdates: false,
            )
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
  final _navigator = GlobalKey<NavigatorState>();
  final _home = GlobalKey<HomeShellState>();
  final _readerHandoff = ReaderHandoffNavigation();
  late ReadingWidgetController _readingWidgets =
      ReadingWidgetController.forState(state);
  late ReadingWidgetCards _widgetCards = ReadingWidgetCards.forState(state);
  bool _startupWidgetReady = false, _widgetRouteQueued = false;
  String? _widgetDestination;
  String? _activeWidgetConfiguration;
  bool _returningFromWidgetConfiguration = false;
  late String _lastTypeface = state.appFontId;
  Locale _systemLocale = chineseLocale(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  bool _startupReadingConsumed = false;
  bool _startupInboxReady = false, _startupUpdatesReady = false;
  bool _startupReadingQueued = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.settingsChanges.addListener(_orientationChanged);
    _orientationChanged();
    _startupReadingConsumed = !state.openRecentOnLaunch;
    _updateNavigation.addListener(_queueStartupReading);
    updates?.addListener(_queueStartupReading);
    if (!_startupReadingConsumed) unawaited(_prepareStartupReading());
    unawaited(_prepareLanSync());
    unawaited(
      _readingWidgets.attach().then((_) {
        if (mounted) return _widgetCards.attach();
      }),
    );
    unawaited(_prepareReadingWidgets());
  }

  Future<void> _prepareReadingWidgets() async {
    try {
      await ReadingWidgetBridge.start(_readingWidgetRequested);
    } on PlatformException {
      // A widget inbox failure does not block normal startup or file opening.
    } finally {
      if (mounted) {
        setState(() => _startupWidgetReady = true);
        _queueStartupReading();
        _queueReadingWidgetRoute();
      }
    }
  }

  void _readingWidgetRequested(String destination) {
    _startupReadingConsumed = true;
    _widgetDestination = destination;
    _queueReadingWidgetRoute();
  }

  void _queueReadingWidgetRoute() {
    if (!mounted || _widgetDestination == null || _widgetRouteQueued) return;
    _widgetRouteQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetRouteQueued = false;
      if (!mounted || _widgetDestination == null) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      final context = _navigator.currentState?.overlay?.context;
      if (context == null) {
        _queueReadingWidgetRoute();
        return;
      }
      final destination = _widgetDestination!;
      _widgetDestination = null;
      if (destination.startsWith('configure:')) {
        unawaited(_configureWidget(context, destination.substring(10)));
      } else if (destination == 'excerpts') {
        unawaited(
          pushNovelPage<void>(
            context,
            BookmarkLibraryPage(state: state, repository: repository),
            reduceMotion: state.reduceMotion,
            slot: ('reading-widget', destination),
          ),
        );
      } else if (destination == 'continue') {
        unawaited(_continueFromWidget(context));
      } else if (destination == 'moments') {
        unawaited(
          showReadingMomentsHistory(
            context,
            store: state.readingMoments,
            reduceMotion: state.reduceMotion,
          ),
        );
      } else {
        unawaited(
          pushNovelPage<void>(
            context,
            ReadingStatisticsPage(state: state, repository: repository),
            reduceMotion: state.reduceMotion,
            slot: ('reading-widget', destination),
          ),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _configureWidget(BuildContext context, String id) async {
    if (_activeWidgetConfiguration == id) return;
    setState(() => _activeWidgetConfiguration = id);
    final confirmed = await pushNovelPage<bool>(
      context,
      ReadingWidgetSettingsPage(state: state, bindTo: id),
      reduceMotion: state.reduceMotion,
      slot: ('reading-widget-configuration', id),
    );
    if (!mounted) return;
    if (!LocalPlatform.android) {
      setState(() => _activeWidgetConfiguration = null);
      return;
    }
    _returningFromWidgetConfiguration = true;
    try {
      await ReadingWidgetBridge.channel.invokeMethod<void>(
        'completeConfiguration',
        {'widgetId': id, 'confirmed': confirmed == true},
      );
    } on PlatformException {
      _returningFromWidgetConfiguration = false;
      if (context.mounted) showNovelFeedback(context, '桌面配置未能完成，请重新添加');
    } finally {
      if (mounted) setState(() => _activeWidgetConfiguration = null);
    }
  }

  Future<void> _continueFromWidget(BuildContext context) async {
    final id = state.readingHistoryIds.firstOrNull;
    if (id == null) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
      _home.currentState?.openShelf();
      return;
    }
    final book =
        state.cachedNovel(id) ??
        Novel(
          id: id,
          title: '书籍 $id',
          author: '',
          genre: '',
          summary: '',
          colors: const [Colors.grey, Colors.black],
        );
    final position = state.positionFor(id);
    final page = ReaderLoaderPage(
      novel: book,
      state: state,
      repository: repository,
    );
    try {
      if (position != null && _readerHandoff.hasReader) {
        await _readerHandoff.open(
          bookId: id,
          position: position,
          page: page,
          reduceMotion: state.reduceMotion,
        );
      } else {
        // The route slot also deduplicates taps while the catalogue is loading.
        unawaited(
          pushNovelPage<void>(
            context,
            page,
            reduceMotion: state.reduceMotion,
            slot: ('widget-reading', id),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书页暂未打开，请重试');
    }
  }

  Future<void> _prepareStartupReading() async {
    final service = updates;
    try {
      await service?.loadInstalled();
    } catch (_) {
      // Installed-version metadata must not prevent an otherwise usable reader.
    }
    if (!mounted || !identical(service, updates)) return;
    _startupUpdatesReady = true;
    _queueStartupReading();
  }

  void _initialBookInboxSettled(bool hadRequest) {
    if (_startupReadingConsumed) return;
    _startupInboxReady = true;
    if (hadRequest) {
      // A system file-open is the user's explicit launch destination.
      _bookOpenRequested();
      return;
    }
    _queueStartupReading();
  }

  void _bookOpenRequested() {
    // Warm file intents can arrive while release notes are delaying startup.
    _startupReadingConsumed = true;
  }

  void _queueStartupReading() {
    if (!mounted || _startupReadingConsumed || _startupReadingQueued) return;
    if (_updateNavigation.hasPageBeyondRoot) {
      _startupReadingConsumed = true;
      return;
    }
    _startupReadingQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupReadingQueued = false;
      if (!mounted || _startupReadingConsumed) return;
      if (!state.openRecentOnLaunch || _updateNavigation.hasPageBeyondRoot) {
        _startupReadingConsumed = true;
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!_startupInboxReady ||
          !_startupWidgetReady ||
          !_startupUpdatesReady ||
          lifecycle != null && lifecycle != AppLifecycleState.resumed ||
          !_updateNavigation.rootReady ||
          updates?.shouldShowReleaseNotes == true) {
        return;
      }
      _startupReadingConsumed = true;
      final id = state.readingHistoryIds.firstOrNull;
      if (id == null) return;
      final book =
          state.cachedNovel(id) ??
          Novel(
            id: id,
            title: '书籍 $id',
            author: '',
            genre: '',
            summary: '',
            colors: const [Colors.grey, Colors.black],
          );
      unawaited(
        pushNovelPage<void>(
          _navigator.currentState!.overlay!.context,
          ReaderLoaderPage(novel: book, state: state, repository: repository),
          reduceMotion: state.reduceMotion,
          slot: ('startup-reading', id),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool? _portraitApplied;
  void _orientationChanged() {
    if (!LocalPlatform.readerAppearance) return;
    final force = state.forcePortrait;
    if (_portraitApplied == force) return;
    _portraitApplied = force;
    unawaited(
      SystemChrome.setPreferredOrientations(
        force
            ? [DeviceOrientation.portraitUp]
            // Flutter-OH maps an empty list to UNSPECIFIED, which leaves the
            // main window portrait. All four enables system-lock-aware rotation.
            : LocalPlatform.harmony
            ? DeviceOrientation.values
            : [],
      ),
    );
  }

  @override
  void didUpdateWidget(NovelApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != state) {
      _widgetCards.dispose();
      _widgetCards = ReadingWidgetCards.forState(state);
      unawaited(_widgetCards.attach());
      _readingWidgets.dispose();
      _readingWidgets = ReadingWidgetController.forState(state);
      unawaited(_readingWidgets.attach());
      _startupReadingConsumed = true;
      oldWidget.state.settingsChanges.removeListener(_orientationChanged);
      state.settingsChanges.addListener(_orientationChanged);
      _portraitApplied = null;
      _orientationChanged();
    }
    if (oldWidget.updates != updates) {
      oldWidget.updates?.removeListener(_queueStartupReading);
      updates?.addListener(_queueStartupReading);
      if (!_startupReadingConsumed) {
        _startupUpdatesReady = false;
        unawaited(_prepareStartupReading());
      }
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
    final handoff = _lanSync?.handoff;
    if (handoff == null) {
      throw const FormatException('局域网续读暂未准备好，请重试');
    }
    final resolved = await handoff.resolveReceipt(receipt);
    if (!mounted || !context.mounted || !identical(handoff.received, receipt)) {
      throw const FormatException('续读提醒已更新，请重新选择');
    }
    final book = resolved.book;
    await state.rememberNovel(book);
    if (!mounted || !context.mounted || !identical(handoff.received, receipt)) {
      return;
    }
    await _readerHandoff.open(
      bookId: book.id,
      position: resolved.position,
      reuseCurrentReader: receipt.online == null,
      page: ReaderPage(
        novel: book,
        state: state,
        repository: repository,
        initialChapter: resolved.position.chapter,
        initialPosition: resolved.position,
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
    if (!LocalPlatform.nearbyReading || repository is! OfflineNovelRepository) {
      return;
    }
    final sync = LanReadingSync(
      state: state,
      preferences: await SharedPreferences.getInstance(),
      books: (repository as OfflineNovelRepository).local,
      repository: repository,
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
    if (_returningFromWidgetConfiguration &&
        (lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.hidden ||
            lifecycle == AppLifecycleState.resumed)) {
      setState(() => _returningFromWidgetConfiguration = false);
    }
    if (lifecycle == AppLifecycleState.resumed) _queueStartupReading();
    if (lifecycle == AppLifecycleState.resumed) _queueReadingWidgetRoute();
    // The reader settles its final eligible interval in this same lifecycle
    // dispatch. Publish on the next event turn, after its ledger microtasks.
    if (lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.hidden) {
      unawaited(Future<void>.delayed(Duration.zero, _readingWidgets.publish));
    }
    if (lifecycle == AppLifecycleState.resumed &&
        state.appPalette.source == AppPaletteSource.system) {
      unawaited(state.refreshSystemPalette());
    }
  }

  @override
  void dispose() {
    _widgetCards.dispose();
    state.settingsChanges.removeListener(_orientationChanged);
    WidgetsBinding.instance.removeObserver(this);
    features?.shelfSync?.dispose();
    _updateNavigation.dispose();
    updates?.removeListener(_queueStartupReading);
    _readerHandoff.dispose();
    _lanSync?.dispose();
    _readingWidgets.dispose();
    ReadingWidgetBridge.stop();
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
          title: '轻小说文库',
          locale: state.language.locale ?? _systemLocale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'HK'),
            Locale('zh', 'TW'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          localeResolutionCallback: (locale, _) =>
              chineseLocale(state.language.locale ?? locale),
          navigatorObservers: [_updateNavigation, _readerHandoff],
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
                          promptsEnabled:
                              _startupWidgetReady &&
                              _activeWidgetConfiguration == null &&
                              !_returningFromWidgetConfiguration,
                          child: content,
                        ),
                );
              },
            ),
          ),
          // Match detail routes from the first page onward. Mixing Material's
          // root route with Cupertino detail routes inserts/removes a delegated
          // transition wrapper and reparents the entire retained home subtree.
          // Keep Navigator's default initial-route/deep-link fallback logic.
          onGenerateRoute: (settings) =>
              settings.name == Navigator.defaultRouteName
              ? softRoute<void>(
                  Builder(
                    builder: (context) {
                      // A newly attached Android surface can report a zero-sized view.
                      // Do not create a glass geometry texture until metrics are ready.
                      if (MediaQuery.sizeOf(context).isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final home = RepaintBoundary(
                        child: HomeShell(
                          key: _home,
                          state: state,
                          repository: repository,
                          network: widget.network,
                        ),
                      );
                      final repo = repository;
                      if (LocalPlatform.fileActions &&
                          repo is OfflineNovelRepository &&
                          repo.local != null) {
                        return BookOpenMonitor(
                          books: repo.local!,
                          library: state,
                          onOpen: _openLocalBook,
                          onInitialInboxSettled: _initialBookInboxSettled,
                          onOpenRequested: _bookOpenRequested,
                          child: home,
                        );
                      }
                      _initialBookInboxSettled(false);
                      return home;
                    },
                  ),
                  settings: settings,
                )
              : null,
        );
      },
    );
  }
}
