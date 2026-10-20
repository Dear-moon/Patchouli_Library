# 构建公开源码预览

此工程用于阅读器、界面和本地书库开发。构建后的应用名为「轻小说文库 · 源码预览」，使用独立包名 `org.mewx.wenku8_flutter.source_preview`，不会覆盖正式版或访问其应用数据。

## 本地构建

环境：Flutter 3.41.5、Dart 3.11.3、JDK 17、Android SDK。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
cd android
./gradlew :app:testReleaseUnitTest
```

预览支持本地导入、阅读、书架、缓存记录和界面开发。源码预览不是正式升级包。

未配置签名时使用本机调试证书。自己的签名可配置在 `android/key.properties`，字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`；密钥、文件和本机路径不要提交到 Git。

## 导出源码

在项目根目录执行：

```sh
python3 tools/export_public_source.py ../Wenku8_Flutter-public-source
python3 tools/check_public_source.py ../Wenku8_Flutter-public-source
```

输出目录必须为空。脚本保留公开源文件、测试、资源、平台工程和许可，排除本机配置、密钥、日志、截图、构建产物和开发记录；导出前检查受限组件与已识别凭据，失败时不写出目录。`--source-only` 为兼容旧调用保留，不能放宽边界。

提交前审阅实际差异，并更新 `tools/public-source-files.txt` 中经过确认的文件清单。首次使用此仓库时运行 `git config core.hooksPath .githooks`；推送前会检查每个新增提交的实际内容，未列入清单的文件需先审阅。

## GitHub Actions

[Flutter source checks](../.github/workflows/flutter-ci.yml) 在主分支、Pull Request 或手动运行时执行源码清单检查、Flutter 与原生测试、独立预览构建。它只具有读取权限，不读取正式签名，不上传构建产物，也不创建或更新 Release。

正式安装包沿用已配置的长期签名。维护者通过独立的「Sign reviewed distribution」手动任务签署经过确认的草稿安装包；该任务只向草稿上传签名结果，不自动公开版本。发布前仍须核对包名、版本、构建号、三种架构和旧版签名，确认附件后更新镜像发布清单。

## 许可与分发

保留原项目的 `LICENSE`、`NOTICE`、`assets/licenses/` 和各第三方组件源码与声明。本 Flutter 组合版本使用 GPL version 3；在线听书适配与文档导入库等仍适用各自许可，见 [第三方组件与分发条件](THIRD_PARTY.md)。

分发组合产物前，按实际组件核对对应源码、署名与分发授权。保留完整的第三方许可与修改记录。
