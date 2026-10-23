import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_haptics.dart';
import 'package:wenku8_flutter/haptic_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Object?>[];
  var clock = Duration.zero;
  setUp(() {
    calls.clear();
    clock = Duration.zero;
    AppHaptics.resetForTesting(now: () => clock);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      (call) async {
        calls.add(call.arguments);
        return true;
      },
    );
  });
  tearDown(() {
    AppHaptics.resetForTesting();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      null,
    );
  });

  test('all cues map to independently adjustable interaction groups', () {
    expect(HapticCue.action.category, HapticCategory.controls);
    expect(HapticCue.selection.category, HapticCategory.controls);
    expect(HapticCue.shelfStep.category, HapticCategory.shelf);
    expect(HapticCue.pageTurn.category, HapticCategory.reading);
    expect(HapticCue.detent.category, HapticCategory.adjustment);
    expect(HapticCue.longPress.category, HapticCategory.longPress);
    expect(HapticCue.boundary.category, HapticCategory.boundary);
    for (final cue in [HapticCue.success, HapticCue.warning, HapticCue.error]) {
      expect(cue.category, HapticCategory.result);
    }
  });

  testWidgets('muting buttons does not swallow a same-time shelf tick', (
    tester,
  ) async {
    late BuildContext source;
    var prefs = const HapticPreferences()
        .withCategoryEnabled(HapticCategory.controls, false)
        .withCategoryStrength(HapticCategory.shelf, HapticStrength.strong);
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: HapticScope(
          preferences: prefs,
          child: Builder(
            builder: (context) {
              source = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await mount();
    AppHaptics.play(source, HapticCue.action);
    AppHaptics.play(source, HapticCue.shelfStep);
    await tester.pump();
    expect(calls, [
      {'cue': 'shelfStep', 'strength': 'strong'},
    ]);
    prefs = prefs.withEnabled(false);
    await mount();
    clock += const Duration(seconds: 1);
    for (final cue in HapticCue.values) {
      AppHaptics.play(source, cue);
    }
    await tester.pump();
    expect(calls, hasLength(1));
    prefs = prefs.withEnabled(true);
    await mount();
    AppHaptics.play(source, HapticCue.shelfStep);
    await tester.pump();
    expect(calls.last, {'cue': 'shelfStep', 'strength': 'strong'});
    expect(calls, hasLength(2));
  });

  testWidgets('preview uses committed strength and still honors mute', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final prefs = const HapticPreferences().withCategoryStrength(
      HapticCategory.reading,
      HapticStrength.light,
    );
    AppHaptics.preview(source, HapticCue.pageTurn, preferences: prefs);
    await tester.pump();
    expect(calls, [
      {'cue': 'pageTurn', 'strength': 'light'},
    ]);
    clock += const Duration(seconds: 1);
    AppHaptics.preview(
      source,
      HapticCue.pageTurn,
      preferences: prefs.withCategoryEnabled(HapticCategory.reading, false),
    );
    AppHaptics.preview(
      source,
      HapticCue.pageTurn,
      preferences: prefs.withEnabled(false),
    );
    await tester.pump();
    expect(calls, hasLength(1));
    AppHaptics.play(source, HapticCue.pageTurn);
    await tester.pump();
    expect(
      calls.last,
      'pageTurn',
      reason: 'existing unscoped standard callers stay compatible',
    );
  });

  testWidgets('custom strength native refusal never adds fallback', (
    tester,
  ) async {
    final fallbacks = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppHaptics.channel,
      (_) async => false,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        fallbacks.add(call);
        return null;
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    late BuildContext source;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            source = context;
            return const SizedBox();
          },
        ),
      ),
    );
    AppHaptics.preview(
      source,
      HapticCue.action,
      preferences: const HapticPreferences().withStrength(
        HapticStrength.strong,
      ),
    );
    await tester.pump();
    expect(
      fallbacks.where((call) => call.method == 'HapticFeedback.vibrate'),
      isEmpty,
    );
  });
}
