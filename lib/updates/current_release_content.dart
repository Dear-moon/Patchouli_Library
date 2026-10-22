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
const _readerRoundTrip = '修复反复显隐控件、翻页再返回后，同一页内容和分页逐次变化的问题。';
const _readerReflow = '新增 **“控件显隐时正文重排”** 开关，默认开启；关闭后控件覆盖正文，不改变正文排版。';
const _readerBoundary = '修复快速跨章往返可能出现的白屏、正文重叠和顶部信息重复问题，优化重排卡顿。';
const _readerContinuation = '跨章沿用当前翻页效果与速度，改善相邻章节衔接。';
const _readerPageFrame = '统一正文、章节标题、页码及应用内时间、电量行的翻动，修复两侧裁切、下一页提前露出和上一页边缘残留闪烁。';
const _readerEntrance = '新增 **“章节入场动画”** 开关，默认关闭，不影响跨章翻页效果。';
const _readerBothSides =
    '分区点按翻页下新增 **“左右点按均为下一页”**，默认关闭；开启后两侧都前进，中间仍显隐控件，滑动方向不变。';
const _readerSettingsIcon = '阅读器右上角 Aa 更换为调节图标，保留原阅读设置入口。';
const _bilingualLayout = '改善双语 EPUB 的语言识别及原书浅字、透明度效果。';
const _bilingualDisplay = '本书语言支持显示全部语言或仅显示指定语言，修正选择中文却隐藏中文的问题。';
const _bilingualSpeech = '双语朗读自动按段落语言匹配，支持仅朗读指定语言，与正文显示语言独立。';
const _bilingualVoice = '支持每种语言单独配置音色；没有对应语言模型时跳过相关段落，不使用其他语言代读。';
const _speechResume = '修复部分短语段暂停后无法继续播放的问题，改善 App 和通知栏的续播。';
const _localDoc = '新增旧版 Word **DOC** 格式导入。';
const _localOpenWith = '支持从系统“打开方式”选择本 App，并通过系统“始终”选项设为对应格式的默认阅读器。';
const _localLink = '改善原文件关联和权限处理，可读取时直接打开，减少重复选择原文件，不自动复制整本原书。';
const _localSummary = '本地书籍详情及编辑页移除简介；继续阅读按钮只保留节号，不再重复附带章节名称。';
const _localCover = '合卷更换封面时，可选择各原卷的封面。';
const _authorFilter = '书架、本地页支持按作者筛选，保留原有手动分类。';
const _localSync = '修复“更多本地设置 → 跨设备同步设置”点击无反应的问题。';
const _shelfLoading = '立体书架改为书形波浪骨架加载，书籍与封面逐本接续显示，减少加载前后的突兀跳变。';
const _directReading = '“点书直接阅读”支持分别选择发现页、书架页、本地页，支持多选。';
const _navigationTop = '再次点击当前选中的底部导航按钮，可回到页面顶部；切换栏目仍保留各自位置。';
const _forcePortrait = 'App 设置的“使用方式”新增 **“强制竖屏”**，不改变系统旋转设置或其他 App 的方向。';
const _commentCopy = '评论支持选中复制、整条复制、提取及复制链接。';
const _commentMarkup = '改善原始 HTML、多层转义及代码块中的评论显示，减少标签直接出现在正文中的问题。';
const _commentLinks = '点击评论链接后，可交由系统打开对应应用或浏览器。';
const _websiteSession = '优化官网验证后的连续阅读衔接，减少跨章节重复打开验证页。';
const _illustrationNetwork = '优化插图连接超时处理及失败恢复，图片失败不影响前后正文。';

const _releaseChanges =
    '### 阅读器与翻页\n\n- $_readerRoundTrip\n- $_readerReflow\n- $_readerBoundary\n- $_readerContinuation\n- $_readerPageFrame\n- $_readerEntrance\n- $_readerBothSides\n- $_readerSettingsIcon\n\n'
    '### 双语 EPUB 与听书\n\n- $_bilingualLayout\n- $_bilingualDisplay\n- $_bilingualSpeech\n- $_bilingualVoice\n- $_speechResume\n\n'
    '### 本地书籍与书库整理\n\n- $_localDoc\n- $_localOpenWith\n- $_localLink\n- $_localSummary\n- $_localCover\n- $_authorFilter\n- $_localSync\n\n'
    '### 界面与使用方式\n\n- $_shelfLoading\n- $_directReading\n- $_navigationTop\n- $_forcePortrait\n\n'
    '### 评论与联网阅读\n\n- $_commentCopy\n- $_commentMarkup\n- $_commentLinks\n- $_websiteSession\n- $_illustrationNetwork';

// Keep the in-app opening intact. Public announcements omit contact information.
const publicReleaseNotes =
    '$_freeNoticeBody\n\n$releaseReadingNotice\n\n**$currentReleaseSourcePolicy**\n\n$_releaseChanges';
const currentReleaseNotes = '$inAppCommunityNotice\n\n$publicReleaseNotes';

const currentReleaseSummary = [
  inAppCommunityNotice,
  releaseFreeNotice,
  releaseReadingNotice,
  currentReleaseSourcePolicy,
  _readerBoundary,
  _readerBothSides,
  _bilingualVoice,
  _localDoc,
  _shelfLoading,
  _forcePortrait,
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
  ReleaseSection("阅读器与翻页", [
    _readerRoundTrip,
    _readerReflow,
    _readerBoundary,
    _readerContinuation,
    _readerPageFrame,
    _readerEntrance,
    _readerBothSides,
    _readerSettingsIcon,
  ]),
  ReleaseSection("双语 EPUB 与听书", [
    _bilingualLayout,
    _bilingualDisplay,
    _bilingualSpeech,
    _bilingualVoice,
    _speechResume,
  ]),
  ReleaseSection("本地书籍与书库整理", [
    _localDoc,
    _localOpenWith,
    _localLink,
    _localSummary,
    _localCover,
    _authorFilter,
    _localSync,
  ]),
  ReleaseSection("界面与使用方式", [
    _shelfLoading,
    _directReading,
    _navigationTop,
    _forcePortrait,
  ]),
  ReleaseSection("评论与联网阅读", [
    _commentCopy,
    _commentMarkup,
    _commentLinks,
    _websiteSession,
    _illustrationNetwork,
  ]),
];
