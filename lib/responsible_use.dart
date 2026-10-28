import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'feature_pages.dart';

const sourceImportRisk = '仅导入你有权使用的书源。规则可执行脚本并访问其配置的网站，请先核对来源与地址。';

/// Shared copy for the app's About and import entry points.
class ResponsibleUsePage extends StatelessWidget {
  const ResponsibleUsePage({super.key});

  static const sections = <(String, String)>[
    (
      '尊重作品与授权',
      '请尊重来源网站与作品的授权范围。'
          '请仅使用已获授权、属于公共领域或你依法有权使用的作品及服务。导入规则、拥有文件或能够访问网站，不等于获得作品的复制、传播或其他使用授权。',
    ),
    (
      '使用边界',
      '本项目反对侵犯著作权及其他合法权益的行为，不提供绕过付费、账号权限、DRM 或其他访问保护的服务。'
          '请遵守适用法律、来源网站规则与授权范围；未经许可，不要传播正文、插图、缓存或他人的登录信息。开源许可仅适用于相应代码，不授予第三方内容的使用权。',
    ),
    (
      '第三方规则与隐私风险',
      '书源可以包含 JavaScript、远程脚本和网络请求。使用时，搜索词、请求信息，以及你填写的登录资料可能发送到规则配置的服务。'
          '请只导入可信规则，检查地址和脚本，不要在不可信书源中填写账号。导出规则前，检查手工写入代码的密码、Cookie 或 Token。',
    ),
    (
      '可用性与数据',
      '第三方网站、规则和服务可能变更、失效或返回错误内容，兼容导入格式不代表内容已获授权、安全或持续可用。'
          '请妥善保存原始文件并备份阅读记录。在线听书会将待朗读文字发送给你选择的语音服务；使用前请确认有权这样处理内容。',
    ),
    (
      '权利反馈与处理',
      '如认为本项目公开提供的材料或功能侵犯你的权益，请通过仓库问题反馈入口提供具体位置、权利证明和联系方式。'
          '不要公开提交密码、Cookie、个人数据或整本受保护作品。维护者会核查并对项目控制范围内的问题采取相应处理；外部网站的内容由相应服务方管理。',
    ),
    ('声明的适用范围', '本声明用于说明使用边界与已知风险，不替代实际的产品约束和发布审查，也不排除或限制依法应承担的责任。'),
  ];

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '使用与风险声明',
    code: 'RESPONSIBLE USE',
    child: ListView.separated(
      padding: featurePadding(context),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        final (title, body) = sections[index];
        return ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              AppText(body, style: const TextStyle(fontSize: 14, height: 1.8)),
            ],
          ),
        );
      },
    ),
  );
}
