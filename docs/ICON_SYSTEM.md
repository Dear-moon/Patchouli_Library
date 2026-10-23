# 折页墨线 · 纸页与档案 II

87 枚原创矢量图标，以折页、墨块和印刷留白建立家族特征。书架是带切角的档案书脊，本地页是露出纸张的文件夹，“我的”是一张折角身份卡；播放与暂停像两片深浅不同的纸。纸色、轻玻璃和桌面图标沿用项目原有设计。

## 看效果

```sh
flutter run -t tools/icon_studio.dart
```

独立预览使用真实的底部导航、玻璃按钮和图标绘制器。点击「播放一轮」查看完整动作，也可逐个点击或悬停。核心区放大展示六个高频图标；完整图标表在下方。右上角可切换深浅主题和动效。

生成可直接用浏览器打开的动态总览、87 份 SVG 以及 Flutter 实际渲染图：

```sh
flutter test test/archive_icons_test.dart \
  --dart-define=EXPORT_ARCHIVE_ICONS=true \
  --dart-define=REVIEW_ARTIFACTS=build/icon-studio \
  --dart-define=REVIEW_FONT=test/fixtures/fonts/SourceHanSerifCN-VF.otf
```

输出在 `build/icon-studio/index.html`、`svg/`、`icons-light.png` 和 `icons-dark.png`。HTML 自包含，可离线查看。SVG 和网页动画均由 Flutter 使用的同一份矢量几何生成。

## 直接用在现有控件上

`app_ui.dart` 导出图标组件。现有 `GlassIconButton`、`GlassPillButton`、`GlassDock` 和 `FeatureEntry` 已自动接入，无需改变它们的业务回调。

```dart
GlassIconButton(
  icon: playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
  label: playing ? '暂停' : '播放',
  onPressed: togglePlayback,
)
```

进入页面时，当前可见的动态图标从上到下依次播放一次折页动作；同一行一起动，最上行与最下行间隔 360 ms。返回页面、切回标签页也会重新问候一次。普通重建、加载进度和滚动缓存不会反复触发。入场只重绘图标，不移动文字或控件，也不产生振动。

轻点后会完整播放一次动作：起势、展开、错峰回弹、落定。松手不会提前收回。播放/暂停、书签、选择圆圈、显示/隐藏和展开箭头在原位变形；业务操作即时执行。

不在按钮中的图标可直接使用语义名称：

```dart
const ArchiveIcon.symbol(ArchiveSymbol.language, size: 24)
```

独立按钮使用 `ArchiveIconButton`。已有自定义触摸控件同时传入按下状态与成功点击次数：按下只轻压，点击确认后完整播放，手势取消不触发完整动作。

```dart
ArchiveIconContact(
  pressed: pressed,
  activation: completedTaps,
  child: const ArchiveIcon.symbol(ArchiveSymbol.sliders),
)
```

空书架、无结果、连接错误等展示图标不需要点击。使用 `ambient`，首次显示播放一次，落定后间隔 2.6 秒再播放；暂停期间没有运行中的逐帧动画。

```dart
const ArchiveIcon.symbol(ArchiveSymbol.shelf, size: 34, ambient: true)
```

`ContentNotice` 已统一接入。所有图标在页面隐藏、被另一页面或弹窗覆盖、App 进入后台时停止，重新显示再播放一次入场。工具栏、电量等图标落定后不循环；只有显式设置 `ambient` 的展示图标保留原有间歇动作。

底部导航只让新选中的图标播放，离开的图标立即静止，按压也只跟随手指所在的分区。上一章／下一章等操作型 Dock 使用 `animateInactiveIcons: true`，按下的动作不依赖导航选中项。

## 动作跟着用途走

