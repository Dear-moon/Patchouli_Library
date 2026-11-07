# 书源接口与兼容范围

> 适用版本：帕秋莉图书馆 Android 0.5.6。

本文与[编写与注册指南](SOURCE_AUTHORING.md)、[引擎声明参考](SOURCE_ENGINE.md)配套。仅说明通用文本小说规则，不包含站点规则、真实登录参数或资源地址。

## 导入、登录与数据

在「我的 → 书源管理」通过文件、链接或粘贴导入 UTF-8 规则，预览确认后启用。再次导入同一 `bookSourceUrl` 更新该规则；书源导入与启用不会自动代表登录成功。

账号入口位于「我的 → 账号与登录」。表单与网页登录按规则声明提供；网页登录后使用「保存并返回」保存会话，再由验证规则判断服务器是否接受。Cookie 或令牌存在，只能说明本机保存了会话。

登录信息保存在本机加密会话中，导出规则不包含设备会话。作者仍需自行检查写进脚本或静态请求头的敏感值。不同源默认隔离；同源变体只有显式声明 `engine.session` 才共享会话。

`enabledCookieJar` 控制普通请求是否自动保存服务器的 `Set-Cookie`；关闭它仍会发送网页登录或脚本明确保存的会话。

登录 UI V2 使用 `loginUi(state)`、`loginAction(action, state, form)`，支持字段、错误、倒计时、状态更新、保存登录信息及关闭命令。V1 的 `java.upLoginData`、`java.reLoginView` 可更新或重建表单；更新表单不等于登录成功。

### 可选账号扩展：验证、云书架与签到

阅读的 `loginCheckJs` 是请求响应处理脚本，不是统一的账号状态、云书架或签到接口。已有源的登录表单自定义按钮继续原样执行，不按按钮名称猜测站点接口。

本应用另提供可选的 **`ruleAccount` 扩展**，可在书源编辑器「账号扩展」或完整 JSON 中填写。它不改变原阅读字段和语法；未声明的能力不显示按钮。以下仅为自编接口的结构示例，不包含可用内容源：

```json
{
  "ruleAccount": {
    "verify": {
      "url": "/api/account",
      "loggedIn": "$.authenticated"
    },
    "shelf": {
      "url": "/api/shelf?page={{page}}",
      "bookList": "$.items[*]",
      "name": "$.name",
      "bookUrl": "$.url",
      "author": "$.author",
      "coverUrl": "$.cover",
      "nextPageUrl": "$.next"
    },
    "checkIn": {
      "url": "/api/check-in,{\"method\":\"POST\"}",
      "success": "$.success",
      "already": "$.already"
    }
  }
}
```

- URL、GET／POST、请求头、Cookie、CSS／XPath／JSONPath／JS 均沿用现有书源宿主。认证信息使用本机登录会话，不写进示例或分享文件。
- `verify.loggedIn` 必须明确返回 `true／false` 或 `1／0`；HTML 规则可用 JS 转换成布尔值。HTTP 401 记为未登录，403、网络错误或无法识别的结果记为验证未完成。不会把 `loginCheckJs` 没有抛错当成验证通过。
- `shelf` 复用书目字段，可补充 `kind／intro／lastChapter`。支持 `nextPageUrl` 或 `{{page}}`，最多 64 页／5000 本。云收藏视图只读展示，不自动加入本机收藏，不覆盖阅读进度与书签，不向站点上传或删除记录。
- `checkIn.success` 与可选 `already` 同样返回明确布尔值。签到由用户点击触发，不后台执行、不自动重试；成功后当天显示「今日已签到」。清除或更换登录信息后可重新执行，站点仍负责判断该账号是否已经签到。
- 打开卡片只读取本机状态，不执行扩展请求。已停用的源不会自动验证，也不能从卡片触发同步或签到。

请求头含不合法字符时会提示检查书源请求头或重新登录，不修改、丢弃或显示其中的认证内容。

## 规则兼容范围

当前只适配阅读 3 的 **JSON 与纯 JS 文本小说书源**，漫画、音频、视频及文件型书源暂缓。规则与请求解析直接适配上游 `3.26082823` 的实现，兼容基线为该固定版本，不等同于完整同步阅读 MD3 分支的所有后续能力。解析器复用与脚本宿主兼容是两件事：导入成功不代表站点、登录和全部脚本都已可用。

