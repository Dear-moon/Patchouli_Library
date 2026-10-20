import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../app_interactions.dart';
import 'app_updates.dart';
import 'release_notices.dart';

export 'release_notices.dart' show currentReleaseSourcePolicy;

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const currentReleaseSummary = [
  currentReleaseSourcePolicy,
  '**免费开源**，请从项目仓库或 App 内更新获取安装包。',
  '改善账号会话恢复与折叠屏阅读，调整夜读亮度和阅读进度显示。',
  '新增整书查找、书签分类与局域网续读；可选择手机已安装的朗读引擎。',
  '新增单书排版、阅读背景和本地封面；字体按需下载，改善 EPUB 注音、注释与导入体验。',
  '新增旧 EPUB 排版升级、批量封面重建与存储整理；局域网自动同步书签和分类，支持冲突处理。',
];

const currentReleaseSections = [
  ReleaseSection('重要说明 · 请务必阅读', [
    currentReleaseSourcePolicy,
    '应用名称保持「轻小说文库」。不再提供其他来源或自定义书源的导入、管理及在线阅读功能。',
    projectFreeNotice,
    projectContentNotice,
    projectRightsNotice,
    projectRiskNotice,
  ]),
  ReleaseSection('账号与兼容', [
    '文库账号页新增「注册文库账号」，可前往官网注册，完成后返回登录；无需另外创建 App 账号。',
    '改善部分设备从小窗恢复后，页面顶部出现大块空白的问题，保留正常的摄像头与系统栏避让。',
    '「我的 → 文库账号」新增保持登录，会话过期后自动重新连接；已有账号首次开启时确认一次密码，关闭或退出账号即可清除本机自动连接凭据。',
    '回到 App 时沿用有效登录，减少额外等待；断网不会清除账号，连接恢复后继续使用。推荐、收藏和评论不会因恢复登录而重复提交。',
    '统一账号入口，一次登录后自动继续连接；不再分别登录，只有需要人工访问验证时才提示。',
    '改善重启后的登录状态恢复，临时读取异常不再清除已保存的账号连接；个别操作失败时保留连接正常的账号。',
    '修复重新登录后又被先前的过期提示退出的问题；账号确实过期时，登录状态会及时更新。',
    '改善签到前的连接恢复；签到已完成后，积分刷新失败不再误报为签到失败，跨天后可继续签到。',
    '修复推荐结果被误报为网络异常的问题，正确显示官网的次数限制与操作提示。',
    '修复部分折叠屏完全展开后，横排或竖排正文只占半边的问题。',
    '改善隐藏系统状态栏后顶部黑边的兼容性，保留原来的时间、电量和安全区布局。',
    '打开阅读设置、目录或章内查找时，保留阅读亮度和隐藏状态栏设置，避免突然变亮或时间、电量重叠。',
  ]),
  ReleaseSection('阅读体验', [
    '「我的 → 设置 → 阅读与外观」新增「主题配色」：可保留原色、跟随系统莫奈取色，或自选主色；浅／深色自动配套，玻璃和控件一同适配，阅读器仍保持独立配色。',
    '图片取色可自动推荐颜色，也能在图片上点选或拖动；只保存选定颜色，原图不变。',
    '主题配色页新增「图标莫奈取色」独立开关，支持的 Android 桌面可跟随系统壁纸着色；关闭时提供原图标，实际显示由桌面的主题图标设置决定。',
    '目录面板左侧改为「章节进度」、右侧为「章节目录」，打开时优先显示进度调整，回到章首、跳至章末与章内查找仍在原处。',
    '目录的进度页可切换本章或整书，预览目标章节后再前往；整书比例按章节计算，不会因拖动而反复加载正文。章内查找中新增整书查找，可点结果跳到对应章节并高亮。',
    '整书查找默认读取本地和已缓存正文，不会自动缓存整本在线书；未缓存章节可确认后联网查找。',
    '「阅读设置 → 排版 → 阅读背景」可导入图片，选择填满或完整显示、透明预览浓度；沿用本书或通用范围，支持纯色与删除背景。',
    '修复阅读背景或本地封面已经导入成功，却仍显示失败提示的问题；原图和已保存的背景、封面保留。',
    '「阅读设置 → 排版」新增排版范围；选择「本书」可独立保存字体、字号、行距、配色、阅读方式与边距，不影响其他书。切回「通用」后保留本书的设置，随时可再启用。',
    '新增「文字细节」，可选择字重、调整字间距；横排与竖排均生效，拖动时透明预览，恢复默认排版时一并复位。',
    '可下载字体提供思源宋体、思源黑体、霞鹜文楷屏幕版、朱雀仿宋与芫荽五种选择，不再预装字库；支持离线使用、删除和重新下载，App、阅读器与单书可分别选择。',
    '字体下载在原按钮内显示轻盈圆环，不再另占一块区域或显示百分比；中央停止键可直接取消，下载大小、校验与失败重试保留。「字体」页右上角 ＋ 可导入自己的字体，选择列表优先展示已导入和已下载字体。',
    '修复阅读控件收放时，上下模糊区域短暂闪黑或闪白，保留原有模糊强度与正文移动效果。',
    '夜读默认文字更柔和，可在「阅读设置 → 排版 → 夜读文字亮度」单独调暗文字，控件仍保持清楚。',
    '阅读亮度支持调至设备最低档，左边缘滑动调亮度与设置滑块保持一致。',
    '隐藏控件后，滚动阅读顶部同一行显示章节名称与章内百分比；翻页模式的章节行同时保留页码和百分比。',
    '滚动阅读显示或隐藏控件时，顶部章节行柔和淡出、淡入，不再突然消失。修复向下阅读时百分比反而减少的问题；往回阅读仍可正常回退。',
    '调整字号、页边距或屏幕尺寸后，进度显示同步更新，避免遮挡正文。',
    '「阅读设置 → 排版」新增翻页速度，可选舒缓、标准或利落；横排、竖排和音量键翻页保持一致。',
    '竖排展开或收起屏幕时，从当前文字继续，避免回退到前面几段。',
    '竖排阅读使用直角引号显示中文弯引号；横排、原文、复制内容与书签位置保持不变。',
    '改善小阅读区域或大字号下，超宽表情等字符附近的文字重复和排版错位。',
    '滚动阅读的惯性停在章末，保留末段供阅读；再次从章末上滑即可续读下一章，自动阅读仍正常续章。',
    '隐藏系统状态栏后，时间与电量避让系统报告的摄像头；「阅读设置 → 操作」新增留边调整，拖动时透明预览，不改变正文排版。',
    '「纸页翻动」改为随手指弯曲的纸面，带纸背与柔和阴影；松手翻过或反向拖回。手机单页与大屏对页均适配，对页从书缝翻动，竖排仍左右翻页；其他效果和默认选择不变。',
    '华为设备的阅读操作页补充系统悬浮导航球关闭指引，可主动打开系统设置；不擅自改变系统导航方式。',
  ]),
  ReleaseSection('书签、续读与听书', [
    '「我的 → 书签」新增书签分类与筛选；阅读设置的书签页也可修改分类，两处共用同一份书签，分类随阅读记录备份保留。',
    '已配对的局域网设备自动增量同步书签、摘录分类与书籍分类；修改和删除后自动接续，两台 App 需保持前台。',
    '两端同时修改同一条记录时保留全部版本，在「局域网续读 → 同步冲突」选择继续使用哪项；删除冲突暂按删除处理，避免旧记录重新出现。中断后可继续合并。',
    '局域网续读移至「我的 → 设置」首页。同一 Wi-Fi 自动发现设备，首次连接时核对两端数字并确认，不用输入地址或连接码；以后自动重连。手动连接收进折叠选项。',
    '本地书的「目录 → 章节进度」新增「在其他设备上续读」。选择已配对设备，对方缺书时一并传送这本书，收到后点「继续阅读」即可接着读；已有同一本书时只传位置，不重复复制。',
    '传书保留原书、目录、插图、封面与合订本结构，支持停止和重试；不会搬走手机上的原书。两台 App 需保持前台，接收提醒不打断当前阅读。平时仍自动同步两端已有书籍的较新位置。',
    '续读设备卡片跟随阅读配色，不再出现突兀底色。接收方已在阅读器内时，点「继续阅读」也可正常接续：同一本书原位跳转，另一本替换当前书页，避免反复叠加阅读器。',
    '听书的音源选择新增「系统引擎」，自动检测手机已安装的 TTS 引擎，可选择系统默认或指定引擎，并查看其音色。',
    '现有自然在线、自定义接口、0.5～3 倍速、段落跟随与续听保留。系统引擎是否离线取决于安装的引擎和音色；选择时不自动播放声音。',
  ]),
  ReleaseSection('本地导入', [
    '「批量整理」右上角新增「修复与整理」，多选后分别升级旧 EPUB 排版、重建原书封面或整理存储；合订本按原卷处理，一本失败不影响其他书。',
    '旧 EPUB 升级保留原书、目录、阅读位置、书签和分类，成功后才切换新版排版；原书与旧正文不一致时保留旧数据并说明原因，不重新拆章。',
    '改善 EPUB 粗体、斜体、下划线、分页边界和表格内容；注音、注释弹窗、对齐、分隔线及混合横竖排一同保留，新导入和手动升级均可使用。',
    '批量重建原书封面时保留自选封面；存储整理只清理已核对可恢复的重复资源和升级后的旧正文，原书、未知文件及阅读记录保留。',
    '批量选择书籍后逐本处理并及时清理临时副本，减少大批量导入的额外空间占用；一本失败不影响后面的书，仍统一确认分卷合并。',
    '新导入 EPUB 不再额外保存整套解压插图；保留原图清晰度、离线查看、原书同步与封面快速显示。已有书籍不自动改写或清理。',
    '本地书籍详情右上角配置新增更换封面与恢复原书封面。合订本可单独设置；不改写原书，也不影响正文、进度与书签。',
    'TXT 新增 Big5 和香港扩展编码，改善部分繁体本地书籍的导入；目录识别补全常见繁体章名与数字。',
    '改善 UTF-16 编码 EPUB 的目录、书名与正文读取，保留特殊字和表情。',
    '改善 EPUB 附属资源引用和索引路径的兼容性。目录损坏时按原书顺序及正文标题恢复，并在导入结果中说明；不会因此丢弃可阅读的整本书。',
    '新导入 EPUB 时，原书目录未列出的独立插图页按原顺序并入正文，不再误生成一章；原书明确列出的插图章节仍保留，已有书籍目录和阅读记录不重写。',
    '新导入 EPUB 支持横排与竖排注音，注音不再混在正文、复制或朗读里；支持点按原书注释打开说明，关闭后留在原处。',
    '新导入 EPUB 保留常见段落对齐、分隔线与混合横竖排，图片按原书顺序和尺寸显示；不改写已导入书籍的目录和定位。',
    '本地及合并书架的批量整理新增「移动分类」，可先搜索、多选，再统一移入现有或新建分类；取消或保存失败时保留选择。',
    'TXT 编码移至「本地 → 显示与筛选 → 更多本地设置 → 导入与目录」，沿用紧凑选项按钮，可随阅读记录备份恢复。',
    '新增 TXT 自定义目录，可分别设置章名与卷名规则、选择常见样式并预览；默认仍为自动识别。',
    '原书未提供标题时，可选择标为正文片段。新设置只影响之后导入的书，已有目录、进度和书签不重写。',
    '自定义目录随原书同步，两端目录规则不一致时保留本机记录并提示。',
  ]),
  ReleaseSection('书架与性能', [
    '新版本提醒、「关于」页与本版详细说明统一支持 Markdown，标题、重点、列表和链接显示更清楚；重要说明补充免费开源、内容来源与使用风险提醒。',
    '统一发现、出版分类、搜索、作者作品、标签书单、评论和云书架的刷新体验：保留已有内容与位置，不重播骨架或整组入场；骨架只在首次加载时显示。',
    '多页列表刷新完成后再一起更新，避免先缩短列表再陆续补回；中途失败仍保留原列表，可直接重试。',
    '发现页左上角的 W8 标记换成 App 图标，保留原有尺寸与标题对齐。',
    '书籍缓存、字体下载与应用更新统一使用原位进度按钮：细圆弧柔和推进，完成后轻巧收尾；缓存进度回到原缓存按钮，不再重复显示大圆环，保留已保存章数及取消、继续缓存。',
    '修复整书缓存遗漏插图，正文图片与独立插图章节一并保存，重启后可离线查看；已有正文也能补齐插图。失败保留已缓存内容，点继续缓存只补缺失部分；清除本书缓存时一并清理插图。',
    '进一步减少长章节分页缓存的内存占用，保留原文、插图、字形与动效。',
    '提前加载并准备相邻书籍的封面，减少切换到中央时才突然出现图片的情况。',
    '英文书名沿书脊成组排列，不再一个字母占一行；中文书脊仍保持竖排。',
    '自动翻页在等待期间不再持续刷新静止书页；改善大书库恢复和分类筛选时的界面停顿。',
    '减少竖排长章节及控件收放时的额外内存和重排开销，保留阅读进度、书签定位与逐列动效。',
    '进一步减少超长段落首次分页的等待；竖排调整行距、对齐方式或展开窗口时，正文更快完成重新排版。',
    '减少启动时不需要的准备工作；思源宋体不再预装进安装包，按需下载后保留原有字形与字重。',
    '缩小安装包，保留现有玻璃效果、动效和阅读功能。',
    '调整基础组件与工程结构。',
    currentReleaseSourcePolicy,
  ]),
];

