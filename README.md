<p align="center">
  <img src="assets/branding/app-icon.png" width="96" alt="轻小说文库" />
</p>

<h1 align="center">轻小说文库</h1>

<p align="center">基于 Flutter 的 Android 轻小说阅读客户端</p>

<p align="center">
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml"><img src="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml/badge.svg?branch=master" alt="Build" /></a>
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest"><img src="https://img.shields.io/github/v/release/mikufoxxx/Wenku8_Flutter?style=flat-square&amp;color=555555" alt="Release" /></a>
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases"><img src="https://img.shields.io/github/downloads/mikufoxxx/Wenku8_Flutter/total?style=flat-square&amp;label=GitHub%20Downloads&amp;color=555555" alt="GitHub Release 下载量" /></a>
  <img src="https://img.shields.io/badge/Platform-Android-555555?style=flat-square" alt="Android" />
  <a href="assets/licenses/GPL-3.0.txt"><img src="https://img.shields.io/badge/License-GPL--3.0-555555?style=flat-square" alt="GPL 3.0" /></a>
</p>

<p align="center">
  <a href="https://git.3952039.xyz/#releases">下载</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/issues">问题反馈</a> ·
  <a href="docs/RELEASING.md">构建指南</a>
</p>

## 简介

轻小说文库是面向 Android 手机与平板的轻小说阅读客户端，集成书籍发现、书架管理、本地书库、离线阅读与在线听书。奶白玻璃材质、档案式排版与立体书架贯穿界面，阅读器支持滚动、横排翻页、竖排翻页和大屏对页。

## 界面预览

<p align="center">
  <img src="docs/images/discovery.png" width="30%" alt="发现" />
  &nbsp;
  <img src="docs/images/reader.png" width="30%" alt="阅读器" />
  &nbsp;
  <img src="docs/images/settings.png" width="30%" alt="设置" />
</p>

## 功能特性

- **书籍发现**：分类、排行、出版文库；按书名、作者或标签筛选搜索，点击详情页作者或标签查看相应书单。
- **书架管理**：立体书架支持循环轮播、惯性滚动、吸附与触觉反馈，可切换为纯列表；与本地书库共用分类，支持搜索，可按阅读状态与书籍来源叠加筛选。
- **阅读排版**：上下滚动、横排翻页与竖排翻页，大屏对页；可选逐段接续、平移、覆盖、纸页翻动或无动画。曲面纸页跟随手指，对页从书缝翻动；翻页速度可调。字号、行距、字重、字间距、四边页边距、缩进与对齐支持实时预览，也可为单本书独立保存。
- **主题与字体**：支持系统莫奈配色、自选主色、图片取色与桌面主题图标开关；阅读器可独立配色、导入背景图片。五款字体按需下载、离线使用或删除，也可导入 TTF／OTF，App、阅读器和单书分别选择，不预装阅读字库。
- **阅读工具**：分卷目录、本章／整书进度、章内与整书查找、分区点按、音量键翻页、自动阅读与跨章衔接。封面与插图可双指缩放、保存原图；支持点书直接续读，并从阅读器进入详情。
- **书签与摘录**：长按正文选句或段落，复制、加入书签或快速查看本卷插图；书签支持分类、定位高亮与图片分享，可选 App 图标水印。
- **离线阅读**：App 内章节与插图缓存、失败续缓存、缓存管理、阅读历史和本地备份。在线书籍仅提供 App 内缓存，不提供整书文件下载或导出。
- **本地书库**：多选导入 TXT、EPUB、MOBI／AZW／AZW3／PRC、FB2、PDF、DOCX、RTF、HTML、Markdown 与 ZIP；支持扫描共享存储或指定文件夹，勾选后导入，同系列分卷可合并。支持自定义 TXT 目录、书名与作者编辑、自选封面和分卷顺序调整。本地与合并书架可多选、批量移动分类和删除。
- **EPUB 与书库整理**：支持注音、注释弹窗、常见段落对齐、分隔线与混合横竖排；可手动升级旧 EPUB 排版、批量重建原书封面或整理重复资源，保留原书、目录、进度与书签。
- **局域网续读**：同一 Wi-Fi 自动发现设备，首次两端确认后自动重连；在「目录 → 章节进度 → 在其他设备上续读」选择设备，缺书时一并传送。两台 App 保持前台时，自动增量同步进度、书签和分类；同时修改可在冲突页选择保留内容。
- **网盘与同步**：OpenList／WebDAV、夸克网盘导入（实验性），通过 OneDrive、Google Drive 等系统云文档入口手动合并同步原书与阅读记录。
- **听书**：自然在线音色、自定义 Microsoft SSML 接口，或自动检测手机已安装的系统 TTS 引擎及音色；支持 0.5～3 倍速、段落跟随、睡眠定时、后台与锁屏控制。系统引擎能否离线使用取决于所选音色。
- **账号与社区**：文库账号、云书架、书评与回复。
- **中文支持**：简体中文、香港繁体与台湾繁体，可跟随系统或手动选择。
- **性能设置**：帧率偏好与低性能设备模式，可独立调整玻璃折射、模糊、动效与立体书架。
- **使用方式**：离线时隐藏发现、保留可离线阅读的书；阅读器模式保留本地或合并书架与「我的」，随书库展示方式联动。

