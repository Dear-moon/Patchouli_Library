import 'release_notices.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const inAppCommunityNotice = r'''**交流群：1131397088**\
遇到问题或有功能建议，欢迎进群反馈。''';
const releaseFreeNotice = "**本项目完全免费、开源，无任何赞助、打赏或付费渠道。**";
const releaseReadingNotice =
    "**本项目仅为第三方阅读客户端，提供阅读界面与本地书籍管理，不运营在线书库、不自行发布小说资源。在线内容及可读状态一切以 Wenku8 为准；不提供因版权限制而停止开放的在线书籍阅读。**";

const _freeHeading = '### ⚠️ 免费开源，请勿付费';
const _freeFraudNotice =
    '不出售会员、激活码或功能解锁服务。任何以本项目或开发者名义收费、募捐、索要赞助的行为均与本项目无关，请勿付款。';
const _downloadNotice = '请通过**项目仓库或 App 内更新**获取安装包。';
const _freeNoticeBody =
    '$_freeHeading\n\n$releaseFreeNotice\n\n$_freeFraudNotice\n\n$_downloadNotice';
const _websiteReadingFix =
    '改善部分设备及网络环境下官网书籍详情、目录和正文无法加载的问题；需要访问验证时，可在官网页面完成验证后返回继续阅读。';
const _chineseUsernameFix = '修复文库账号用户名输入框无法正常输入中文的问题。';
const _trialShelfFix = '修复试读或缓存章节后书籍自动出现在书架的问题；在线书籍仅在主动加入书架后显示，缓存与阅读进度保留。';
const _releaseChanges =
    '### 本次更新\n\n- $_websiteReadingFix\n- $_chineseUsernameFix\n- $_trialShelfFix';

// Keep the in-app opening intact. Public announcements omit contact information.
const publicReleaseNotes =
    '$_freeNoticeBody\n\n$releaseReadingNotice\n\n**$currentReleaseSourcePolicy**\n\n$_releaseChanges';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';

const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  _websiteReadingFix,
  _chineseUsernameFix,
  _trialShelfFix,
];

const currentReleaseSections = [
  ReleaseSection("重要说明 · 请务必阅读", [
    inAppCommunityNotice,
    _freeHeading,
    releaseFreeNotice,
    _freeFraudNotice,
    _downloadNotice,
    releaseReadingNotice,
    currentReleaseSourcePolicy,
  ]),
  ReleaseSection("本次更新", [
    _websiteReadingFix,
    _chineseUsernameFix,
    _trialShelfFix,
  ]),
];
