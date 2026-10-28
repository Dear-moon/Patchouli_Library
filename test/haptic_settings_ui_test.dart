import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/haptic_preferences.dart';
import 'package:wenku8_flutter/haptic_settings_page.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/pages.dart';

import 'support/visual_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadReviewFonts);
  late LibraryState state;
  final pulses = <Object?>[];
  var clock = Duration.zero;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await LibraryState.load();
    pulses.clear();
    clock = Duration.zero;
    debugDefaultTargetPlatformOverride = null;
    AppHaptics.resetForTesting(now: () => clock);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppHaptics.channel, (call) async {
          if (call.method == 'play') pulses.add(call.arguments);
          return true;
        });
  });
  tearDown(() {
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
    AppHaptics.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppHaptics.channel, null);
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
    clock += const Duration(seconds: 1);
    await tester.tap(finder);
    await flush(tester);
  }

  Finder control(String key) => find.byKey(ValueKey(key));
  Finder strength(String key, String label) =>
      find.descendant(of: control(key), matching: find.text(label));

  testWidgets('settings entry is in app performance and effects', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: Scaffold(body: SettingsPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HapticSettingsPage), findsNothing);
    await tap(
      tester,
      find.descendant(
        of: control('settings-effects-entry'),
        matching: find.text('性能与动效'),
      ),
    );
    expect(control('settings-effects-page'), findsOneWidget);
    await tap(
      tester,
      find.descendant(
        of: control('settings-haptics'),
        matching: find.text('振动反馈'),
      ),
    );
    expect(find.byType(HapticSettingsPage), findsOneWidget);
    expect(control('haptic-global-enabled'), findsOneWidget);
  });

  testWidgets(
    'category controls persist and preview once without losing muted values',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child!),
          home: HapticSettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await captureReview(tester, boundary, 'haptic-settings-top');
      await tap(tester, strength('haptic-shelf-strength', '强'));
      expect(
        state.haptics.levelFor(HapticCategory.shelf),
        HapticStrength.strong,
      );
      expect(pulses, [
        {'cue': 'shelfStep', 'strength': 'strong'},
      ]);
      expect(find.text('已分别设置'), findsOneWidget);
      await tap(tester, strength('haptic-shelf-strength', '强'));
      expect(pulses.length, 1);
      await tap(tester, control('haptic-shelf-preview'));
      expect(pulses.length, 2);
      await tap(tester, control('haptic-shelf-enabled'));
      expect(pulses.length, 2);
      expect(state.haptics.levelFor(HapticCategory.shelf), isNull);
      expect(
        tester
            .widget<GlassTextButton>(control('haptic-shelf-preview'))
            .onPressed,
        isNull,
      );
      await tap(tester, control('haptic-global-enabled'));
      expect(pulses.length, 2);
      expect(state.haptics.enabled, isFalse);
      expect(
        tester
            .widget<AppGlassSwitch>(control('haptic-controls-enabled'))
            .onChanged,
        isNull,
      );
      await tap(tester, control('haptic-global-enabled'));
      expect(
        state.haptics.forCategory(HapticCategory.shelf).strength,
        HapticStrength.strong,
      );
      expect(state.haptics.forCategory(HapticCategory.shelf).enabled, isFalse);
      expect(pulses.last, 'action');
      await tap(tester, control('haptic-shelf-enabled'));
      expect(pulses.last, {'cue': 'shelfStep', 'strength': 'strong'});
      await tap(tester, strength('haptic-all-strength', '轻'));
      expect(state.haptics.uniformStrength, HapticStrength.light);
      expect(pulses.last, {'cue': 'action', 'strength': 'light'});
      await tap(tester, control('haptic-result-preview'));
      expect(pulses.last, {'cue': 'success', 'strength': 'light'});
      await captureReview(tester, boundary, 'haptic-settings-categories');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'iOS result feedback preserves switch and preview with system strength',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: HapticSettingsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(control('haptic-result-strength'), findsNothing);
      expect(find.text('强度由系统控制'), findsOneWidget);
      await tap(tester, control('haptic-result-preview'));
      expect(pulses, ['success']);
      await tap(tester, control('haptic-result-enabled'));
      expect(state.haptics.forCategory(HapticCategory.result).enabled, isFalse);
      expect(pulses, ['success']);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
