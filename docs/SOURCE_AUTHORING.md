# 书源编写与注册指南

> 适用版本：帕秋莉图书馆 Android 0.5.6。

本文面向帕秋莉图书馆的书源作者，按当前 Android 引擎说明规则的导入、执行和更新方式。示例使用虚构地址与演示文字，不包含真实站点规则、账号或小说资源。

## 1. 规则如何注册

普通书源通过用户导入注册，无需在客户端增加站点名称、修改代码或重新编译 APK。

```text
JSON 文件／链接／粘贴，或纯 JS 文件
  → 导入预览：检查格式，列出可导入项
  → 用户勾选并确认
  → SourceStore.saveSources：按 bookSourceUrl 新增或更新
  → 保存本机索引，登记 engine 声明
  → 用户启用并选择平台
  → SourcePlatform 将规则与本次操作交给 Android 引擎
  → BookSourceEngine 分派到 JSON 提取规则或 mainJs 函数
  → 书目、目录和正文交给 App 展示
```

`bookSourceUrl` 是规则的稳定身份，不只是一个请求地址。同值再次导入会更新已有源，并保留原启用状态；改名或修改分组不需要更换它。书籍身份还关联该源及 `bookUrl`，发布更新时应保持两者稳定，否则可能形成另一份书籍记录。

启动时 App 会重新读取已保存的规则。`SourceDeclarations.register` 负责登记平台、书号、系列、字体等声明；它不向远端服务器注册书源，也不预先请求该源全部内容。每次执行时，原生引擎接收所选规则和操作参数。

JSON 导入预览不执行其中的 JS。纯 JS 预览需要运行脚本以读取 `config`，但该阶段不允许联网、读取设备文件或访问已有账号会话，因此不要在脚本顶层执行请求或登录操作。

## 2. 选择规则形式

| 形式 | 适用情况 | 执行方式 |
| --- | --- | --- |
| 阅读 3 JSON | HTML 或 JSON 页面，提取流程可用声明表达 | `searchUrl`、`ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent` 等 |
| 纯 JS 单文件 | 自定义 API、多个请求组合或特殊协议 | `config` 配置加命名函数；导入后脚本保存为 `mainJs` |

JSON 也可携带字符串形式的 `mainJs`。只要 `mainJs` 非空，搜索、发现、详情、目录和正文就走脚本入口；不会在某个函数缺失时自动回退到对应的 JSON 提取规则。不要把两套入口当成逐项后备机制。

当前只接受文本小说源，`bookSourceType` 为 `0` 或省略。阅读 3 的主要小说规则语法已适配，但不是完整复制阅读 MD3 的所有宿主接口与新增功能。漫画、音频、视频、文件下载类书源不在当前范围内。

## 3. 阅读 3 JSON 示例

下面是假设站点提供 JSON API 时的结构模板。保存为 UTF-8 `.json` 文件，再按实际响应修改地址和路径。示例域名不可访问，不能用于真实站点联调。

```json
{
  "bookSourceName": "示例 API 书库",
  "bookSourceUrl": "https://books.example.invalid",
  "bookSourceGroup": "自编示例",
  "bookSourceType": 0,
  "enabled": true,
  "enabledExplore": true,
  "searchUrl": "https://books.example.invalid/api/search?q={{key}}&page={{page}}",
  "exploreUrl": "最新::https://books.example.invalid/api/latest?page={{page}}",
  "ruleSearch": {
    "bookList": "$.items[*]",
    "name": "$.name",
    "author": "$.author",
    "bookUrl": "$.bookUrl"
  },
  "ruleExplore": {
    "bookList": "$.items[*]",
    "name": "$.name",
    "author": "$.author",
    "bookUrl": "$.bookUrl"
  },
  "ruleBookInfo": {
    "name": "$.name",
    "author": "$.author",
    "intro": "$.intro",
    "tocUrl": "$.tocUrl"
  },
  "ruleToc": {
    "chapterList": "$.chapters[*]",
    "chapterName": "$.title",
    "chapterUrl": "$.url"
  },
  "ruleContent": {
    "content": "$.text"
  }
}
```

此模板假定搜索／最新列表、详情、目录、正文分别返回以下结构：

```json
{"items":[{"name":"演示小说","author":"示例作者","bookUrl":"https://books.example.invalid/api/books/1001"}]}
```

```json
{"name":"演示小说","author":"示例作者","intro":"演示简介","tocUrl":"https://books.example.invalid/api/books/1001/chapters"}
```

