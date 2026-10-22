import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;
void registerAppLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Wenku8 Flutter',
    ], await rootBundle.loadString('assets/licenses/GPL-3.0.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Source Han Serif CN · Adobe',
    ], await rootBundle.loadString('assets/fonts/OFL-SourceHanSerif.txt'));
    for (final entry in const {
      'SourceHanSans': 'Source Han Sans CN · Adobe',
      'LXGWWenKaiScreen': 'LXGW WenKai GB Screen · LXGW / Klee Project',
      'ZhuqueFangsong': 'Zhuque Fangsong · TrionesType / Alegreya',
      'Iansui': 'Iansui · But Ko / Klee Project',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.value,
      ], await rootBundle.loadString('assets/fonts/OFL-${entry.key}.txt'));
    }
    yield LicenseEntryWithLineBreaks(const [
      'edge-tts protocol · rany',
    ], await rootBundle.loadString('assets/licenses/edge-tts.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'libmobi · Bartek Fabiszewski',
    ], await rootBundle.loadString('assets/licenses/libmobi.txt'));
    for (final item in const {
      'jsoup · Jonathan Hedley': 'jsoup',
      'commonmark-java · Atlassian': 'commonmark',
      'PDFBox Android · Apache Software Foundation / Tom Roush': 'pdfbox',
      'PDFBox / FontBox notices': 'pdfbox-notice',
      'Apache POI HWPF and document dependencies': 'poi',
      'Bouncy Castle': 'bouncycastle',
      'OpenJDK desugaring · Oracle / Google': 'desugar-jdk',
      'OpenCC dictionaries · BYVoid and contributors': 'opencc',
      'juniversalchardet · Mozilla / Kohei Taketa / Alberto Fernández':
          'juniversalchardet',
      'Cronet · Chromium and bundled third-party components': 'cronet',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        item.key,
      ], await rootBundle.loadString('assets/licenses/${item.value}.txt'));
    }
  });
}
