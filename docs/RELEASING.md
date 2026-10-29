# 源码快照与安装包

使用应用请下载 [GitHub Releases](https://github.com/mikufoxxx/Wenku8_Flutter/releases/latest) 中适合设备的安装包。Android 使用签名 APK，iOS 与 HarmonyOS 的未签名包需自行签名。

本仓库是部分实现的参考快照，保留了一些未提供模块的引用，不能独立构建或复现正式安装包。GitHub 自动生成的 Source code ZIP／tar.gz 是此快照的压缩文件，不是安装包。发行版功能以实际安装包及发布说明为准。

## 文件检查

```sh
python3 tools/check_public_source.py
```

该检查验证公开文件清单及已识别的敏感内容，不是 Flutter 编译或运行验证。公开 CI 只执行此检查，不创建、删除或更新 Release 和安装包。

## 许可

保留 LICENSE、NOTICE、assets/licenses/ 和第三方组件的声明。公开文件仍遵循对应许可；部分参考快照不等同于正式二进制的完整对应源码。
