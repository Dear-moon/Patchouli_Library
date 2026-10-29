import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'book_identity.dart';
import 'reader_preferences.dart';
import 'reader_book_style.dart';
import 'library_backup.dart';
import 'performance_preferences.dart';
import 'haptic_preferences.dart';
import 'app_typography.dart';
import 'font_catalog.dart';
import 'app_language.dart';
import 'local_library_preferences.dart';
import 'local_import_options.dart';
import 'user_fonts.dart';
import 'illustration_placement.dart';
import 'personal_images.dart';
import 'app_palette.dart';
import 'palette_platform.dart';
import 'reading_entry.dart';
import 'blocked_tags.dart';
import 'book_grid_density.dart';
import 'book_collection_mode.dart';
import 'book_shelf_preferences.dart';
import 'book_shelf_content_preferences.dart';
import 'discovery_shelf_query.dart';
import 'reader_underline.dart';
import 'reader_annotation_range.dart';
import 'reading_activity.dart';
import 'reading_moments.dart';
export 'reading_entry.dart';

class ReadingPosition {
  const ReadingPosition({
    required this.chapter,
    required this.chapterId,
    required this.offset,
    required this.fraction,
    required this.fontSize,
    required this.width,
    required this.updatedAt,
    this.lineHeight = 1.72,
    this.paragraphIndex,
    this.paragraphFraction = 0,
    this.textOffset,
    this.textScale = 1,
    this.typeface = 'system',
    this.layout = '',
    this.contentRevision = '',
  });
  final int chapter;
  final int chapterId;
  final double offset;
  final double fraction;
  final double fontSize;
  final double width;
  final int updatedAt;
  final double lineHeight;
  final int? paragraphIndex;
  final double paragraphFraction;

  /// UTF-16 position inside the original paragraph, independent of layout.
  final int? textOffset;
  final double textScale;
  final String typeface;
  final String layout;
  final String contentRevision;

  Map<String, Object> toJson() => {
    'chapter': chapter,
    'chapterId': chapterId,
    'offset': offset,
    'fraction': fraction,
    'fontSize': fontSize,
    'width': width,
    'updatedAt': updatedAt,
    'lineHeight': lineHeight,
    'paragraphIndex': ?paragraphIndex,
    'paragraphFraction': paragraphFraction,
    'textOffset': ?textOffset,
    'textScale': textScale,
    'typeface': typeface,
    if (layout.isNotEmpty) 'layout': layout,
    if (contentRevision.isNotEmpty) 'contentRevision': contentRevision,
  };

  factory ReadingPosition.fromJson(Map<String, dynamic> value) {
    double number(String key, double fallback) {
      final number = value[key];
      return number is num && number.isFinite ? number.toDouble() : fallback;
    }

    return ReadingPosition(
      chapter: value['chapter'] is int
          ? (value['chapter'] as int).clamp(0, 100000)
          : 0,
      chapterId: value['chapterId'] is int ? value['chapterId'] : 0,
      offset: number('offset', 0).clamp(0, double.infinity),
      fraction: number('fraction', 0).clamp(0, 1),
      fontSize: number('fontSize', 19),
      width: number('width', 0),
      updatedAt: value['updatedAt'] is int ? value['updatedAt'] : 0,
      lineHeight: number('lineHeight', 1.72).clamp(1.3, 2.2),
      paragraphIndex:
          value['paragraphIndex'] is int && value['paragraphIndex'] >= 0
          ? value['paragraphIndex']
          : null,
      paragraphFraction: number('paragraphFraction', 0).clamp(0, 1),
      textOffset: value['textOffset'] is int && value['textOffset'] >= 0
          ? value['textOffset']
          : null,
      textScale: number('textScale', 1).clamp(.5, 5),
      typeface: validFontChoice(value['typeface'])
          ? value['typeface']
          : 'system',
      layout: value['layout'] is String ? value['layout'] : '',
      contentRevision: value['contentRevision'] is String
          ? value['contentRevision']
          : '',
    );
  }
}

class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.chapterTitle,
    required this.position,
    this.quote = '',
    this.category = '',
    this.categoryAt = 0,
    this.underlineRanges = const [],
    ReaderAnnotationData? annotation,
    this.rangeUpdatedAt = 0,
    this.createdAt,
    this.createdOffsetMinutes,
  }) : _annotation = annotation;
  final String id;
  final String chapterTitle;
  final ReadingPosition position;
  final String quote;
  final String category;
  final int categoryAt;

  /// UTC instant plus the recording-zone offset; legacy marks remain unknown.
  final DateTime? createdAt;
  final int? createdOffsetMinutes;

  /// Empty for ordinary bookmarks; underline selections retain source ranges.
  final List<ReaderUnderlineRange> underlineRanges;
  final ReaderAnnotationData? _annotation;

  /// Missing legacy metadata retains underline semantics only for exact ranges.
  ReaderAnnotationData get annotation =>
      _annotation ??
      (isUnderline
          ? const ReaderAnnotationData()
          : const ReaderAnnotationData(style: ReaderMarkStyle.none));
  final int rangeUpdatedAt;
  String get note => annotation.note;
  String get kindLabel =>
      isUnderline && annotation.style != ReaderMarkStyle.none
      ? annotation.style.label
      : '书签';
  bool get isUnderline => underlineRanges.isNotEmpty;
  ReaderBookmark withCategory(String value, int at) => ReaderBookmark(
    id: id,
    chapterTitle: chapterTitle,
    position: position,
    quote: quote,
    category: value,
    categoryAt: at,
    underlineRanges: underlineRanges,
    annotation: annotation,
    rangeUpdatedAt: rangeUpdatedAt,
    createdAt: createdAt,
    createdOffsetMinutes: createdOffsetMinutes,
  );

  /// Edits appearance/thoughts without changing identity, quote or source anchor.
  ReaderBookmark withAnnotation(ReaderAnnotationData value) => ReaderBookmark(
    id: id,
    chapterTitle: chapterTitle,
    position: position,
    quote: quote,
    category: category,
    categoryAt: categoryAt,
    underlineRanges: underlineRanges,
    annotation: value,
    rangeUpdatedAt: rangeUpdatedAt,
    createdAt: createdAt,
    createdOffsetMinutes: createdOffsetMinutes,
  );

  /// Replaces only source geometry, retaining identity and all personal metadata.
  ReaderBookmark withRange({
    required String chapterTitle,
    required ReadingPosition position,
    required List<ReaderUnderlineRange> ranges,
    required String quote,
    required int updatedAt,
  }) => ReaderBookmark(
    id: id,
    chapterTitle: chapterTitle,
    position: position,
    quote: quote,
    category: category,
    categoryAt: categoryAt,
    underlineRanges: ranges,
    annotation: annotation,
    rangeUpdatedAt: updatedAt,
    createdAt: createdAt,
    createdOffsetMinutes: createdOffsetMinutes,
  );

  ReaderBookmark withCreation(DateTime at, int? offsetMinutes) =>
      ReaderBookmark(
        id: id,
        chapterTitle: chapterTitle,
        position: position,
        quote: quote,
        category: category,
        categoryAt: categoryAt,
        underlineRanges: underlineRanges,
        annotation: annotation,
        rangeUpdatedAt: rangeUpdatedAt,
        createdAt: at.toUtc(),
        createdOffsetMinutes: offsetMinutes,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'chapterTitle': chapterTitle,
    'position': position.toJson(),
    if (quote.isNotEmpty) 'quote': quote,
    if (category.isNotEmpty || categoryAt > 0) 'category': category,
    if (categoryAt > 0) 'categoryAt': categoryAt,
    if (!annotation.isEmpty ||
        isUnderline && annotation.style == ReaderMarkStyle.none)
      'annotation': annotation.toJson(),
    if (rangeUpdatedAt > 0) 'rangeUpdatedAt': rangeUpdatedAt,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (createdAt != null && createdOffsetMinutes != null)
      'createdOffsetMinutes': createdOffsetMinutes!,
    if (isUnderline)
      'underlineRanges': underlineRanges
          .map((range) => range.toJson())
          .toList(),
  };

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['chapterTitle'];
    final position = json['position'];
    final quote = json['quote'] ?? '';
    final category = json['category'] ?? '';
    final createdAt = json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null;
    final createdOffset = json['createdOffsetMinutes'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        position is! Map ||
        quote is! String ||
        quote.length > 12000 ||
        category is! String ||
        category.length > 30 ||
        (json['createdAt'] != null &&
            (createdAt == null || !createdAt.isUtc)) ||
        (createdOffset != null &&
            (createdOffset is! int ||
                createdOffset < -840 ||
                createdOffset > 840 ||
                createdAt == null)) ||
        (json['rangeUpdatedAt'] != null &&
            (json['rangeUpdatedAt'] is! int || json['rangeUpdatedAt'] < 0)) ||
        (json['categoryAt'] != null &&
            (json['categoryAt'] is! int || json['categoryAt'] < 0))) {
      throw const FormatException('Damaged bookmark');
    }
    return ReaderBookmark(
      id: id,
      chapterTitle: title,
      position: ReadingPosition.fromJson(Map<String, dynamic>.from(position)),
      quote: quote,
      category: category,
      categoryAt: json['categoryAt'] ?? 0,
      createdAt: createdAt,
      createdOffsetMinutes: createdOffset,
      annotation: json['annotation'] == null
          ? null
          : ReaderAnnotationData.fromJson(json['annotation']),
      rangeUpdatedAt: json['rangeUpdatedAt'] ?? 0,
      underlineRanges: decodeReaderUnderlineRanges(
        json['underlineRanges'],
        position: position,
      ),
    );
  }
}

class LibraryState extends ChangeNotifier {
  LibraryState(
    this._prefs, {
    UserFontStore? fonts,
    ReaderBackgroundStore? backgrounds,
    PalettePlatform? palettePlatform,
  }) : fonts = fonts ?? UserFontStore(),
       palettePlatform = palettePlatform ?? const PalettePlatform(),
       backgrounds = backgrounds ?? ReaderBackgroundStore() {
    final activity = _prefs.get(ReadingActivityStore.preferenceKey);
    try {
      readingActivity = ReadingActivityStore(
        record: activity is String ? activity : null,
        persist: _persistReadingActivity,
      );
    } on FormatException {
      // Activity is independent of saved positions and original book content.
      readingActivity = ReadingActivityStore(persist: _persistReadingActivity);
    }
    final moments = _prefs.get(ReadingMomentsStore.preferenceKey);
    try {
      readingMoments = ReadingMomentsStore(
        record: moments is String ? moments : null,
        persist: _persistReadingMoments,
      );
    } on FormatException {
      readingMoments = ReadingMomentsStore(persist: _persistReadingMoments);
    }
    _shelf.addAll(
      _preferenceStrings(_prefs.get('shelf'))
          .map(int.tryParse)
          .whereType<int>()
          .where((id) => id > 0 && !isLocalBook(id)),
    );
    _hiddenHistory.addAll(
      _preferenceStrings(
        _prefs.get('reading_history_hidden'),
      ).map(int.tryParse).whereType<int>().where((id) => id > 0),
    );
    // Hidden-local recovery is retired; retained originals are visible again.
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(bookReaderStylePrefix)) {
        final id = int.tryParse(key.substring(bookReaderStylePrefix.length));
        final style = ReaderBookStyle.fromRecord(_prefs.get(key));
        if (id != null && id > 0 && style != null) {
          _bookReaderStyles[id] = style;
        }
      }
      if (key.startsWith('chapter_')) {
        final id = int.tryParse(key.substring('chapter_'.length));
        final value = _prefs.get(key);
        if (id != null && value is int) _chapters[id] = value.clamp(0, 100000);
      }
      if (key.startsWith('shelf_added_')) {
        final id = int.tryParse(key.substring('shelf_added_'.length));
        final value = _prefs.get(key);
        if (id != null && value is int) _added[id] = value;
      }
      if (key.startsWith('novel_meta_')) {
        try {
          final novel = Novel.fromSnapshot(
            jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>,
          );
          _known[novel.id] = novel;
          _persistedNovels[novel.id] = novel;
        } catch (_) {
          // A damaged cache never removes its saved shelf ID or preferences.
        }
      }
      if (key.startsWith('reading_position_')) {
        final id = int.tryParse(key.substring('reading_position_'.length));
        if (id == null) continue;
        try {
          _positions[id] = ReadingPosition.fromJson(
            jsonDecode(_prefs.getString(key)!) as Map<String, dynamic>,
          );
        } catch (_) {
          // The legacy chapter index remains usable without a position record.
        }
      }
      if (key.startsWith('illustration_layout_')) {
        final id = int.tryParse(key.substring('illustration_layout_'.length));
        if (id == null || id <= 0) continue;
        try {
          final records = jsonDecode(_prefs.getString(key)!);
          if (records is! List) continue;
          final placements = <IllustrationPlacement>[];
          final ids = <String>{};
          for (final record in records.take(2000)) {
            try {
              final placement = IllustrationPlacement.fromJson(
                Map<String, dynamic>.from(record as Map),
              );
              if (ids.add(placement.id)) placements.add(placement);
            } catch (_) {
              /* Isolate damaged placement records. */
            }
          }
          _illustrations[id] = placements;
        } catch (_) {
          /* Original chapter text is independent of local layout. */
        }
      }
      if (key.startsWith('reader_bookmarks_')) {
        final id = int.tryParse(key.substring('reader_bookmarks_'.length));
        if (id == null || id <= 0) continue;
        try {
          final records = jsonDecode(_prefs.getString(key)!);
          if (records is! List) continue;
          final bookmarks = <ReaderBookmark>[];
          final ids = <String>{};
          for (final record in records) {
            try {
              final bookmark = ReaderBookmark.fromJson(
                Map<String, dynamic>.from(record as Map),
              );
              if (ids.add(bookmark.id)) bookmarks.add(bookmark);
            } catch (_) {
              // One damaged bookmark does not erase the remaining marks.
            }
          }
          bookmarks.sort(
            (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
          );
          _bookmarks[id] = bookmarks;
          _updateUnderlineIndex(id, notify: false);
        } catch (_) {
          // Resume records are independent of the bookmark list.
        }
      }
    }
    _theme = switch (_prefs.get('theme')) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    try {
      _appPalette = AppPalettePreferences.decode(
        _prefs.get(AppPalettePreferences.key),
      );
    } on FormatException {
      /* Preserve an unreadable record; use the original theme until edited. */
    }
    double preference(String key, double fallback, double min, double max) {
      final value = _prefs.get(key);
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    _fontSize = preference(
      'readerFontSize',
      19,
      minimumReaderFontSize,
      maximumReaderFontSize,
    );
    _lineHeight = preference('readerLineHeight', 1.72, 1.3, 2.2);
    _reduceMotion = _prefs.get('reduceMotion') == true;
    _haptics = HapticPreferences.fromRecords({
      HapticPreferences.preferenceKey: _prefs.get(
        HapticPreferences.preferenceKey,
      ),
    });
    _appTypeface = AppTypeface.fromRecord(_prefs.get('appTypeface'));
    final custom = _prefs.get('appCustomFont');
    _appCustomFont =
        validFontChoice(custom) && (custom as String).startsWith('font_')
        ? custom
        : null;
    final reader = _prefs.get('readerTypeface');
    _readerTypeface = validFontChoice(reader, follow: true)
        ? reader as String
        : followAppFont;
    _performance = PerformancePreferences.fromRecords({
      for (final key in [
        PerformancePreferences.modeKey,
        ...PerformanceEffect.values.map((effect) => effect.preferenceKey),
      ])
        key: _prefs.get(key),
    });
    _glassBlur = preference('glassBlur', 8, 0, 24);
    _glassOpacity = preference('glassOpacity', .87, 0, 1);
    _keepScreenOn = _prefs.get('readerKeepScreenOn') == true;
    _forcePortrait = _prefs.get('forcePortrait') == true;
    _readerPreferences = ReaderPreferences.fromRecord(
      _prefs.get('readerPreferences'),
    );
    _shelfSort = switch (_prefs.get('shelfSort')) {
      'recentAdded' => 'recentAdded',
      'title' => 'title',
      _ => 'recentRead',
    };
    _shelfFilter = switch (_prefs.get('shelfFilter')) {
      'unread' => 'unread',
      'reading' => 'reading',
      'finished' => 'finished',
      _ => 'all',
    };
    _shelfLayout = BookCollectionMode.parseOrDefault(
      _prefs.get('shelfLayout'),
    ).storageValue;
    _shelfGridDensity = BookGridDensity.parseOrAuto(
      _prefs.get('shelfGridDensity'),
    );
    _shelfPreferences = BookShelfPreferences.parseOrDefault(
      _prefs.get('shelfPreferences'),
    );
    _shelfContent = BookShelfContentPreferences.parseOrDefault(
      _prefs.get('shelfContent'),
    );
    _discoveryViewMode = BookCollectionMode.parseOrDefault(
      _prefs.get('discoveryLayout'),
    );
    _discoveryGridDensity = BookGridDensity.parseOrAuto(
      _prefs.get('discoveryGridDensity'),
    );
    _discoveryShelfPreferences = BookShelfPreferences.parseOrDefault(
      _prefs.get('discoveryShelfPreferences'),
    );
    _discoveryShelfContent = BookShelfContentPreferences.parseOrDefault(
      _prefs.get('discoveryShelfContent'),
    );
    final discoveryQuery = DiscoveryShelfQuery.tryParse(
      _prefs.get('discoveryShelfQuery'),
    );
    _hasDiscoveryShelfQuery = discoveryQuery != null;
    _discoveryShelfQuery =
        discoveryQuery ?? const DiscoveryShelfQuery.defaults();
    _shelfSourceFilter =
        ['local', 'cached', 'online'].contains(_prefs.get('shelfSourceFilter'))
        ? _prefs.get('shelfSourceFilter') as String
        : 'all';
    _adaptWhenOffline = _prefs.get('adaptWhenOffline') != false;
    _localReaderMode = _prefs.get('localReaderMode') == true;
    _directReadingPages = ReadingEntry.decode(
      _prefs.get('directReadingPages'),
      legacy: _prefs.get('directReading') == true,
    );
    _directReadingEnabled =
        _prefs.get('directReading') == true && _directReadingPages.isNotEmpty;
    _openRecentOnLaunch = _prefs.get('openRecentOnLaunch') == true;
    _startPage = AppStartPage.parseOrDefault(_prefs.get('startPage'));
    _combinedShelf = _prefs.get('combinedShelf') == true;
    _blockedTags = BlockedTags.fromRecord(
      _prefs.get(BlockedTags.preferenceKey),
    );
    final recent = _prefs.get('recentSearches');
    if (recent is List) {
      final seen = <String>{};
      _recentSearches = _preferenceStrings(recent)
          .map((query) => query.trim())
          .where(
            (query) =>
                validSearchHistory(query) && seen.add(query.toLowerCase()),
          )
          .take(12)
          .toList(growable: false);
    }
  }

