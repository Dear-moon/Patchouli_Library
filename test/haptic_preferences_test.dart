import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/haptic_preferences.dart';
import 'package:wenku8_flutter/library_backup.dart';
import 'package:wenku8_flutter/library_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy defaults preserve all categories at standard strength', () {
    final defaults = HapticPreferences.fromRecords(const {});
    expect(defaults, const HapticPreferences());
    for (final category in HapticCategory.values) {
      expect(defaults.forCategory(category).enabled, isTrue);
      expect(defaults.levelFor(category), HapticStrength.standard);
    }
    expect(
      HapticPreferences.fromRecords({HapticPreferences.preferenceKey: 'bad'}),
      defaults,
    );
    final partial = HapticPreferences.fromRecords({
      HapticPreferences.preferenceKey: jsonEncode({
        'categories': {
          'shelf': {'strength': 'strong'},
        },
      }),
    });
    expect(partial.levelFor(HapticCategory.shelf), HapticStrength.strong);
    expect(partial.levelFor(HapticCategory.controls), HapticStrength.standard);
  });

  test('master and category switches retain independent strengths', () {
    const original = HapticPreferences();
    final custom = original
        .withCategoryStrength(HapticCategory.shelf, HapticStrength.strong)
        .withCategoryEnabled(HapticCategory.controls, false);
    expect(custom.uniformStrength, isNull);
    final muted = custom.withEnabled(false);
    expect(
      HapticCategory.values.every((c) => muted.levelFor(c) == null),
      isTrue,
    );
    expect(muted.withEnabled(true), custom);
    expect(original.uniformStrength, HapticStrength.standard);
    final allLight = muted.withStrength(HapticStrength.light);
    expect(allLight.enabled, isFalse);
    expect(allLight.forCategory(HapticCategory.controls).enabled, isFalse);
    expect(allLight.uniformStrength, HapticStrength.light);
    expect(
      allLight.withEnabled(true).levelFor(HapticCategory.controls),
      isNull,
    );
    expect(HapticPreferences.fromRecords(custom.toRecords()), custom);
    expect(
      HapticPreferences.fromRecords(custom.toRecords()).hashCode,
      custom.hashCode,
    );
  });

  test(
    'save reload and backup restoration preserve the complete preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      addTearDown(state.dispose);
      var notifications = 0;
      state.applicationChanges.addListener(() => notifications++);
      final desired = state.haptics
          .withStrength(HapticStrength.light)
          .withCategoryStrength(HapticCategory.shelf, HapticStrength.strong)
          .withCategoryEnabled(HapticCategory.reading, false)
          .withEnabled(false);
      await state.setHaptics(desired);
      expect(notifications, 1);
      await state.setHaptics(desired);
      expect(notifications, 1);
      final reloaded = await LibraryState.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.haptics, desired);
      final backup = await state.createBackup();
      final parsed = await LibraryBackup.parse(await backup.encode());
      expect(
        parsed.records[HapticPreferences.preferenceKey],
        desired.toRecords()[HapticPreferences.preferenceKey],
      );

      await state.setHaptics(const HapticPreferences());
      await state.restoreBackup(parsed);
      expect(state.haptics, const HapticPreferences());
      await state.restoreBackup(parsed, importPreferences: true);
      expect(state.haptics, desired);
      final restored = await LibraryState.load();
      addTearDown(restored.dispose);
      expect(restored.haptics, desired);
      await state.restoreBackup(
        await LibraryBackup.fromRecords({'theme': 'light'}),
        importPreferences: true,
      );
      expect(state.haptics, desired);
    },
  );

  test(
    'backup rejects malformed haptic configuration before restore',
    () async {
      for (final invalid in [
        true,
        'bad',
        jsonEncode({'enabled': 'yes'}),
        jsonEncode({
          'categories': {
            'shelf': {'strength': 'maximum'},
          },
        }),
      ]) {
        await expectLater(
          LibraryBackup.fromRecords({HapticPreferences.preferenceKey: invalid}),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
