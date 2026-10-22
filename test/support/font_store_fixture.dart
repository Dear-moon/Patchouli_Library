import 'package:flutter/services.dart';
import 'package:wenku8_flutter/font_download.dart';
import 'package:wenku8_flutter/user_fonts.dart';
import 'serif_fixture.dart';

Future<void>? _prepared;
bool _ready = false;
Future<void> prepareSerifFixture() async {
  if (_ready) return;
  await (_prepared ??= (FontLoader(
    'SourceHanSerifCN',
  )..addFont(loadSerifFixture())).load());
  _ready = true;
}

/// Typography tests that previously had a bundled face now explicitly model an
/// already installed face. Download/persistence/deletion use the real store in
/// downloadable_fonts_test.dart instead of this availability fixture.
class InstalledSerifFixture extends UserFontStore {
  @override
  bool available(String id) => id == sourceHanFontId || super.available(id);
  @override
  Future<void> ensureLoaded(String id) =>
      id == sourceHanFontId ? prepareSerifFixture() : super.ensureLoaded(id);
}
