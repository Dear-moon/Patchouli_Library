import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/updates/release_markdown.dart';
import 'package:wenku8_flutter/updates/release_notices.dart';
import 'support/visual_review.dart';

const _richNotes = '''## 阅读体验

支持 **重点**、*斜体*、~~旧说明~~ 和 `原始代码`。

> [!IMPORTANT]
> **免费开源**，请认准项目仓库。

1. 查看更新
   - 保留已有内容
   - 不改变阅读位置
2. 返回阅读

- [x] 本地原书保留
- [ ] 升级前备份

| 功能 | 使用位置 | 说明 |
| --- | --- | --- |
| 阅读背景 | 阅读设置中的排版 | 支持本书和通用设置 |

---

```text
原始代码 https://example.com/阅读/更新不会转换
```

[项目仓库](https://github.com/mikufoxxx/Wenku8_Flutter)

![更新配图](https://example.com/release.png)
''';

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadReviewFonts();
    await ChineseText.prepare();
  });

  Widget host(
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh', 'CN'),
    double scale = 1,
    GlobalKey? capture,
  }) => RepaintBoundary(
    key: capture,
    child: MaterialApp(
      theme: novelTheme(brightness),
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'HK'),
        Locale('zh', 'TW'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    ),
  );

  List<TextSpan> textSpans(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .expand((widget) => _spans(widget.text))
      .toList();

  testWidgets('GFM renders real structure, emphasis, links and warnings', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      host(
        ReleaseNotes(_richNotes, onOpenLink: (uri) async => opened.add(uri)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅读体验', findRichText: true), findsOneWidget);
    expect(find.textContaining('支持 **重点**', findRichText: true), findsNothing);
    expect(
      find.textContaining('[!IMPORTANT]', findRichText: true),
      findsNothing,
    );
    expect(
      find.text('重要说明\n免费开源，请认准项目仓库。', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(Table), findsOneWidget);
    final spans = textSpans(tester);
    expect(
      spans.any(
        (s) => s.text == '重点' && s.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (s) => s.text == '斜体' && s.style?.fontStyle == FontStyle.italic,
      ),
      isTrue,
    );
    final link = spans.singleWhere(
      (s) => s.text == '项目仓库' && s.recognizer != null,
    );
    expect(opened, isEmpty);
    (link.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(
      opened.single.toString(),
      'https://github.com/mikufoxxx/Wenku8_Flutter',
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('查看图片：更新配图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final region in ['HK', 'TW']) {
    testWidgets('$region converts prose, not code or link destinations', (
      tester,
    ) async {
      final opened = <Uri>[];
      final url = 'https://example.com/阅读?字体=默认';
      await tester.pumpWidget(
        host(
          ReleaseNotes(
            '## 阅读与字体\n\n[查看说明]($url)\n\n`阅读字体`\n\n```text\n阅读字体\n```',
            onOpenLink: (uri) async => opened.add(uri),
          ),
          locale: Locale('zh', region),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(region == 'HK' ? '閲讀與字體' : '閱讀與字型', findRichText: true),
        findsOneWidget,
        reason: textSpans(tester).map((s) => s.text).join('|'),
      );
      expect(find.text('阅读字体', findRichText: true), findsNWidgets(2));
      final link = textSpans(tester).singleWhere(
        (s) =>
            s.text == (region == 'HK' ? '查看説明' : '檢視說明') &&
            s.recognizer != null,
      );
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(opened.single, Uri.parse(url));
      expect(tester.takeException(), isNull);
    });
  }

  test('only explicit web links are resolvable', () {
    final base = Uri.parse(
      'https://github.com/example/app/releases/tag/v1.0.0',
    );
    expect(
      releaseLinkUri('../v1.0.1', baseUri: base),
      Uri.parse('https://github.com/example/app/releases/v1.0.1'),
    );
    for (final value in [
      null,
      '',
      '/no-base',
      'javascript:alert(1)',
      'file:///tmp/book',
      'intent://install',
      'data:text/html,hi',
      'https://user:password@example.com',
    ]) {
      expect(releaseLinkUri(value), isNull);
    }
  });

  testWidgets('plain older notes retain separate lines', (tester) async {
    await tester.pumpWidget(host(const ReleaseNotes('第一项改动\n第二项改动')));
    await tester.pumpAndSettle();
    expect(find.text('第一项改动\n第二项改动', findRichText: true), findsOneWidget);
  });

  for (final scene in [
    (
      name: 'phone',
      size: const Size(390, 844),
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'compact-large',
      size: const Size(320, 640),
      scale: 2.0,
      brightness: Brightness.light,
    ),
    (
      name: 'landscape-dark',
      size: const Size(844, 390),
      scale: 1.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets(
      '${scene.name} Markdown fits and long blocks scroll horizontally',
      (tester) async {
        tester.view.physicalSize = scene.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(
          host(
            const ReleaseNotes(_richNotes),
            brightness: scene.brightness,
            scale: scene.scale,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        await captureReview(tester, capture, 'markdown-${scene.name}');
        expect(
          tester
              .widgetList<SingleChildScrollView>(
                find.byType(SingleChildScrollView),
              )
              .where((s) => s.scrollDirection == Axis.horizontal)
              .length,
          2,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('important notices remain readable in the shared renderer', (
    tester,
  ) async {
    await tester.pumpWidget(host(const ReleaseNotes(projectImportantNotices)));
    await tester.pumpAndSettle();
    expect(find.text('免费与开源', findRichText: true), findsOneWidget);
    expect(find.text('内容来源与项目身份', findRichText: true), findsOneWidget);
    expect(find.text('版权与使用提醒', findRichText: true), findsOneWidget);
    expect(find.text('服务与数据风险', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
