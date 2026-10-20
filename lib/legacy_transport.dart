import 'dart:typed_data';
import 'online_component.dart';

/// Optional image-provider boundary for the public, local-reading build.
abstract final class LegacyTransport {
  static Future<Uint8List> Function(String) illustrationReader = (_) =>
      unavailableOnline();
  static Future<void> setUpdatePriority(bool enabled) async {}
  static Future<Uint8List> illustration(String url) => illustrationReader(url);
  static Future<void> clearIllustrations() async {}
}