```json
{"chapters":[{"title":"第一章","url":"https://books.example.invalid/api/chapters/2001"}]}
```

```json
{"text":"第一段演示文字。\n\n第二段演示文字。"}
```

`ruleSearch.bookList` 先提取列表，`name` 等字段再针对每个条目求值。搜索结果需要有效书名和书籍地址。详情的 `tocUrl` 指向目录接口，目录各项的 URL 再指向正文接口。不要混用网站展示页、API 地址和目录地址。

HTML 页面可改用已支持的 Default／JSoup、XPath 或正则规则；JS 可使用 `@js:` 等阅读 3 语法。相关语法和宿主支持范围见[使用自己的书源](CUSTOM_SOURCES.md)。

JSON URL 模板中的 `page` 从 1 开始。需要分页时按实际接口设置列表下一页、目录下一页或正文下一页规则；不要假定每个站点都使用页码，也不要持续返回同一页冒充后续数据。

## 4. 可离线试跑的纯 JS 示例

把下面整个代码块保存为 UTF-8 `example-source.js`，不要保留 Markdown 的代码围栏。在「我的 → 书源管理 → 文件导入」选择它，确认导入后搜索“演示”，或查看“演示栏目”。示例只返回内嵌的虚构文字，不发出网络请求，可先确认导入和返回值是否正确。

```javascript
var config = {
  bookSourceName: "离线演示书源",
  bookSourceUrl: "https://books.example.invalid#demo",
  bookSourceGroup: "自编示例",
  bookSourceType: 0,
  homeSections: [
    {id: "demo", title: "演示栏目", url: "demo"}
  ],
  engine: {
    version: 1,
    platform: {id: "author-demo", name: "演示书库", mark: "EX"},
    identity: {displayIdPattern: "[/]book[/]([^/?#]+)"}
  }
};

function demoBook() {
  return {
    name: "演示小说",
    author: "示例作者",
    bookUrl: "https://books.example.invalid/book/1001",
    tocUrl: "https://books.example.invalid/book/1001/chapters",
    intro: "仅用于验证规则结构的演示文字。"
  };
}

function search(key, page) {
  var item = demoBook();
  var matches = !key || item.name.indexOf(key) >= 0;
  return {items: page === 1 && matches ? [item] : [], hasMore: false};
}

function explore(url, page) {
  if (url !== "demo") throw new Error("未知演示栏目");
  return {items: page === 1 ? [demoBook()] : [], hasMore: false};
}

function getBookInfo(book) {
  return demoBook();
}

function getChapters(book) {
  return [
    {title: "第一章", url: "https://books.example.invalid/chapter/2001"},
    {title: "第二章", url: "https://books.example.invalid/chapter/2002"}
  ];
}

function getContent(chapter, book, nextChapterUrl) {
  return chapter.title + "\n\n这是演示正文第一段。\n\n这是演示正文第二段。";
}
```

纯 JS 导入要求存在 `config`，以及 `search`、`getChapters`、`getContent` 三个函数。声明 `exploreUrl` 或普通首页栏目时还必须实现 `explore`。建议新源使用 `config`，不要使用旧式同名 `source` 配置，以免与执行期宿主对象混淆。

函数同步返回普通值，不返回 Promise。脚本运行于原生 JS 宿主，不是浏览器页面，也不是 Node.js；不能直接使用 `window`、DOM、浏览器 `fetch` 或 Node.js `require`。网络和持久数据通过引擎提供的接口处理。

## 5. 脚本入口与返回格式

| 入口 | 何时调用 | 返回值 |
| --- | --- | --- |
| `search(key, page)` | 搜索 | 书目数组，或 `{items, hasMore, pageUrl?, nextUrl?}` |
| `explore(url, page)` | 分类或首页栏目 | 与搜索相同；`url` 为本次栏目或分页地址 |
| `getBookInfo(book)` | 详情 | 书目对象；可省略函数，使用已有资料 |
| `getChapters(book)` | 目录 | 章节数组，允许卷标题项 |
| `getContent(chapter, book, nextChapterUrl)` | 正文 | 正文字符串；配套字体形式见下文 |
| `getEpub(book)` | `engine.content.epubPattern` 命中 | EPUB 下载地址字符串，可携带已支持的请求选项 |
| `getShelf(page, nextPageUrl)` | 声明了 `cloudShelf: true` 的 JS 云收藏 | `{items, hasMore, nextUrl?}` |