| 规则 | 当前实现 |
| --- | --- |
| 核心字段 | `ruleSearch`、`ruleExplore`、`ruleBookInfo`、`ruleToc`、`ruleContent` |
| HTML | 上游 Default／JSoup 语法、索引／范围／排除、文本／属性／HTML 提取 |
| JSON | JsonPath，支持列表、路径、过滤条件 |
| XPath | 元素、属性与文本提取 |
| 组合规则 | `||` 后备、`&&` 合并、`%%` 交错、`##` 替换、捕获组与模板表达式 |
| JavaScript | Rhino 安全解释环境；`@js:`、混合 `<js>…</js>`、内联／远程 `jsLib`，请求、持久变量、编码与加密辅助 API |
| 纯 JS 源 | `config`（兼容旧 `source`）配置，`search`、`explore`、`getBookInfo`、`getChapters`、`getContent`；结果转换复用上游 `JsSourceMarshaller`，保留分卷、变量、可选详情和 JSON 返回语义 |
| JSON 返回值 | 复用上游基础 Gson 转换器，支持字符串字段接收对象／数组的 JSON 表示，避免合法变量对象导致整条书目被丢弃 |
| 脚本基础库 | CryptoJS 与安全随机数；有界编译缓存，共享库定义与按源隔离的 `globalThis／global` 状态，不混用调用绑定 |
| JS 运行时 | 同版 `htmlunit-core-js 5.3.0-legado.4`，移植上游 E4X 与旧式 let／const 兼容，保留动态 this／eval 作用域语义 |
| 登录 UI V2 | 上游 `LoginUiV2` / `RowUi` 协议；状态、字段错误、倒计时、保存与关闭命令 |
| 小说详情 | 上游 `BookInfo` 的名称保护、初始化、字段执行顺序与可选字段容错；安全错误提示不含脚本或账号 |
| 请求 | 上游 URL／分页模板、GET／POST／HEAD、表单／JSON、指定字符集、动态请求头、重定向、按源 Cookie 与并发间隔；区分字符串响应与 JSoup 响应，有序批量请求与单次超时 |
| 网页 | 独立进程 WebView、DOM 脚本、资源／跳转嗅探、交互验证与验证码；不复用网盘登录浏览器 |
| 脚本资源 | 按源隔离的资源下载、文件、ZIP／RAR4／RAR5／7z 提取和通用解压，ICU 自动编码检测 |
| 字体规则 | 适配上游 `QueryTTF`，支持 URL／Base64／字节数组输入、字形查询、字体缓存及 `replaceFont` 反混淆 |
| 图片 | 封面／正文图片请求头、`coverDecodeJs` 与 `imageDecode`，保留图片 URL 的请求选项与内联 Base64 图片，独立磁盘缓存 |
| 目录／正文 | 分卷、目录分页、`formatJs` 连续格式化、章节附加属性、章内分页合并后的全文替换、按 URL 去重、原位图片标记 |
| 发现 | JSON 分类数组、`标题::地址` 列表、返回上述结构的 JS；保留分组与布局元数据，分类面板按屏幕自适应列数 |

`@put`／`@get`、书籍／章节变量、登录状态与缓存按书源隔离并保存。网络会话使用 Android Keystore 加密存储，不随规则导出。

### 脚本宿主已对齐的常用接口

