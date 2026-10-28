import 'dart:convert';

import 'reader_preferences.dart';
import 'user_fonts.dart';
import 'reader_languages.dart';

const bookReaderStylePrefix = 'reader_style_';

/// A book's own typography, separate from shared gestures/window behaviour.
/// Disabled styles remain available when the user enables them again.
class ReaderBookStyle {
  ReaderBookStyle({
    required this.preferences,
    required this.fontSize,
    required this.lineHeight,
    required this.typeface,
    this.enabled = true,
    this.onlyLanguage,
    Set<String> hiddenLanguages = const {},
  }) : hiddenLanguages = Set.unmodifiable(hiddenLanguages);

  final ReaderPreferences preferences;
  final double fontSize, lineHeight;
  final String typeface;
  final bool enabled;
  final String? onlyLanguage;
  static const _unchanged = Object();
  final Set<String> hiddenLanguages;
  ReaderPreferences? _defaults, _effective;

  ReaderPreferences resolve(ReaderPreferences defaults) {
    if (!enabled) return defaults;
    if (!identical(_defaults, defaults)) {
      _defaults = defaults;
      _effective = defaults.withLayoutOf(preferences);
    }
    return _effective!;
  }

  ReaderBookStyle copyWith({
    ReaderPreferences? preferences,
    double? fontSize,
    double? lineHeight,
    String? typeface,
    bool? enabled,
    Set<String>? hiddenLanguages,
    Object? onlyLanguage = _unchanged,
  }) => ReaderBookStyle(
    preferences: preferences ?? this.preferences,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    typeface: typeface ?? this.typeface,
    enabled: enabled ?? this.enabled,
    hiddenLanguages: hiddenLanguages ?? this.hiddenLanguages,
    onlyLanguage: identical(onlyLanguage, _unchanged)
        ? this.onlyLanguage
        : onlyLanguage as String?,
  );

  static const _layoutKeys = {
    'paper',
    'mode',
    'verticalLatinOrientation',
    'margin',
    'marginLeft',
    'marginRight',
    'marginTop',
    'marginBottom',
    'paragraphGap',
    'paragraphGapOverride',
    'indent',
    'justify',
    'nightTextBrightness',
    'letterSpacing',
    'textWeight',
    'backgroundImage',
    'backgroundOpacity',
    'backgroundFit',
  };

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    if (onlyLanguage != null) 'onlyLanguage': onlyLanguage,
    if (hiddenLanguages.isNotEmpty)
      'hiddenLanguages': hiddenLanguages.toList()..sort(),
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'typeface': typeface,
    'layout': {
      for (final entry in preferences.toJson().entries)
        if (_layoutKeys.contains(entry.key)) entry.key: entry.value,
    },
  };

  factory ReaderBookStyle.fromJson(Map<String, dynamic> json) {
    double number(String key, double min, double max) {
      final value = json[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('本书排版数值超出范围');
      }
      return value.toDouble();
    }

    final layout = json['layout'];
    final hidden = json['hiddenLanguages'] ?? const <String>[];
    final only = json['onlyLanguage'];
    if (only != null &&
        (only is! String || only.isEmpty || readerLanguageCode(only) != only)) {
      throw const FormatException('本书语言设置格式有误');
    }
    if (hidden is! List ||
        hidden.length > 32 ||
        hidden.any(
          (code) =>
              code is! String ||
              code.isEmpty ||
              readerLanguageCode(code) != code,
        )) {
      throw const FormatException('本书语言设置格式有误');
    }
    if (json['enabled'] is! bool ||
        !validFontChoice(json['typeface'], follow: true) ||
        layout is! Map ||
        layout.keys.any((key) => !_layoutKeys.contains(key))) {
      throw const FormatException('本书排版格式有误');
    }
    return ReaderBookStyle(
      enabled: json['enabled'] as bool,
      hiddenLanguages: hidden.cast<String>().toSet(),
      onlyLanguage: only as String?,
      preferences: ReaderPreferences.fromJson(
        Map<String, dynamic>.from(layout),
      ),
      fontSize: number(
        'fontSize',
        minimumReaderFontSize,
        maximumReaderFontSize,
      ),
      lineHeight: number('lineHeight', 1.3, 2.2),
      typeface: json['typeface'] as String,
    );
  }

  static ReaderBookStyle? fromRecord(Object? record) {
    try {
      return ReaderBookStyle.fromJson(jsonDecode(record as String));
    } catch (_) {
      return null;
    }
  }
}