| 图标组 | 数量 | 主要内容 | 动态方式 |
| --- | ---: | --- | --- |
| 导航 | 17 | 发现、书架、本地、我的、方向与更多 | 纸上罗盘拨动、书脊依次抽出、夹内纸张探出；墨点跳动 |
| 阅读 | 14 | 目录、书签、字体、插图、双语与阅读设置 | 翻动一页、书签弯折、三条纵轨错峰滑动、日光旋开 |
| 听书 | 11 | 播放、暂停、上下段、音色、音量与速度 | 深浅双页变形，波形错峰起落、刻度指针回弹 |
| 操作 | 17 | 搜索、筛选、选择、编辑、删除、复制与分享 | 镜片舒张、筛选收束、墨迹勾选、笔尖与箱盖动作 |
| 文件 | 8 | 同步、下载、缓存、导入、文档与整理 | 纸张分离、箭头落入托盘、同步半转回落、星芒展开 |
| 系统 | 20 | 账号、官网、设备、连接、状态和排查 | 可操作图标短反馈；电量、充电等信息标记保持安静 |

## 尺寸、颜色和性能

- 基准画布 24 × 24，默认笔画 1.72，圆角端点与切角轮廓并用。小于 18 的图标使用 1.9 单位笔画；高对比度使用 2.05。墨块的深浅继承同一前景色。
- 颜色、透明度、禁用态和文字缩放继承 `IconTheme`，支持 App 自选配色；不为图标另设彩色底片。
- 单个入场动作固定 520 ms，首屏可见行之间分配最多 360 ms 错峰，整轮最长 880 ms；只有一行时不等待。成功点击后的完整动作 640 ms，状态变形 380 ms。三组纸张部件使用错开的同一条曲线，包含预备、主动作和两次衰减回弹。连续点击从当前姿态接续。动画只重绘图标，不改变占位。
- 入场复用页面的 `ArchiveMotionScope`、路由可见状态和标签页 `TickerMode`；布局后核对屏幕与滚动裁剪范围。离屏缓存图标不启动可见动作，页面退出会取消未完成入场，不添加延迟补播队列。
- 「低性能设备模式 → 动态图标」单独控制图标动作，与「过渡动效」互不依赖。轻量预设默认关闭，正常模式默认开启；选择会保存并跟随设置备份。系统或 App 明确开启「减少动态效果」时仍保持静止。
- `PerformanceScope.explicitReduceMotion` 接收系统与用户的实际减少动态选择，不包括性能预设对页面过渡的关闭。未传入时沿用 `MediaQuery.disableAnimations`，隐藏页面的 `TickerMode` 始终生效。
- 返回/前进保留文字方向规则；纯装饰矢量不向读屏暴露内部路径，操作名称仍由原按钮提供。

## 维护入口

- `lib/archive_icons.dart`：语义清单、兼容映射、触摸反馈与状态过渡。
- `lib/archive_icon_art.dart`：原创几何、绘制与 SVG 导出，只有一份图形来源。
- `lib/archive_icon_fold_art.dart`：全套折页造型及局部动作。
- `lib/archive_icon_motion.dart`：三段错峰动作、回弹曲线与共享时长。
- `tools/icon_studio.dart`：Flutter 交互预览。
- `tools/export_icon_studio.dart`：离线网页和 SVG 输出。
- `test/archive_icons_test.dart`：全套逐帧边界、快速点击完整演绎、既有图标覆盖、连续切换、语义、禁用态、减少动态效果以及 48px/24px 原生动作录制。
- `test/archive_icon_behavior_test.dart`：导航出入状态、操作型 Dock、真实空书架、展示图标间歇动效，以及隐藏页面、覆盖路由、后台和减少动态效果时停止。
- `test/archive_icon_entrance_test.dart`：全图标单次入场、上中下逐行实际帧与同行同步、离屏缓存、保留标签页往返、共享页头、普通重建、无自动振动及真实尺寸截图。
- `test/performance_preferences_test.dart`：图标与过渡独立开关、持久化与备份、减少动态优先级、低性能页面开关和恢复预设。

新增功能优先选择已有语义。确需新图标时，在清单与几何中一并添加，并运行覆盖检查，避免重新混用系统图标字体。