class CurrentReleaseCard extends StatelessWidget {
  const CurrentReleaseCard({super.key, this.updates});
  final AppUpdates? updates;
  @override
  Widget build(BuildContext context) {
    final service = updates;
    Widget card() => ContentPanel(
      key: const ValueKey('current-release-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArchiveSection(
            title: '本版更新',
            code:
                'RELEASE / ${service?.installed?.version ?? currentAppVersion}',
          ),
          const SizedBox(height: 12),
          for (final item in currentReleaseSummary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText(
                '· $item',
                style: TextStyle(
                  fontSize: item == currentReleaseSourcePolicy ? 18 : 13,
                  fontWeight: item == currentReleaseSourcePolicy
                      ? FontWeight.w700
                      : FontWeight.normal,
                  height: 1.6,
                ),
              ),
            ),
          const SizedBox(height: 6),
          GlassTextButton(
            key: const ValueKey('view-current-release-details'),
            onPressed: () =>
                showInstalledReleaseNotes(context, updates: service),
            child: const AppText('查看详细更新说明'),
          ),
        ],
      ),
    );
    return service == null
        ? card()
        : AnimatedBuilder(animation: service, builder: (_, _) => card());
  }
}

Future<bool> showInstalledReleaseNotes(
  BuildContext context, {
  AppUpdates? updates,
  bool automatic = false,
}) async {
  if (updates != null && updates.installed == null) {
    try {
      await updates.loadInstalled();
    } catch (_) {
      // Manual viewing remains available when platform metadata is unavailable.
    }
    if (!context.mounted) return false;
  }
  final installed = updates?.installed;
  final appearance = GlassAppearance.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final completed =
      await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: !automatic,
        barrierLabel: '关闭更新说明',
        barrierColor: Colors.black.withValues(alpha: .16),
        transitionDuration: reduced ? Duration.zero : NovelMotion.enter,
        transitionBuilder: (context, animation, secondary, child) =>
            GlassOverlayTransition(
              animation: animation,
              kind: GlassOverlayKind.sheet,
              reduceMotion: reduced,
              child: child,
            ),
        pageBuilder: (context, _, _) => GlassAppearance(
          blur: appearance.blur,
          opacity: appearance.opacity,
          child: PopScope(
            canPop: !automatic,
            child: _ReleaseDetails(
              version: installed?.version ?? currentAppVersion,
              build: installed?.build ?? currentAppBuild,
            ),
          ),
        ),
      ) ==
      true;
  if (completed && installed != null && updates != null) {
    try {
      await updates.rememberReleaseNotes(installed);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '阅读状态未保存，下次打开可能再次显示');
    }
  }
  return completed;
}