## 下载与更新

当前正式版为 **[0.4.2 · build 139](https://github.com/mikufoxxx/Wenku8_Flutter/releases/tag/v0.4.2)**，沿用原包名与正式签名，可直接覆盖升级。ARM64 安装包约 **32.8 MB**，比 0.4.1 缩小约 **42%**。

可从 [镜像下载页](https://git.3952039.xyz/#releases)、[GitHub Releases](https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest)，或 **我的 → 关于 → 检查更新** 获取。近年的 Android 手机与平板通常选择 **arm64-v8a**；旧款 32 位设备选择 **armeabi-v7a**，x86_64 用于对应架构的设备或模拟器。App 自动优先使用镜像，连接失败时回退到 GitHub，无需手动选择。

本版新增局域网传书续读、书签分类与自动同步、系统朗读引擎、自定义背景和封面、莫奈主题配色；改善 EPUB 注音与注释、批量导入及阅读性能。完整内容见 [更新日志](CHANGELOG.md)。

> [!IMPORTANT]
> **本 APP 以后只保留轻小说文库源和本地导入功能，不再支持任何其他源以及自定义书源。**
>
> **本项目免费使用，公开源码遵循仓库许可证。** 第三方组件遵循各自许可，不要购买所谓付费版、激活码或解锁服务。升级前请备份重要原书和阅读记录，不要先卸载正在使用的应用。

小说、封面和插图归各自权利人所有，源码许可不授予这些内容的使用权。本项目为第三方客户端，不支持侵权行为；仅阅读、导入和缓存有权使用的内容。服务可能调整或停止，反馈问题时请勿附带密码、Cookie 或令牌。

阅读与自定义语音见 [阅读器与本地书库](docs/READER.md)，网盘连接见 [网盘导入指南](docs/CLOUD_IMPORT.md)，标签与关键词用法见 [搜索指南](docs/SEARCH.md)。

## 构建

开发环境：**Flutter 3.41.5 / Dart 3.11.3、JDK 17、Android SDK**。

```sh
git clone https://github.com/mikufoxxx/Wenku8_Flutter.git
cd Wenku8_Flutter
flutter pub get
flutter build apk --release --target-platform android-arm64
```

此工程用于本地导入、阅读器、书架与界面开发。构建产物为独立的「轻小说文库 · 源码预览」，不会覆盖正式版或访问其应用数据。

### GitHub Actions

- [Flutter source checks](https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml)：代码检查、自动测试与独立源码预览构建，不上传安装包或创建版本发布。

构建方式见 [构建指南](docs/RELEASING.md)。

## 友情链接

[LINUX DO 社区](https://linux.do/)

## 贡献

欢迎通过 [Issues](https://github.com/mikufoxxx/Wenku8_Flutter/issues) 反馈问题或提出建议，通过 Pull Request 参与开发。提交问题时请提供应用版本、Android 版本和复现步骤。

## 致谢与许可

本项目基于 [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android) 重构。感谢 MewX、Baby Pepper（SeraphRoy）、Jack Liu（aaassseee）及原项目贡献者。

- 应用源码：保留原项目 [GPL v2 或后续版本声明](LICENSE)，本 Flutter 组合版本按 [GPL v3](assets/licenses/GPL-3.0.txt) 分发。
- 字体按需下载或自行导入，不预装字库；各字体遵循其 SIL OFL 1.1 许可。
- 在线语音协议适配：[rany2/edge-tts](https://github.com/rany2/edge-tts)，[LGPL v3](assets/licenses/edge-tts.txt)。

完整版权声明与第三方组件说明见 [NOTICE](NOTICE) 和 [第三方组件许可](docs/THIRD_PARTY.md)。

## Star History

<a href="https://www.star-history.com/?repos=mikufoxxx%2Fwenku8_flutter&type=date&releases=&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=mikufoxxx/wenku8_flutter&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=mikufoxxx/wenku8_flutter&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=mikufoxxx/wenku8_flutter&type=date&legend=top-left" />
 </picture>
</a>
