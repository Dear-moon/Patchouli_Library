# 通用书源引擎声明 v1

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
| `identity.chapterIdPattern` | 以第一个捕获组作为数字章节 ID；规则需保证该书内唯一 |
| `search.group` | 全平台搜索中去重共享搜索结果的规则变体 |
| `search.quotedLabels` | 标签或作者跳转使用引号搜索语义 |
| `login.webUrl` | 为表单登录另行提供手动网页登录入口；未声明则不显示 |
| `login.thirdPartyCookies` | 显式允许手动登录页使用第三方 Cookie；默认关闭，供需要跨域验证的站点声明 |
| `requestTimeoutMs` | 网络规则运行超时；EPUB 下载使用独立下载预算 |
| `errors` | JS 抛出 `SOURCE_ERROR=ACCESS` 后显示声明的固定提示，诊断只记录固定错误码 |

`engine.filters` 声明筛选菜单：`trigger` 是发现条目的地址，`path` 是筛选结果地址，`title` 是菜单标题，`queryKey` 是搜索参数名，`choices` 是由 `key`、`label`、`options` 组成的列表。参数通过 URI 编码传回规则。

JS 常用入口为 `search(key, page)`、`explore(url, page)`、`getBookInfo(book)`、`getChapters(book)`、`getContent(chapter, book, nextChapterUrl)`；账号通过现有 `loginUi`、`loginUrl`、`ruleAccount` 声明。分页可返回 `{items, hasMore, nextUrl}`，目录返回章节或卷册列表。

原生能力不识别具体站点：所有 HTTP 仍受书源限流约束，前台文字请求优先于插图和后台验证。网页登录只能由用户在账号页主动触发。

运行私有规则回归时，可在本机配置 `PATCHOULI_RULE_TESTS` 指向外部 Kotlin 测试目录；这些文件只加入测试源集，不进入发布 APK。公开 CI 不设置该变量。