  final SharedPreferences _prefs;

  // Native codecs preserve the elements, not Dart's generic list type.
  // In particular iOS restores string arrays as List<Object?>.
  static Iterable<String> _preferenceStrings(Object? value) =>
      value is List ? value.whereType<String>() : const <String>[];

  /// Local measured reading time; its notifications never rebuild the reader.
  late final ReadingActivityStore readingActivity;

  /// Verified reading and durable milestones; independent of foreground totals.
  late final ReadingMomentsStore readingMoments;
  final UserFontStore fonts;
  final ReaderBackgroundStore backgrounds;
  final PalettePlatform palettePlatform;
  AppPalettePreferences _appPalette = const AppPalettePreferences();
  AppPalettePreferences get appPalette => _appPalette;
  SystemTonalColors? systemTonalColors;
  bool paletteLoaded = false, themedIconSupported = false;
  String? paletteError;
  Future<void>? _paletteLoad;
  Future<void> refreshSystemPalette() => _paletteLoad ??= _readSystemPalette()
      .whenComplete(() => _paletteLoad = null);
  Future<void> _readSystemPalette() async {
    try {
      final info = await palettePlatform.read();
      if (_disposed) return;
      final changed = systemTonalColors?.signature != info.colors?.signature;
      systemTonalColors = info.colors;
      themedIconSupported = info.iconSupported;
      paletteError = null;
      if (info.iconSupported) {
        await _queuePositionWrite(() async {
          if (_appPalette.themedIcon != info.themedIcon) {
            await palettePlatform.setThemedIcon(_appPalette.themedIcon);
          }
        });
      }
      if (changed &&
          !_disposed &&
          _appPalette.source == AppPaletteSource.system) {
        _application.notifyListeners();
        _appearance.notifyListeners();
      }
    } catch (_) {
      if (!_disposed) paletteError = '系统配色读取未完成，请重试';
    } finally {
      if (!_disposed) {
        paletteLoaded = true;
        _settings.notifyListeners();
      }
    }
  }

