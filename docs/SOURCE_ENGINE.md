# 通用书源引擎声明 v1

> 适用版本：帕秋莉图书馆 Android 0.5.6。

新建书源请先阅读[书源编写与注册指南](SOURCE_AUTHORING.md)，其中包含注册流程、JSON／纯 JS 示例、函数返回格式和调试步骤。

规则使用现有阅读 3 JSON 字段及可选的 `mainJs`。`bookSourceUrl` 是稳定的规则标识；`engine.origin` 可为逻辑标识另行提供 HTTP 基址。App 不根据站点域名选择适配。

```json
{
  "bookSourceName": "示例书库",
  "bookSourceUrl": "https://books.example#translation-a",
  "engine": {
    "version": 1,
    "origin": "https://books.example/",
    "platform": {"id": "example", "name": "示例平台", "mark": "EX"},
    "session": {"id": "example-session", "members": ["https://books.example#translation-a", "https://books.example#translation-b"]},
    "content": {"seriesPattern": "^https://books\\.example/series/[^?]+$", "epubPattern": "[?]volume=", "baseUrl": "https://books.example/", "font": "embedded", "intro": "html"},
    "identity": {"chapterIdPattern": "[/]([0-9]+)$"},
    "search": {"group": "example", "quotedLabels": true},
    "requestTimeoutMs": 120000,
    "login": {"webUrl": "https://books.example/login"},
    "errors": {"ACCESS": "请在账号页登录后重试"}
  }
}
```

| 声明 | 引擎行为 |
|---|---|
| `version` | 当前只接受 1；不支持的版本在导入时明确拒绝 |
| `platform` | 平台分组、显示名称与书籍编号前缀 |
| `session` | 同站点变体共享本机加密会话；成员必须同源，组不可跨站点复用 |
| `content.seriesPattern` | 该书显示卷册列表，选择卷册后打开对应条目 |
| `content.seriesUrlPattern` | 匹配卷册地址，第一个捕获组为所属系列地址；收藏显示系列卡片，各卷阅读记录独立保留 |
| `content.epubPattern` | 调用规则 `getEpub(book)`，下载到磁盘后按需解析；提供下载和解析进度 |
| `content.baseUrl` | 正文 HTML 的资源解析基址，适用于保留历史逻辑地址的书籍 |
| `content.font` | `embedded` 时读取正文返回的 `fontUrl`，加载并缓存配套字体 |
| `content.intro` | `html` 时按段落、换行显示简介，包含历史已转义 HTML |
| `identity.bookIdPattern` | 第一个捕获组为原数字书籍 ID，范围 1～0x1fffffff；保留旧收藏与进度，跨源冲突明确拒绝 |
| `identity.displayIdPattern` | 从书籍地址的第一个捕获组提取并 URL 解码展示书号，保留原字符且不补零；仅影响界面编号，不改变本机 ID、收藏或进度。未声明或缺少匹配地址时沿用本机编号，本地书仍使用 LOCAL 编号 |
| `identity.chapterIdPattern` | 以第一个捕获组作为数字章节 ID；规则需保证该书内唯一 |
| `links.bookPage` | 可选的浏览器详情地址映射：`pattern` 为正则，`replacement` 中的 `$1`、`$2` 对应捕获组。未声明时使用书籍现有 HTTP(S) 地址；逻辑地址需由规则转换为 HTTP(S)，本机书籍不显示外链按钮。映射只影响打开网页，不修改书籍 ID、收藏或阅读进度 |
| `search.group` | 全平台搜索中去重共享搜索结果的规则变体 |
| `search.quotedLabels` | 标签或作者跳转使用引号搜索语义 |
| `login.webUrl` | 为表单登录另行提供手动网页登录入口；未声明则不显示 |
| `login.thirdPartyCookies` | 显式允许手动登录页使用第三方 Cookie；默认关闭，供需要跨域验证的站点声明 |
| `requestTimeoutMs` | 网络规则运行超时；EPUB 下载使用独立下载预算 |
| `errors` | JS 抛出 `SOURCE_ERROR=ACCESS` 后显示声明的固定提示，诊断只记录固定错误码 |

`engine.filters` 声明筛选菜单：`trigger` 是发现条目的地址，`path` 是筛选结果地址，`title` 是菜单标题，`queryKey` 是搜索参数名，`choices` 是由 `key`、`label`、`options` 组成的列表。参数通过 URI 编码传回规则。

JS 常用入口为 `search(key, page)`、`explore(url, page)`、`getBookInfo(book)`、`getChapters(book)`、`getContent(chapter, book, nextChapterUrl)`；账号通过现有 `loginUi`、`loginUrl`、`ruleAccount` 声明。分页可返回 `{items, hasMore, nextUrl}`，目录返回章节或卷册列表。

账号规则返回的 avatarUrl 可为普通 HTTP(S) 地址或带请求选项的图片定位符（地址后接 ,{...}）。带选项的头像独立通过书源图片通道加载，支持规则请求头、来源标头和引擎缓存；普通 URL 保持现有显示方式。头像加载失败只显示平台标记，不改变账号验证状态。

原生能力不识别具体站点：所有 HTTP 仍受书源限流约束，前台文字请求优先于插图和后台验证。网页登录只能由用户在账号页主动触发。

## 解析器来源与版本

规则解析以 [Legado 3.26082823 对应提交](https://github.com/LegadoTeam/legado/commit/3046111c1718e7b67c2ad468e54edf295ec05820)为兼容基线，复用并移植其中的选择器、组合规则、部分 JS 宿主协议及结果转换代码。

移植时替换了应用实体、存储、日志和调用接口，增加执行预算、取消及资源访问限制；网络、会话和 Flutter 展示由帕秋莉图书馆提供。具体兼容范围见[接口与兼容范围说明](CUSTOM_SOURCES.md)，不代表完整同步阅读 MD3 的所有后续能力。

复用代码保留上游作者、版权及 GPL-3.0 声明；上游许可证见 [Legado LICENSE](https://github.com/LegadoTeam/legado/blob/3046111c1718e7b67c2ad468e54edf295ec05820/LICENSE)。
