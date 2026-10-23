import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_palette.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/palette_image.dart';
import 'package:wenku8_flutter/palette_platform.dart';
import 'package:wenku8_flutter/reader_appearance.dart';
import 'package:wenku8_flutter/reader_preferences.dart';

SystemTonalColors sampleSystemColors() {
  final core = SchemeTonalSpot(
    sourceColorHct: Hct.fromInt(0xff607d71),
    isDark: false,
    contrastLevel: 0,
  );
  return SystemTonalColors([
    core.primaryPalette.asList,
    core.secondaryPalette.asList,
    core.tertiaryPalette.asList,
    core.neutralPalette.asList,
    core.neutralVariantPalette.asList,
  ]);
}

class FixturePalettePlatform extends PalettePlatform {
  bool icon = true, fail = false;
  final changes = <bool>[];
  @override
  Future<PalettePlatformInfo> read() async => PalettePlatformInfo(
    colors: sampleSystemColors(),
    iconSupported: true,
    themedIcon: icon,
  );
  @override
  Future<void> setThemedIcon(bool enabled) async {
    if (fail) throw const FormatException('无法切换图标');
    changes.add(enabled);
    icon = enabled;
  }
}

Future<Uint8List> twoColorImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 200),
    Paint()..color = const Color(0xffff0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(200, 0, 200, 200),
    Paint()..color = const Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 200);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
  }

  test(
    'palette records preserve original defaults and reject invalid opaque colors',
    () {
      final defaults = AppPalettePreferences.decode(null);
      expect(defaults.source, AppPaletteSource.original);
      expect(defaults.themedIcon, true);
      final custom = defaults.copyWith(
        source: AppPaletteSource.custom,
        seed: 0xff8762a8,
        themedIcon: false,
      );
      expect(AppPalettePreferences.decode(custom.encode()), custom);
      for (final raw in [
        jsonEncode({
          'source': 'unknown',
          'seed': 0xff123456,
          'themedIcon': false,
        }),
        jsonEncode({
          'source': 'custom',
          'seed': 0x00123456,
          'themedIcon': false,
        }),
      ]) {
        expect(() => AppPalettePreferences.decode(raw), throwsFormatException);
      }
    },
  );
  test(
    'seed schemes keep text contrast in light and dark while original stays neutral',
    () {
      for (final brightness in Brightness.values) {
        final original = novelTheme(brightness);
        expect(
          original.colorScheme,
          novelTheme(
            brightness,
            palette: const AppPalettePreferences(),
          ).colorScheme,
        );
        for (final seed in [
          0xff607d71,
          0xff0000ff,
          0xffff0000,
          0xff9b8452,
          0xff887aa5,
          0xff000000,
          0xffffffff,
        ]) {
          final scheme = novelTheme(
            brightness,
            palette: AppPalettePreferences(
              source: AppPaletteSource.custom,
              seed: seed,
            ),
          ).colorScheme;
          expect(contrast(scheme.onSurface, scheme.surface), greaterThan(7));
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.primary, scheme.onPrimary),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );
  test(
    'system palettes use actual Android tones and reject incomplete responses',
    () {
      final colors = sampleSystemColors();
      expect(
        SystemTonalColors.fromMap(colors.palettes)!.signature,
        colors.signature,
      );
      expect(
        SystemTonalColors.fromMap([
          [1],
        ]),
        null,
      );
      final p = TonalPalette.fromList(colors.palettes.first);
      expect(colors.scheme(Brightness.light).primary, Color(p.get(40)));
      expect(colors.scheme(Brightness.dark).primary, Color(p.get(80)));
    },
  );
  test(
    'reading paper and all reader control colors remain independent of app palette',
    () {
      for (final paper in ReaderPaper.values) {
        for (final brightness in Brightness.values) {
          final prefs = ReaderPreferences(paper: paper);
          final before = readerTheme(novelTheme(brightness), prefs);
          final after = readerTheme(
            novelTheme(
              brightness,
              palette: const AppPalettePreferences(
                source: AppPaletteSource.custom,
                seed: 0xff0000ff,
              ),
            ),
            prefs,
          );
          expect(after.colorScheme, before.colorScheme);
          expect(after.extension<AppTonalColors>(), null);
        }
      }
    },
  );
  test(
    'palette persists and restores with backup without changing reader settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'theme': 'dark',
        'readerFontSize': 22.0,
      });
      final prefs = await SharedPreferences.getInstance();
      final state = LibraryState(prefs);
      const chosen = AppPalettePreferences(
        source: AppPaletteSource.custom,
        seed: 0xff887aa5,
      );
      await state.setAppPalette(chosen);
      expect(LibraryState(prefs).appPalette, chosen);
      expect(state.fontSize, 22);
      final backup = await LibraryBackup.fromRecords({
        AppPalettePreferences.key: chosen.encode(),
      });
      expect(backup.records[AppPalettePreferences.key], chosen.encode());
      state.dispose();
    },
  );
  test(
    'icon change is independent of theme repaint and failed native changes are not saved',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final platform = FixturePalettePlatform();
      final state = LibraryState(prefs, palettePlatform: platform);
      await state.refreshSystemPalette();
      var paints = 0;
      state.applicationChanges.addListener(() => paints++);
      await state.setAppPalette(state.appPalette.copyWith(themedIcon: false));
      expect(platform.changes, [false]);
      expect(state.appPalette.themedIcon, false);
      expect(paints, 0);
      platform.fail = true;
      await expectLater(
        state.setAppPalette(state.appPalette.copyWith(themedIcon: true)),
        throwsFormatException,
      );
      expect(state.appPalette.themedIcon, false);
      expect(
        AppPalettePreferences.decode(
          prefs.get(AppPalettePreferences.key),
        ).themedIcon,
        false,
      );
      state.dispose();
    },
  );
  test(
    'image sampling handles letterboxing and extracts real image colors once',
    () async {
      final image = await PaletteImage.decode(await twoColorImage());
      expect((image.width, image.height), (256, 128));
      expect(image.colorAt(const Offset(10, 10), const Size(100, 100)), null);
      expect(
        image.colorAt(const Offset(10, 50), const Size(100, 100)),
        const Color(0xffff0000),
      );
      expect(
        image.colorAt(const Offset(90, 50), const Size(100, 100)),
        const Color(0xff0000ff),
      );
      expect(image.seeds, isNotEmpty);
      expect(image.seeds.toSet().difference({0xffff0000, 0xff0000ff}), isEmpty);
      final grey = Uint8List.fromList(
        List.filled(64, [128, 128, 128, 255]).expand((c) => c).toList(),
      );
      expect(await paletteImageSeeds(grey), [0xff808080]);
      final thin = Uint8List(64)..setAll(4, [255, 0, 0, 255]);
      expect(await paletteImageSeeds(thin), [0xffff0000]);
      await expectLater(
        paletteImageSeeds(Uint8List(256)),
        throwsFormatException,
      );
    },
  );
}