- `java.ajax` 返回正文字符串，`java.connect` 返回字符串响应；传输失败保持可检查的错误文本，取消与安全限制仍会中止。错误文本保留类型，不包含请求地址、账号或完整堆栈。`url()` 返回字符串，`raw()`、`headers()`、`code()`、`message()`、`callTime()` 与错误正文可供规则读取。
- `java.get／post／head` 返回 JSoup 风格响应，`url()` 返回 URL；请求头可用 Map 或 JSON 字符串，默认不跟随重定向，HTTP 错误会抛出。`ajaxAll／ajaxTestAll` 并发请求并按输入顺序返回数组；批次失败会取消未完成的同批请求，脚本仍可自行处理失败。
- `importScript` 返回文本，使用 `eval(java.importScript(urlOrPath))` 才执行；支持远程地址或本书源临时资源中的相对路径。`cacheFile(url, 秒数)` 缓存远程文本；`cache` 支持有效期、数值读取、字节数组、文本文件型缓存与进程内缓存。`cache.putFile` 的值仍与资源目录分开；内存缓存不写入持久会话，全局有 50 MiB 预算。
- `source／sourceApi` 继承通用网络和编码辅助接口，提供请求头、登录信息、变量、独立 `evalJS` 与共享库刷新方法。动态请求头在书源上下文中执行，不误用当前章节的同名变量。尚未保存登录信息时，可从 V1 表单提取默认值；动态表单的回读有重入保护。
- `book／chapter` 支持变量读取、写入、删除与 `variableMap`，常用字段访问、书籍自定义变量／分类列表，以及章节绝对地址、标识和文件名方法。章节的原始目录索引、附加信息、VIP／购买标记留在原生书源状态中，不因 Flutter 的可读章节列表过滤卷标题而丢失。
- `toURL` 使用上游 URL 对象；Base64 支持字符集、换行、去填充及 URL-safe 标志；HTML 格式化与时间格式沿用上游实现。辅助请求内的 URL／正文脚本不会覆盖调用方的 `result`、`src` 或地址绑定。
- `downloadFile` 是规则内部资源 API，将网络字节或旧式十六进制参数保存到本书源的缓存目录，并返回相对路径。`getFile` 返回受控的 File 风格对象，配合 `readFile`、`readTxtFile`、`deleteFile` 使用；不开放任意设备文件、文件流或跨源路径。它不增加小说下载／导出入口。
- `getZipByteArrayContent／getZipStringContent` 读取远程 ZIP 或十六进制 ZIP 中的指定项；未找到时返回 `null`／空字符串。`unzipFile／unArchiveFile` 将 ZIP 展开到本书源临时目录，`getTxtInFolder` 合并目录内文本后清理该目录。拒绝越界路径和已有符号链接，解压时不创建链接；超量文件与超限展开会中止并清理临时结果。
- `queryTTF／queryBase64TTF` 使用同版上游的 TrueType 字形解析；`replaceFont` 按 Unicode 码点匹配字形，保留补充平面字符，支持过滤缺失字形。缓存按源隔离，全局最多四份、估算 32 MiB；不保留已结束请求的取消回调。上游这一版的 cmap 解析覆盖 0／4／6，不代表支持所有字体容器与 cmap 格式。
- `webViewGetSource／webViewGetOverrideUrl` 按完整地址匹配规则，返回捕获地址，不擅自再请求该资源，也不以中途 HTML 或脚本返回值提前结束嗅探。支持 `cacheFirst` 和延迟参数；`getWebViewUA` 在 Android 使用系统 WebView 的默认 UA。

### 网页验证、变量与其他宿主接口

- `startBrowserAwait／startBrowser／showBrowser` 等网页能力受调用场景限制。网页登录与访问验证由用户在账号页主动打开；普通发现、搜索、正文和后台验证请求不会自动拉起验证页。规则不能依赖后台弹窗完成访问验证。
- `getVerificationCode` 使用现有玻璃抽屉输入图片验证码；取消请求会关闭对应验证，不关闭其他页面。同源、同站点并发验证可合并，失败与取消会正确传递；验证等待不消耗原规则的工作预算。
- `showBrowser` 接入预加载脚本、底部网页窗口的尺寸、拖动、遮罩和 WebView 配置；网页可用 `java.upConfig／dismiss` 更新或关闭当前窗口。网页桥不开放任意 Android／JVM 对象。
- 书籍与章节变量按 10,000 字符分流：小值在变量表，大值单独加密落盘，支持读取、替换、删除及旧记录迁移。`getBigVariable／putBigVariable` 可显式操作大变量。章节 `update` 保存元数据，标题显示支持传入的文字／正则替换。
- `source` 的字段与 getter／setter 使用同一份运行时定义；`getSearchRule／getTocRule／getContentRule` 等规则对象也可读写。目录执行 `preUpdateJs`，其中 `refreshTocUrl／reGetBook` 可刷新详情和精确重新定位作品，保持已有本机身份与缓存。
- `lock／singleFlight／tick` 按书源和名称隔离，支持重入、合并成功请求、失败后重试、超时与取消。`t2s／s2t／toNumChapter` 使用对照版本的转换规则。
- RAR／7z 的 ByteArrayContent／StringContent、`unrarFile／un7zFile` 使用与对照版本相同的 libarchive，未找到指定项时保持 `null`／空字符串语义。通用解压拒绝链接、特殊文件、加密压缩包和越界路径，取消或超限会清理临时结果。
- File 风格对象支持查询、目录、创建、删除、重命名、时间和权限操作，只限本书源目录。UTF-8、UTF-16、GB18030、Big5、Shift-JIS 等编码采用同版 ICU 检测器；短文本有歧义时，规则可明确指定编码。
- `toast／longToast` 走应用提示；阅读与主题配置接口返回当前应用的配置，`androidId` 返回安装级匿名标识。`openUrl` 先请用户确认，阅读协议的书源链接进入现有导入预览，不自动保存。

兼容目标是固定版本的小说规则与上述宿主接口，不复制阅读的全部原生应用页面、支付、视频或漫画能力。文件、网络与外部应用遵循本应用的权限边界，不返回原始 File、文件流或可自行联网的 URL／JSoup 连接。纯 JS 返回的非小说条目不交给文字阅读器。通用回归使用自编文档和本地 HTTP 服务，并把原版与适配后的 HTML／CSS、JSONPath、XPath、正则解析器分别编译，运行相同规则对照；空列表、站点失效、登录要求与解析错误分别判断。

