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
const _animatedIcons = '换用原创折页墨线动态图标，统一导航、按钮及空白状态的视觉与动效。';
const _iconEntrance = '进入页面时，图标由上到下错峰入场，同一行同步播放；离开页面后停止动画。';
const _iconPerformance = '低性能模式支持单独开关图标动画，按设备表现与个人偏好选择。';
const _hapticSettings = 'App 设置 **“性能与动效 → 振动反馈”** 新增总开关与分类开关，支持轻、标准、强三档强度及试振。';
const _hapticCues = '按点按确认、切换、翻页、长按和调节刻度区分触感，优化反馈的清晰度。';
const _hapticShelf = '保留立体书架滑动的反馈密度；普通触屏及普通滚动开始不振动。';
const _searchRecovery = '修复部分搜索失败及失败后已有结果被清空的问题。';
const _tagSearch = '优化标签组合搜索、分页进度与重复查询，查找和继续加载更加连贯。';
const _searchRefresh = '修复刷新后仍显示旧搜索结果的问题。';
const _readerTitle = '修复翻页时顶部章节名称偶尔显示为其他章节的问题。';
const _readerLineReflow = '显隐控件时，横排正文按实际文字行衔接重排，不再按整段跳动；上下滚动模式不受正文重排影响。';
const _readerScroll = '上下滚动支持连续跨章，改善章节交界处的衔接。';
const _speechPrecache = '听书提前准备后续 **3 个语段**，减少段落间等待；暂停、更换音色或跳转语段后，及时清除旧的待播内容。';
const _illustrationCancel = '修复插图拖动取消后仍切换图片的问题。';

const _releaseChanges =
    '### 图标与页面动效\n\n- $_animatedIcons\n- $_iconEntrance\n- $_iconPerformance\n\n'
    '### 振动反馈\n\n- $_hapticSettings\n- $_hapticCues\n- $_hapticShelf\n\n'
    '### 搜索与标签\n\n- $_searchRecovery\n- $_tagSearch\n- $_searchRefresh\n\n'
    '### 阅读与听书\n\n- $_readerTitle\n- $_readerLineReflow\n- $_readerScroll\n- $_speechPrecache\n- $_illustrationCancel';

// Keep the in-app opening intact. Public announcements omit contact information.
const publicReleaseNotes =
    '$_freeNoticeBody\n\n$releaseReadingNotice\n\n**$currentReleaseSourcePolicy**\n\n$_releaseChanges';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';

const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  '原创折页墨线动态图标，入场更连贯。',
  '振动支持分类开关、强度选择与试振。',
  '修复搜索与章节标题，改善逐行重排和连续滚动。',
  '听书提前准备后续 3 个语段。',
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
  ReleaseSection("图标与页面动效", [_animatedIcons, _iconEntrance, _iconPerformance]),
  ReleaseSection("振动反馈", [_hapticSettings, _hapticCues, _hapticShelf]),
  ReleaseSection("搜索与标签", [_searchRecovery, _tagSearch, _searchRefresh]),
  ReleaseSection("阅读与听书", [
    _readerTitle,
    _readerLineReflow,
    _readerScroll,
    _speechPrecache,
    _illustrationCancel,
  ]),
];
