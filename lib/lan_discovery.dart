import 'dart:async';
import 'package:flutter/services.dart';

class LanNearbyDevice {
  const LanNearbyDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });
  final String id, name, host;
  final int port;
}

/// The platform owns mDNS reception. No subnet/port scans or cloud directory.
class LanDiscovery {
  static const _channel = MethodChannel('org.mewx.wenku8/lan_discovery');
  final _changes = StreamController<List<LanNearbyDevice>>.broadcast();
  Stream<List<LanNearbyDevice>> get changes => _changes.stream;
  String name = '我的设备';
  bool available = false;
  int _generation = 0;
  bool _disposed = false;
  List<LanNearbyDevice> _devices = const [];
  Future<void> start(String id, int port) async {
    if (_disposed) return;
    final generation = ++_generation;
    var nativeStateReported = false;
    available = false;
    _devices = const [];
    _channel.setMethodCallHandler((call) async {
      if (_disposed || generation != _generation) return;
      if (call.method == 'failure') {
        nativeStateReported = true;
        available = false;
        _devices = const [];
        _changes.add(_devices);
        return;
      }
      if (call.method == 'ready') {
        nativeStateReported = true;
        available = true;
        _changes.add(_devices);
        return;
      }
      if (call.method != 'devices' || call.arguments is! List) return;
      final devices = <LanNearbyDevice>[];
      for (final value in call.arguments as List) {
        if (value is! Map ||
            value['id'] is! String ||
            value['name'] is! String ||
            value['host'] is! String ||
            value['port'] is! int) {
          continue;
        }
        devices.add(
          LanNearbyDevice(
            id: value['id'],
            name: value['name'],
            host: value['host'],
            port: value['port'],
          ),
        );
      }
      _devices = List.unmodifiable(devices);
      _changes.add(_devices);
    });
    try {
      final label = await _channel.invokeMethod<String>('start', {
        'id': id,
        'port': port,
      });
      if (_disposed || generation != _generation) return;
      name = label ?? name;
      if (!nativeStateReported) available = true;
    } on MissingPluginException {
      if (generation == _generation) available = false;
    } on PlatformException {
      if (generation == _generation) available = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    _channel.setMethodCallHandler(null);
    available = false;
    _devices = const [];
    if (!_disposed) _changes.add(_devices);
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      /* Manual pairing remains available on other hosts. */
    } on PlatformException {
      /* The platform may already have stopped discovery. */
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}