书目至少有 `name`、`bookUrl`；常用可选字段为 `author`、`coverUrl`、`intro`、`kind`、`tocUrl`、`latestChapterTitle`。不要把页面标题字段 `title` 当成书名 `name`。

章节至少有 `title`、`url`。卷标题可设置 `isVolume: true`；真实正文仍需单独返回章节，不要用卷标题替代首章。建议输出稳定的绝对 URL，避免域名、基址或临时签名变化引发身份变化。

分页对象必须提供数组 `items` 与布尔值 `hasMore`；不能返回 `"false"` 字符串。数组返回形式按“非空则可能有下一页”处理，能判断结束的接口宜使用分页对象。`pageUrl`／`nextUrl` 用于游标分页，不是书籍地址。

`getContent` 普通正文返回字符串即可，使用换行分段；支持的正文 HTML 会由引擎转换，并处理图片。需要配套字体时返回 `{content: "正文", fontUrl: "字体地址"}`，同时声明 `engine.content.font: "embedded"`。不要用 `{text: "正文"}` 替代它；当前对象形式用于附带字体，需提供有效的 `fontUrl`。

不同操作会重新执行主脚本，不能依赖顶层临时变量保存跨请求状态。跨请求数据应使用已支持的书源／书籍／章节变量或宿主缓存；不要把密码、Cookie 或令牌写进 `config`、书籍信息或分享文件。

## 6. 声明平台与特殊能力

`engine`、`homeSections`、`ruleAccount` 是可选扩展。普通规则不需要把它们全部填写；只声明实际实现的能力。`engine` 存在时必须提供 `version: 1`。

| 需求 | 声明位置 | 规则作者负责什么 |
| --- | --- | --- |
| 平台名、图标字样、编号前缀 | `engine.platform` | 提供稳定的 `id`，以及 `name`、`mark` |
| 显示源站书号 | `engine.identity.displayIdPattern` | 第一个捕获组提取原书号，不改变内部收藏 ID |
| 首页多栏目 | 顶层 `homeSections` | 每栏提供唯一 `id`、`title`、`url`，实现相应发现入口 |
| 系列卡片与卷册入口 | `engine.content.seriesPattern`、`seriesUrlPattern` | 声明系列／单卷地址关系，返回对应书目与目录 |
| 下载并解析在线 EPUB 卷 | `engine.content.epubPattern` | 实现 `getEpub(book)`；下载、解析、持久缓存和更新由 App 处理 |
| 字体混淆 | `engine.content.font` | 返回正文及其配套字体；或使用已支持的字形查询／替换 API |
| HTML 简介 | `engine.content.intro: "html"` | 返回正确的简介 HTML，避免提前破坏段落结构 |
| 同站译文共享账号 | `engine.session` | 明确列出同源成员及共享会话 ID；不用于跨站共享 |
| 浏览器打开书籍页 | `engine.links.bookPage` | 将内部逻辑地址映射为源站 HTTP(S) 页面 |
| 固定错误提示 | `engine.errors` | 抛出 `SOURCE_ERROR=错误码`，映射到明确、无敏感信息的提示 |

平台 ID 只负责分组展示，不能代替 `engine.session` 共享登录态。只有展示书号的需求时使用 `displayIdPattern`；`bookIdPattern` 会参与内部数字 ID 分配，存在跨源冲突约束，不应随意设置。

站点的正文重排算法、API 参数和协议调用写在规则里；已有的字体、压缩、SignalR、图片解码、EPUB 等通用能力由宿主提供。真正缺少的能力需要先扩展引擎并发布新版 App，再由规则调用或声明。仅在 JSON 中增加一个字段不会自动新增实现。

完整字段和结构见[通用书源引擎声明](SOURCE_ENGINE.md)。这些扩展也不意味着同一规则能直接在其他阅读客户端中获得相同功能。

## 7. 网络、登录与账号功能

请求使用 `java.ajax`、`java.connect`、`java.get`、`java.post` 等已支持接口；请求头、Cookie、重定向、字符集、超时与请求选项按宿主约定传入。所有请求仍受源级限流约束，不要自行增加无间隔的重试循环。

注意响应类型：`java.ajax(...)` 返回正文字符串；`java.connect(...)` 的响应提供 `body()`、`code()` 等方法；`java.get/post/head` 是 JSoup 风格响应，应使用 `body()`、`statusCode()`。后者遇到 HTTP 错误会抛出，不能对 `java.post` 的结果调用 `code()`。

