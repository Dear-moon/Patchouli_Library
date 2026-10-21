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
const _websiteRedirectFix =
    '修复合法官网跳转被误判为“其他站点”的问题，改善详情、目录和正文加载；遇到临时网络故障时，自动尝试备用官网一次。';
const _backgroundConcentrationFix = '阅读器自定义背景图片浓度最高支持 **100%**，并可保存该设置。';
const _releaseChanges =
    '### 本次更新\n\n- $_websiteRedirectFix\n- $_backgroundConcentrationFix';

// Keep the in-app opening intact. Public announcements omit contact information.
const publicReleaseNotes =
    '$_freeNoticeBody\n\n$releaseReadingNotice\n\n**$currentReleaseSourcePolicy**\n\n$_releaseChanges';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';

const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  _websiteRedirectFix,
  _backgroundConcentrationFix,
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
  ReleaseSection("本次更新", [_websiteRedirectFix, _backgroundConcentrationFix]),
];
