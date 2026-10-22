import 'app_typography.dart';

// Keep the original preference ID and filename: existing installations can
// reuse their downloaded face without a migration or another transfer.
const sourceHanFontId = 'sourceHanSerif';
const sourceHanFontFile = 'SourceHanSerifCN-2.003.otf';
const sourceHanFontBytes = 22613144;

class DownloadableFont {
  const DownloadableFont({
    required this.typeface,
    required this.fileName,
    required this.bytes,
    required this.description,
    required this.sourceUrls,
    this.archiveEntry,
    int? transferBytes,
  }) : transferBytes = transferBytes ?? bytes;

  final AppTypeface typeface;
  final String fileName, description;
  final int bytes, transferBytes;
  final List<String> sourceUrls;
  final String? archiveEntry;
  String get id => typeface.name;
  String get name => typeface.label;
  String get sizeLabel => '${(transferBytes / 1048576).toStringAsFixed(1)} MiB';
}

// Unmodified, fixed upstream releases. Only the catalogue and license text are
// bundled; no font, remote preview or font API is fetched on page load.
const downloadableFonts = [
  DownloadableFont(
    typeface: AppTypeface.sourceHanSerif,
    fileName: sourceHanFontFile,
    bytes: sourceHanFontBytes,
    description: '宋体 · 书页般的清晰与层次',
    sourceUrls: [
      'https://mirror.iscas.ac.cn/adobe-fonts/source-han-serif/Variable/OTF/Subset/SourceHanSerifCN-VF.otf',
      'https://raw.githubusercontent.com/adobe-fonts/source-han-serif/2.003R/Variable/OTF/Subset/SourceHanSerifCN-VF.otf',
    ],
  ),
  DownloadableFont(
    typeface: AppTypeface.sourceHanSans,
    fileName: 'SourceHanSansCN-2.005.otf',
    bytes: 15636088,
    description: '黑体 · 简洁利落，多种字重',
    sourceUrls: [
      'https://mirror.iscas.ac.cn/adobe-fonts/source-han-sans/Variable/OTF/Subset/SourceHanSansCN-VF.otf',
      'https://raw.githubusercontent.com/adobe-fonts/source-han-sans/2.005R/Variable/OTF/Subset/SourceHanSansCN-VF.otf',
    ],
  ),
  DownloadableFont(
    typeface: AppTypeface.lxgwWenKai,
    fileName: 'LXGWWenKaiGBScreen-1.530.ttf',
    bytes: 26456786,
    description: '文楷 · 为屏幕阅读调整笔画',
    sourceUrls: [
      'https://github.com/lxgw/LxgwWenKai-Screen/releases/download/v1.530/LXGWWenKaiGBScreen.ttf',
    ],
  ),
  DownloadableFont(
    typeface: AppTypeface.zhuqueFangsong,
    fileName: 'ZhuqueFangsong-0.212.ttf',
    bytes: 8824084,
    transferBytes: 5743932,
    archiveEntry: 'ZhuqueFangsong-Regular.ttf',
    description: '仿宋 · 轻盈书卷气，字体预览版',
    sourceUrls: [
      'https://github.com/TrionesType/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip',
    ],
  ),
  DownloadableFont(
    typeface: AppTypeface.iansui,
    fileName: 'Iansui-1.020.ttf',
    bytes: 9447424,
    description: '繁体楷书 · 台湾字形与温润笔意',
    sourceUrls: [
      'https://raw.githubusercontent.com/ButTaiwan/iansui/v1.020/fonts/ttf/Iansui-Regular.ttf',
    ],
  ),
];

DownloadableFont? downloadableFont(String id) =>
    downloadableFonts.where((font) => font.id == id).firstOrNull;