  Future<void> setAppPalette(AppPalettePreferences value) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return setAppPalette(value);
    }
    AppPalettePreferences.decode(value.encode());
    if (value.source == AppPaletteSource.system && systemTonalColors == null) {
      throw const FormatException('当前设备未提供系统配色，请选择自选配色');
    }
    await _queuePositionWrite(() async {
      final before = _appPalette;
      if (before == value) return;
      final iconChanged = before.themedIcon != value.themedIcon;
      if (iconChanged) {
        if (!themedIconSupported) throw const FormatException('当前设备不支持切换主题图标');
        await palettePlatform.setThemedIcon(value.themedIcon);
      }
      try {
        await writeLibraryPreference(
          _prefs,
          AppPalettePreferences.key,
          value.encode(),
        );
      } catch (_) {
        if (iconChanged) await palettePlatform.setThemedIcon(before.themedIcon);
        rethrow;
      }
      _appPalette = value;
      if (!_disposed) {
        if (before.source != value.source || before.seed != value.seed) {
          _application.notifyListeners();
          _appearance.notifyListeners();
        }
        _settings.notifyListeners();
      }
    });
  }

  String? fontError;
  LocalLibraryPreferences? _organization;
  LocalLibraryPreferences get organization =>
      _organization ??= (LocalLibraryPreferences(_prefs)..load());
  final _appearance = ChangeNotifier();
  final _application = ChangeNotifier();
  final _glassChanges = ChangeNotifier();
  final _readerSettings = ChangeNotifier();
  final _settings = ChangeNotifier();
  final _history = ChangeNotifier();
  final _bookmarkChanges = ChangeNotifier();
  final _underlineChanges = ChangeNotifier();
  final _illustrationChanges = ChangeNotifier();
  final _searchChanges = ChangeNotifier();
  final _blockedTagsChanges = ChangeNotifier();
  final _shelfViewChanges = ChangeNotifier();
  final _discoveryViewChanges = ChangeNotifier();
  final _readerBehaviorChanges = ChangeNotifier();
  final _navigationChanges = ChangeNotifier();
  final Set<int> _shelf = {};
  final Set<int> _hiddenHistory = {};
  final Set<int> _hiddenLocalBooks = {};
  final Map<int, Novel> _known = {};
  final Map<int, Novel> _persistedNovels = {};
  final Map<int, int> _chapters = {};
  final Map<int, ReadingPosition> _positions = {};
  final Map<int, int> _activeReaders = {};
  Map<int, ReadingPosition> get readingPositions =>
      Map.unmodifiable(_positions);
  VoidCallback holdReadingPosition(int id) {
    _activeReaders.update(id, (value) => value + 1, ifAbsent: () => 1);
    var released = false;
    return () {
      if (released) return;
      released = true;
      final count = _activeReaders[id] ?? 0;
      if (count <= 1) {
        _activeReaders.remove(id);
      } else {
        _activeReaders[id] = count - 1;
      }
    };
  }

  Future<int> mergeLanPositions(Map<Novel, ReadingPosition> incoming) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
    }
    var count = 0;
    await _queuePositionWrite(() async {
      final updates = <int, ReadingPosition>{};
      for (final entry in incoming.entries) {
        final book = entry.key, position = entry.value;
        if (_activeReaders.containsKey(book.id) ||
            position.updatedAt <= (_positions[book.id]?.updatedAt ?? -1)) {
          continue;
        }
        final chapter = chapterForPosition(book, position);
        if (chapter == null) continue;
        updates[book.id] = ReadingPosition.fromJson({
          ...position.toJson(),
          'chapter': chapter,
          'chapterId': book.chapters[chapter].id,
        });
      }
      await _commitLibraryRecords({
        for (final entry in updates.entries) ...{
          'reading_position_${entry.key}': jsonEncode(entry.value.toJson()),
          'chapter_${entry.key}': entry.value.chapter,
        },
      });
      for (final entry in updates.entries) {
        _positions[entry.key] = entry.value;
        _chapters[entry.key] = entry.value.chapter;
        count++;
      }
      if (count > 0) _historyChanged();
    });
    return count;
  }

  final Map<int, int> _added = {};
  final Map<int, List<ReaderBookmark>> _bookmarks = {};
  final Map<int, List<ReaderUnderlineRange>> _underlineRanges = {};
  final Map<int, Map<int, List<ReaderUnderlineRange>>> _underlinesByChapter =
      {};
  final Map<int, List<ReaderAnnotationRange>> _annotationRanges = {};
  final Map<int, Map<int, List<ReaderAnnotationRange>>> _annotationsByChapter =
      {};
  final Map<int, List<IllustrationPlacement>> _illustrations = {};
  final Map<int, int> _shelfRevisions = {};
  BlockedTags _blockedTags = BlockedTags.empty;
  List<String> _recentSearches = const [];
  String _shelfSort = 'recentRead';
  String _shelfFilter = 'all';
  String _shelfSourceFilter = 'all';
  String _shelfLayout = 'shelf';
  BookGridDensity _shelfGridDensity = const BookGridDensity.auto();
  BookShelfPreferences _shelfPreferences =
      const BookShelfPreferences.defaults();
  BookShelfContentPreferences _shelfContent =
      const BookShelfContentPreferences.defaults();
  BookCollectionMode _discoveryViewMode = BookCollectionMode.shelfList;
  BookGridDensity _discoveryGridDensity = const BookGridDensity.auto();
  BookShelfPreferences _discoveryShelfPreferences =
      const BookShelfPreferences.defaults();
  BookShelfContentPreferences _discoveryShelfContent =
      const BookShelfContentPreferences.defaults();
  DiscoveryShelfQuery _discoveryShelfQuery =
      const DiscoveryShelfQuery.defaults();
  bool _hasDiscoveryShelfQuery = false;
  bool _keepScreenOn = false;
  bool _forcePortrait = false;
  bool _adaptWhenOffline = true, _localReaderMode = false;
  Set<ReadingEntry> _directReadingPages = {};
  bool _directReadingEnabled = false;
  bool _openRecentOnLaunch = false;
  AppStartPage _startPage = AppStartPage.discovery;
  bool _combinedShelf = false;
  ReaderPreferences _readerPreferences = const ReaderPreferences();
  final _bookReaderStyles = <int, ReaderBookStyle>{};
  int _metadataEncodes = 0;
  Future<void> _positionWrites = Future.value();
  Completer<void>? _restoreBarrier;
  ThemeMode _theme = ThemeMode.system;
  double _fontSize = 19;
  double _lineHeight = 1.72;
  bool _reduceMotion = false;
  HapticPreferences _haptics = const HapticPreferences();
  AppTypeface _appTypeface = AppTypeface.system;
  String? _appCustomFont;
  String _readerTypeface = followAppFont;
  PerformancePreferences _performance = const PerformancePreferences();
  double _glassBlur = 8;
  double _glassOpacity = .87;
  bool _disposed = false;
  bool _historyNotificationQueued = false;

  static Future<LibraryState> load() async {
    final prefs = await SharedPreferences.getInstance();
    await recoverLibraryRestore(prefs);
    final state = LibraryState(prefs);
    final storedShelf = prefs.get('shelf');
    if (_preferenceStrings(
      storedShelf,
    ).map(int.tryParse).whereType<int>().any(isLocalBook)) {
      // Migrate only membership. Originals, metadata, positions and bookmarks
      // remain available to the local library and cross-device sync.
      await state._commitLibraryRecords({
        'shelf': state._shelf.map((id) => '$id').toList(),
      });
    }
    return state;
  }

  Future<void> loadFonts() async {
    try {
      await fonts.load();
      await fonts.ensureLoaded(appFontId);
      await fonts.ensureLoaded(readerFontId);
      fontError = null;
      if (!_disposed) {
        _application.notifyListeners();
        _appearance.notifyListeners();
        _readerSettings.notifyListeners();
        _settings.notifyListeners();
      }
    } catch (_) {
      fontError = '自定义字体读取失败，暂用系统字体；可在字体设置中重试。';
    }
  }

  Set<int> get shelf => Set.unmodifiable(_shelf);
  Listenable get appearanceChanges => _appearance;
  Listenable get applicationChanges => _application;
  AppLanguage get language => AppLanguage.fromRecord(_prefs.get('appLanguage'));
  Future<void> setLanguage(AppLanguage value) async {
    if (chineseLocale(
          value.locale ?? WidgetsBinding.instance.platformDispatcher.locale,
        ).countryCode !=
        'CN') {
      await ChineseText.prepare();
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'appLanguage', value.name);
      if (!_disposed) {
        _application.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  bool get readerChromeVisible => _prefs.get('readerChromeVisible') == true;
  bool get readerChromeHintSeen => _prefs.get('readerChromeHintSeen') == true;
  Future<void> setReaderChromeVisible(bool visible) => _queuePositionWrite(
    () => writeLibraryPreference(_prefs, 'readerChromeVisible', visible),
  );
  Future<void> markReaderChromeHintSeen() => _queuePositionWrite(
    () => writeLibraryPreference(_prefs, 'readerChromeHintSeen', true),
  );
  Listenable get glassChanges => _glassChanges;
  Listenable get readerSettingsChanges => _readerSettings;
  Listenable get settingsChanges => _settings;
  Listenable get historyChanges => _history;
  Listenable get bookmarkChanges => _bookmarkChanges;

  /// Changes only when persisted underline geometry changes, not on reflow.
  Listenable get underlineChanges => _underlineChanges;
  Listenable get illustrationChanges => _illustrationChanges;
  List<IllustrationPlacement> illustrationsFor(int id, {int? chapterId}) =>
      List.unmodifiable(
        (_illustrations[id] ?? const <IllustrationPlacement>[]).where(
          (item) => chapterId == null || item.chapterId == chapterId,
        ),
      );

  Future<void> putIllustration(int id, IllustrationPlacement placement) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return putIllustration(id, placement);
    }
    await _queuePositionWrite(() async {
      final next = [...?_illustrations[id]]
        ..removeWhere((item) => item.url == placement.url);
      if (next.length >= 2000) throw const FormatException('本书插图排版已达上限，请先整理');
      next.add(placement);
      await writeLibraryPreference(
        _prefs,
        'illustration_layout_$id',
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
      _illustrations[id] = next;
      if (!_disposed) _illustrationChanges.notifyListeners();
    });
  }

  Future<void> removeIllustration(int id, String placementId) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return removeIllustration(id, placementId);
    }
    await _queuePositionWrite(() async {
      final next = [...?_illustrations[id]]
        ..removeWhere((item) => item.id == placementId);
      await writeLibraryPreference(
        _prefs,
        'illustration_layout_$id',
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
      _illustrations[id] = next;
      if (!_disposed) _illustrationChanges.notifyListeners();
    });
  }

  Listenable get searchChanges => _searchChanges;
  Set<String> get blockedTags => _blockedTags.tags;
  Listenable get blockedTagsChanges => _blockedTagsChanges;
  Listenable get shelfViewChanges => _shelfViewChanges;
  Listenable get discoveryViewChanges => _discoveryViewChanges;
  Set<int> get hiddenLocalBooks => Set.unmodifiable(_hiddenLocalBooks);
  bool localBookVisible(int id) => !_hiddenLocalBooks.contains(id);
  Future<void> setLocalBookHidden(int id, bool hidden) =>
      setLocalBooksHidden([id], hidden);

  Future<void> setLocalBooksHidden(Iterable<int> ids, bool hidden) {
    if (hidden) throw const FormatException('仅移出功能已取消，书籍和文件未变动');
    final targets = ids.where(isLocalBook).toSet();
    if (targets.isEmpty) return Future.value();
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setLocalBooksHidden(targets, hidden));
    }
    return _queuePositionWrite(() async {
      final next = {..._hiddenLocalBooks};
      if (hidden) {
        next.addAll(targets);
      } else {
        next.removeAll(targets);
      }
      if (setEquals(next, _hiddenLocalBooks)) return;
      await writeLibraryPreference(
        _prefs,
        'local_shelf_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenLocalBooks
        ..clear()
        ..addAll(next);
      if (!_disposed) _shelfViewChanges.notifyListeners();
    });
  }

  Listenable get readerBehaviorChanges => _readerBehaviorChanges;
  Listenable get navigationChanges => _navigationChanges;
  bool get adaptWhenOffline => _adaptWhenOffline;
  bool get localReaderMode => _localReaderMode;
  bool get directReading => _directReadingEnabled;
  bool get openRecentOnLaunch => _openRecentOnLaunch;
  AppStartPage get startPage => _startPage;
  Set<ReadingEntry> get directReadingPages =>
      Set.unmodifiable(_directReadingPages);
  bool directReadingOn(ReadingEntry page) =>
      directReading && _directReadingPages.contains(page);
  bool get combinedShelf => _combinedShelf;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  String get shelfSort => _shelfSort;
  String get shelfFilter => _shelfFilter;
  String get shelfSourceFilter => _shelfSourceFilter;
  String get shelfLayout => _shelfLayout;
  BookCollectionMode get shelfViewMode =>
      BookCollectionMode.parseOrDefault(_shelfLayout);
  BookGridDensity get shelfGridDensity => _shelfGridDensity;
  BookShelfPreferences get shelfPreferences => _shelfPreferences;
  BookShelfContentPreferences get shelfContent => _shelfContent;
  BookCollectionMode get discoveryViewMode => _discoveryViewMode;
  BookGridDensity get discoveryGridDensity => _discoveryGridDensity;
  BookShelfPreferences get discoveryShelfPreferences =>
      _discoveryShelfPreferences;
  BookShelfContentPreferences get discoveryShelfContent =>
      _discoveryShelfContent;
  DiscoveryShelfQuery get discoveryShelfQuery => _discoveryShelfQuery;
  bool get hasDiscoveryShelfQuery => _hasDiscoveryShelfQuery;
  bool get keepScreenOn => _keepScreenOn;
  bool get forcePortrait => _forcePortrait;
  ReaderPreferences get readerPreferences => _readerPreferences;
  bool independentReaderStyle(int id) => _bookReaderStyles[id]?.enabled == true;
  ReaderBookStyle? _readerStyleFor(int? id) {
    final style = _bookReaderStyles[id];
    return style?.enabled == true ? style : null;
  }

  ReaderPreferences readerPreferencesFor(int? id) =>
      _readerStyleFor(id)?.resolve(_readerPreferences) ?? _readerPreferences;
  double readerFontSizeFor(int? id) =>
      _readerStyleFor(id)?.fontSize ?? _fontSize;
  double readerLineHeightFor(int? id) =>
      _readerStyleFor(id)?.lineHeight ?? _lineHeight;
  String readerTypefaceFor(int? id) =>
      _readerStyleFor(id)?.typeface ?? _readerTypeface;
  String readerFontIdFor(int? id) {
    final choice = readerTypefaceFor(id);
    return choice == followAppFont
        ? appFontId
        : fonts.available(choice)
        ? choice
        : 'system';
  }

  String? readerFontFamilyFor(int? id) => fonts.family(readerFontIdFor(id));
  ThemeMode get theme => _theme;
  double get fontSize => _fontSize;
  double get lineHeight => _lineHeight;
  int get debugMetadataEncodeCount => _metadataEncodes;
  bool get reduceMotion => _reduceMotion;
  HapticPreferences get haptics => _haptics;
  AppTypeface get appTypeface => _appTypeface;
  String get appFontChoice => _appCustomFont ?? _appTypeface.name;
  String get appFontId =>
      fonts.available(appFontChoice) ? appFontChoice : 'system';
  String? get appFontFamily => fonts.family(appFontId);
  String get readerTypeface => _readerTypeface;
  String get readerFontId => _readerTypeface == followAppFont
      ? appFontId
      : fonts.available(_readerTypeface)
      ? _readerTypeface
      : 'system';
  String? get readerFontFamily => fonts.family(readerFontId);
  String fontLabel(String choice) =>
      choice == followAppFont ||
          validFontChoice(choice) && !choice.startsWith('font_') ||
          fonts.available(choice)
      ? fonts.label(choice)
      : '字体未在本机导入';
  PerformancePreferences get performance => _performance;
  bool get effectiveReduceMotion => _reduceMotion || !_performance.motion;
  double get glassBlur => _glassBlur;
  double get glassOpacity => _glassOpacity;

  bool contains(int id) => _shelf.contains(id);
  int chapterFor(int id) => _chapters[id] ?? _positions[id]?.chapter ?? 0;
  Novel? cachedNovel(int id) => _known[id];
  ReadingPosition? positionFor(int id) => _positions[id];
  List<ReaderBookmark> bookmarksFor(int id) =>
      List.unmodifiable(_bookmarks[id] ?? const <ReaderBookmark>[]);

  /// Indexed immutable source ranges; repeated paragraph builds do not scan marks.
  List<ReaderUnderlineRange> underlinesFor(int id, {int? chapterId}) =>
      chapterId == null
      ? _underlineRanges[id] ?? const []
      : _underlinesByChapter[id]?[chapterId] ?? const [];

  /// Immutable appearance-aware index; paragraph builds never scan bookmarks.
  List<ReaderAnnotationRange> annotationsFor(int id, {int? chapterId}) =>
      chapterId == null
      ? _annotationRanges[id] ?? const []
      : _annotationsByChapter[id]?[chapterId] ?? const [];

  bool _updateUnderlineIndex(int id, {bool notify = true}) {
    final styledMarks =
        List<ReaderBookmark>.of(_bookmarks[id] ?? const <ReaderBookmark>[])
          ..sort((a, b) {
            final edited = b.annotation.updatedAt.compareTo(
              a.annotation.updatedAt,
            );
            return edited != 0 ? edited : b.id.compareTo(a.id);
          });
    final annotations = <ReaderAnnotationRange>[
      for (final mark in styledMarks)
        for (final range in mark.underlineRanges)
          ReaderAnnotationRange(
            range,
            mark.annotation.style,
            mark.annotation.color,
          ),
    ];
    final ranges =
        <ReaderUnderlineRange>[
          for (final mark in _bookmarks[id] ?? const <ReaderBookmark>[])
            ...mark.underlineRanges,
        ]..sort((a, b) {
          for (final pair in [
            (a.chapterId, b.chapterId),
            (a.startParagraph, b.startParagraph),
            (a.startOffset, b.startOffset),
            (a.endParagraph, b.endParagraph),
            (a.endOffset, b.endOffset),
          ]) {
            final order = pair.$1.compareTo(pair.$2);
            if (order != 0) return order;
          }
          return a.contentRevision.compareTo(b.contentRevision);
        });
    if (listEquals(_underlineRanges[id] ?? const [], ranges) &&
        listEquals(_annotationRanges[id] ?? const [], annotations)) {
      return false;
    }
    final previous = _underlinesByChapter[id];
    final chapters = <int, List<ReaderUnderlineRange>>{};
    for (final range in ranges) {
      (chapters[range.chapterId] ??= []).add(range);
    }
    _underlineRanges[id] = List.unmodifiable(ranges);
    _underlinesByChapter[id] = {
      for (final entry in chapters.entries)
        entry.key: listEquals(previous?[entry.key], entry.value)
            ? previous![entry.key]!
            : List.unmodifiable(entry.value),
    };
    _annotationRanges[id] = List.unmodifiable(annotations);
    final styledChapters = <int, List<ReaderAnnotationRange>>{};
    for (final item in annotations) {
      (styledChapters[item.range.chapterId] ??= []).add(item);
    }
    final oldStyled = _annotationsByChapter[id];
    _annotationsByChapter[id] = {
      for (final entry in styledChapters.entries)
        entry.key: listEquals(oldStyled?[entry.key], entry.value)
            ? oldStyled![entry.key]!
            : List.unmodifiable(entry.value),
    };
    if (notify && !_disposed) _underlineChanges.notifyListeners();
    return true;
  }

  List<({int novelId, ReaderBookmark bookmark})> get bookmarkEntries {
    final entries =
        [
          for (final entry in _bookmarks.entries)
            for (final mark in entry.value)
              (novelId: entry.key, bookmark: mark),
        ]..sort(
          (a, b) => b.bookmark.position.updatedAt.compareTo(
            a.bookmark.position.updatedAt,
          ),
        );
    return List.unmodifiable(entries);
  }

  int? chapterForPosition(Novel novel, ReadingPosition position) {
    if (position.chapterId > 0) {
      final index = novel.chapters.indexWhere(
        (chapter) => chapter.id == position.chapterId,
      );
      return index < 0 ? null : index;
    }
    return position.chapter >= 0 && position.chapter < novel.chapters.length
        ? position.chapter
        : null;
  }

  bool hasRead(int id) =>
      _chapters.containsKey(id) || _positions.containsKey(id);
  int addedAt(int id) => _added[id] ?? 0;
  int shelfRevision(int id) => _shelfRevisions[id] ?? 0;
  Map<int, int> get shelfRevisions => Map.unmodifiable(_shelfRevisions);
  int lastReadAt(int id) => _positions[id]?.updatedAt ?? 0;

  bool finishedReading(Novel novel) {
    final position = positionFor(novel.id);
    final count = novel.chapters.isEmpty
        ? novel.chapterCount
        : novel.chapters.length;
    if (position == null || count <= 0 || position.fraction < .995) {
      return false;
    }
    if (position.chapterId > 0 && novel.chapters.isNotEmpty) {
      return novel.chapters.last.id == position.chapterId;
    }
    return position.chapter == count - 1;
  }

  static bool validSearchHistory(String query) =>
      query.isNotEmpty &&
      query.length <= 120 &&
      !RegExp(r'[\x00-\x1f]').hasMatch(query);

  Future<void> recordSearch(String query) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => recordSearch(query));
    }
    final term = query.trim();
    if (!validSearchHistory(term)) return Future.value();
    return _queuePositionWrite(() async {
      if (_recentSearches.isNotEmpty && _recentSearches.first == term) return;
      final next = [
        term,
        ..._recentSearches.where(
          (old) => old.toLowerCase() != term.toLowerCase(),
        ),
      ].take(12).toList(growable: false);
      await writeLibraryPreference(_prefs, 'recentSearches', next);
      _recentSearches = next;
      if (!_disposed) _searchChanges.notifyListeners();
    });
  }

  Future<void> clearRecentSearches() {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => clearRecentSearches());
    }
    return _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'recentSearches', <String>[]);
      _recentSearches = const [];
      if (!_disposed) _searchChanges.notifyListeners();
    });
  }

  Future<void> setBlockedTags(Iterable<String> values) {
    final input = List<String>.of(values);
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setBlockedTags(input));
    }
    return _queuePositionWrite(() async {
      final next = await BlockedTags.fromInput(input);
      if (_blockedTags.sameAs(next)) return;
      await writeLibraryPreference(
        _prefs,
        BlockedTags.preferenceKey,
        next.toRecord(),
      );
      _blockedTags = next;
      if (!_disposed) {
        _blockedTagsChanges.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setShelfView({
    String? sort,
    String? filter,
    String? layout,
    BookCollectionMode? mode,
    String? source,
    BookGridDensity? gridDensity,
    BookShelfPreferences? shelfPreferences,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setShelfView(
          sort: sort,
          filter: filter,
          layout: layout,
          mode: mode,
          source: source,
          gridDensity: gridDensity,
          shelfPreferences: shelfPreferences,
        ),
      );
    }
    await _queuePositionWrite(() async {
      final nextSort = ['recentRead', 'recentAdded', 'title'].contains(sort)
          ? sort!
          : _shelfSort;
      final nextFilter =
          ['all', 'unread', 'reading', 'finished'].contains(filter)
          ? filter!
          : _shelfFilter;
      final nextLayout =
          (mode ?? BookCollectionMode.tryParse(layout))?.storageValue ??
          _shelfLayout;
      final nextGridDensity = gridDensity ?? _shelfGridDensity;
      final nextShelfPreferences = shelfPreferences ?? _shelfPreferences;
      final nextSource = ['all', 'local', 'cached', 'online'].contains(source)
          ? source!
          : _shelfSourceFilter;
      await _commitLibraryRecords({
        'shelfSort': nextSort,
        'shelfFilter': nextFilter,
        'shelfLayout': nextLayout,
        'shelfGridDensity': nextGridDensity.value,
        'shelfPreferences': nextShelfPreferences.record,
        'shelfSourceFilter': nextSource,
      });
      if (nextSort != _shelfSort ||
          nextFilter != _shelfFilter ||
          nextLayout != _shelfLayout ||
          nextGridDensity != _shelfGridDensity ||
          nextShelfPreferences != _shelfPreferences ||
          nextSource != _shelfSourceFilter) {
        _shelfSort = nextSort;
        _shelfFilter = nextFilter;
        _shelfLayout = nextLayout;
        _shelfGridDensity = nextGridDensity;
        _shelfPreferences = nextShelfPreferences;
        _shelfSourceFilter = nextSource;
        if (!_disposed) _shelfViewChanges.notifyListeners();
      }
    });
  }

  Future<void> setDiscoveryView({
    BookCollectionMode? mode,
    BookGridDensity? gridDensity,
    BookShelfPreferences? shelfPreferences,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setDiscoveryView(
          mode: mode,
          gridDensity: gridDensity,
          shelfPreferences: shelfPreferences,
        ),
      );
    }
    await _queuePositionWrite(() async {
      final nextMode = mode ?? _discoveryViewMode;
      final nextDensity = gridDensity ?? _discoveryGridDensity;
      final nextShelfPreferences =
          shelfPreferences ?? _discoveryShelfPreferences;
      if (nextMode == _discoveryViewMode &&
          nextDensity == _discoveryGridDensity &&
          nextShelfPreferences == _discoveryShelfPreferences) {
        return;
      }
      await _commitLibraryRecords({
        'discoveryLayout': nextMode.storageValue,
        'discoveryGridDensity': nextDensity.value,
        'discoveryShelfPreferences': nextShelfPreferences.record,
      });
      _discoveryViewMode = nextMode;
      _discoveryGridDensity = nextDensity;
      _discoveryShelfPreferences = nextShelfPreferences;
      if (!_disposed) _discoveryViewChanges.notifyListeners();
    });
  }

  /// Only the featured region changes; existing collection controls stay put.
  Future<void> setShelfContent(BookShelfContentPreferences value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setShelfContent(value));
    }
    await _queuePositionWrite(() async {
      if (_shelfContent == value) return;
      await _commitLibraryRecords({'shelfContent': value.record});
      _shelfContent = value;
      if (!_disposed) _shelfViewChanges.notifyListeners();
    });
  }

  /// Discovery keeps its region selection separate from shelf/local choices.
  Future<void> setDiscoveryShelfContent(
    BookShelfContentPreferences value,
  ) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setDiscoveryShelfContent(value));
    }
    await _queuePositionWrite(() async {
      if (_discoveryShelfContent == value) return;
      await _commitLibraryRecords({'discoveryShelfContent': value.record});
      _discoveryShelfContent = value;
      if (!_disposed) _discoveryViewChanges.notifyListeners();
    });
  }

  /// Persists only the upper region's remote query, without changing the lower feed.
  Future<void> setDiscoveryShelfQuery(DiscoveryShelfQuery value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setDiscoveryShelfQuery(value));
    }
    await _queuePositionWrite(() async {
      if (_hasDiscoveryShelfQuery && _discoveryShelfQuery == value) return;
      await _commitLibraryRecords({'discoveryShelfQuery': value.record});
      _discoveryShelfQuery = value;
      _hasDiscoveryShelfQuery = true;
      if (!_disposed) _discoveryViewChanges.notifyListeners();
    });
  }

  Future<void> setKeepScreenOn(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setKeepScreenOn(value));
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'readerKeepScreenOn', value);
      if (_keepScreenOn != value) {
        _keepScreenOn = value;
        if (!_disposed) {
          _readerBehaviorChanges.notifyListeners();
          _settings.notifyListeners();
        }
      }
    });
  }

  Future<void> setForcePortrait(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setForcePortrait(value));
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'forcePortrait', value);
      if (_forcePortrait != value) {
        _forcePortrait = value;
        if (!_disposed) _settings.notifyListeners();
      }
    });
  }

  Future<void> setOpenRecentOnLaunch(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setOpenRecentOnLaunch(value));
    }
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'openRecentOnLaunch', value);
      if (_openRecentOnLaunch != value) {
        _openRecentOnLaunch = value;
        if (!_disposed) _settings.notifyListeners();
      }
    });
  }

  Future<void> setStartPage(AppStartPage value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setStartPage(value));
    }
    await _queuePositionWrite(() async {
      if (_startPage == value) return;
      await writeLibraryPreference(_prefs, 'startPage', value.name);
      _startPage = value;
      if (!_disposed) _settings.notifyListeners();
    });
  }

  Future<void> setNavigationMode({
    bool? adaptWhenOffline,
    bool? localReaderMode,
    bool? combinedShelf,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setNavigationMode(
          adaptWhenOffline: adaptWhenOffline,
          localReaderMode: localReaderMode,
          combinedShelf: combinedShelf,
        ),
      );
    }
    await _queuePositionWrite(() async {
      final offline = adaptWhenOffline ?? _adaptWhenOffline;
      final local = localReaderMode ?? _localReaderMode;
      final combined = combinedShelf ?? _combinedShelf;
      if (offline == _adaptWhenOffline &&
          local == _localReaderMode &&
          combined == _combinedShelf) {
        return;
      }
      await _commitLibraryRecords({
        'adaptWhenOffline': offline,
        'localReaderMode': local,
        'combinedShelf': combined,
      });
      _adaptWhenOffline = offline;
      _localReaderMode = local;
      _combinedShelf = combined;
      if (!_disposed) {
        _navigationChanges.notifyListeners();
        _shelfViewChanges.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setDirectReading(bool value) => _setDirectReadingPages(
    value && _directReadingPages.isEmpty
        ? ReadingEntry.values.toSet()
        : _directReadingPages,
    value,
  );

  Future<void> setDirectReadingPages(Set<ReadingEntry> pages) =>
      _setDirectReadingPages(pages, pages.isNotEmpty);

  Future<void> _setDirectReadingPages(
    Set<ReadingEntry> pages,
    bool enabled,
  ) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => _setDirectReadingPages(pages, enabled));
    }
    final selected = Set<ReadingEntry>.of(pages);
    await _queuePositionWrite(() async {
      await _commitLibraryRecords({
        'directReading': enabled && selected.isNotEmpty,
        'directReadingPages': [
          for (final page in ReadingEntry.values)
            if (selected.contains(page)) page.name,
        ],
      });
      _directReadingPages = selected;
      _directReadingEnabled = enabled && selected.isNotEmpty;
      if (!_disposed) _settings.notifyListeners();
    });
  }

  Future<void> setReaderPreferences(
    ReaderPreferences value, {
    bool persist = true,
    int? bookId,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setReaderPreferences(value, persist: persist, bookId: bookId),
      );
    }
    if (_readerStyleFor(bookId) case final style?) {
      final shared = value.withLayoutOf(_readerPreferences);
      return _setBookReaderStyle(
        bookId!,
        style.copyWith(preferences: value),
        persist: persist,
        shared: shared,
      );
    }
    final record = jsonEncode(value.toJson());
    ReaderPreferences.fromJson(jsonDecode(record));
    if (persist) {
      await _queuePositionWrite(
        () => writeLibraryPreference(_prefs, 'readerPreferences', record),
      );
    }
    if (jsonEncode(_readerPreferences.toJson()) == record) return;
    _readerPreferences = value;
    if (!_disposed) {
      _readerSettings.notifyListeners();
      _readerBehaviorChanges.notifyListeners();
      _settings.notifyListeners();
    }
  }

  Future<void> setIndependentReaderStyle(int id, bool enabled) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setIndependentReaderStyle(id, enabled));
    }
    if (independentReaderStyle(id) == enabled) return;
    final style =
        (_bookReaderStyles[id] ??
                ReaderBookStyle(
                  preferences: _readerPreferences,
                  fontSize: _fontSize,
                  lineHeight: _lineHeight,
                  typeface: _readerTypeface,
                ))
            .copyWith(enabled: enabled);
    if (enabled) await fonts.ensureLoaded(_readerFontIdForStyle(style));
    await _setBookReaderStyle(id, style);
  }

  Set<String> hiddenReaderLanguagesFor(int id) =>
      _bookReaderStyles[id]?.hiddenLanguages ?? const {};
  String? onlyReaderLanguageFor(int id) => _bookReaderStyles[id]?.onlyLanguage;

  Future<void> setHiddenReaderLanguages(
    int id,
    Set<String> hidden, {
    String? onlyLanguage,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setHiddenReaderLanguages(id, hidden, onlyLanguage: onlyLanguage),
      );
    }
    final style =
        _bookReaderStyles[id] ??
        ReaderBookStyle(
          preferences: _readerPreferences,
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          typeface: _readerTypeface,
          enabled: false,
        );
    await _setBookReaderStyle(
      id,
      style.copyWith(hiddenLanguages: hidden, onlyLanguage: onlyLanguage),
    );
  }

  Future<void> removeReaderBackground(String image) async {
    if (!validBackgroundId(image)) throw const FormatException('阅读背景记录有误');
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => removeReaderBackground(image));
    }
    await _queuePositionWrite(() async {
      final shared = _readerPreferences.backgroundImage == image
          ? _readerPreferences.copyWith(clearBackground: true)
          : _readerPreferences;
      final styles = <int, ReaderBookStyle>{
        for (final entry in _bookReaderStyles.entries)
          if (entry.value.preferences.backgroundImage == image)
            entry.key: entry.value.copyWith(
              preferences: entry.value.preferences.copyWith(
                clearBackground: true,
              ),
            ),
      };
      final records = <String, Object>{
        if (!identical(shared, _readerPreferences))
          'readerPreferences': jsonEncode(shared.toJson()),
        for (final entry in styles.entries)
          '$bookReaderStylePrefix${entry.key}': jsonEncode(
            entry.value.toJson(),
          ),
      };
      if (records.isNotEmpty) {
        await _commitLibraryRecords(records);
        _readerPreferences = shared;
        _bookReaderStyles.addAll(styles);
        if (!_disposed) {
          _readerSettings.notifyListeners();
          _settings.notifyListeners();
        }
      }
    });
    await backgrounds.remove(image);
  }

  String _readerFontIdForStyle(ReaderBookStyle style) =>
      style.typeface == followAppFont
      ? appFontId
      : fonts.available(style.typeface)
      ? style.typeface
      : 'system';

  Future<void> _setBookReaderStyle(
    int id,
    ReaderBookStyle value, {
    bool persist = true,
    ReaderPreferences? shared,
  }) async {
    if (id <= 0 || id > 0x7fffffff) {
      throw const FormatException('书籍标识无效');
    }
    ReaderBookStyle.fromJson(value.toJson());
    final previous = _bookReaderStyles[id];
    final previousShared = _readerPreferences;
    final sharedRecord = shared == null ? null : jsonEncode(shared.toJson());
    final sharedChanged =
        sharedRecord != null &&
        sharedRecord != jsonEncode(_readerPreferences.toJson());
    if (persist) {
      final record = jsonEncode(value.toJson());
      await _queuePositionWrite(
        () => _commitLibraryRecords({
          '$bookReaderStylePrefix$id': record,
          if (sharedChanged) 'readerPreferences': sharedRecord,
        }),
      );
    }
    // A slower disk commit must not replace a newer live slider preview.
    if (identical(_bookReaderStyles[id], previous)) {
      _bookReaderStyles[id] = value;
    }
    if (sharedChanged && identical(_readerPreferences, previousShared)) {
      _readerPreferences = shared!;
    }
    if (!_disposed) {
      _readerSettings.notifyListeners();
      if (sharedChanged) _readerBehaviorChanges.notifyListeners();
      _settings.notifyListeners();
    }
  }

  Set<int> get recordedReadingIds =>
      Set.unmodifiable({..._chapters.keys, ..._positions.keys});

  List<int> get readingHistoryIds {
    final ids =
        {
            ..._chapters.keys,
            ..._positions.keys,
          }.where((id) => id > 0 && !_hiddenHistory.contains(id)).toList()
          ..sort((a, b) {
            final time = lastReadAt(b).compareTo(lastReadAt(a));
            return time != 0 ? time : a.compareTo(b);
          });
    return List.unmodifiable(ids);
  }

  void _historyChanged() {
    if (_disposed) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_historyNotificationQueued) return;
      _historyNotificationQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _historyNotificationQueued = false;
        if (!_disposed) _history.notifyListeners();
      });
      return;
    }
    _history.notifyListeners();
  }

  Future<void> _queuePositionWrite(Future<void> Function() write) {
    _positionWrites = _positionWrites.catchError((Object _) {}).then((_) async {
      if (_prefs.get(restoreJournalKey) != null) {
        await recoverLibraryRestore(_prefs);
      }
      await write();
    });
    return _positionWrites;
  }

  Future<void> _persistReadingActivity() async {
    if (_restoreBarrier case final barrier?) await barrier.future;
    await _queuePositionWrite(
      () => writeLibraryPreference(
        _prefs,
        ReadingActivityStore.preferenceKey,
        readingActivity.encode(),
      ),
    );
  }

  Future<void> _persistReadingMoments() async {
    if (_restoreBarrier case final barrier?) await barrier.future;
    await _queuePositionWrite(
      () => writeLibraryPreference(
        _prefs,
        ReadingMomentsStore.preferenceKey,
        readingMoments.encode(),
      ),
    );
  }

  /// Hide history without destroying resume positions, shelf or body files.
  Future<void> hideReadingHistory(int id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => hideReadingHistory(id));
    }
    return _queuePositionWrite(() async {
      if (id <= 0 || !hasRead(id) || _hiddenHistory.contains(id)) return;
      final next = {..._hiddenHistory, id};
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  Future<void> clearReadingHistory() {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => clearReadingHistory());
    }
    return _queuePositionWrite(() async {
      final visible = readingHistoryIds;
      if (visible.isEmpty) return;
      final next = {..._hiddenHistory, ...visible};
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  Future<void> restoreReadingHistory(int id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => restoreReadingHistory(id));
    }
    return _queuePositionWrite(() async {
      if (id <= 0 || !hasRead(id) || !_hiddenHistory.contains(id)) return;
      final next = {..._hiddenHistory}..remove(id);
      await writeLibraryPreference(
        _prefs,
        'reading_history_hidden',
        next.map((id) => '$id').toList(),
      );
      _hiddenHistory
        ..clear()
        ..addAll(next);
      _historyChanged();
    });
  }

  int chapterForNovel(Novel novel) {
    final position = _positions[novel.id];
    if (position != null && position.chapterId > 0) {
      final index = novel.chapters.indexWhere(
        (chapter) => chapter.id == position.chapterId,
      );
      if (index >= 0) return index;
    }
    final count = novel.chapters.isEmpty
        ? novel.chapterCount
        : novel.chapters.length;
    return count == 0
        ? chapterFor(novel.id)
        : chapterFor(novel.id).clamp(0, count - 1);
  }

  String? _novelSnapshot(Novel novel) {
    if (identical(_persistedNovels[novel.id], novel)) return null;
    assert(() {
      _metadataEncodes++;
      return true;
    }());
    final snapshot = jsonEncode(novel.toSnapshot());
    _persistedNovels[novel.id] = novel;
    return snapshot;
  }

  Future<void> _writeNovel(Novel novel, String snapshot) async {
    try {
      await writeLibraryPreference(_prefs, 'novel_meta_${novel.id}', snapshot);
    } catch (_) {
      if (identical(_persistedNovels[novel.id], novel)) {
        _persistedNovels.remove(novel.id);
      }
      rethrow;
    }
  }

  Future<void> rememberNovel(Novel novel) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => rememberNovel(novel));
    }
    if (novel.id <= 0) return Future.value();
    _known[novel.id] = novel;
    final snapshot = _novelSnapshot(novel);
    return snapshot == null
        ? _positionWrites
        : _queuePositionWrite(() => _writeNovel(novel, snapshot));
  }

  /// Adds an exact source selection once, regardless of the active layout.
  Future<ReaderBookmark> addUnderline({
    required Novel novel,
    required ReadingPosition position,
    required List<ReaderUnderlineRange> ranges,
    String quote = '',
  }) async => (await _changeUnderline(
    novel: novel,
    position: position,
    ranges: ranges,
    quote: quote,
    toggle: false,
  ))!;

  /// Toggles the same source ranges, returning true when a line was added.
  Future<bool> toggleUnderline({
    required Novel novel,
    required ReadingPosition position,
    required List<ReaderUnderlineRange> ranges,
    String quote = '',
  }) async =>
      await _changeUnderline(
        novel: novel,
        position: position,
        ranges: ranges,
        quote: quote,
        toggle: true,
      ) !=
      null;

  /// Saves an exact-text mark and its personal thought in one serialized write.
  /// A repeated selection edits its existing record rather than adding a copy.
  Future<ReaderBookmark> saveAnnotation({
    required Novel novel,
    required ReadingPosition position,
    required List<ReaderUnderlineRange> ranges,
    String quote = '',
    ReaderMarkStyle style = ReaderMarkStyle.underline,
    ReaderMarkColor color = ReaderMarkColor.ink,
    String note = '',
  }) async => (await _changeUnderline(
    novel: novel,
    position: position,
    ranges: ranges,
    quote: quote,
    toggle: false,
    annotation: ReaderAnnotationData.fromJson({
      'style': style.name,
      'color': color.name,
      'note': note,
      'updatedAt': 0,
    }),
  ))!;

  /// Editing saved notes does not require the original local file to be present.
  Future<ReaderBookmark> updateBookmarkAnnotation(
    int novelId,
    String id, {
    required ReaderMarkStyle style,
    required ReaderMarkColor color,
    required String note,
  }) async {
    final data = ReaderAnnotationData.fromJson({
      'style': style.name,
      'color': color.name,
      'note': note,
      'updatedAt': 0,
    });
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => updateBookmarkAnnotation(
          novelId,
          id,
          style: style,
          color: color,
          note: note,
        ),
      );
    }
    late ReaderBookmark result;
    await _queuePositionWrite(() async {
      final marks = _bookmarks[novelId] ?? const <ReaderBookmark>[];
      final previous = marks.where((mark) => mark.id == id).firstOrNull;
      if (previous == null) throw const FormatException('这条书签已被移除');
      result = previous.withAnnotation(_datedAnnotation(data, previous));
      final next = [for (final mark in marks) mark.id == id ? result : mark];
      await _writeBookmarks(novelId, next);
      _bookmarks[novelId] = next;
      _updateUnderlineIndex(novelId);
      if (!_disposed) _bookmarkChanges.notifyListeners();
    });
    return result;
  }

  /// Commits geometry and any explicitly edited note together. Other marks at
  /// the same coordinates stay independent, and reading progress is untouched.
  Future<ReaderBookmark> updateBookmarkRange(
    int novelId,
    String id, {
    required Novel novel,
    required ReaderAnnotationRangeChange change,
    required int expectedRangeUpdatedAt,
    required List<ReaderUnderlineRange> expectedRanges,
    ReaderAnnotationData? annotation,
  }) async {
    if (novelId != novel.id ||
        change.novelId != novelId ||
        change.ranges.any(
          (range) => !novel.chapters.any((c) => c.id == range.chapterId),
        )) {
      throw const FormatException('原文范围不属于这本书');
    }
    final ranges = canonicalReaderUnderlineRanges(
      change.ranges,
      chapterOrder: novel.chapters.map((c) => c.id),
    );
    if (change.quote.length > 12000) {
      throw const FormatException('摘录过长，请选择不超过 12000 字的内容');
    }
    final edited = annotation == null
        ? null
        : ReaderAnnotationData.fromJson(annotation.toJson());
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => updateBookmarkRange(
          novelId,
          id,
          novel: novel,
          change: change,
          expectedRangeUpdatedAt: expectedRangeUpdatedAt,
          expectedRanges: expectedRanges,
          annotation: edited,
        ),
      );
    }
    late ReaderBookmark result;
    await _queuePositionWrite(() async {
      final marks = _bookmarks[novelId] ?? const <ReaderBookmark>[];
      final previous = marks.where((mark) => mark.id == id).firstOrNull;
      if (previous == null) throw const FormatException('这条书签已被移除');
      if (previous.rangeUpdatedAt != expectedRangeUpdatedAt ||
          !listEquals(previous.underlineRanges, expectedRanges)) {
        throw const FormatException('原文范围刚刚发生变化，请重新打开这条书签再调整');
      }
      final first = ranges.first;
      final chapter = novel.chapters.indexWhere((c) => c.id == first.chapterId);
      final position = ReadingPosition.fromJson({
        ...previous.position.toJson(),
        'chapter': chapter,
        'chapterId': first.chapterId,
        'paragraphIndex': first.startParagraph,
        'textOffset': first.startOffset,
        'paragraphFraction': 0,
        'contentRevision': first.contentRevision,
        'offset': 0,
        'fraction': 0,
        'width': 0,
        'layout': '',
      });
      final now = DateTime.now().millisecondsSinceEpoch;
      result = previous.withRange(
        chapterTitle: novel.chapters[chapter].title,
        position: position,
        ranges: ranges,
        quote: change.quote,
        updatedAt: now > previous.rangeUpdatedAt
            ? now
            : previous.rangeUpdatedAt + 1,
      );
      if (edited != null) {
        result = result.withAnnotation(_datedAnnotation(edited, previous));
      }
      final next = [for (final mark in marks) mark.id == id ? result : mark];
      await _writeBookmarks(novelId, next);
      _bookmarks[novelId] = next;
      _updateUnderlineIndex(novelId);
      if (!_disposed) _bookmarkChanges.notifyListeners();
    });
    return result;
  }

  ReaderAnnotationData _datedAnnotation(
    ReaderAnnotationData data,
    ReaderBookmark? previous,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = previous?.annotation.updatedAt ?? 0;
    return data.at(now > last ? now : last + 1);
  }

  Future<ReaderBookmark?> _changeUnderline({
    required Novel novel,
    required ReadingPosition position,
    required List<ReaderUnderlineRange> ranges,
    required String quote,
    required bool toggle,
    ReaderAnnotationData? annotation,
  }) async {
    final chapterIds = novel.chapters.map((chapter) => chapter.id).toSet();
    if (novel.id <= 0 ||
        ranges.any((range) => !chapterIds.contains(range.chapterId))) {
      throw const FormatException('暂时无法定位选中的文字，请重新选择');
    }
    final selected = canonicalReaderUnderlineRanges([
      for (final range in ranges)
        range.contentRevision.isEmpty && range.chapterId == position.chapterId
            ? range.withRevision(position.contentRevision)
            : range,
    ], chapterOrder: novel.chapters.map((chapter) => chapter.id));
    final excerpt = quote.trim();
    if (excerpt.length > 12000) {
      throw const FormatException('摘录过长，请选择不超过 12000 字的内容');
    }
    if (!position.offset.isFinite ||
        position.offset < 0 ||
        !position.fraction.isFinite ||
        position.fraction < 0 ||
        position.fraction > 1 ||
        !position.width.isFinite ||
        !position.fontSize.isFinite ||
        !position.lineHeight.isFinite) {
      throw const FormatException('暂时无法定位选中的文字，请重新选择');
    }
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => _changeUnderline(
          novel: novel,
          position: position,
          ranges: selected,
          quote: excerpt,
          toggle: toggle,
          annotation: annotation,
        ),
      );
    }
    ReaderBookmark? result;
    await _queuePositionWrite(() async {
      final marks = _bookmarks[novel.id] ?? const <ReaderBookmark>[];
      final matching = marks.where((mark) {
        return mark.isUnderline &&
            listEquals(
              canonicalReaderUnderlineRanges(
                mark.underlineRanges,
                chapterOrder: novel.chapters.map((chapter) => chapter.id),
              ),
              selected,
            );
      }).toList();
      final existing = matching.firstOrNull;
      if (existing != null) {
        if (!toggle) {
          if (annotation == null) {
            result = existing;
            return;
          }
          result = existing.withAnnotation(
            _datedAnnotation(annotation, existing),
          );
          final next = [
            for (final mark in marks) mark.id == existing.id ? result! : mark,
          ];
          await _writeBookmarks(novel.id, next);
          _bookmarks[novel.id] = next;
          _updateUnderlineIndex(novel.id);
          if (!_disposed) _bookmarkChanges.notifyListeners();
          return;
        }
        final ids = matching.map((mark) => mark.id).toSet();
        final next = marks.where((mark) => !ids.contains(mark.id)).toList();
        await _writeBookmarks(novel.id, next);
        _bookmarks[novel.id] = next;
        _updateUnderlineIndex(novel.id);
        if (!_disposed) _bookmarkChanges.notifyListeners();
        return;
      }
      if (marks.length >= 1000) {
        throw const FormatException('本书书签和划线已达 1000 个，请先整理');
      }
      final first = selected.first;
      final chapter = novel.chapters.indexWhere((c) => c.id == first.chapterId);
      final sameChapter = position.chapterId > 0
          ? position.chapterId == first.chapterId
          : position.chapter == chapter;
      final anchor = ReadingPosition.fromJson({
        ...position.toJson(),
        'chapter': chapter,
        'chapterId': first.chapterId,
        'paragraphIndex': first.startParagraph,
        'textOffset': first.startOffset,
        'paragraphFraction': 0,
        'contentRevision': first.contentRevision,
        if (!sameChapter) ...{'offset': 0, 'width': 0, 'layout': ''},
      });
      final createdAt = DateTime.now();
      final mark = ReaderBookmark(
        id: '${createdAt.microsecondsSinceEpoch}-${marks.length}',
        createdAt: createdAt.toUtc(),
        createdOffsetMinutes: createdAt.timeZoneOffset.inMinutes,
        chapterTitle: novel.chapters[chapter].title,
        position: anchor,
        quote: excerpt,
        underlineRanges: selected,
        annotation: annotation == null
            ? const ReaderAnnotationData()
            : _datedAnnotation(annotation, null),
      );
      final next = [mark, ...marks];
      final snapshot = _novelSnapshot(novel);
      if (snapshot != null) await _writeNovel(novel, snapshot);
      await _writeBookmarks(novel.id, next);
      _known[novel.id] = novel;
      _bookmarks[novel.id] = next;
      _updateUnderlineIndex(novel.id);
      if (!_disposed) _bookmarkChanges.notifyListeners();
      result = mark;
    });
    return result;
  }

  Future<ReaderBookmark?> addBookmark({
    required Novel novel,
    required ReadingPosition position,
    String quote = '',
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => addBookmark(novel: novel, position: position, quote: quote),
      );
    }
    final index = chapterForPosition(novel, position);
    final excerpt = quote.trim();
    if (excerpt.length > 12000) {
      throw const FormatException('摘录过长，请选择不超过 12000 字的内容');
    }
    if (novel.id <= 0 ||
        index == null ||
        !position.offset.isFinite ||
        position.offset < 0 ||
        !position.fraction.isFinite ||
        position.fraction < 0 ||
        position.fraction > 1 ||
        !position.width.isFinite ||
        !position.fontSize.isFinite ||
        !position.lineHeight.isFinite) {
      return null;
    }
    ReaderBookmark? result;
    await _queuePositionWrite(() async {
      final marks = _bookmarks[novel.id] ?? const <ReaderBookmark>[];
      for (final mark in marks) {
        if (!mark.isUnderline &&
            mark.quote == excerpt &&
            chapterForPosition(novel, mark.position) == index &&
            (excerpt.isEmpty ||
                mark.position.paragraphIndex == position.paragraphIndex &&
                    mark.position.textOffset == position.textOffset) &&
            (mark.position.offset - position.offset).abs() < 12 &&
            (mark.position.fontSize - position.fontSize).abs() < .01 &&
            (mark.position.lineHeight - position.lineHeight).abs() < .01 &&
            (mark.position.width - position.width).abs() < 1) {
          result = mark;
          return;
        }
      }
      if (marks.length >= 1000) {
        throw const FormatException('本书书签已达 1000 个，请先整理书签');
      }
      final createdAt = DateTime.now();
      final mark = ReaderBookmark(
        id: '${createdAt.microsecondsSinceEpoch}-${marks.length}',
        createdAt: createdAt.toUtc(),
        createdOffsetMinutes: createdAt.timeZoneOffset.inMinutes,
        chapterTitle: novel.chapters[index].title,
        position: position,
        quote: excerpt,
      );
      final next = [mark, ...marks];
      final snapshot = _novelSnapshot(novel);
      if (snapshot != null) await _writeNovel(novel, snapshot);
      await _writeBookmarks(novel.id, next);
      _known[novel.id] = novel;
      _bookmarks[novel.id] = next;
      _updateUnderlineIndex(novel.id);
      if (!_disposed) _bookmarkChanges.notifyListeners();
      result = mark;
    });
    return result;
  }

  Future<void> removeBookmark(int novelId, String id) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => removeBookmark(novelId, id));
    }
    return _queuePositionWrite(() async {
      final marks = _bookmarks[novelId];
      if (marks == null || !marks.any((mark) => mark.id == id)) return;
      final next = marks.where((mark) => mark.id != id).toList();
      await _writeBookmarks(novelId, next);
      _bookmarks[novelId] = next;
      _updateUnderlineIndex(novelId);
      if (!_disposed) _bookmarkChanges.notifyListeners();
    });
  }

  Future<void> categorizeBookmark(int novelId, String id, String category) {
    category = category.trim();
    if (category.length > 30) throw const FormatException('分类名称最多 30 个字');
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => categorizeBookmark(novelId, id, category),
      );
    }
    return _queuePositionWrite(() async {
      final marks = _bookmarks[novelId] ?? const <ReaderBookmark>[];
      final previous = marks.where((mark) => mark.id == id).firstOrNull;
      if (previous == null || previous.category == category) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = [
        for (final mark in marks)
          mark.id == id
              ? mark.withCategory(
                  category,
                  now > previous.categoryAt ? now : previous.categoryAt + 1,
                )
              : mark,
      ];
      await _writeBookmarks(novelId, next);
      _bookmarks[novelId] = next;
      _updateUnderlineIndex(novelId);
      if (!_disposed) _bookmarkChanges.notifyListeners();
    });
  }

  Future<void> _writeBookmarks(int novelId, List<ReaderBookmark> marks) async {
    final record = jsonEncode(marks.map((mark) => mark.toJson()).toList());
    await writeLibraryPreference(_prefs, 'reader_bookmarks_$novelId', record);
  }

  /// Format migrations change only coordinates, never edit timestamps, quotes,
  /// mark IDs, categories or active-reader positions. One journaled commit.
  Future<void> remapBookCoordinates(
    int id,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) resolve,
  ) => _queuePositionWrite(() async {
    final position = _positions[id];
    final marks = _bookmarks[id] ?? const <ReaderBookmark>[];
    final nextPosition = position == null || _activeReaders.containsKey(id)
        ? position
        : ReadingPosition.fromJson(await resolve(position.toJson()));
    // Visit each chapter's anchors together so a large book needs only a
    // bounded decoded-chapter cache; keep the user's original bookmark order.
    final ordered = marks.toList()
      ..sort(
        (a, b) =>
            (a.position.chapterId == 0
                    ? a.position.chapter
                    : a.position.chapterId)
                .compareTo(
                  b.position.chapterId == 0
                      ? b.position.chapter
                      : b.position.chapterId,
                ),
      );
    final converted = <String, ReaderBookmark>{};
    for (final mark in ordered) {
      final position = await resolve(mark.position.toJson());
      final ranges = <ReaderUnderlineRange>[];
      for (final (index, range) in mark.underlineRanges.indexed) {
        Map<String, Object> endpoint(int paragraph, int offset) {
          final chapter = _known[id]?.chapters.indexWhere(
            (chapter) => chapter.id == range.chapterId,
          );
          return {
            ...mark.position.toJson(),
            'chapterId': range.chapterId,
            if (chapter != null && chapter >= 0) 'chapter': chapter,
            'paragraphIndex': paragraph,
            'textOffset': offset,
            'paragraphFraction': 0,
            'contentRevision': range.contentRevision,
          };
        }

        final start = index == 0
            ? position
            : await resolve(endpoint(range.startParagraph, range.startOffset));
        final end = await resolve(
          endpoint(range.endParagraph, range.endOffset),
        );
        final mapped = ReaderUnderlineRange.fromJson({
          'chapterId': start['chapterId'],
          'startParagraph': start['paragraphIndex'],
          'startOffset': start['textOffset'],
          'endParagraph': end['paragraphIndex'],
          'endOffset': end['textOffset'],
          'contentRevision': start['contentRevision'] ?? '',
        });
        if (start['chapterId'] != end['chapterId']) {
          throw const FormatException('划线章节映射不一致，原记录已保留');
        }
        ranges.add(mapped);
      }
      converted[mark.id] = ReaderBookmark.fromJson({
        ...mark.toJson(),
        'position': position,
        if (mark.isUnderline)
          'underlineRanges': ranges.map((range) => range.toJson()).toList(),
      });
    }
    final nextMarks = [for (final mark in marks) converted[mark.id]!];
    final changes = <String, Object>{};
    if (nextPosition != null &&
        jsonEncode(nextPosition.toJson()) != jsonEncode(position?.toJson())) {
      changes['reading_position_$id'] = jsonEncode(nextPosition.toJson());
    }
    if (jsonEncode(marks.map((m) => m.toJson()).toList()) !=
        jsonEncode(nextMarks.map((m) => m.toJson()).toList())) {
      changes['reader_bookmarks_$id'] = jsonEncode(
        nextMarks.map((m) => m.toJson()).toList(),
      );
    }
    if (changes.isEmpty) return;
    await _commitLibraryRecords(changes);
    if (nextPosition != null) _positions[id] = nextPosition;
    _bookmarks[id] = nextMarks;
    _updateUnderlineIndex(id);
    if (!_disposed) _bookmarkChanges.notifyListeners();
    _historyChanged();
  });

  Future<void> applySyncedBookmarks(
    Map<int, List<ReaderBookmark>> updates,
    Map<int, String> expected,
  ) => _queuePositionWrite(() async {
    for (final id in updates.keys) {
      if (jsonEncode(bookmarksFor(id).map((m) => m.toJson()).toList()) !=
          expected[id]) {
        throw const FormatException('本机书签已变化，将在下次同步合并');
      }
      if (updates[id]!.length > 1000 ||
          updates[id]!.map((m) => m.id).toSet().length != updates[id]!.length) {
        throw const FormatException('同步书签数量或标识有误');
      }
    }
    await _commitLibraryRecords({
      for (final e in updates.entries)
        'reader_bookmarks_${e.key}': jsonEncode(
          e.value.map((m) => m.toJson()).toList(),
        ),
    });
    _bookmarks.addAll(updates);
    var underlineChanged = false;
    for (final id in updates.keys) {
      underlineChanged =
          _updateUnderlineIndex(id, notify: false) || underlineChanged;
    }
    if (underlineChanged && !_disposed) _underlineChanges.notifyListeners();
    if (!_disposed) _bookmarkChanges.notifyListeners();
  });

  Future<void> toggleShelf(int id, {Novel? novel}) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => toggleShelf(id, novel: novel));
    }
    return setShelfMembership(id, !contains(id), novel: novel);
  }

  /// One transactional merge/notification rather than rebuilding the shelf
  /// once per imported cloud/legacy ID. Reading records are never overwritten.
  Future<void> addShelfIds(Iterable<int> values) async {
    final ids = values.where((id) => id > 0 && !isLocalBook(id)).toSet();
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return addShelfIds(ids);
    }
    await _queuePositionWrite(() async {
      final additions = ids.difference(_shelf);
      if (additions.isEmpty) return;
      final shelf = {..._shelf, ...additions};
      final now = DateTime.now().millisecondsSinceEpoch;
      await _commitLibraryRecords({
        'shelf': shelf.map((id) => '$id').toList(),
        for (final id in additions) 'shelf_added_$id': now,
      });
      _shelf.addAll(additions);
      for (final id in additions) {
        _added[id] = now;
        _shelfRevisions[id] = shelfRevision(id) + 1;
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> applyCloudShelf({
    required Set<int> add,
    required Set<int> remove,
    required Map<int, int> expectedRevisions,
  }) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => applyCloudShelf(
          add: add,
          remove: remove,
          expectedRevisions: expectedRevisions,
        ),
      );
    }
    return _queuePositionWrite(() async {
      final next = {..._shelf};
      final now = DateTime.now().millisecondsSinceEpoch;
      final added = <int>{};
      for (final id in {...add, ...remove}) {
        if (id <= 0 ||
            isLocalBook(id) ||
            shelfRevision(id) != (expectedRevisions[id] ?? 0)) {
          continue;
        }
        if (add.contains(id)) {
          if (next.add(id)) added.add(id);
        } else {
          next.remove(id);
        }
      }
      if (setEquals(next, _shelf)) return;
      final changed = {...next.difference(_shelf), ..._shelf.difference(next)};
      await _commitLibraryRecords({
        'shelf': next.map((id) => '$id').toList(),
        for (final id in added) 'shelf_added_$id': now,
      });
      _shelf
        ..clear()
        ..addAll(next);
      for (final id in added) {
        _added[id] = now;
      }
      for (final id in changed) {
        _shelfRevisions[id] = shelfRevision(id) + 1;
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> setShelfMembership(
    int id,
    bool present, {
    Novel? novel,
    int? restoredAddedAt,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setShelfMembership(
          id,
          present,
          novel: novel,
          restoredAddedAt: restoredAddedAt,
        ),
      );
    }
    if (id <= 0) return;
    present = present && !isLocalBook(id);
    await _queuePositionWrite(() async {
      final changedMembership = contains(id) != present;
      final shelf = {..._shelf};
      if (present) {
        shelf.add(id);
      } else {
        shelf.remove(id);
      }
      final timestamp = changedMembership && present
          ? restoredAddedAt != null && restoredAddedAt >= 0
                ? restoredAddedAt
                : DateTime.now().millisecondsSinceEpoch
          : _added[id];
      final snapshot = novel == null ? null : _novelSnapshot(novel);
      try {
        await _commitLibraryRecords({
          if (changedMembership) 'shelf': shelf.map((id) => '$id').toList(),
          if (present && timestamp != null) 'shelf_added_$id': timestamp,
          'novel_meta_$id': ?snapshot,
        });
      } catch (_) {
        if (novel != null && identical(_persistedNovels[id], novel)) {
          _persistedNovels.remove(id);
        }
        rethrow;
      }
      _shelf
        ..clear()
        ..addAll(shelf);
      if (present && timestamp != null) _added[id] = timestamp;
      if (novel != null) _known[id] = novel;
      if (changedMembership) _shelfRevisions[id] = shelfRevision(id) + 1;
      if (!_disposed && (changedMembership || novel != null)) notifyListeners();
    });
  }

  /// Copy records through explicit chapter identities without deleting the
  /// source records. Receipts make repeated reconciliation safe after a restart
  /// and prevent removed series bookmarks from being copied back again.
  Future<void> combineBookRecords({
    required Novel target,
    required Map<Novel, Map<int, int>> sources,
    bool? onShelf,
    bool revealTarget = true,
    bool splitUnderlines = false,
  }) async {
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return combineBookRecords(
        target: target,
        sources: sources,
        onShelf: onShelf,
        revealTarget: revealTarget,
        splitUnderlines: splitUnderlines,
      );
    }
    await _queuePositionWrite(() async {
      final receiptKey = 'book_merge_${target.id}';
      final receipts = {...?_prefs.getStringList(receiptKey)};
      final indices = {for (final (i, c) in target.chapters.indexed) c.id: i};
      ReadingPosition? move(
        ReadingPosition value,
        Map<int, int> mapping,
        Novel source,
      ) {
        final index = chapterForPosition(source, value);
        if (index == null) return null;
        final chapterId = mapping[source.chapters[index].id];
        final next = indices[chapterId];
        return next == null
            ? null
            : ReadingPosition.fromJson({
                ...value.toJson(),
                'chapter': next,
                'chapterId': chapterId,
              });
      }

      final identity = {for (final c in target.chapters) c.id: c.id};
      List<ReaderUnderlineRange>? moveRanges(
        ReaderBookmark mark,
        Map<int, int> mapping, {
        bool partial = false,
      }) {
        final ranges = <ReaderUnderlineRange>[];
        for (final range in mark.underlineRanges) {
          final id = mapping[range.chapterId];
          if (id == null || !indices.containsKey(id)) {
            if (partial) continue;
            return null;
          }
          ranges.add(range.inChapter(id));
        }
        return List.unmodifiable(ranges);
      }

      var position = _positions[target.id];
      if (position != null) {
        position = move(position, identity, target) ?? position;
      }
      int? legacyChapter = _chapters[target.id];
      final bookmarks = <ReaderBookmark>[
        for (final mark in _bookmarks[target.id] ?? const <ReaderBookmark>[])
          ReaderBookmark(
            id: mark.id,
            chapterTitle: mark.chapterTitle,
            position: move(mark.position, identity, target) ?? mark.position,
            quote: mark.quote,
            category: mark.category,
            categoryAt: mark.categoryAt,
            underlineRanges: moveRanges(mark, identity) ?? mark.underlineRanges,
            annotation: mark.annotation,
            rangeUpdatedAt: mark.rangeUpdatedAt,
            createdAt: mark.createdAt,
            createdOffsetMinutes: mark.createdOffsetMinutes,
          ),
      ];
      final markIds = bookmarks.map((m) => m.id).toSet();
      final fingerprints = <String, List<int>>{};
      for (var i = 0; i < bookmarks.length; i++) {
        (fingerprints[_bookmarkFingerprint(bookmarks[i])] ??= []).add(i);
      }
      for (final entry in sources.entries) {
        final source = entry.key;
        if (source.id == target.id) continue;
        receipts.add('${source.id}');
        final old = _positions[source.id];
        final moved = old == null ? null : move(old, entry.value, source);
        if (moved != null &&
            (position == null || moved.updatedAt > position.updatedAt)) {
          position = moved;
        }
        if (legacyChapter == null &&
            hasRead(source.id) &&
            source.chapters.isNotEmpty) {
          final oldIndex = chapterForNovel(source);
          legacyChapter = indices[entry.value[source.chapters[oldIndex].id]];
        }
        for (final mark in _bookmarks[source.id] ?? const <ReaderBookmark>[]) {
          var mapped = move(mark.position, entry.value, source);
          final ranges = moveRanges(
            mark,
            entry.value,
            partial: splitUnderlines,
          );
          if (ranges == null) continue;
          if (mark.isUnderline && ranges.isEmpty) continue;
          if (mapped == null && splitUnderlines && ranges.isNotEmpty) {
            final first = ranges.first;
            mapped = ReadingPosition.fromJson({
              ...mark.position.toJson(),
              'chapter': indices[first.chapterId],
              'chapterId': first.chapterId,
              'paragraphIndex': first.startParagraph,
              'textOffset': first.startOffset,
              'paragraphFraction': 0,
              'offset': 0,
              'fraction': 0,
              'width': 0,
              'layout': '',
              'contentRevision': first.contentRevision,
            });
          }
          if (mapped == null) continue;
          if (!receipts.add('m/${source.id}/${mark.id}')) continue;
          final id = '${source.id}/${mark.id}';
          final copied = ReaderBookmark(
            id: id,
            chapterTitle: target.chapters[mapped.chapter].title,
            position: mapped,
            quote: mark.quote,
            category: mark.category,
            categoryAt: mark.categoryAt,
            underlineRanges: ranges,
            annotation: mark.annotation,
            rangeUpdatedAt: mark.rangeUpdatedAt,
            createdAt: mark.createdAt,
            createdOffsetMinutes: mark.createdOffsetMinutes,
          );
          final fingerprint = _bookmarkFingerprint(copied);
          final duplicate = (fingerprints[fingerprint] ?? const <int>[])
              .where((at) => _canDeduplicateBookmark(bookmarks[at], copied))
              .firstOrNull;
          if (duplicate != null) {
            bookmarks[duplicate] = _mergeBookmarkMetadata(
              bookmarks[duplicate],
              copied,
            );
          } else if (markIds.add(id)) {
            (fingerprints[fingerprint] ??= []).add(bookmarks.length);
            bookmarks.add(copied);
          }
        }
      }
      if (bookmarks.length > 1000) {
        throw const FormatException('合并后超过 1000 个书签，请先整理书签；原阅读记录仍保留');
      }
      bookmarks.sort(
        (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
      );
      final memberIds = sources.keys
          .map((b) => b.id)
          .where((id) => id != target.id)
          .toSet();
      final present =
          !isLocalBook(target.id) &&
          (onShelf ?? (contains(target.id) || memberIds.any(contains)));
      final shelf = {..._shelf}..removeAll(memberIds);
      if (present) {
        shelf.add(target.id);
      } else {
        shelf.remove(target.id);
      }
      final hidden = {..._hiddenHistory, ...memberIds.where(hasRead)};
      if (revealTarget && (position != null || legacyChapter != null)) {
        hidden.remove(target.id);
      }
      final chapter = position?.chapter ?? legacyChapter;
      final sourceAdded =
          memberIds.map((id) => _added[id]).whereType<int>().toList()..sort();
      final added =
          _added[target.id] ??
          (sourceAdded.isEmpty
              ? DateTime.now().millisecondsSinceEpoch
              : sourceAdded.first);
      final snapshot = jsonEncode(target.toSnapshot());
      final records = <String, Object>{
        receiptKey: receipts.toList()..sort(),
        'shelf': shelf.map((id) => '$id').toList(),
        'reading_history_hidden': hidden.map((id) => '$id').toList(),
        'novel_meta_${target.id}': snapshot,
        if (present) 'shelf_added_${target.id}': added,
        'chapter_${target.id}': ?chapter,
        if (position != null)
          'reading_position_${target.id}': jsonEncode(position.toJson()),
        if (bookmarks.isNotEmpty || _bookmarks.containsKey(target.id))
          'reader_bookmarks_${target.id}': jsonEncode(
            bookmarks.map((m) => m.toJson()).toList(),
          ),
      };
      records.removeWhere((key, value) {
        final old = _prefs.get(key);
        return old == value ||
            value is List<String> && old is List && listEquals(value, old);
      });
      if (records.isNotEmpty) await _commitLibraryRecords(records);
      final oldShelf = {..._shelf};
      _shelf
        ..clear()
        ..addAll(shelf);
      for (final id in {...oldShelf, ...shelf}) {
        if (oldShelf.contains(id) != shelf.contains(id)) {
          _shelfRevisions[id] = shelfRevision(id) + 1;
        }
      }
      _hiddenHistory
        ..clear()
        ..addAll(hidden);
      _known[target.id] = target;
      _persistedNovels[target.id] = target;
      if (present) _added[target.id] = added;
      if (position != null) _positions[target.id] = position;
      if (chapter != null) _chapters[target.id] = chapter;
      if (bookmarks.isNotEmpty || _bookmarks.containsKey(target.id)) {
        _bookmarks[target.id] = bookmarks;
        _updateUnderlineIndex(target.id);
      }
      if (!_disposed && records.isNotEmpty) {
        _historyChanged();
        _bookmarkChanges.notifyListeners();
        notifyListeners();
      }
    });
  }

  /// Projects a changed local-series directory after detached records have
  /// been copied back to their originals. No reading timestamp is advanced.
  Future<void> remapBookContents({
    required Novel previous,
    required Novel target,
    Set<int> detachedSourceIds = const {},
  }) async {
    if (previous.id != target.id || target.chapters.isEmpty) {
      throw const FormatException('书籍目录已变化，请返回后重试');
    }
    if (_restoreBarrier case final barrier?) {
      await barrier.future;
      return remapBookContents(
        previous: previous,
        target: target,
        detachedSourceIds: detachedSourceIds,
      );
    }
    await _queuePositionWrite(() async {
      final indices = {for (final (i, c) in target.chapters.indexed) c.id: i};
      ReadingPosition? project(
        ReadingPosition value, {
        bool resume = false,
        ReaderUnderlineRange? anchor,
      }) {
        final oldIndex = chapterForPosition(previous, value);
        final id = value.chapterId > 0
            ? value.chapterId
            : oldIndex == null
            ? null
            : previous.chapters[oldIndex].id;
        var index = indices[id];
        var relocated = false;
        if (index == null && anchor != null) {
          index = indices[anchor.chapterId];
          relocated = true;
        }
        if (index == null && resume) {
          // Prefer the next surviving chapter; at the end, use the nearest
          // preceding one. Its text anchor starts fresh, not at the old offset.
          final start = oldIndex ?? value.chapter;
          for (var i = start + 1; i < previous.chapters.length; i++) {
            if ((index = indices[previous.chapters[i].id]) != null) break;
          }
          for (var i = start - 1; index == null && i >= 0; i--) {
            if (i < previous.chapters.length) {
              index = indices[previous.chapters[i].id];
            }
          }
          index ??= 0;
          relocated = true;
        }
        if (index == null) return null;
        return ReadingPosition.fromJson({
          ...value.toJson(),
          'chapter': index,
          'chapterId': target.chapters[index].id,
          if (relocated) ...{
            'offset': 0,
            'fraction': 0,
            'width': 0,
            'layout': '',
            'paragraphIndex': anchor?.startParagraph ?? 0,
            'paragraphFraction': 0,
            'textOffset': anchor?.startOffset ?? 0,
            'contentRevision': anchor?.contentRevision ?? '',
          },
        });
      }

      final oldPosition = _positions[target.id];
      final position = oldPosition == null
          ? null
          : project(oldPosition, resume: true);
      final oldChapter = _chapters[target.id];
      final chapter =
          position?.chapter ??
          (oldChapter == null
              ? null
              : project(
                  ReadingPosition.fromJson({'chapter': oldChapter}),
                  resume: true,
                )!.chapter);
      final bookmarks = <ReaderBookmark>[];
      for (final mark in _bookmarks[target.id] ?? const <ReaderBookmark>[]) {
        final ranges = mark.underlineRanges
            .where((range) => indices.containsKey(range.chapterId))
            .toList(growable: false);
        if (mark.isUnderline && ranges.isEmpty) continue;
        final mapped = project(mark.position, anchor: ranges.firstOrNull);
        if (mapped == null) continue;
        bookmarks.add(
          ReaderBookmark(
            id: mark.id,
            chapterTitle: target.chapters[mapped.chapter].title,
            position: mapped,
            quote: mark.quote,
            category: mark.category,
            categoryAt: mark.categoryAt,
            underlineRanges: ranges,
            annotation: mark.annotation,
            rangeUpdatedAt: mark.rangeUpdatedAt,
            createdAt: mark.createdAt,
            createdOffsetMinutes: mark.createdOffsetMinutes,
          ),
        );
      }
      final receiptKey = 'book_merge_${target.id}';
      final receipts = {...?_prefs.getStringList(receiptKey)}
        ..removeWhere(
          (receipt) => detachedSourceIds.any(
            (id) => receipt == '$id' || receipt.startsWith('m/$id/'),
          ),
        );
      final snapshot = jsonEncode(target.toSnapshot());
      final records = <String, Object>{
        receiptKey: receipts.toList()..sort(),
        'novel_meta_${target.id}': snapshot,
        'chapter_${target.id}': ?chapter,
        if (position != null)
          'reading_position_${target.id}': jsonEncode(position.toJson()),
        if (_bookmarks.containsKey(target.id))
          'reader_bookmarks_${target.id}': jsonEncode(
            bookmarks.map((mark) => mark.toJson()).toList(),
          ),
      };
      records.removeWhere((key, value) {
        final old = _prefs.get(key);
        return old == value ||
            value is List<String> && old is List && listEquals(value, old);
      });
      if (records.isNotEmpty) await _commitLibraryRecords(records);
      _known[target.id] = target;
      _persistedNovels[target.id] = target;
      if (position != null) _positions[target.id] = position;
      if (chapter != null) _chapters[target.id] = chapter;
      if (_bookmarks.containsKey(target.id)) {
        _bookmarks[target.id] = bookmarks;
        _updateUnderlineIndex(target.id);
      }
      if (!_disposed && records.isNotEmpty) {
        _historyChanged();
        _bookmarkChanges.notifyListeners();
        notifyListeners();
      }
    });
  }

  Future<void> setChapter(int id, int chapter) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setChapter(id, chapter));
    }
    if (id <= 0 || chapter < 0) return;
    _chapters[id] = chapter;
    final reveal = _hiddenHistory.remove(id);
    final hidden = reveal ? _hiddenHistory.map((id) => '$id').toList() : null;
    notifyListeners();
    _historyChanged();
    await _queuePositionWrite(() async {
      await writeLibraryPreference(_prefs, 'chapter_$id', chapter);
      if (hidden != null) {
        await writeLibraryPreference(_prefs, 'reading_history_hidden', hidden);
      }
    });
  }

  Future<void> savePosition({
    required Novel novel,
    required int chapter,
    required double offset,
    required double maximum,
    required double width,
    bool notify = true,
    int? paragraphIndex,
    double paragraphFraction = 0,
    int? textOffset,
    double textScale = 1,
    String? typeface,
    String contentRevision = '',
  }) {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => savePosition(
          novel: novel,
          chapter: chapter,
          offset: offset,
          maximum: maximum,
          width: width,
          notify: notify,
          paragraphIndex: paragraphIndex,
          paragraphFraction: paragraphFraction,
          textOffset: textOffset,
          textScale: textScale,
          typeface: typeface,
          contentRevision: contentRevision,
        ),
      );
    }
    if (novel.id <= 0 ||
        !offset.isFinite ||
        !maximum.isFinite ||
        !width.isFinite ||
        !paragraphFraction.isFinite ||
        !textScale.isFinite ||
        chapter < 0 ||
        chapter >= novel.chapters.length) {
      return Future.value();
    }
    final position = ReadingPosition(
      chapter: chapter,
      chapterId: novel.chapters[chapter].id,
      offset: offset.clamp(0, double.infinity),
      fraction: maximum > 0 ? (offset / maximum).clamp(0, 1) : 0,
      fontSize: readerFontSizeFor(novel.id),
      width: width,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      lineHeight: readerLineHeightFor(novel.id),
      paragraphIndex: paragraphIndex != null && paragraphIndex >= 0
          ? paragraphIndex
          : null,
      paragraphFraction: paragraphFraction.clamp(0, 1),
      textOffset: textOffset != null && textOffset >= 0 ? textOffset : null,
      textScale: textScale.clamp(.5, 5),
      typeface: validFontChoice(typeface)
          ? typeface!
          : readerFontIdFor(novel.id),
      layout: readerPreferencesFor(novel.id).layoutKey,
      contentRevision: contentRevision,
    );
    _positions[novel.id] = position;
    final chapterChanged = _chapters[novel.id] != chapter;
    _chapters[novel.id] = chapter;
    _known[novel.id] = novel;
    final reveal = _hiddenHistory.remove(novel.id);
    final hidden = reveal ? _hiddenHistory.map((id) => '$id').toList() : null;
    if (notify) notifyListeners();
    _historyChanged();
    final snapshot = _novelSnapshot(novel);
    final record = jsonEncode(position.toJson());
    return _queuePositionWrite(() async {
      if (chapterChanged) {
        await writeLibraryPreference(_prefs, 'chapter_${novel.id}', chapter);
      }
      await writeLibraryPreference(
        _prefs,
        'reading_position_${novel.id}',
        record,
      );
      if (snapshot != null) await _writeNovel(novel, snapshot);
      if (hidden != null) {
        await writeLibraryPreference(_prefs, 'reading_history_hidden', hidden);
      }
    });
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setTheme(mode));
    }
    if (_theme == mode) {
      if (_prefs.get('theme') != null && _prefs.get('theme') != mode.name) {
        await writeLibraryPreference(_prefs, 'theme', mode.name);
      }
      return;
    }
    _theme = mode;
    _application.notifyListeners();
    _appearance.notifyListeners();
    _settings.notifyListeners();
    notifyListeners();
    await writeLibraryPreference(_prefs, 'theme', mode.name);
  }

  Future<void> setAppTypeface(AppTypeface value) => setAppFont(value.name);

  Future<void> downloadReadingFont([String id = sourceHanFontId]) async {
    await fonts.downloadFont(id);
    if (_bookReaderStyles.values.any(
      (style) => style.enabled && style.typeface == id,
    )) {
      await fonts.ensureLoaded(id);
    }
    await loadFonts();
  }

  Future<void> setAppFont(String choice) => _setFont(choice, reader: false);
  Future<void> setReaderTypeface(String choice, {int? bookId}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setReaderTypeface(choice, bookId: bookId),
      );
    }
    if (_readerStyleFor(bookId) case final style?) {
      if (choice != followAppFont && !fonts.available(choice)) {
        throw const FormatException('请先导入这款字体');
      }
      await fonts.ensureLoaded(choice);
      return _setBookReaderStyle(bookId!, style.copyWith(typeface: choice));
    }
    return _setFont(choice, reader: true);
  }

  Future<void> _setFont(String choice, {required bool reader}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => _setFont(choice, reader: reader));
    }
    if (!(reader && choice == followAppFont) && !fonts.available(choice)) {
      throw const FormatException('请先导入这款字体');
    }
    await fonts.ensureLoaded(choice);
    await _queuePositionWrite(() async {
      if ((reader ? _readerTypeface : appFontChoice) == choice) return;
      final oldReader = readerFontId;
      final oldApp = appFontId;
      if (reader) {
        await _commitLibraryRecords({'readerTypeface': choice});
        _readerTypeface = choice;
      } else {
        final builtin = AppTypeface.fromRecord(choice);
        final custom = choice.startsWith('font_') ? choice : '';
        await _commitLibraryRecords({
          'appTypeface': builtin.name,
          'appCustomFont': custom,
        });
        _appTypeface = builtin;
        _appCustomFont = custom.isEmpty ? null : custom;
      }
      if (!_disposed) {
        if (!reader) {
          _application.notifyListeners();
          _appearance.notifyListeners();
        }
        if (oldReader != readerFontId ||
            oldApp != appFontId &&
                _bookReaderStyles.values.any(
                  (style) => style.enabled && style.typeface == followAppFont,
                )) {
          _readerSettings.notifyListeners();
        }
        _settings.notifyListeners();
        notifyListeners();
      }
    });
  }

  Future<void> removeUserFont(String id) async {
    if (appFontChoice == id) await setAppFont('system');
    if (_readerTypeface == id) await setReaderTypeface(followAppFont);
    await _queuePositionWrite(() async {
      final changed = {
        for (final entry in _bookReaderStyles.entries)
          if (entry.value.typeface == id)
            entry.key: entry.value.copyWith(typeface: followAppFont),
      };
      if (changed.isEmpty) return;
      await _commitLibraryRecords({
        for (final entry in changed.entries)
          '$bookReaderStylePrefix${entry.key}': jsonEncode(
            entry.value.toJson(),
          ),
      });
      _bookReaderStyles.addAll(changed);
      if (!_disposed) _readerSettings.notifyListeners();
    });
    await fonts.remove(id);
    if (!_disposed) _settings.notifyListeners();
  }

  Future<void> setFontSize(double size, {bool persist = true}) =>
      setTypography(fontSize: size, persist: persist);

  Future<void> setLineHeight(double value, {bool persist = true}) =>
      setTypography(lineHeight: value, persist: persist);

  Future<void> setTypography({
    double? fontSize,
    double? lineHeight,
    bool persist = true,
    int? bookId,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setTypography(
          fontSize: fontSize,
          lineHeight: lineHeight,
          persist: persist,
          bookId: bookId,
        ),
      );
    }
    if (_readerStyleFor(bookId) case final style?) {
      return _setBookReaderStyle(
        bookId!,
        style.copyWith(
          fontSize: fontSize?.isFinite == true
              ? fontSize!.clamp(minimumReaderFontSize, maximumReaderFontSize)
              : style.fontSize,
          lineHeight: lineHeight?.isFinite == true
              ? lineHeight!.clamp(1.3, 2.2)
              : style.lineHeight,
        ),
        persist: persist,
      );
    }
    final font = fontSize?.isFinite == true
        ? fontSize!.clamp(minimumReaderFontSize, maximumReaderFontSize)
        : _fontSize;
    final spacing = lineHeight?.isFinite == true
        ? lineHeight!.clamp(1.3, 2.2)
        : _lineHeight;
    if (font != _fontSize || spacing != _lineHeight) {
      _fontSize = font;
      _lineHeight = spacing;
      _readerSettings.notifyListeners();
      _settings.notifyListeners();
    }
    if (persist) {
      if (fontSize?.isFinite == true) {
        await writeLibraryPreference(_prefs, 'readerFontSize', font);
      }
      if (lineHeight?.isFinite == true) {
        await writeLibraryPreference(_prefs, 'readerLineHeight', spacing);
      }
    }
  }

  /// Persist before notifying so failed writes never change the active pulses.
  Future<void> setHaptics(HapticPreferences value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setHaptics(value));
    }
    await _queuePositionWrite(() async {
      if (_haptics == value) return;
      await _commitLibraryRecords(value.toRecords());
      _haptics = value;
      if (!_disposed) {
        _application.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setPerformance(PerformancePreferences value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setPerformance(value));
    }
    await _queuePositionWrite(() async {
      if (_performance == value) return;
      // Commit all switches together. A failed disk write must not leave the
      // visible mode different from the one restored on the next launch.
      await _commitLibraryRecords(value.toRecords());
      _performance = value;
      if (!_disposed) {
        _application.notifyListeners();
        _appearance.notifyListeners();
        _settings.notifyListeners();
      }
    });
  }

  Future<void> setReduceMotion(bool value) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setReduceMotion(value));
    }
    if (_reduceMotion == value) {
      if (_prefs.get('reduceMotion') != null &&
          _prefs.get('reduceMotion') != value) {
        await writeLibraryPreference(_prefs, 'reduceMotion', value);
      }
      return;
    }
    _reduceMotion = value;
    _application.notifyListeners();
    _appearance.notifyListeners();
    _settings.notifyListeners();
    notifyListeners();
    await writeLibraryPreference(_prefs, 'reduceMotion', value);
  }

  Future<void> setGlassBlur(double value, {bool persist = true}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then((_) => setGlassBlur(value, persist: persist));
    }
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 24.0);
    if (_glassBlur != next) {
      _glassBlur = next;
      _glassChanges.notifyListeners();
      _appearance.notifyListeners();
      _settings.notifyListeners();
      notifyListeners();
    }
    if (persist) {
      await writeLibraryPreference(_prefs, 'glassBlur', next);
    }
  }

  Future<void> setGlassOpacity(double value, {bool persist = true}) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => setGlassOpacity(value, persist: persist),
      );
    }
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 1.0);
    if (_glassOpacity != next) {
      _glassOpacity = next;
      _glassChanges.notifyListeners();
      _appearance.notifyListeners();
      _settings.notifyListeners();
      notifyListeners();
    }
    if (persist) {
      await writeLibraryPreference(_prefs, 'glassOpacity', next);
    }
  }

  Map<String, Object> _backupRecords({bool includeReadingActivity = true}) => {
    if (includeReadingActivity)
      ReadingActivityStore.preferenceKey: readingActivity.encode(),
    if (includeReadingActivity)
      ReadingMomentsStore.preferenceKey: readingMoments.encode(),
    for (final entry in _bookReaderStyles.entries)
      '$bookReaderStylePrefix${entry.key}': jsonEncode(entry.value.toJson()),
    for (final entry in _illustrations.entries)
      'illustration_layout_${entry.key}': jsonEncode(
        entry.value.map((item) => item.toJson()).toList(),
      ),
    for (final key in _prefs.getKeys().where(
      (k) => k.startsWith('book_merge_'),
    ))
      key: _prefs.getStringList(key) ?? <String>[],
    'shelf': _shelf.map((id) => '$id').toList(),
    'reading_history_hidden': _hiddenHistory.map((id) => '$id').toList(),
    'local_shelf_hidden': _hiddenLocalBooks.map((id) => '$id').toList(),
    'recentSearches': _recentSearches,
    BlockedTags.preferenceKey: _blockedTags.toRecord(),
    'theme': _theme.name,
    'readerFontSize': _fontSize,
    'appLanguage': language.name,
    'readerLineHeight': _lineHeight,
    'reduceMotion': _reduceMotion,
    ..._haptics.toRecords(),
    'appTypeface': _appTypeface.name,
    'appCustomFont': _appCustomFont ?? '',
    'readerTypeface': _readerTypeface,
    ..._performance.toRecords(),
    'glassBlur': _glassBlur,
    'glassOpacity': _glassOpacity,
    'readerKeepScreenOn': _keepScreenOn,
    'forcePortrait': _forcePortrait,
    'readerPreferences': jsonEncode(_readerPreferences.toJson()),
    'shelfSort': _shelfSort,
    'shelfFilter': _shelfFilter,
    'shelfSourceFilter': _shelfSourceFilter,
    'shelfLayout': _shelfLayout,
    'shelfGridDensity': _shelfGridDensity.value,
    'shelfPreferences': _shelfPreferences.record,
    'shelfContent': _shelfContent.record,
    'discoveryShelfPreferences': _discoveryShelfPreferences.record,
    'discoveryShelfContent': _discoveryShelfContent.record,
    if (_hasDiscoveryShelfQuery)
      'discoveryShelfQuery': _discoveryShelfQuery.record,
    'localShelfContent': organization.shelfContent.record,
    'discoveryLayout': _discoveryViewMode.storageValue,
    'discoveryGridDensity': _discoveryGridDensity.value,
    'adaptWhenOffline': _adaptWhenOffline,
    'localReaderMode': _localReaderMode,
    'directReading': directReading,
    'openRecentOnLaunch': _openRecentOnLaunch,
    'startPage': _startPage.name,
    'directReadingPages': [
      for (final page in ReadingEntry.values)
        if (_directReadingPages.contains(page)) page.name,
    ],
    'combinedShelf': _combinedShelf,
    'localTxtEncoding': organization.encoding,
    if (_prefs.containsKey(LocalImportOptions.preferenceKey))
      LocalImportOptions.preferenceKey: organization.importOptions.encode(),
    for (final entry in _added.entries) 'shelf_added_${entry.key}': entry.value,
    for (final entry in _known.entries)
      'novel_meta_${entry.key}': jsonEncode(entry.value.toSnapshot()),
    for (final entry in _chapters.entries) 'chapter_${entry.key}': entry.value,
    for (final entry in _positions.entries)
      'reading_position_${entry.key}': jsonEncode(entry.value.toJson()),
    for (final entry in _bookmarks.entries)
      'reader_bookmarks_${entry.key}': jsonEncode(
        entry.value.map((mark) => mark.toJson()).toList(),
      ),
  };

  /// Manual backups include activity; cloud book synchronization excludes this
  /// local-only ledger explicitly while retaining its existing reading data.
  Future<LibraryBackup> createBackup({
    bool includeReadingActivity = true,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => createBackup(includeReadingActivity: includeReadingActivity),
      );
    }
    late LibraryBackup backup;
    await _queuePositionWrite(() async {
      backup = await LibraryBackup.fromRecords(
        _backupRecords(includeReadingActivity: includeReadingActivity),
      );
    });
    return backup;
  }

  /// Merge, do not replace: current newer positions and metadata win. Memory is
  /// published only after all keys commit, with a rollback journal across kills.
  Future<void> restoreBackup(
    LibraryBackup backup, {
    bool importPreferences = false,
  }) async {
    if (_restoreBarrier case final barrier?) {
      return barrier.future.then(
        (_) => restoreBackup(backup, importPreferences: importPreferences),
      );
    }
    final barrier = Completer<void>();
    _restoreBarrier = barrier;
    try {
      if (importPreferences && backup.records.containsKey('appLanguage')) {
        final restoredLanguage = AppLanguage.fromRecord(
          backup.records['appLanguage'],
        );
        if (chineseLocale(
              restoredLanguage.locale ??
                  WidgetsBinding.instance.platformDispatcher.locale,
            ).countryCode !=
            'CN') {
          await ChineseText.prepare();
        }
      }
      final restoredBlockedTags =
          importPreferences &&
              backup.records.containsKey(BlockedTags.preferenceKey)
          ? await BlockedTags.fromInput(
              (backup.records[BlockedTags.preferenceKey] as List)
                  .cast<String>(),
            )
          : null;
      await _queuePositionWrite(() async {
        final records = backup.records;
        final shelf = {
          ..._shelf,
          ...(records['shelf'] as List<String>? ?? const [])
              .map(int.parse)
              .where((id) => !isLocalBook(id)),
        };
        final added = {..._added};
        final known = {..._known};
        final chapters = {..._chapters};
        final positions = {..._positions};
        final marks = <int, List<ReaderBookmark>>{
          for (final entry in _bookmarks.entries) entry.key: [...entry.value],
        };
        final hidden = {..._hiddenHistory};
        final hiddenLocal = {
          ..._hiddenLocalBooks,
          ...(records['local_shelf_hidden'] as List<String>? ??
                  const <String>[])
              .map(int.parse)
              .where(isLocalBook),
        };
        final changed = <String, Object>{};
        final incomingActivity = records[ReadingActivityStore.preferenceKey];
        final incomingMoments = records[ReadingMomentsStore.preferenceKey];
        if (incomingMoments is String) {
          changed[ReadingMomentsStore.preferenceKey] = readingMoments
              .mergedRecord(
                incomingMoments,
                importPreferences: importPreferences,
              );
        }
        if (incomingActivity is String) {
          changed[ReadingActivityStore.preferenceKey] = readingActivity
              .mergedRecord(incomingActivity);
        }
        final bookStyles = {..._bookReaderStyles};
        final oldRead = {..._chapters.keys, ..._positions.keys};
        for (final entry in records.entries) {
          final key = entry.key;
          if (key.startsWith(bookReaderStylePrefix)) {
            if (importPreferences) {
              final id = int.parse(key.substring(bookReaderStylePrefix.length));
              bookStyles[id] = ReaderBookStyle.fromJson(
                jsonDecode(entry.value as String),
              );
              changed[key] = entry.value;
            }
          } else if (key.startsWith('book_merge_')) {
            changed[key] = {
              ...?_prefs.getStringList(key),
              ...(entry.value as List<String>),
            }.toList()..sort();
          } else if (key.startsWith('novel_meta_')) {
            final id = int.parse(key.substring('novel_meta_'.length));
            if (!known.containsKey(id)) {
              known[id] = Novel.fromSnapshot(jsonDecode(entry.value as String));
              changed[key] = entry.value;
            }
          } else if (key.startsWith('shelf_added_')) {
            final id = int.parse(key.substring('shelf_added_'.length));
            if (!added.containsKey(id)) {
              added[id] = entry.value as int;
              changed[key] = entry.value;
            }
          } else if (key.startsWith('chapter_')) {
            final id = int.parse(key.substring('chapter_'.length));
            if (!chapters.containsKey(id) && !positions.containsKey(id)) {
              chapters[id] = entry.value as int;
              changed[key] = entry.value;
            }
          } else if (key.startsWith('reading_position_')) {
            final id = int.parse(key.substring('reading_position_'.length));
            final incoming = ReadingPosition.fromJson(
              jsonDecode(entry.value as String),
            );
            if (positions[id] == null ||
                positions[id]!.updatedAt < incoming.updatedAt) {
              positions[id] = incoming;
              chapters[id] = incoming.chapter;
              changed[key] = jsonEncode(incoming.toJson());
              changed['chapter_$id'] = incoming.chapter;
            }
          } else if (key.startsWith('illustration_layout_')) {
            final id = int.parse(key.substring('illustration_layout_'.length));
            final values = {
              for (final item in illustrationsFor(id)) item.url: item,
            };
            for (final raw in jsonDecode(entry.value as String) as List) {
              final incoming = IllustrationPlacement.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (values[incoming.url] == null ||
                  values[incoming.url]!.updatedAt < incoming.updatedAt) {
                values[incoming.url] = incoming;
              }
            }
            if (values.length > 2000) {
              throw const FormatException('合并后的插图排版超过上限');
            }
            changed[key] = jsonEncode(
              values.values.map((item) => item.toJson()).toList(),
            );
          } else if (key.startsWith('reader_bookmarks_')) {
            final id = int.parse(key.substring('reader_bookmarks_'.length));
            final current = marks.putIfAbsent(id, () => []);
            final fingerprints = <String, List<int>>{};
            final byIds = <String, int>{};
            for (var i = 0; i < current.length; i++) {
              (fingerprints[_bookmarkFingerprint(current[i])] ??= []).add(i);
              byIds[current[i].id] = i;
            }
            final ids = current.map((mark) => mark.id).toSet();
            for (final raw in jsonDecode(entry.value as String) as List) {
              var mark = ReaderBookmark.fromJson(
                Map<String, dynamic>.from(raw),
              );
              final fingerprint = _bookmarkFingerprint(mark);
              final sameId = byIds[mark.id];
              if (sameId != null &&
                  (_bookmarkFingerprint(current[sameId]) == fingerprint ||
                      current[sameId].rangeUpdatedAt > 0 ||
                      mark.rangeUpdatedAt > 0)) {
                final before = _bookmarkFingerprint(current[sameId]);
                current[sameId] = _mergeBookmarkVersion(current[sameId], mark);
                final after = _bookmarkFingerprint(current[sameId]);
                if (before != after) {
                  fingerprints[before]?.remove(sameId);
                  (fingerprints[after] ??= []).add(sameId);
                }
                continue;
              }
              final duplicate = (fingerprints[fingerprint] ?? const <int>[])
                  .where((at) => _canDeduplicateBookmark(current[at], mark))
                  .firstOrNull;
              if (duplicate case final at?) {
                current[at] = _mergeBookmarkMetadata(current[at], mark);
                continue;
              }
              var candidate = mark.id;
              for (var suffix = 1; ids.contains(candidate); suffix++) {
                candidate = 'import-${mark.position.updatedAt}-$suffix';
              }
              ids.add(candidate);
              if (candidate != mark.id) {
                mark = ReaderBookmark(
                  id: candidate,
                  chapterTitle: mark.chapterTitle,
                  position: mark.position,
                  quote: mark.quote,
                  category: mark.category,
                  categoryAt: mark.categoryAt,
                  underlineRanges: mark.underlineRanges,
                  annotation: mark.annotation,
                  rangeUpdatedAt: mark.rangeUpdatedAt,
                  createdAt: mark.createdAt,
                  createdOffsetMinutes: mark.createdOffsetMinutes,
                );
              }
              (fingerprints[fingerprint] ??= []).add(current.length);
              byIds[mark.id] = current.length;
              current.add(mark);
            }
            if (current.length > 1000) {
              throw const FormatException('合并后单本书超过 1000 个书签，请先整理书签');
            }
            current.sort(
              (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
            );
            changed[key] = jsonEncode(
              current.map((mark) => mark.toJson()).toList(),
            );
          }
        }
        for (final id in shelf) {
          added.putIfAbsent(id, () => backup.createdAt);
          if (!_added.containsKey(id)) changed['shelf_added_$id'] = added[id]!;
        }
        for (final id
            in (records['reading_history_hidden'] as List<String>? ?? const [])
                .map(int.parse)) {
          if (!oldRead.contains(id) &&
              (positions.containsKey(id) || chapters.containsKey(id))) {
            hidden.add(id);
          }
        }
        final seen = <String>{};
        final searches = <String>[
          ..._recentSearches,
          ...(records['recentSearches'] as List<String>? ?? const []),
        ].where((term) => seen.add(term.toLowerCase())).take(12).toList();
        changed['shelf'] = shelf.map((id) => '$id').toList();
        changed['reading_history_hidden'] = hidden.map((id) => '$id').toList();
        changed['local_shelf_hidden'] = hiddenLocal.map((id) => '$id').toList();
        changed['recentSearches'] = searches;
        if (importPreferences) {
          for (final key in backupPreferenceKeys) {
            if (records[key] case final value?) {
              // Local layout joins the transaction below under its own queue.
              if (key != 'localShelfContent') changed[key] = value;
            }
          }
          if (restoredBlockedTags != null) {
            changed[BlockedTags.preferenceKey] = restoredBlockedTags.toRecord();
          }
          if (records.containsKey('appTypeface') &&
              !records.containsKey('appCustomFont')) {
            changed['appCustomFont'] = '';
          }
        }
        if (importPreferences) {
          for (final choice in [
            records['appCustomFont'],
            records['readerTypeface'],
            for (final style in bookStyles.values)
              if (style.enabled) style.typeface,
          ].whereType<String>().toSet()) {
            await fonts.ensureLoaded(choice);
          }
        }
        final localContent = importPreferences
            ? records['localShelfContent']
            : null;
        if (localContent is String) {
          await organization.restoreShelfContent(
            BookShelfContentPreferences.parseOrDefault(localContent),
            commit: (record) {
              changed[LocalLibraryPreferences.key] = record;
              return _commitLibraryRecords(changed);
            },
          );
        } else {
          await _commitLibraryRecords(changed);
        }
        if (incomingActivity is String) {
          // Merge into the latest memory rather than replacing it: a final
          // reader interval may have settled while the restore was committing.
          await readingActivity.mergeRecord(incomingActivity, persist: false);
        }
        if (incomingMoments is String) {
          await readingMoments.mergeRecord(
            incomingMoments,
            persist: false,
            importPreferences: importPreferences,
          );
        }
        if (importPreferences) {
          _bookReaderStyles
            ..clear()
            ..addAll(bookStyles);
        }
        for (final entry in changed.entries.where(
          (entry) => entry.key.startsWith('illustration_layout_'),
        )) {
          _illustrations[int.parse(
            entry.key.substring('illustration_layout_'.length),
          )] = [
            for (final raw in jsonDecode(entry.value as String) as List)
              IllustrationPlacement.fromJson(Map<String, dynamic>.from(raw)),
          ];
        }
        final oldShelf = {..._shelf};
        _shelf
          ..clear()
          ..addAll(shelf);
        for (final id in {...oldShelf, ...shelf}) {
          if (oldShelf.contains(id) != shelf.contains(id)) {
            _shelfRevisions[id] = shelfRevision(id) + 1;
          }
        }
        _added
          ..clear()
          ..addAll(added);
        _known
          ..clear()
          ..addAll(known);
        _persistedNovels
          ..clear()
          ..addAll(known);
        _chapters
          ..clear()
          ..addAll(chapters);
        _positions
          ..clear()
          ..addAll(positions);
        _bookmarks
          ..clear()
          ..addAll(marks);
        for (final id in marks.keys) {
          _updateUnderlineIndex(id, notify: false);
        }
        _hiddenHistory
          ..clear()
          ..addAll(hidden);
        _hiddenLocalBooks.clear();
        _recentSearches = searches;
        if (restoredBlockedTags != null) _blockedTags = restoredBlockedTags;
        if (importPreferences) {
          if (records['theme'] case final String value) {
            _theme = ThemeMode.values.firstWhere((mode) => mode.name == value);
          }
          if (records[AppPalettePreferences.key] case final String value) {
            _appPalette = AppPalettePreferences.decode(value);
          }
          if (records['readerFontSize'] case final num value) {
            _fontSize = value.toDouble();
          }
          if (records['readerLineHeight'] case final num value) {
            _lineHeight = value.toDouble();
          }
          if (records['glassBlur'] case final num value) {
            _glassBlur = value.toDouble();
          }
          if (records['glassOpacity'] case final num value) {
            _glassOpacity = value.toDouble();
          }
          if (records['reduceMotion'] case final bool value) {
            _reduceMotion = value;
          }
          if (records.containsKey(HapticPreferences.preferenceKey)) {
            _haptics = HapticPreferences.fromRecords(records);
          }
          if (records['appTypeface'] case final String value) {
            _appTypeface = AppTypeface.fromRecord(value);
            if (!records.containsKey('appCustomFont')) _appCustomFont = null;
          }
          if (records['appCustomFont'] case final String value) {
            _appCustomFont = value.isEmpty ? null : value;
          }
          if (records['readerTypeface'] case final String value) {
            _readerTypeface = value;
          }
          _performance = PerformancePreferences.fromRecords({
            ..._performance.toRecords(),
            for (final key in _performance.toRecords().keys)
              if (records.containsKey(key)) key: records[key],
          });
          if (records['readerKeepScreenOn'] case final bool value) {
            _keepScreenOn = value;
          }
          if (records['forcePortrait'] case final bool value) {
            _forcePortrait = value;
          }
          if (records['readerPreferences'] case final String value) {
            _readerPreferences = ReaderPreferences.fromRecord(value);
          }
          if (records['shelfSort'] case final String value) _shelfSort = value;
          if (records['shelfFilter'] case final String value) {
            _shelfFilter = value;
          }
          if (records['shelfSourceFilter'] case final String value) {
            _shelfSourceFilter = value;
          }
          if (records['shelfLayout'] case final String value) {
            _shelfLayout = BookCollectionMode.parseOrDefault(
              value,
            ).storageValue;
          }
          if (records['shelfGridDensity'] case final String value) {
            _shelfGridDensity = BookGridDensity.parseOrAuto(value);
          }
          if (records['shelfPreferences'] case final String value) {
            _shelfPreferences = BookShelfPreferences.parseOrDefault(value);
          }
          if (records['shelfContent'] case final String value) {
            _shelfContent = BookShelfContentPreferences.parseOrDefault(value);
          }
          if (records['discoveryLayout'] case final String value) {
            _discoveryViewMode = BookCollectionMode.parseOrDefault(value);
          }
          if (records['discoveryGridDensity'] case final String value) {
            _discoveryGridDensity = BookGridDensity.parseOrAuto(value);
          }
          if (records['discoveryShelfPreferences'] case final String value) {
            _discoveryShelfPreferences = BookShelfPreferences.parseOrDefault(
              value,
            );
          }
          if (records['discoveryShelfContent'] case final String value) {
            _discoveryShelfContent = BookShelfContentPreferences.parseOrDefault(
              value,
            );
          }
          if (records['discoveryShelfQuery'] case final String value) {
            _discoveryShelfQuery = DiscoveryShelfQuery.parseOrDefault(value);
            _hasDiscoveryShelfQuery = true;
          }
          if (records['adaptWhenOffline'] case final bool value) {
            _adaptWhenOffline = value;
          }
          if (records['localReaderMode'] case final bool value) {
            _localReaderMode = value;
          }
          if (records['openRecentOnLaunch'] case final bool value) {
            _openRecentOnLaunch = value;
          }
          if (records['startPage'] case final String value) {
            _startPage = AppStartPage.parseOrDefault(value);
          }
          if (records.containsKey('directReadingPages') ||
              records.containsKey('directReading')) {
            _directReadingPages = ReadingEntry.decode(
              records['directReadingPages'],
              legacy: records['directReading'] == true,
            );
            _directReadingEnabled =
                records['directReading'] == true &&
                _directReadingPages.isNotEmpty;
          }
          if (records['combinedShelf'] case final bool value) {
            _combinedShelf = value;
          }
        }
        if (!_disposed) {
          _historyChanged();
          _bookmarkChanges.notifyListeners();
          _underlineChanges.notifyListeners();
          _illustrationChanges.notifyListeners();
          _searchChanges.notifyListeners();
          _shelfViewChanges.notifyListeners();
          if (importPreferences) {
            _application.notifyListeners();
            _appearance.notifyListeners();
            _glassChanges.notifyListeners();
            _readerSettings.notifyListeners();
            _readerBehaviorChanges.notifyListeners();
            _settings.notifyListeners();
            _navigationChanges.notifyListeners();
            _discoveryViewChanges.notifyListeners();
            _blockedTagsChanges.notifyListeners();
          }
          notifyListeners();
        }
      });
    } finally {
      _restoreBarrier = null;
      barrier.complete();
    }
  }

  static String _bookmarkFingerprint(ReaderBookmark bookmark) {
    if (bookmark.isUnderline) {
      return jsonEncode({
        'underlineRanges': canonicalReaderUnderlineRanges(
          bookmark.underlineRanges,
        ).map((range) => range.toJson()).toList(),
      });
    }
    final position = {...bookmark.position.toJson()}..remove('updatedAt');
    if (bookmark.quote.isNotEmpty) position['quote'] = bookmark.quote;
    return jsonEncode(position);
  }

  static ReaderBookmark _mergeBookmarkMetadata(
    ReaderBookmark current,
    ReaderBookmark incoming,
  ) {
    var result = current;
    if (incoming.categoryAt > result.categoryAt) {
      result = result.withCategory(incoming.category, incoming.categoryAt);
    }
    if (incoming.annotation.updatedAt > result.annotation.updatedAt) {
      result = result.withAnnotation(incoming.annotation);
    }
    if (incoming.createdAt != null &&
        (result.createdAt == null ||
            incoming.createdAt!.isBefore(result.createdAt!))) {
      result = result.withCreation(
        incoming.createdAt!,
        incoming.createdOffsetMinutes,
      );
    } else if (result.createdAt != null &&
        result.createdAt == incoming.createdAt &&
        result.createdOffsetMinutes == null &&
        incoming.createdOffsetMinutes != null) {
      result = result.withCreation(
        result.createdAt!,
        incoming.createdOffsetMinutes,
      );
    }
    return result;
  }

  static bool _canDeduplicateBookmark(ReaderBookmark a, ReaderBookmark b) =>
      a.rangeUpdatedAt == 0 &&
      b.rangeUpdatedAt == 0 &&
      a.annotation.style == b.annotation.style &&
      a.annotation.color == b.annotation.color &&
      a.note == b.note;

  static ReaderBookmark _mergeBookmarkVersion(
    ReaderBookmark current,
    ReaderBookmark incoming,
  ) {
    if (incoming.rangeUpdatedAt > current.rangeUpdatedAt) {
      return _mergeBookmarkMetadata(incoming, current);
    }
    return _mergeBookmarkMetadata(current, incoming);
  }

  Future<void> _commitLibraryRecords(Map<String, Object> changes) async {
    changes.removeWhere(
      (key, value) => jsonEncode(_prefs.get(key)) == jsonEncode(value),
    );
    if (changes.isEmpty) return;
    final journal = jsonEncode({
      for (final key in changes.keys) key: _prefs.get(key),
    });
    if (utf8.encode(journal).length > LibraryBackup.maxBytes * 2) {
      throw const FormatException('本地恢复日志过大');
    }
    try {
      await writeLibraryPreference(_prefs, restoreJournalKey, journal);
      for (final entry in changes.entries) {
        await writeLibraryPreference(_prefs, entry.key, entry.value);
      }
      await writeLibraryPreference(_prefs, restoreJournalKey, null);
    } catch (_) {
      if (_prefs.get(restoreJournalKey) != null) {
        await recoverLibraryRestore(_prefs);
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    readingActivity.dispose();
    readingMoments.dispose();
    _appearance.dispose();
    _application.dispose();
    _glassChanges.dispose();
    _readerSettings.dispose();
    _settings.dispose();
    _history.dispose();
    _bookmarkChanges.dispose();
    _underlineChanges.dispose();
    _illustrationChanges.dispose();
    _searchChanges.dispose();
    _blockedTagsChanges.dispose();
    _shelfViewChanges.dispose();
    _discoveryViewChanges.dispose();
    _readerBehaviorChanges.dispose();
    _navigationChanges.dispose();
    _organization?.dispose();
    fonts.dispose();
    super.dispose();
  }
}
