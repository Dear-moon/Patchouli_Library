# 构建与发布

本仓库只发布空书源的通用多源引擎版。外部站点规则、账号、Cookie、私密仓库凭据和旧原生站点组件不得进入源码或 APK。

## 构建

配置本机 Flutter SDK 与 Android SDK 后执行：

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64
```

包名保持现有独立发行标识，以支持覆盖安装。签名使用发行者本机未跟踪的 Android 签名配置；不要提交密钥、密码或本机 SDK 路径。

## 发布检查

检查公开源码清单及 Git 快照，运行直接修改模块的检查并完成发行编译。确认 APK 无站点 JSON、私密规则测试或旧站点原生运行库；验证空书源首次启动、手动导入、账号与阅读流程。站点规则更新由独立仓库生成 JSON，手动导入，不嵌入 GitHub 访问凭据。

新仓库采用经过审核的源码快照作为初始历史，不携带旧仓库中已发布的站点规则。保留 GPL 许可证、原作者及第三方组件的版权和许可证声明。

发行入口为本仓库 Releases。App 更新检查指向 `Dear-moon/Patchouli_Library`；上游发行包仅作为项目历史参考。
