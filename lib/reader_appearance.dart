import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'glass_palette.dart';
import 'library_state.dart';
import 'reader_preferences.dart';
import 'app_palette.dart';

ThemeData readerTheme(
  ThemeData app,
  ReaderPreferences preferences, {
  String? fontFamily,
}) {
  final appDark = app.brightness == Brightness.dark;
  final paper = preferences.background(appDark);
  final brightness = ThemeData.estimateBrightnessForColor(paper);
  final dark = brightness == Brightness.dark;
  final base = novelTheme(brightness, fontFamily: fontFamily);
  // Dim only the article's ink. Sliders, buttons and text selection retain
  // their readable control contrast while a user previews night text levels.
  final ink = preferences.controlForeground(appDark);
  Color raised(double amount) => Color.lerp(paper, ink, amount)!;
  final scheme = base.colorScheme.copyWith(
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: raised(.64),
    primary: ink,
    onPrimary: paper,
    surfaceDim: paper,
    surfaceBright: raised(.12),
    surfaceContainerLowest: paper,
    surfaceContainerLow: raised(.025),
    surfaceContainer: raised(.05),
    surfaceContainerHigh: raised(.08),
    surfaceContainerHighest: raised(.12),
    surfaceTint: Colors.transparent,
    outline: raised(.38),
    outlineVariant: raised(.18),
    inverseSurface: ink,
    onInverseSurface: paper,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    iconTheme: base.iconTheme.copyWith(color: ink),
    disabledColor: raised(.35),
    dividerColor: scheme.outlineVariant,
    textTheme: base.textTheme.apply(
      fontFamily: fontFamily ?? 'Roboto',
      bodyColor: ink,
      displayColor: ink,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainerLow,
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: ink,
      primaryContrastingColor: paper,
      scaffoldBackgroundColor: paper,
    ),
    extensions: [
      ...base.extensions.values.where(
        (extension) =>
            extension is! GlassPalette && extension is! AppTonalColors,
      ),
      GlassPalette(
        tint: dark ? raised(.10) : Color.lerp(paper, Colors.white, .24)!,
        thumb: Color.lerp(paper, Colors.white, dark ? .90 : .62)!,
      ),
    ],
  );
}

/// The same live palette wraps the article, chrome and entire popup surface.
/// Typography-only notifications reuse ThemeData and do not repaint chrome.
class ReaderAppearance extends StatefulWidget {
  const ReaderAppearance({
    super.key,
    required this.state,
    required this.appTheme,
    required this.child,
    this.bookId,
  });
  final LibraryState state;
  final ThemeData appTheme;
  final Widget child;
  final int? bookId;

  /// Continue a reader-owned route without changing ordinary app entry points.
  /// Reuse the live book palette rather than capturing one ThemeData snapshot.
  static Widget inherit(BuildContext context, {required Widget child}) {
    final owner = context.findAncestorWidgetOfExactType<ReaderAppearance>();
    return owner == null
        ? child
        : ReaderAppearance(
            state: owner.state,
            appTheme: owner.appTheme,
            bookId: owner.bookId,
            child: child,
          );
  }

  @override
  State<ReaderAppearance> createState() => _ReaderAppearanceState();
}

class _ReaderAppearanceState extends State<ReaderAppearance> {
  ThemeData? _base, _theme;
  ReaderPaper? _paper;
  String? _family;
  ThemeData _resolve() {
    final preferences = widget.state.readerPreferencesFor(widget.bookId);
    final paper = preferences.paper;
    final family = widget.state.readerFontFamilyFor(widget.bookId);
    if (_base?.brightness != widget.appTheme.brightness ||
        _paper != paper ||
        _family != family) {
      _base = widget.appTheme;
      _paper = paper;
      _family = family;
      _theme = readerTheme(_base!, preferences, fontFamily: family);
    }
    return _theme!;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    child: widget.child,
    builder: (context, child) {
      final theme = _resolve();
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: novelSystemUiStyle(theme.brightness),
        child: Theme(
          data: theme,
          // Theme alone does not replace MaterialApp's DefaultSelectionStyle.
          // Its app-light dark tint would disappear on a separately dark paper.
          child: DefaultSelectionStyle.merge(
            selectionColor: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: .20)
                : Colors.black.withValues(alpha: .18),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: IconTheme(data: theme.iconTheme, child: child!),
            ),
          ),
        ),
      );
    },
  );
}
