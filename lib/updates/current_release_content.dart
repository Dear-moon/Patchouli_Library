import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const releaseFreeNotice = '**本项目完全免费，无任何赞助、打赏或付费渠道。**';
const releaseReadingNotice = '**在线内容以轻小说文库开放状态为准，不提供因版权限制而停止开放的在线书籍阅读。**';
const _connection = '优化文库账号连接、验证和书籍加载。';
const _sync = '新增 WebDAV 自动同步阅读进度。';
const _reader = '阅读信息可选上下位置，新增纯白背景、文字颜色和透明度。';
const _library = '支持书架正序／倒序，优化小组件显示与听书时长统计。';
const _fixes = '修复 iOS 原文件关联、切换后台闪动等问题。';
const _changes = [_connection, _sync, _reader, _library, _fixes];
const _installation =
    'Android 可直接更新；iOS 与 HarmonyOS 安装包未签名，需自行签名后安装。升级前请备份重要书籍和阅读记录。';
const publicReleaseNotes =
    '''
### 免费使用，请勿付费

$releaseFreeNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### 本次更新
- $_connection
- $_sync
- $_reader
- $_library
- $_fixes

### 安装说明
$_installation
''';
const currentReleaseNotes = publicReleaseNotes;
const currentReleaseSummary = [
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  ..._changes,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    releaseFreeNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('本次更新', [..._changes, _installation]),
];