搜索、目录与正文在 Android 后台工作线程执行；跨源搜索最多同时处理三个源，可取消。OkHttp 复用连接，图片任务与正文任务分开排队。HTTP 单次响应上限 8 MiB，脚本 1 MiB，正文 4 MiB，目录最多 64 个分页、正文最多 32 个分页，并有执行时间和指令预算。规则文件每项 8 MiB、单次 ZIP 展开合计 32 MiB／4096 项、单源文件缓存 64 MiB；这些限制与用户的本地电子书导入上限无关。脚本不开放任意 JVM 类、Android 对象或任意设备路径。

## 云端收藏

JS 源可声明顶层 `cloudShelf: true` 并实现 `getShelf(page, nextPageUrl)`，返回 `{items, hasMore, nextUrl?}`；已有 `ruleAccount.shelf` 的声明式源也可提供只读云收藏。书目字段与普通列表一致。

浏览云收藏不自动加入本机书架，也不在源站增删收藏。账号操作、搜索、发现和阅读各自需要实现及验证，不能由其中一步成功推断其他能力可用。

### 账号脚本扩展

已有 URL 形式的 `ruleAccount` 保持不变。支持协议不适合普通 HTTP 规则的平台，可显式声明 `verify: {"js": "getAccount"}` 与 `checkIn: {"js": "checkIn"}`，由多源引擎调用同名 `mainJs` 函数；`js` 只能是函数名。

验证函数返回 `{loggedIn: boolean, id?: string, displayName?: string, avatarUrl?: string, checkedInToday?: boolean}`。宿主仅保存这些安全资料字段，Cookie、令牌和表单不进入资料响应。已确认的认证过期可抛出带 `SOURCE_AUTH_EXPIRED` 标识的错误；网络或服务异常应正常抛出，宿主保留会话并显示验证异常。不能仅凭本地存在令牌就返回已登录。

签到函数返回 `{success: true, already: false}` 或 `{already: true}`。宿主只在明确成功或源站确认已签到后记录今日结果，避免重开页面重复提交。切换账号会清除旧账号的签到记录，令牌续期不会清除。

### 多步骤签到

`ruleAccount.checkIn` 继续作为原签到操作。需要追加步骤时，声明非空 `checkInRevision`、可选的 `checkInLabel`，以及 `checkInExtras` 列表；列表各项须提供唯一的 `id`、`label` 和已有格式的 HTTP 规则或 `js` 函数名，例如：

```json
{
  "ruleAccount": {
    "checkIn": {"js": "checkIn"},
    "checkInRevision": "combined-v1",
    "checkInLabel": "账户签到",
    "checkInExtras": [{"id": "coins", "label": "七日轻币", "js": "checkInCoins"}]
  }
}
```

函数可额外返回 `message`，内容会显示在账号页，不应包含会话或原始响应。各步骤独立记录当天结果，只有全部完成才标记整体完成；普通失败保留已成功步骤，认证过期或取消会中止。明确切换账号后清除旧账号的结果，自动续期保留结果。此扩展不自动推断奖励任务，也不替换已有签到规则。

## 书源首页栏目

书源可通过 `homeSections` 声明首页栏目；栏目数量随书源配置变化。每个栏目需要唯一的 `id` 和 `title`。普通书单使用 `url` 对应其 `explore(url, page)`，云端收藏使用 `operation: "cloudShelf"`。例如：

```json
{
  "cloudShelf": true,
  "homeSections": [
    {"id": "shelf", "title": "我的收藏", "operation": "cloudShelf"},
    {"id": "popular", "title": "热门书籍", "url": "popular"},
    {"id": "updated", "title": "最近更新", "url": "latest"}
  ]
}
```

首页每栏最多预览 10 本，标题旁的方点／箭头入口及列表底部入口可进入独立完整列表。首次进入仅加载预览需要的页面，后续分页由完整列表触发；栏目之间的请求和游标相互隔离。分类面板的「首页」可返回栏目视图。未声明栏目的自定义源继续使用原有发现列表。

脚本 `search` 与 `explore` 可继续返回书籍数组，也可返回分页对象：

```javascript
return {items: books, hasMore: true, pageUrl: currentUrl, nextUrl: nextPageUrl};
```

分页对象的 `items` 和布尔值 `hasMore` 必须提供，`pageUrl`、`nextUrl` 可省略。游标地址必须能区分后续页面；需要服务端推荐序列的书源，应在后续请求中保留该序列。普通数组仍按非空结果判断下一页。源站权限和现有限流继续生效。
