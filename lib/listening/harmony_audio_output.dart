import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'models.dart';

/// Harmony owns only decoding and the system media session. Segment selection,
/// prefetch, sleep timers, progress and source selection remain in the controller.
class HarmonyListeningOutput implements ListeningAudioOutput {
  HarmonyListeningOutput({
    this.channel = const MethodChannel('org.mewx.wenku8/harmony_audio'),
    this.events = const EventChannel('org.mewx.wenku8/harmony_audio/events'),
  });

  final MethodChannel channel;
  final EventChannel events;
  final _positions = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  int _loadId = 0;
  bool _disposed = false;

  Future<void> initialize() async {
    _subscription = events.receiveBroadcastStream().listen(
      _event,
      onError: (Object error, StackTrace stack) {
        if (!_disposed) _completions.addError(error, stack);
      },
    );
    await channel.invokeMethod<void>('initializePlayer');
  }

  void _event(dynamic value) {
    if (_disposed || value is! Map || value['loadId'] != _loadId) return;
    switch (value['type']) {
      case 'position':
        final position = value['position'];
        if (position is num) {
          _positions.add(Duration(milliseconds: position.round()));
        }
      case 'completed':
        _completions.add(null);
      case 'error':
        _completions.addError(
          PlatformException(
            code: '${value['code'] ?? 'harmony_audio'}',
            message: '${value['message'] ?? '音频播放失败，请重试'}',
          ),
        );
    }
  }

  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<void> get completions => _completions.stream;
  @override
  Future<Duration?> load(File file, Duration position) async {
    final duration = await channel.invokeMethod<num>('load', {
      'path': file.path,
      'position': position.inMilliseconds,
      'loadId': ++_loadId,
    });
    return duration == null ? null : Duration(milliseconds: duration.round());
  }

  @override
  Future<void> play() => channel.invokeMethod<void>('play');
  @override
  Future<void> suspend() => channel.invokeMethod<void>('suspend');
  @override
  Future<void> pause() => channel.invokeMethod<void>('pause');
  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
  @override
  Future<void> seek(Duration position) =>
      channel.invokeMethod<void>('seek', {'position': position.inMilliseconds});
  @override
  Future<void> setSpeed(double speed) =>
      channel.invokeMethod<void>('setSpeed', {'speed': speed});
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    try {
      await channel.invokeMethod<void>('disposePlayer');
    } finally {
      await _positions.close();
      await _completions.close();
    }
  }
}

/// Publishes chapter metadata, never the internal clip as a separate track.
class HarmonyListeningService {
  HarmonyListeningService(
    this.controller, {
    this.channel = const MethodChannel('org.mewx.wenku8/harmony_audio'),
    this.bufferingGrace = const Duration(milliseconds: 500),
  });
  final ListeningController controller;
  final MethodChannel channel;
  final Duration bufferingGrace;
  bool _closed = false;
  bool _publishing = false;
  bool _dirty = false;
  String? _metadataKey;
  String? _readyKey;
  Timer? _bufferingTimer;
  bool _holdingTransition = false;

  Future<void> initialize() async {
    channel.setMethodCallHandler(_command);
    await channel.invokeMethod<void>('initializeService');
    controller.snapshot.addListener(_state);
    controller.chapterProgress.addListener(_publish);
    _state();
  }

  Future<void> _command(MethodCall call) async {
    switch (call.method) {
      case 'play':
        await controller.resume();
      case 'pause':
      case 'interrupted':
        await controller.pause();
      case 'stop':
        await controller.stop();
      case 'next':
        await controller.moveChapter(1);
      case 'previous':
        await controller.moveChapter(-1);
      case 'forward':
        await controller.seekBy(const Duration(seconds: 15));
      case 'rewind':
        await controller.seekBy(const Duration(seconds: -15));
    }
  }

  void _publish() {
    if (_closed) return;
    _dirty = true;
    if (!_publishing) unawaited(_drain());
  }

  void _state() {
    final state = controller.snapshot.value;
    final key =
        '${state.novel?.id}/${state.chapter}/${state.chapterTitle}/${state.voice.engine}/${state.voice.id}/${state.spokenLanguage}';
    if (state.phase == ListeningPhase.preparing &&
        state.requestingPlayback &&
        _readyKey == key) {
      if (_bufferingTimer == null) {
        _holdingTransition = true;
        _bufferingTimer = Timer(bufferingGrace, () {
          _holdingTransition = false;
          _publish();
        });
      }
    } else {
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
      _holdingTransition = false;
      if (state.phase == ListeningPhase.playing ||
          state.phase == ListeningPhase.paused) {
        _readyKey = key;
      }
    }
    _publish();
  }

  Future<void> _drain() async {
    _publishing = true;
    try {
      while (_dirty && !_closed) {
        _dirty = false;
        final state = controller.snapshot.value;
        final novel = state.novel;
        if (novel != null) {
          final artist =
              state.spokenLanguage == null && state.languages.length > 1
              ? '多语言朗读 · 自动匹配'
              : state.outputVoice.label;
          final key =
              '${novel.id}/${novel.title}/${state.chapter}/${state.chapterTitle}/$artist';
          if (_metadataKey != key) {
            await channel.invokeMethod<void>('setMetadata', {
              'id': 'wenku:${novel.id}:${state.chapter}',
              'title': state.chapterTitle.isEmpty
                  ? '正在准备章节'
                  : '第 ${state.chapter + 1} 章 · ${state.chapterTitle}',
              'album': novel.title,
              'artist': artist,
            });
            _metadataKey = key;
          }
        }
        final current = controller.snapshot.value;
        if (_holdingTransition && current.phase == ListeningPhase.preparing) {
          continue;
        }
        await channel.invokeMethod<void>('setPlaybackState', {
          'phase': current.phase.name,
          'playing': current.requestingPlayback,
          'speed': current.speed,
          'position': controller.chapterProgress.value.position.inMilliseconds,
        });
      }
    } on PlatformException catch (error) {
      // Make a failed media/background lifecycle visible through the same
      // playback failure channel, rather than leaving a fake running session.
      if (controller.snapshot.value.requestingPlayback) {
        await controller.pause();
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'Harmony listening media session',
        ),
      );
    } finally {
      _publishing = false;
      if (_dirty && !_closed) unawaited(_drain());
    }
  }

  void close() {
    _closed = true;
    _bufferingTimer?.cancel();
    controller.snapshot.removeListener(_state);
    controller.chapterProgress.removeListener(_publish);
    channel.setMethodCallHandler(null);
  }
}
