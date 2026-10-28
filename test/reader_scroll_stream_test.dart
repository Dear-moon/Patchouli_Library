import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_scroll_stream.dart';

class _Fixture extends StatefulWidget {
  const _Fixture({
    super.key,
    this.initial = 0,
    this.loader,
    this.deferPreparation = false,
    this.controller,
  });
  final int initial;
  final bool deferPreparation;
  final ReaderScrollStreamController<List<String>>? controller;
  final Future<List<String>> Function(int)? loader;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final scroll = ScrollController(keepScrollOffset: false);
  late final stream =
      widget.controller ?? ReaderScrollStreamController<List<String>>();
  late int chapter = widget.initial;
  final calls = <int>[];
  List<String> data(int chapter) =>
      List.generate(24, (row) => 'C$chapter / paragraph $row');
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ReaderScrollStream<List<String>>(
        controller: stream,
        deferPreparation: widget.deferPreparation,
        scroll: scroll,
        identity: 1,
        geometry: 1,
        chapter: chapter,
        data: data(chapter),
        chapterCount: 8,
        rowCount: (data) => data.length,
        load: (index) async {
          calls.add(index);
          return widget.loader == null
              ? data(index)
              : await widget.loader!(index);
        },
        onChapterChanged: (index, _) => setState(() => chapter = index),
        itemBuilder: (context, index, data, row) => SizedBox(
          height: row < 0
              ? 80
              : row == data.length
              ? 24
              : 64,
          child: row < 0
              ? Text('Chapter $index')
              : row == data.length
              ? const Divider()
              : ReaderParagraph(
                  registry: stream.registryFor(index)!,
                  index: row,
                  child: Text(data[row]),
                ),
        ),
        pendingBuilder: (context, index, error, retry) => error == null
            ? Text('Loading $index')
            : TextButton(onPressed: retry, child: Text('Retry $index')),
      ),
    ),
  );
}

void main() {
  testWidgets('preparation requested before attachment is retained', (
    tester,
  ) async {
    final controller = ReaderScrollStreamController<List<String>>();
    controller.prepareAdjacent();
    final key = GlobalKey<_FixtureState>();
    await tester.pumpWidget(
      _Fixture(key: key, deferPreparation: true, controller: controller),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.calls, contains(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a real drag activates deferred continuous chapter loading', (
    tester,
  ) async {
    final key = GlobalKey<_FixtureState>();
    await tester.pumpWidget(_Fixture(key: key, deferPreparation: true));
    await tester.pumpAndSettle();
    expect(key.currentState!.calls, isEmpty);
    await tester.drag(
      find.byKey(const ValueKey('reader-scroll')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.calls, contains(1));
    expect(key.currentState!.stream.dataFor(1), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('reaching a failed prefetch retries once in the foreground', (
    tester,
  ) async {
    var attempts = 0;
    final key = GlobalKey<_FixtureState>();
    await tester.pumpWidget(
      _Fixture(
        key: key,
        loader: (index) async {
          if (index == 1 && ++attempts == 1) {
            throw StateError('transient request');
          }
          return List.generate(24, (row) => 'C$index / paragraph $row');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 1);
    final position = key.currentState!.scroll.position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(key.currentState!.stream.dataFor(1), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a failed adjacent load retains prose and retries inline', (
    tester,
  ) async {
    final key = GlobalKey<_FixtureState>();
    var attempts = 0;
    final next = Completer<List<String>>();
    await tester.pumpWidget(
      _Fixture(
        key: key,
        loader: (index) {
          attempts++;
          return next.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    final position = key.currentState!.scroll.position;
    expect(find.text('C0 / paragraph 0'), findsOneWidget);
    expect(attempts, 1);
    next.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Retry 1'), findsOneWidget);
    expect(
      attempts,
      2,
      reason:
          'A failed prefetch gets one foreground retry, not a request loop.',
    );
    expect(key.currentState!.chapter, 0);
    final at = position.pixels;
    await tester.pumpWidget(
      _Fixture(
        key: key,
        loader: (index) async => key.currentState!.data(index),
      ),
    );
    await tester.tap(find.text('Retry 1'));
    await tester.pumpAndSettle();
    expect(key.currentState!.scroll.position, same(position));
    expect(position.pixels, at);
    expect(key.currentState!.calls.where((index) => index == 1).length, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('one drag crosses chapters without replacing the scroll position', (
    tester,
  ) async {
    final key = GlobalKey<_FixtureState>();
    await tester.pumpWidget(_Fixture(key: key));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    final position = state.scroll.position;
    final finger = await tester.startGesture(const Offset(250, 350));
    await finger.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 60));
    for (var frame = 0; frame < 70; frame++) {
      final before = position.pixels;
      await finger.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        position.pixels - before,
        closeTo(120, .01),
        reason:
            'forward $frame: $before -> ${position.pixels}; max ${position.maxScrollExtent}; chapter ${state.chapter}; loads ${state.calls}',
      );
      expect(state.scroll.position, same(position));
    }
    expect(state.chapter, greaterThanOrEqualTo(4));
    for (var frame = 0; frame < 55; frame++) {
      final before = position.pixels;
      await finger.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        position.pixels - before,
        closeTo(-120, .01),
        reason:
            'backward $frame: $before -> ${position.pixels}; min ${position.minScrollExtent}; chapter ${state.chapter}; loads ${state.calls}',
      );
    }
    expect(state.chapter, lessThanOrEqualTo(2));
    await finger.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'previous chapters extend above a nonzero starting chapter without a jump',
    (tester) async {
      final key = GlobalKey<_FixtureState>();
      await tester.pumpWidget(_Fixture(key: key, initial: 3));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final position = state.scroll.position;
      expect(position.pixels, 0);
      expect(position.minScrollExtent, lessThan(0));
      final finger = await tester.startGesture(const Offset(250, 250));
      await finger.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 60));
      for (var frame = 0; frame < 25; frame++) {
        final before = position.pixels;
        await finger.moveBy(const Offset(0, 120));
        await tester.pump(const Duration(milliseconds: 60));
        expect(position.pixels - before, closeTo(-120, .01));
      }
      expect(state.chapter, lessThanOrEqualTo(2));
      expect(state.scroll.position, same(position));
      await finger.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
