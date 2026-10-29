import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const inAppCommunityNotice = '**交流群：1131397088**\n遇到问题或有功能建议，欢迎进群反馈。';
const releaseFreeNotice = '**本项目完全免费、开源，无任何赞助、打赏或付费渠道。**';
const releaseReadingNotice =
    '**本项目仅为第三方阅读客户端，提供阅读界面与本地书籍管理，不运营在线书库、不自行发布小说资源。在线内容及可读状态一切以 Wenku8 为准；不提供因版权限制而停止开放的在线书籍阅读。**';
const _freeNotice = '不出售会员、激活码或功能解锁服务。任何以本项目或开发者名义收费、募捐、索要赞助的行为均与本项目无关，请勿付款。';
const _downloadNotice = '请通过项目仓库或 App 内更新获取安装包；升级前请备份原书和阅读记录。';
const _imports = '修复 iOS 背景、字体和本地书籍的文件选择；保留默认关联原文件与显式复制导入，修复重启后书架列表恢复异常。';
const _connection = '连接检查优先处理，限制检查等待时间，失败后可重新检查；官网要求验证时保留明确提示。';
const _harmony = '修复 HarmonyOS 小组件目录已存在时再次启动异常；安装包只保留完整的 ARM64 原生库。';
const _updates =
    'iOS 与 HarmonyOS 支持应用内自动提醒和手动检查，仅在对应平台有新安装包时提醒；通过版本页下载、自行签名后安装。';
const _migration = '旧版 iOS／HarmonyOS 0.5.0 需先手动安装本次修复版，此后可接收应用内更新提醒。';
const publicReleaseNotes =
    '''
### ⚠️ 免费开源，请勿付费

$releaseFreeNotice

$_freeNotice

$_downloadNotice

$releaseReadingNotice

**$currentReleaseSourcePolicy**

### iOS 与 HarmonyOS 修复
- $_imports
- $_connection
- $_harmony

### 更新提醒
- $_updates
- $_migration

### 安装说明
- iOS IPA 与 HarmonyOS HAP 均未签名，需要自行签名后安装。
- Android 继续使用已发布的 0.5.1（261），本次不替换 Android 安装包。
''';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';
const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  _imports,
  _connection,
  _harmony,
  _updates,
  _migration,
];
const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    inAppCommunityNotice,
    releaseFreeNotice,
    _freeNotice,
    _downloadNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection('文件导入与书架', [_imports]),
  ReleaseSection('连接与启动', [_connection, _harmony]),
  ReleaseSection('更新提醒与安装', [
    _updates,
    _migration,
    'iOS IPA 与 HarmonyOS HAP 均未签名，需要自行签名后安装。',
    'Android 继续使用已发布的 0.5.1（261），本次不替换 Android 安装包。',
  ]),
];