class _ReleaseDetails extends StatefulWidget {
  const _ReleaseDetails({required this.version, required this.build});
  final String version;
  final int build;
  @override
  State<_ReleaseDetails> createState() => _ReleaseDetailsState();
}

class _ReleaseDetailsState extends State<_ReleaseDetails> {
  final _pages = PageController();
  final _sections = currentReleaseSections
      .where((s) => s.items.isNotEmpty)
      .toList(growable: false);
  int _page = 0;
  bool _moving = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _move(int page) async {
    if (_moving) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      setState(() => _moving = true);
      await _pages.animateToPage(
        page,
        duration: NovelMotion.enter,
        curve: NovelMotion.ease,
      );
      if (mounted) setState(() => _moving = false);
    }
  }

  Widget _navigation(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previous = GlassTextButton(
        key: const ValueKey('release-details-previous'),
        onPressed: _page == 0 || _moving ? null : () => _move(_page - 1),
        child: const AppText('上一页'),
      );
      final next = GlassPillButton(
        key: const ValueKey('release-details-next'),
        label: _page == _sections.length - 1 ? '完成' : '下一页',
        icon: _page == _sections.length - 1
            ? CupertinoIcons.checkmark
            : CupertinoIcons.arrow_right,
        onPressed: _moving
            ? null
            : () {
                if (_page == _sections.length - 1) {
                  Navigator.pop(context, true);
                } else {
                  _move(_page + 1);
                }
              },
      );
      if (constraints.maxWidth <
          MediaQuery.textScalerOf(context).scale(14) * 8 + 120) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [previous, const SizedBox(height: 6), next],
        );
      }
      return Row(
        children: [
          Expanded(child: previous),
          const SizedBox(width: 12),
          Expanded(child: next),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: GlassOverlaySurface(
              key: const ValueKey('installed-release-details'),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArchiveCode(
                      'RELEASE / ${widget.version} · ${widget.build}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            '本版更新',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AppText(
                          '${_page + 1}/${_sections.length}',
                          key: const ValueKey('release-details-progress'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: PageView.builder(
                        key: const ValueKey('release-details-pages'),
                        controller: _pages,
                        itemCount: _sections.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppText(
                                _sections[index].title,
                                key: ValueKey('release-section-$index'),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (final item in _sections[index].items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: AppText(
                                    '· $item',
                                    style: TextStyle(
                                      fontSize: index == 0 ? 18 : 14,
                                      fontWeight: index == 0
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      height: 1.75,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _navigation(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
