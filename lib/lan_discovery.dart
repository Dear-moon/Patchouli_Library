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
  Future<void> start(String id, int port) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'failure') {
        available = false;
        if (!_changes.isClosed) _changes.add(const []);
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
      if (!_changes.isClosed) _changes.add(devices);
    });
    try {
      name =
          await _channel.invokeMethod<String>('start', {
            'id': id,
            'port': port,
          }) ??
          name;
      available = true;
    } on MissingPluginException {
      available = false;
    } on PlatformException {
      available = false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      /* Manual pairing remains available on other hosts. */
    } on PlatformException {
      /* The platform may already have stopped discovery. */
    }
    available = false;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_changes.close());
  }
}