表单使用 `loginUi` 和 `loginUrl`；纯 JS 可实现 `loginUi(state)`、`loginAction(action, state, form)` 的 V2 协议。网页登录地址通过 HTTP(S) `loginUrl` 或 `engine.login.webUrl` 声明。网页验证只能由用户在账号页主动打开，普通发现、搜索、正文请求不要依赖自动弹窗完成验证。

账号状态验证、云收藏及签到分别声明，不能用“本机有 Cookie”或“登录函数没有抛错”判断服务器接受了登录。`loginCheckJs` 是请求响应处理，不是账号资料查询接口。

例如，以下配置表示由主脚本实现两个账号操作；它是配置片段，不是可单独导入的完整书源：

```json
{
  "ruleAccount": {
    "verify": {"js": "getAccount"},
    "checkIn": {"js": "checkIn"}
  }
}
```

`getAccount()` 必须返回 `{loggedIn: true}` 或 `{loggedIn: false}`，可另带 `id`、`displayName`、`avatarUrl`、`checkedInToday`。认证过期与网络异常应区分；没有拿到服务端结果时不要伪造登录成功。

`checkIn()` 成功返回 `{success: true, already: false}`，源站确认已签到可返回 `{already: true}`。云收藏、联合签到、V1／V2 表单及登录存储接口详见[账号扩展说明](CUSTOM_SOURCES.md#可选账号扩展验证云书架与签到)。

## 8. 开发与验证顺序

1. 先确定稳定的源身份、书籍地址、目录地址、章节地址，并观察真实响应结构。
2. 先打通一部作品的“搜索 → 详情 → 目录 → 正文”，再加发现、分页、图片与账号。
3. 导入或更新规则，在书源编辑页使用「检查书源」，输入确定存在的书名。该工具按顺序检查搜索、首条结果的详情、目录及首个可读章节；不自动加入书架。
4. 单独检查发现首页和各栏目。搜索通过不代表发现通过；只实现搜索的源可以没有首页书单。
5. 检查第一页、下一页和最后一页，确认没有无限重复；检查卷标题、首章、末章及插图章。
6. 按需要测试登录、重启 App 后验证、账号过期、云收藏分页与签到。无账号功能的源不必声明这些入口。
7. EPUB、配套字体、系列等扩展需要在实际阅读器验证；内置检查不是全部能力验收。
8. 导出规则，检查没有手工写入的账号或令牌，再分发 UTF-8 JSON 或 JS。聚合 JSON 顶层用数组，同一个 `bookSourceUrl` 表示更新同一源。

规则通过导入文件或链接交付；修改本地 JS 文件后需要再次导入，不会因文件已保存而自动热更新。链接导入是读取当时的内容，也不等于自动订阅。JSON 中的 `lastUpdateTime` 可作规则更新时间，不代替稳定身份或重新导入。

## 9. 常见问题

| 现象 | 优先检查 |
| --- | --- |
| 能导入，首页显示暂无书籍 | 是否实现发现／首页栏目，栏目 URL 是否传对，列表字段是否存在，当前请求是否要求登录 |
| 搜索有数据，App 里没有结果 | 是否使用 `name`、`bookUrl`，是否返回支持的文本小说类型，以及搜索词是否与书名／作者匹配 |
| 目录条目被丢弃 | 是否有非空 `title`、`url`，卷标题是否误当正文，URL 是否可解析 |
| 提示 JS 规则执行失败 | 入口函数名称与返回类型、宿主方法是否存在、响应对象方法是否用对；结合执行阶段和安全错误码定位 |
| 正文显示 HTML／标记或排版异常 | 返回的是正文字符串还是 JSON 字符串，HTML 是否重复转义，是否手工拼接了内部图片标记 |
| 每次更新后出现重复书籍／进度丢失 | `bookSourceUrl`、`bookUrl`、章节 URL 是否被修改，是否把临时下载地址当成稳定书籍地址 |
| 其他客户端正常，本 App 不正常 | 依赖的语法、宿主 API、扩展字段与执行限制是否在当前兼容范围；同时排查站点响应与登录差异 |

## 10. 实现与参考

- [使用自己的书源](CUSTOM_SOURCES.md)：规则语法、宿主接口、账号与限制。
- [通用书源引擎声明](SOURCE_ENGINE.md)：平台、系列、字体、EPUB、会话与书号声明。
- [解析器来源与版本](SOURCE_ENGINE.md#解析器来源与版本)：复用的阅读解析代码、修改范围和许可证。
