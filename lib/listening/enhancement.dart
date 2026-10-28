import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-local listening gain. Saved intent is not proof of an active audio effect.
@immutable
class ListeningEnhancementPreference {
  const ListeningEnhancementPreference({this.enabled = false, this.gainDb = 2})
    : assert(gainDb == 2 || gainDb == 4 || gainDb == 6);

  static const gains = <int>[2, 4, 6];
  final bool enabled;
  final int gainDb;

  factory ListeningEnhancementPreference.fromJson(Map<Object?, Object?> value) {
    final gain = value['gainDb'];
    return ListeningEnhancementPreference(
      enabled: value['enabled'] == true,
      gainDb: gains.contains(gain) ? (gain as num).toInt() : 2,
    );
  }

  Map<String, Object> toJson() => {'enabled': enabled, 'gainDb': gainDb};

  @override
  bool operator ==(Object other) =>
      other is ListeningEnhancementPreference &&
      enabled == other.enabled &&
      gainDb == other.gainDb;
  @override
  int get hashCode => Object.hash(enabled, gainDb);
}

enum ListeningEnhancementPhase {
  checking,
  unavailable,
  off,
  waitingSession,
  active,
  failed,
}

/// Read-back state from the current player session, separate from saved intent.
@immutable
class ListeningEnhancementState {
  const ListeningEnhancementState({
    required this.phase,
    this.supported = false,
    this.hasControl = false,
    this.enabled = false,
    this.gainDb = 0,
    this.sessionId,
    this.reason,
  });

  final ListeningEnhancementPhase phase;
  final bool supported, hasControl, enabled;
  final double gainDb;
  final int? sessionId;
  final String? reason;
  bool get active =>
      phase == ListeningEnhancementPhase.active && enabled && hasControl;

  factory ListeningEnhancementState.fromJson(Map<Object?, Object?> value) {
    final phase = ListeningEnhancementPhase.values.firstWhere(
      (item) => item.name == value['phase'],
      orElse: () => ListeningEnhancementPhase.failed,
    );
    final gain = value['gainDb'];
    return ListeningEnhancementState(
      phase: phase,
      supported: value['supported'] == true,
      hasControl: value['hasControl'] == true,
      enabled: value['enabled'] == true,
      gainDb: gain is num && gain.isFinite ? gain.toDouble() : 0,
      sessionId: (value['sessionId'] as num?)?.toInt(),
      reason: value['reason'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ListeningEnhancementState &&
      phase == other.phase &&
      supported == other.supported &&
      hasControl == other.hasControl &&
      enabled == other.enabled &&
      gainDb == other.gainDb &&
      sessionId == other.sessionId &&
      reason == other.reason;
  @override
  int get hashCode => Object.hash(
    phase,
    supported,
    hasControl,
    enabled,
    gainDb,
    sessionId,
    reason,
  );
}

/// Optional effect attached to the existing Android player's session.
///
/// An effect failure never escapes into the transport. iOS and Harmony keep
/// their existing players and explicitly report that protected gain is not yet
/// supported; neither ordinary player volume nor raw gain is a substitute.
class ListeningEnhancement {
  ListeningEnhancement({bool? android, MethodChannel? channel})
    : _android =
          android ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
      _channel =
          channel ??
          const MethodChannel('org.mewx.wenku8/listening_enhancement');

  final bool _android;
  final MethodChannel _channel;
  final status = ValueNotifier<ListeningEnhancementState>(
    const ListeningEnhancementState(phase: ListeningEnhancementPhase.checking),
  );
  ListeningEnhancementPreference _preference =
      const ListeningEnhancementPreference();
  final preferences = ValueNotifier<ListeningEnhancementPreference>(
    const ListeningEnhancementPreference(),
  );
  int? _sessionId;
  int _revision = 0;
  bool _disposed = false;
  Future<void>? _initialized;
  Future<void> _pending = Future.value();

  ListeningEnhancementPreference get preference => _preference;

  /// Update gain without losing the current native player's audio-session ID.
  Future<void> setPreference(ListeningEnhancementPreference value) =>
      configure(value, audioSessionId: _sessionId);

  Future<void> initialize() => _initialized ??= _initialize();

  Future<void> _initialize() async {
    if (!_android) {
      _publish(
        const ListeningEnhancementState(
          phase: ListeningEnhancementPhase.unavailable,
          reason: '当前平台的播放器暂不支持声音增强',
        ),
      );
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && call.arguments is Map) {
        final value = Map<Object?, Object?>.from(call.arguments as Map);
        if (value['revision'] == _revision) _read(value);
      }
    });
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>('info');
      if (value != null) _read(value);
    } on MissingPluginException {
      _publish(
        const ListeningEnhancementState(
          phase: ListeningEnhancementPhase.unavailable,
          reason: '当前版本的播放器暂不支持声音增强',
        ),
      );
    } catch (_) {
      _failed();
    }
  }

  /// Call once for a preference change or a player audio-session ID change.
  /// Null/zero sessions only wait; this never attaches to the global output.
  Future<void> configure(
    ListeningEnhancementPreference preference, {
    int? audioSessionId,
  }) {
    if (_disposed) return Future.value();
    final sessionId = audioSessionId != null && audioSessionId > 0
        ? audioSessionId
        : null;
    if (_initialized != null &&
        preference == _preference &&
        sessionId == _sessionId) {
      return _pending;
    }
    _preference = preference;
    preferences.value = preference;
    _sessionId = sessionId;
    final revision = ++_revision;
    return _pending = _pending.then((_) async {
      await initialize();
      if (_disposed || revision != _revision || !_android) return;
      try {
        final value = await _channel.invokeMapMethod<Object?, Object?>(
          'configure',
          {
            ...preference.toJson(),
            'sessionId': sessionId,
            'revision': revision,
          },
        );
        if (revision == _revision && value != null) _read(value);
      } on MissingPluginException {
        _publish(
          const ListeningEnhancementState(
            phase: ListeningEnhancementPhase.unavailable,
            reason: '当前版本的播放器暂不支持声音增强',
          ),
        );
      } catch (_) {
        if (revision == _revision) _failed();
      }
    });
  }

  void _read(Map<Object?, Object?> value) {
    try {
      _publish(ListeningEnhancementState.fromJson(value));
    } catch (_) {
      _failed();
    }
  }

  void _failed() => _publish(
    ListeningEnhancementState(
      phase: ListeningEnhancementPhase.failed,
      supported: status.value.supported,
      reason: '声音增强暂不可用，普通播放不受影响',
    ),
  );

  void _publish(ListeningEnhancementState value) {
    if (!_disposed && status.value != value) status.value = value;
  }

  /// Release only this app's effect; the caller still owns the audio player.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pending;
    if (_android && _initialized != null) {
      try {
        await _channel.invokeMethod<void>('release');
      } catch (_) {
        // Engine detachment also releases the optional native effect.
      }
      _channel.setMethodCallHandler(null);
    }
    status.dispose();
    preferences.dispose();
  }
}
