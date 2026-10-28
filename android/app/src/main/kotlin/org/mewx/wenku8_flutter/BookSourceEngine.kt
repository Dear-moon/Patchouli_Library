package org.mewx.wenku8_flutter

import org.mewx.wenku8_flutter.legado.AnalyzeRule
import org.mewx.wenku8_flutter.legado.RuleHost
import org.mewx.wenku8_flutter.legado.js.JsSourceMarshaller
import org.mewx.wenku8_flutter.legado.js.Book as ScriptBook
import org.mewx.wenku8_flutter.legado.js.BookSource as ScriptSource
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.jayway.jsonpath.JsonPath
import com.jayway.jsonpath.Configuration
import com.jayway.jsonpath.Option
import org.jsoup.Jsoup
import org.jsoup.helper.W3CDom
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import org.jsoup.select.NodeTraversor
import org.jsoup.select.NodeVisitor
import org.htmlunit.corejs.javascript.BaseFunction
import org.htmlunit.corejs.javascript.Context
import org.htmlunit.corejs.javascript.ContextFactory
import org.htmlunit.corejs.javascript.Scriptable
import org.htmlunit.corejs.javascript.ScriptableObject
import org.htmlunit.corejs.javascript.Undefined
import org.htmlunit.corejs.javascript.TopLevel
import org.htmlunit.corejs.javascript.VarScope
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Base64
import java.util.Date
import java.util.Locale
import java.util.SimpleTimeZone
import java.util.UUID
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import javax.xml.xpath.XPathConstants
import javax.xml.xpath.XPathFactory
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult
import java.io.StringWriter
import java.io.UnsupportedEncodingException

internal data class SourceReply(val url: String, val body: String, val status: Int = 200,
    val headers: Map<String, List<String>> = emptyMap(), val data: ByteArray? = null,
    val message: String = "OK", val callTime: Int = 0, val file: String? = null)
internal data class SourceHttpOptions(val timeout: Long? = null, val followRedirects: Boolean = true,
    val dnsIp: String? = null, val proxy: String? = null, val cookieJar: Boolean = true,
    val callTimeout: Long? = null, val maxResponseBytes: Int = 8 * 1024 * 1024)
internal data class SourceWebRequest(val url: String, val html: String? = null, val script: String? = null,
    val headers: Map<String, String> = emptyMap(), val delay: Long = 0, val result: String? = null,
    val sourceRegex: String? = null, val interactive: Boolean = false, val clearProfile: Boolean = false,
    val overrideUrlRegex: String? = null, val cacheFirst: Boolean = false,
    val title: String? = null, val captureBody: Boolean = false,
    val browserSheet: Boolean = false, val browserConfig: String? = null, val thirdPartyCookies: Boolean = false)
internal class SourceRun(
    val fetch: (String, String, Map<String, String>, ByteArray?) -> SourceReply,
    val cancelled: () -> Boolean = { false },
    deadline: Long = System.nanoTime() + 30_000_000_000L,
    val state: SourceState = SourceState(),
    val fetchOptions: ((String, String, Map<String, String>, ByteArray?, SourceHttpOptions) -> SourceReply)? = null,
    val web: ((SourceWebRequest) -> SourceReply)? = null,
    val cookieRead: (String) -> String = { "" },
    val cookieWrite: (String, String) -> Unit = { _, _ -> },
    val cookieRemove: (String) -> Unit = {},
    val fetchBytes: ((String, String, Map<String, String>, ByteArray?, SourceHttpOptions) -> SourceReply)? = null,
    val fetchFile: ((String, String, Map<String, String>, ByteArray?, SourceHttpOptions) -> SourceReply)? = null,
    val userAgent: String = SourceNetwork.USER_AGENT,
    val filesRoot: java.io.File? = null,
    val webUserAgent: (() -> String)? = null,
    val archiveBackend: SourceArchiveBackend? = null,
    val openBrowser: ((SourceWebRequest) -> Unit)? = null,
    val verifyCode: ((ByteArray) -> String?)? = null,
    val notice: ((String, Boolean) -> Unit)? = null,
    val openExternal: ((String, String?) -> Unit)? = null,
    val appConfig: Map<String, Any?> = emptyMap(),
    val installationId: String = "0000000000000000",
    val diagnostic: ((String) -> Unit)? = null,
    val metrics: SourceRunMetrics = SourceRunMetrics(),
    val hubs: SourceHubConnections? = null,
    val openSocket: ((String, Map<String, String>, okhttp3.WebSocketListener) -> okhttp3.WebSocket)? = null,
    val lowPriority: Boolean = false,
) {
    @Volatile var deadline: Long = deadline; private set
    fun <T> awaitUser(action: () -> T): T {
        check()
        val saved = deadline; val start = System.nanoTime()
        deadline = start + 5 * 60_000_000_000L
        try { return action() } finally { deadline = saved + (System.nanoTime() - start) }
    }
    var requests = 0
    @Synchronized fun countRequest() { check(); check(++requests <= 96) { "书源请求次数超出限制" } }
    private val stopped = java.util.concurrent.atomic.AtomicBoolean()
    private val cancellers = java.util.concurrent.ConcurrentHashMap.newKeySet<() -> Unit>()
    internal class CallGroup {
        private val stopped = java.util.concurrent.atomic.AtomicBoolean()
        private val actions = java.util.concurrent.ConcurrentHashMap.newKeySet<() -> Unit>()
        fun register(action: () -> Unit): () -> Unit {
            actions.add(action); if (stopped.get()) action()
            return { actions.remove(action) }
        }
        fun cancel() { stopped.set(true); actions.forEach { it() } }
        fun check() { if (stopped.get()) throw CancellationException() }
    }
    private val callGroup = ThreadLocal<CallGroup>()
    fun <T> inGroup(group: CallGroup, work: () -> T): T {
        val previous = callGroup.get(); callGroup.set(group)
        try { group.check(); return work() } finally { if (previous == null) callGroup.remove() else callGroup.set(previous) }
    }
    fun cancel() { stopped.set(true); cancellers.forEach { it() } }
    fun onCancel(action: () -> Unit): () -> Unit {
        cancellers.add(action)
        val unregisterGroup = callGroup.get()?.register(action)
        if (stopped.get() || cancelled()) action()
        return { cancellers.remove(action); unregisterGroup?.invoke(); Unit }
    }
    fun check() {
        if (stopped.get() || cancelled() || Thread.currentThread().isInterrupted) throw CancellationException()
        callGroup.get()?.check()
        check(System.nanoTime() < deadline) { "书源执行超时" }
    }
}

/** Native host for the adapted Legado 3 parser. Rule syntax lives in legado/;
 * this class connects book operations, script services and networking. */
internal class BookSourceEngine(source: Map<String, Any?>, private val run: SourceRun) {
    private val source = source.mapValues { (key,value) ->
        if (key in ruleFields && value is Map<*, *>) value.entries.associate { it.key.toString() to it.value }.toMutableMap() else value
    }.toMutableMap()
    private val gson = org.mewx.wenku8_flutter.legado.js.SourceGson.gson
    private var base = (source["engine"] as? Map<*, *>)?.get("origin") as? String ?: source["bookSourceUrl"]?.toString()?.substringBefore("##") ?: ""
    private var key = ""
    private var page = 1
    private var book: Map<String, Any?> = emptyMap()
    private var chapter: Map<String, Any?> = emptyMap()
    private val variables = mutableMapOf<String, String>()
    private var rowVariables: SourceState? = null
    private var rowEntity = "book"
    private fun variableScope(): String = chapter["url"]?.toString()?.takeIf { it.isNotBlank() }?.let { "chapter:$it" }
        ?: book["bookUrl"]?.toString()?.takeIf { it.isNotBlank() }?.let { "book:$it" } ?: "source"
    private fun putVariable(key: String, value: String): String {
        rowVariables?.let { it.putRuleVariable("row", key, value); return value }
        val owner = variableScope()
        if (owner == "source") run.state.put(owner, key, value) else run.state.putRuleVariable(owner, key, value)
        return value
    }
    private fun getVariable(key: String): String = when (key) {
        "bookName" -> book["name"]?.toString().orEmpty()
        "title" -> chapter["title"]?.toString().orEmpty()
        else -> rowVariables?.ruleVariable("row", key)?.takeIf { it.isNotEmpty() } ?: run.state.ruleVariable(variableScope(), key).ifEmpty {
            book["bookUrl"]?.toString()?.let { run.state.ruleVariable("book:$it", key) }.orEmpty()
        }.ifEmpty { run.state.get("source", key) }
    }
    private fun saveRowVariables(owner: String) {
        rowVariables?.let { state ->
            state.copyRuleVariables("row", run.state, owner)
        }
    }
    private val analyzer = AnalyzeRule(object : RuleHost {
        override fun check() = run.check()
        override fun put(key: String, value: String): String = putVariable(key, value)
        override fun get(key: String): String = getVariable(key)
        override fun evalJS(code: String, result: Any?, content: Any?, baseUrl: String?): Any? {
            val value = js(code, result, content, baseUrl)
            // A script can return java.getElement(s) directly. Rhino wraps that
            // Java collection; the rule parser must receive the actual rows,
            // just as it does for a CSS/XPath rule or a JavaScript array.
            return if (value is org.htmlunit.corejs.javascript.Wrapper) value.unwrap() else value
        }
        override fun webJS(code: String, result: Any?, content: Any?, baseUrl: String?): String =
            (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(baseUrl ?: base,
                html = content.toString(), script = code, headers = requestHeaders(), result = gson.toJson(fromJs(result)))).body
    })
    private val jsonConfig = Configuration.defaultConfiguration().addOptions(Option.SUPPRESS_EXCEPTIONS)
    private val factory = object : ContextFactory() {
        override fun makeContext(): Context = org.mewx.wenku8_flutter.legado.runtime.RhinoContext(this, run::check).apply {
            setInterpretedMode(true)
            languageVersion = Context.VERSION_ES6
            instructionObserverThreshold = 4096
            wrapFactory = SourceJavaBoundary()
            // Same result as Rhino's default, without loading its optional
            // java.beans converter on Android. Maps/lists retain native JSON.
            setJavaToJSONConverter { it.toString() }
            setClassShutter { name -> name.startsWith("org.jsoup.") || name.startsWith("org.seimicrawler.xpath.") || name.startsWith("cn.hutool.crypto.") || name.startsWith("org.mewx.wenku8_flutter.legado.") || name in scriptClasses ||
                scriptCollectionPrefixes.any(name::startsWith) }
            maximumInterpreterStackDepth = 1000
        }
        // Preserve the pinned upstream runtime's E4X, Java-map and dynamic
        // this/eval-realm semantics, in addition to its parser implementation.
        override fun hasFeature(cx: Context, featureIndex: Int): Boolean = when (featureIndex) {
            Context.FEATURE_E4X, Context.FEATURE_ENABLE_JAVA_MAP_ACCESS,
            Context.FEATURE_LEGADO_DYNAMIC_DEFAULT_THIS, Context.FEATURE_LEGADO_DYNAMIC_EVAL_REALM -> true
            else -> super.hasFeature(cx, featureIndex)
        }
        override fun observeInstructionCount(cx: Context, count: Int) {
            instructions += count; run.check()
            check(instructions <= 5_000_000) { "书源脚本超出执行预算" }
        }
    }
    private var instructions = 0
    private var scope: TopLevel? = null
    private var libraryLoaded = false
    private var currentResult: Any? = null
    private var extraBindings: Map<String, Any?> = emptyMap()
    private var loginUiReset = false
    private var loginUiChanged = false
    private var loginUiRebuild = false
    private var refreshExplore = false
    private var initializingLoginInfo = false
    private var inspectingScript = false
    private var javaUsesSource = false
    private var preUpdating = false
    private val resources by lazy {
        org.mewx.wenku8_flutter.legado.SourceResources(
            run.filesRoot ?: throw SecurityException("书源当前操作不允许文件访问"), run.state.fileLock, run::check, run.archiveBackend)
    }
    private val loginUiUpdates = linkedMapOf<String, Any?>()
    private val mainScript get() = source["mainJs"]?.toString()?.takeIf { it.isNotBlank() }
    private fun scriptSource() = ScriptSource(source["bookSourceUrl"].toString(), source["bookSourceName"]?.toString().orEmpty())

    fun execute(operation: String, url: String? = null, key: String = "", page: Int = 1,
                book: Map<String, Any?> = emptyMap(), chapter: Map<String, Any?> = emptyMap()): Any {
        try { return executeRule(operation, url, key, page, book, chapter) }
        catch (failure: Exception) { throw declaredFailure(failure) }
    }

    private fun declaredFailure(failure: Exception): Exception {
        if (failure is SourceDeclaredFailure) return failure
        val code = generateSequence<Throwable>(failure) { it.cause }
            .filterIsInstance<org.htmlunit.corejs.javascript.RhinoException>()
            .firstNotNullOfOrNull { Regex("SOURCE_ERROR=([A-Za-z0-9_]{1,64})").find(it.message.orEmpty())?.groupValues?.get(1) }
        val errors = (source["engine"] as? Map<*, *>)?.get("errors") as? Map<*, *>
        val message = errors?.get(code) as? String
        return if (code != null && message != null) SourceDeclaredFailure(code, message, failure) else failure
    }

    @Suppress("UNCHECKED_CAST")
    private fun executeRule(operation: String, url: String? = null, key: String = "", page: Int = 1,
                book: Map<String, Any?> = emptyMap(), chapter: Map<String, Any?> = emptyMap()): Any {
        require(page in 1..100000); this.key = key; this.page = page
        this.book = hydrateEntity(book, true); this.chapter = hydrateEntity(chapter, false)
        run.check()
        if (operation in setOf("accountVerify", "accountShelf", "accountCheckIn") && source["enabled"] == false)
            throw SourceAccountFailure("书源已停用，启用后可执行账号操作")
        when (operation) {
            "accountVerify" -> return accountVerify()
            "accountCheckIn" -> return accountCheckIn()
            "accountShelf" -> {
                val rules = SourceAccountRules(source["ruleAccount"]).shelf()
                    ?: throw SourceAccountFailure("书源没有提供云书架规则")
                return bookListing(url ?: rules["url"].toString(), rules, inferNavigation = false)
            }
            "cloudShelf" -> return scriptMap(callMain("getShelf", linkedMapOf("page" to page, "nextPageUrl" to url)), "云书架")
            "loginUi" -> return loginUi()
            "login" -> {
                loginUiReset = false; loginUiChanged = false; loginUiRebuild = false; refreshExplore = false; loginUiUpdates.clear()
                if (SourceLoginUi.isV2(source["loginUi"])) return loginActionV2(key, book)
                val fields = book["loginInfo"] as? Map<*, *> ?: emptyMap<Any, Any>()
                run.state.put("login", "info", gson.toJson(fields))
                val login = source["loginUrl"]?.toString()?.trim().orEmpty()
                require(!login.startsWith("http")) { "书源需要在登录网页中完成验证" }
                val action = key.ifBlank { "if(typeof login==='function'){login()}else{throw 'Function login not implements!!!'}" }
                js("${mainScript ?: inlineScript(login)}\n$action", fields)
                if (loginUiChanged || loginUiRebuild) {
                    // A legacy callback updates/rebuilds the current login UI;
                    // it is not an implicit successful-login/close command.
                    scope = null; libraryLoaded = false
                    return loginUi() + mapOf("version" to 1, "refreshExplore" to refreshExplore)
                }
                if (refreshExplore) return mapOf("version" to 1, "refreshExplore" to true)
                return true
            }
            "explores" -> return explores()
            "inspectScript" -> {
                inspectingScript = true
                try { return inspectScript(key) } finally { inspectingScript = false }
            }
        }
        if (mainScript != null) return executeScriptBook(operation, url)
        when (operation) {
            "search", "explore" -> {
                val template = url ?: if (operation == "search") source["searchUrl"]?.toString() ?: "" else ""
                require(template.isNotBlank()) { "书源没有${if (operation == "search") "搜索" else "发现"}规则" }
                val exploreRules = rules("ruleExplore")
                val rules = if (operation == "search" || exploreRules["bookList"]?.toString().isNullOrBlank()) rules("ruleSearch") else exploreRules
                return bookListing(template, rules)
            }
            "detail" -> {
                val selected = url ?: error("详情地址为空")
                val resolved = run.state.get("book-resolution", selected).takeIf { it.isNotBlank() }
                    ?.let { this.book["bookUrl"]?.toString() } ?: selected
                val reply = request(resolved, checkLogin = true)
                val rules = rules("ruleBookInfo")
                val result = org.mewx.wenku8_flutter.legado.book.BookInfo.analyze(
                    this.book, rules, analyzer, reply.body, url, reply.url, run::check,
                    strict = { name, work -> try { work() } catch (cancelled: CancellationException) { throw cancelled }
                        catch (failure: Exception) { throw SourceRuleFailure(name, failure) } },
                    warning = { name, failure -> sourceRuleFailureMessage(SourceRuleFailure(name, failure)) ?: "书源可选信息解析未完成" },
                    absolute = ::absolute,
                    onUpdate = { this.book = it.toMap().let { values -> if (values["lastChapter"] != null)
                        values + ("latestChapterTitle" to values["lastChapter"]) else values } },
                    currentBook = { this.book },
                ).toMutableMap()
                result["bookUrl"] = reply.url
                result["author"] = SourceDocumentMetadata.authorName(result["author"]?.toString().orEmpty())
                SourceDocumentMetadata.parse(reply.body, reply.url)?.let { metadata ->
                    // Links/tags supplement the source fields, but page-wide
                    // headings never rename a selected book behind its rule.
                    result["kind"] = metadata.genres(result["kind"]?.toString().orEmpty()).joinToString(",")
                    result["intro"] = metadata.intro(result["intro"]?.toString().orEmpty())
                    result["authorUrl"] = metadata.authorUrl(result["author"]?.toString().orEmpty())
                    result["tagUrls"] = metadata.tagUrls(result["kind"]?.toString().orEmpty().split(Regex("[\\s\\u3000·,，、;；|/]+")))
                }
                result["kind"].toString().split(Regex("[\\s\\u3000·,，、;；|/]+")).firstNotNullOfOrNull { token ->
                    when (token.lowercase()) {
                        "已完结", "已完結", "完结", "完結", "全本", "完本", "completed", "finished" -> true
                        "连载", "連載", "连载中", "連載中", "更新中", "ongoing" -> false
                        else -> null
                    }
                }?.let { result["complete"] = it }
                saveEntity(result, true)
                return result
            }
            "toc" -> {
                return chapterList(url ?: error("目录地址为空"))
            }
            "content" -> {
                return chapterContent(url ?: error("正文地址为空"))
            }
            else -> error("未知书源操作")
        }
    }

    private fun bookListing(template: String, rules: Map<String, Any?>, inferNavigation: Boolean = true): Map<String, Any?> {
        val reply = request(template, checkLogin = true)
        val listRule = rules["bookList"]?.toString().orEmpty()
        val reverse = listRule.startsWith('-')
        val nodes = list(listRule.removePrefix("-").removePrefix("+"), reply.body)
        check(nodes.size <= 1000) { "单页书目超过 1000 项" }
        val items = nodes.mapNotNull { node ->
            this.book = mutableMapOf("origin" to source["bookSourceUrl"], "originName" to source["bookSourceName"])
            rowVariables = SourceState(); rowEntity = "book"
            val name = field(rules, "name", node)
            this.book = this.book + ("name" to name)
            val bookUrl = absolute(field(rules, "bookUrl", node), reply.url)
            this.book = this.book + ("bookUrl" to bookUrl)
            val item = if (name.isBlank() || bookUrl.isBlank()) null else linkedMapOf<String, Any?>(
                "name" to name, "bookUrl" to bookUrl,
                "author" to SourceDocumentMetadata.authorName(field(rules, "author", node)), "kind" to values(rules["kind"], node).joinToString(","),
                "intro" to field(rules, "intro", node), "coverUrl" to absolute(field(rules, "coverUrl", node), reply.url),
                "lastChapter" to field(rules, "lastChapter", node),
            )
            if (item != null) saveRowVariables("book:$bookUrl")
            rowVariables = null
            item
        }
        this.book = emptyMap()
        if (!inferNavigation && items.size != nodes.size) throw SourceAccountFailure("书源云书架中有书籍缺少名称或详情地址，未合并到书架")
        val navigation = if (inferNavigation) SourceDocumentMetadata.parse(reply.body, reply.url)?.navigation() else null
        val explicitNext = values(rules["nextPageUrl"], reply.body).firstNotNullOfOrNull {
            absolute(it, reply.url).takeIf { next -> next.isNotBlank() && next != reply.url }
        }
        val supportsPages = Regex("\\{\\{[\\s\\S]*?\\b(?:page|searchPage)\\b[\\s\\S]*?\\}\\}|<[^>]*,[^>]*>").containsMatchIn(template)
        val nextUrl = explicitNext ?: navigation?.nextUrl?.takeUnless {
            supportsPages && losesTemplateFilters(template, reply.url, it)
        }
        val hasMore = explicitNext != null || navigation?.nextUrl != null ||
            (navigation?.hasPager != true && items.isNotEmpty() && supportsPages)
        return mapOf("items" to items.distinctBy { it["bookUrl"] }.let { if (reverse) it.reversed() else it },
            "pageUrl" to reply.url, "nextUrl" to nextUrl, "hasMore" to hasMore)
    }

    private fun accountVerify(): Boolean {
        val rules = SourceAccountRules(source["ruleAccount"]).verify()
            ?: throw SourceAccountFailure("书源没有提供账号验证规则")
        try {
            if (rules["js"] is String) {
                val profile = scriptMap(callMain(rules["js"] as String, emptyMap()), "账号资料")
                val loggedIn = profile["loggedIn"] as? Boolean
                    ?: throw SourceAccountFailure("书源账号脚本须返回登录状态")
                if (loggedIn) SourceAccountState.profile(run.state, profile)
                run.check(); SourceAccountState.verified(run.state, loggedIn)
                return loggedIn
            }
            val reply = request(rules["url"].toString(), checkStatus = false)
            val loggedIn = if (reply.status == 401) false else {
                if (reply.status !in 200..299) throw SourceAccountFailure("书源账号验证请求未完成，请稍后重试")
                SourceAccountRules.boolean(field(rules, "loggedIn", reply.body))
            }
            run.check(); SourceAccountState.verified(run.state, loggedIn)
            return loggedIn
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) {
            if (SourceAccountState.authenticationRejected(failure)) {
                SourceAccountState.verified(run.state, false)
                return false
            }
            val declared = declaredFailure(failure)
            SourceAccountState.failed(run.state, declared); throw declared
        }
    }

    private fun accountCheckIn(): Map<String, Any?> {
        val config = SourceAccountRules(source["ruleAccount"])
        val primary = config.checkIn() ?: throw SourceAccountFailure("书源没有提供签到规则")
        val extras = config.checkInExtras()
        if (extras.isEmpty()) {
            if (SourceAccountState.checkedInToday(run.state)) return mapOf("already" to true, "complete" to true)
            val receipt = checkInRule(primary)
            run.check(); SourceAccountState.checkedIn(run.state)
            return receipt + mapOf("complete" to true)
        }
        val revision = config.checkInRevision()!!
        val previous = SourceAccountState.checkInReport(run.state, revision).associateBy { it["id"] }
        val rules = listOf(primary + mapOf("id" to "primary", "label" to config.checkInLabel())) + extras
        val steps = mutableListOf<Map<String, Any?>>()
        for (rule in rules) {
            run.check()
            val id = rule["id"] as String
            val saved = previous[id]
            val receipt = if (saved?.get("complete") == true || id == "primary" && SourceAccountState.legacyCheckInToday(run.state)) {
                mapOf("already" to true, "complete" to true, "message" to (saved?.get("message") ?: "今日已完成"))
            } else try {
                checkInRule(rule) + mapOf("complete" to true)
            } catch (failure: Exception) {
                run.check()
                if (SourceAccountState.authenticationRejected(failure)) throw failure
                mapOf("complete" to false, "already" to false,
                    "message" to (sourceRuleFailureMessage(failure) ?: "此项签到未完成，请重试"))
            }
            steps.add(receipt + mapOf("id" to id, "label" to rule["label"]))
            SourceAccountState.saveCheckInReport(run.state, revision, steps)
        }
        val complete = steps.all { it["complete"] == true }
        if (complete) SourceAccountState.checkedIn(run.state, revision)
        return mapOf("already" to steps.all { it["already"] == true }, "complete" to complete, "steps" to steps)
    }

    private fun checkInRule(rules: Map<String, Any?>): Map<String, Any?> {
        if (rules["js"] is String) {
            val value = scriptMap(callMain(rules["js"] as String, emptyMap()), "签到结果")
            val already = value["already"] == true
            if (!already && value["success"] != true)
                throw SourceAccountFailure(value["message"] as? String ?: "书源未确认签到成功，可登录后重试")
            run.check()
            return mapOf("already" to already, "message" to value["message"])
        }
        val reply = request(rules["url"].toString(), checkLogin = true, retryAllowed = false)
        val already = rules["already"]?.toString()?.takeIf { it.isNotBlank() }
            ?.let { SourceAccountRules.boolean(field(rules, "already", reply.body)) } ?: false
        if (!already && !SourceAccountRules.boolean(field(rules, "success", reply.body)))
            throw SourceAccountFailure("书源未确认签到成功，可登录后重试")
        run.check()
        return mapOf("already" to already)
    }

    /** Pagination follows upstream's two forms: a single next-page chain, or a
     * finite list of sibling pages. Sibling links must not recursively expand. */
    private fun paged(first: String, limit: Int, label: String, parse: (String, Boolean) -> List<String>) {
        val visited = linkedSetOf(first)
        fun read(address: String, getNext: Boolean): List<String> {
            run.check(); check(visited.size <= limit) { "$label 分页超过 $limit 页" }
            return parse(address, getNext).filter { it.isNotBlank() && it !in visited }
        }
        val next = read(first, true)
        if (next.size == 1) {
            var address = next.first()
            while (address.isNotBlank() && visited.add(address)) address = read(address, true).firstOrNull().orEmpty()
        } else for (address in next) if (visited.add(address)) read(address, false)
    }
    private fun ruleBoolean(value: String) = value.isNotBlank() && value != "null" &&
        !value.trim().matches(Regex("(?i)^(?:false|no|not|0|0.0)$"))
    private fun chapterList(address: String): List<Map<String, Any?>> {
        val rules = rules("ruleToc")
        var tocAddress = address
        rules["preUpdateJs"]?.toString()?.takeIf { it.isNotBlank() }?.let { code ->
            val original = book["bookUrl"]?.toString().orEmpty()
            preUpdating = true
            try {
                js(inlineScript(code), null)
                if (original.isNotBlank()) run.state.put("book-resolution", original, gson.toJson(book))
                tocAddress = book["tocUrl"]?.toString()?.takeIf { it.isNotBlank() } ?: address
            } finally { preUpdating = false }
        }
        val rawRule = rules["chapterList"]?.toString().orEmpty()
        val rows = mutableListOf<Map<String, Any?>>()
        var currentVolume = ""
        paged(tocAddress, 64, "目录") { next, getNext ->
            val reply = request(next, checkLogin = true)
            val nodes = list(rawRule.removePrefix("-").removePrefix("+"), reply.body)
            // Parse next-page rules before row variables, as upstream does.
            val nextPages = if (getNext) values(rules["nextTocUrl"], reply.body).map { absolute(it, reply.url) } else emptyList()
            val metadata = SourceDocumentMetadata.parse(reply.body, reply.url)
            for ((index, node) in nodes.withIndex()) {
                run.check()
                chapter = SourceEntity.chapterDefaults + mapOf("bookUrl" to book["bookUrl"], "baseUrl" to reply.url)
                rowVariables = SourceState(); rowEntity = "chapter"
                try {
                    val title = field(rules, "chapterName", node)
                    chapter = chapter + ("title" to title)
                    val parsedUrl = absolute(field(rules, "chapterUrl", node), reply.url)
                    chapter = chapter + ("url" to parsedUrl)
                    val info = field(rules, "updateTime", node)
                    val explicitVolume = !rules["isVolume"]?.toString().isNullOrBlank()
                    val group = metadata?.chapterGroup(node, title, parsedUrl) ?: SourceDocumentMetadata.chapterGroup(node)
                    val volume = if (explicitVolume) ruleBoolean(field(rules, "isVolume", node)) else group.isHeader
                    if (title.isBlank()) continue
                    if (volume) currentVolume = title
                    val chapterUrl = parsedUrl.ifEmpty { if (volume) "$title$index" else reply.url }
                    chapter = chapter + mapOf("url" to chapterUrl, "isVolume" to volume, "tag" to info,
                        "isVip" to ruleBoolean(field(rules, "isVip", node)), "isPay" to ruleBoolean(field(rules, "isPay", node)))
                    rows.add(chapter + mapOf("name" to title,
                        "volumeTitle" to if (explicitVolume) currentVolume else group.title.ifBlank { currentVolume }))
                    saveRowVariables("chapter:$chapterUrl")
                } finally { rowVariables = null }
            }
            chapter = emptyMap()
            check(rows.size <= 100000) { "目录超过 100000 章" }
            nextPages
        }
        // Keep the last duplicate, but never drop a readable first chapter
        // merely because its URL is shared by a volume heading.
        val ordered = if (rawRule.startsWith('-')) rows.distinctBy { it["url"] to it["isVolume"] }.reversed()
            else rows.asReversed().distinctBy { it["url"] to it["isVolume"] }.reversed()
        val result = ordered.mapIndexed { index, row -> row + ("index" to index) }.toMutableList()
        val formatJs = rules["formatJs"]?.toString()?.takeIf { it.isNotBlank() }
        if (formatJs != null) {
            val savedScope = scope; val savedLibrary = libraryLoaded; val savedBindings = extraBindings
            try {
                scope = null; libraryLoaded = false
                js("var gInt=0;", null)
                for ((index, row) in result.withIndex()) {
                    chapter = row
                    extraBindings = mapOf("index" to index + 1)
                    try { js(inlineScript(formatJs), null)?.let { result[index] = chapter + ("name" to string(it)) + ("title" to string(it)) } }
                    catch (failure: Exception) { run.check() /* optional title formatting */ }
                }
            } finally { scope = savedScope; libraryLoaded = savedLibrary; extraBindings = savedBindings }
        }
        result.forEach { saveEntity(it, false) }
        chapter = emptyMap()
        return result
    }
    private fun chapterContent(address: String): String {
        val rules = rules("ruleContent")
        val pieces = mutableListOf<String>()
        var size = 0
        var first: SourceReply? = null
        val nextChapter = chapter["nextChapterUrl"]?.toString()?.let { absolute(it, address) }
        paged(address, 32, "正文") { next, getNext ->
            var reply = request(next, checkLogin = true)
            val webJs = rules["webJs"]?.toString()?.takeIf { it.isNotBlank() }
            if (webJs != null) reply = (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(reply.url,
                html = reply.body, script = webJs, headers = requestHeaders(), sourceRegex = rules["sourceRegex"]?.toString()))
            if (first == null) first = reply
            analyzer.setContent(reply.body, next)
            val redirectUrl = analyzer.setRedirectUrl(reply.url)
            var text = analyzer.getString(rules["content"]?.toString(), unescape = false)
            text = org.mewx.wenku8_flutter.legado.HtmlFormatter.formatKeepImg(text, redirectUrl)
            if ('&' in text) text = org.apache.commons.text.StringEscapeUtils.unescapeHtml4(text)
            pieces.add(text); size += text.length
            check(size <= 4 * 1024 * 1024) { "单章正文超过 4 MiB" }
            if (getNext) analyzer.getStringList(rules["nextContentUrl"]?.toString(), isUrl = true).orEmpty()
                .filter { it != nextChapter && it != book["tocUrl"] && it != book["bookUrl"] }
            else emptyList()
        }
        // Replacement runs once over the complete chapter, before converting
        // image HTML into the reader's existing internal marker format.
        val original = first ?: error("书源正文未返回内容")
        analyzer.setContent(original.body, address); analyzer.setRedirectUrl(original.url)
        rules["subContent"]?.toString()?.takeIf { it.isNotBlank() }?.let { subRule ->
            val value = analyzer.getString(subRule).trim()
            if (value.startsWith("http", true)) try { scriptResponse(value) } catch (failure: Exception) { run.check() }
        }
        var text = pieces.joinToString("\n")
        rules["replaceRegex"]?.toString()?.takeIf { it.isNotBlank() }?.let { replace ->
            text = analyzer.getString(replace, text.split(Regex("\r?\n")).joinToString("\n") { it.trim() })
        }
        rules["title"]?.toString()?.takeIf { it.isNotBlank() }?.let { rule ->
            try { analyzer.getString(rule).takeIf { it.isNotBlank() }?.let { chapter = chapter + ("title" to it) } }
            catch (failure: Exception) { run.check() }
        }
        saveEntity(chapter, false)
        saveEntity(book, true)
        text = org.mewx.wenku8_flutter.legado.HtmlFormatter.readerImages(text) { absolute(it, original.url) }
        text = SourceImageMarkup.readerImages(text) { absolute(it, original.url) }
        return text.replace("\r", "").lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n")
    }

    @Suppress("UNCHECKED_CAST")
    private fun rules(name: String) = source[name] as? Map<String, Any?> ?: emptyMap()
    private fun field(rules: Map<String, Any?>, name: String, input: Any?): String = try {
        string(evaluate(rules[name]?.toString() ?: "", input))
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        throw SourceRuleFailure(name, failure)
    }
    private fun list(rule: Any?, input: Any?): List<Any?> {
        if (rule == null || rule.toString().isBlank()) return emptyList()
        return asList(evaluate(rule.toString(), input, elements = true))
    }
    private fun values(rule: Any?, input: Any?): List<String> {
        if (rule == null || rule.toString().isBlank() || input == null) return emptyList()
        analyzer.setContent(input, base); analyzer.setRedirectUrl(base)
        return analyzer.getStringList(rule.toString()).orEmpty()
    }
    private fun asList(value: Any?): List<Any?> = when (value) {
        null -> emptyList(); is List<*> -> value; else -> listOf(value)
    }

    private fun explores(): List<Map<String, Any?>> {
        var raw: Any? = source["exploreUrl"] ?: return emptyList()
        if (raw is String && (raw.trim().startsWith("@js:") || raw.trim().startsWith("<js>"))) {
            val script = raw.trim().removePrefix("@js:").removePrefix("<js>").removeSuffix("</js>")
            raw = fromJs(js("${mainScript.orEmpty()}\n$script", ""))
        }
        if (raw is String && raw.trim().startsWith('[')) raw = gson.fromJson(raw, List::class.java)
        val result = if (raw is List<*>) raw.mapNotNull { value ->
            val item = value as? Map<*, *> ?: return@mapNotNull null
            val url = item["url"]?.toString() ?: return@mapNotNull null
            mapOf("title" to (item["title"]?.toString() ?: "发现"), "url" to url,
                "style" to item["style"], "group" to item["group"])
        } else raw.toString().split(Regex("&&|\\n")).mapNotNull { line ->
            val index = line.indexOf("::")
            if (index > 0) mapOf("title" to line.substring(0, index).trim(), "url" to line.substring(index + 2).trim())
            else line.trim().takeIf { it.isNotEmpty() }?.let { mapOf("title" to "发现", "url" to it) }
        }
        check(result.size <= 10000) { "书源发现分类超过 10000 项" }
        return result
    }

    private fun requestHeaders(): MutableMap<String, String> = headerMap(source["header"]).apply {
        putAll(headerMap(run.state.get("login", "header")))
        if (keys.none { it.equals("User-Agent", true) }) put("User-Agent", run.userAgent)
    }
    private data class RequestPlan(val spec: org.mewx.wenku8_flutter.legado.AnalyzeUrl,
        val headers: Map<String, String>, val body: ByteArray?, val options: SourceHttpOptions, val skipRateLimit: Boolean = false)
    private fun prepareRequest(template: String, explicitHeaders: Map<String, String> = emptyMap(), callTimeout: Long? = null,
                               skipRateLimit: Boolean = false): RequestPlan {
        checkNetworkAccess()
        run.check()
        val spec = org.mewx.wenku8_flutter.legado.AnalyzeUrl(template, key, page, base,
            requestHeaders() + explicitHeaders) { code, result, root -> js(code, result, baseUrl = root) }
        val body = spec.requestBody()
        val headers = spec.headerMap.toMutableMap()
        val options = SourceHttpOptions(spec.readTimeoutMs, spec.followRedirects != false,
            spec.dnsIp, headers.remove("proxy"), source["enabledCookieJar"] != false, callTimeout)
        return RequestPlan(spec, headers, body, options, skipRateLimit)
    }
    private fun fetchPlan(plan: RequestPlan, binary: Boolean = false, forceHttp: Boolean = false, retryAllowed: Boolean = true, download: Boolean = false): SourceReply {
        val (spec, headers, body, options) = plan
        val start = System.nanoTime()
        var reply: SourceReply? = null
        var failure: Exception? = null
        for (attempt in 0..if (retryAllowed) spec.retry.coerceIn(0, 10) else 0) {
            run.countRequest()
            if (!plan.skipRateLimit) SourceRateLimit.await(source["bookSourceUrl"].toString(), run.state.get("source", "__concurrentRate").ifEmpty { source["concurrentRate"]?.toString().orEmpty() }, run)
            try {
                reply = if (download) {
                    (run.fetchFile ?: error("书源文件下载服务不可用"))(spec.requestUrl(), spec.method.name, headers, body, options)
                } else if (binary) {
                    run.fetchBytes?.invoke(spec.requestUrl(), spec.method.name, headers, body, options)
                        ?: run.fetch(spec.requestUrl(), spec.method.name, headers, body)
                } else if (!forceHttp && spec.useWebView && spec.method != org.mewx.wenku8_flutter.legado.RequestMethod.POST) {
                    (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(spec.requestUrl(), script = spec.webJs,
                        headers = headers, delay = spec.webViewDelayTime))
                } else (run.fetchOptions?.invoke(spec.requestUrl(), spec.method.name, headers, body, options)
                    ?: run.fetch(spec.requestUrl(), spec.method.name, headers, body)).let { response ->
                    if (!forceHttp && spec.useWebView && !(spec.followRedirects == false && response.status in 300..399)) {
                        (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(response.url, html = response.body,
                            script = spec.webJs, headers = headers, delay = spec.webViewDelayTime))
                    } else response
                }
                break
            } catch (e: CancellationException) { throw e }
            catch (e: SourceHeaderFailure) { throw e }
            catch (e: Exception) { failure = e }
        }
        return (reply ?: throw (failure ?: IllegalStateException("书源请求未完成")))
            .copy(callTime = ((System.nanoTime() - start) / 1_000_000).coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
    }
    private fun finishResponse(plan: RequestPlan, raw: SourceReply): SourceReply {
        val spec = plan.spec
        var response = raw
        if (spec.type != null) response = response.copy(body = (response.data ?: response.body.toByteArray()).joinToString("") { "%02x".format(it) })
        else spec.bodyJs?.let { response = response.copy(body = string(js(it, response.body))) }
        return response
    }
    private fun request(template: String, explicitHeaders: Map<String, String> = emptyMap(), checkLogin: Boolean = false, checkStatus: Boolean = true, retryAllowed: Boolean = true): SourceReply {
        val plan = prepareRequest(template, explicitHeaders)
        var response = finishResponse(plan, fetchPlan(plan, retryAllowed = retryAllowed))
        base = response.url
        if (checkLogin) source["loginCheckJs"]?.toString()?.takeIf { it.isNotBlank() }?.let { code ->
            response = responseFromJs(js(code, response), response)
        }
        if (checkStatus) check(response.status < 400) { if (response.status in setOf(401, 403)) "书源要求登录或网页验证（HTTP ${response.status}）" else "书源返回 HTTP ${response.status}" }
        run.check(); return response
    }
    private fun scriptResponse(template: String, headers: Map<String, String> = emptyMap(), timeout: Long? = null): SourceResponse {
        val plan = prepareRequest(template, headers, timeout)
        val reply = try { finishResponse(plan, fetchPlan(plan)) }
        catch (failure: Exception) { run.check(); SourceReply(plan.spec.requestUrl(), scriptHttpError(failure)) }
        return SourceResponse(reply)
    }
    private fun scriptHttpError(failure: Exception): String {
        if (failure is CancellationException || failure is SecurityException) throw failure
        val chain = generateSequence<Throwable>(failure) { it.cause }.toList()
        val cause = chain.last()
        // Preserve the upstream soft-failure contract without returning URLs,
        // headers or stack traces containing account-bearing query parameters.
        return "${cause.javaClass.name}: ${sourceRuleFailureMessage(failure) ?: "书源网络请求未完成"}"
    }
    private fun directRequest(address: String, method: String, headers: Map<String, String>, body: String?, timeout: Long?): SourceJsoupResponse {
        checkNetworkAccess()
        run.countRequest()
        SourceRateLimit.await(source["bookSourceUrl"].toString(), run.state.get("source", "__concurrentRate").ifEmpty { source["concurrentRate"]?.toString().orEmpty() }, run)
        SourceNetwork.url(address)
        val options = SourceHttpOptions(timeout ?: 30000, followRedirects = false,
            cookieJar = source["enabledCookieJar"] != false, callTimeout = timeout ?: 30000)
        val response = run.fetchOptions?.invoke(address, method, headers, body?.toByteArray(), options)
            ?: run.fetch(address, method, headers, body?.toByteArray())
        // Jsoup convenience methods follow neither redirects nor HTTP errors.
        if (response.status >= 400) throw org.jsoup.HttpStatusException("书源返回 HTTP ${response.status}", response.status, address)
        run.check()
        return SourceJsoupResponse(response, method)
    }
    private fun scriptResponses(addresses: List<String>, timeout: Long?, skipRateLimit: Boolean): List<SourceResponse> {
        require(addresses.size <= 96) { "书源批量请求超过 96 项" }
        // Resolve URL scripts on the calling Rhino thread. Only native I/O runs
        // concurrently, never mutable JS scopes or analyzer state.
        val plans = addresses.map { prepareRequest(it, callTimeout = timeout, skipRateLimit = skipRateLimit) }
        val groups = plans.map { SourceRun.CallGroup() }
        val pending = plans.mapIndexed { index, plan -> httpWorkers.submit<SourceReply> { run.inGroup(groups[index]) { fetchPlan(plan) } } }
        fun cancelPending() { pending.forEachIndexed { index, future ->
            if (!future.isDone) { groups[index].cancel(); future.cancel(true) }
        } }
        val unregister = run.onCancel(::cancelPending)
        try {
            return pending.mapIndexed { index, future ->
                run.check()
                val reply = try { future.get((run.deadline - System.nanoTime()).coerceAtLeast(1), java.util.concurrent.TimeUnit.NANOSECONDS) }
                catch (failure: java.util.concurrent.ExecutionException) { throw (failure.cause as? Exception ?: failure) }
                SourceResponse(finishResponse(plans[index], reply))
            }
        } finally { unregister(); cancelPending() }
    }
    private fun headerMap(raw: Any?): MutableMap<String, String> {
        val value = try { when (raw) {
            is Map<*, *> -> raw
            is String -> {
                val result = if (raw.startsWith("@js:", true) || raw.startsWith("<js>", true)) isolatedScriptValue(inlineScript(raw)) else expand(raw)
                if (result is Map<*, *>) result else result?.toString()?.takeIf { it.isNotBlank() }
                    ?.let { gson.fromJson(it, Map::class.java) } ?: emptyMap<Any, Any>()
            }
            else -> emptyMap<Any, Any>()
        } } catch (failure: Exception) { if (failure is SecurityException) throw failure; run.check(); emptyMap<Any, Any>() }
        return value.entries.associate { it.key.toString() to it.value.toString() }.toMutableMap()
    }
    /** JsExtensions headers accept a JSON object or Map, not source-header JS. */
    private fun scriptHeaders(raw: Any?): Map<String, String> {
        if (raw == null) return emptyMap()
        val values = when (raw) {
            is Map<*, *> -> raw
            is String -> gson.fromJson(raw, Map::class.java)
            else -> throw IllegalArgumentException("书源请求头必须为 Map 或 JSON 对象")
        } ?: return emptyMap()
        return values.entries.associate { (key, value) ->
            require(key != null && value != null) { "书源请求头名称和值不可为 null" }
            key.toString() to value.toString()
        }
    }
    private fun cachedScript(address: String, saveTime: Int): String {
        // Only the source's network script cache is exposed; arbitrary device
        // files remain outside the script sandbox.
        checkNetworkAccess()
        require(address.startsWith("https://") || address.startsWith("http://")) { "书源脚本缓存仅支持 HTTP / HTTPS 地址" }
        val expiry = run.state.get("script-expiry", address).toLongOrNull()
        if (run.state.contains("script-cache", address) && (expiry == null || expiry > System.currentTimeMillis())) {
            return run.state.get("script-cache", address)
        }
        val plan = prepareRequest(address)
        val response = finishResponse(plan, fetchPlan(plan))
        require(response.status in 200..299) { "书源脚本请求未完成（HTTP ${response.status}）" }
        run.state.put("script-cache", address, response.body)
        if (saveTime == 0) run.state.remove("script-expiry", address)
        else run.state.put("script-expiry", address, "${System.currentTimeMillis() + saveTime.toLong() * 1000}")
        return response.body
    }
    private fun sourceFontBytes(address: String): ByteArray {
        val root = run.filesRoot ?: return resourceBytes(address)
        val cache = synchronized(run.state.fileLock) {
            (run.state.memory("reader-font-cache") as? SourceFontCache) ?: SourceFontCache(java.io.File(root, "reader-fonts-v1")).also {
                run.state.putMemory("reader-font-cache", it)
            }
        }
        val plan = prepareRequest(address)
        val headers = plan.headers.toMutableMap()
        if (headers.keys.none { it.equals("Cookie", true) }) {
            run.cookieRead(address).takeIf { it.isNotBlank() }?.let { headers["Cookie"] = it }
        }
        val identity = gson.toJson(headers.toSortedMap())
        return cache.load(address, identity, run) { conditional -> fetchPlan(plan.copy(headers = headers + conditional), binary = true) }
    }

    private fun resourceBytes(address: String): ByteArray {
        val reply = fetchPlan(prepareRequest(address), binary = true)
        require(reply.status in 200..299) { "书源资源请求未完成（HTTP ${reply.status}）" }
        val bytes = reply.data ?: reply.body.toByteArray()
        require(bytes.size <= org.mewx.wenku8_flutter.legado.SourceResources.MAX_FILE) { "书源资源超过 8 MiB" }
        run.check()
        return bytes
    }
    private fun browserRequest(address: String, title: String?, html: String?, script: String? = null): SourceWebRequest {
        require(address.length < 64 * 1024) { "书源浏览器地址过长" }
        val plan = prepareRequest(address)
        val body = html ?: if (plan.spec.method == org.mewx.wenku8_flutter.legado.RequestMethod.POST)
            finishResponse(plan, fetchPlan(plan, forceHttp = true)).body else null
        return SourceWebRequest(plan.spec.requestUrl(), html = body, headers = plan.headers,
            script = script, title = title, interactive = true, captureBody = true)
    }
    private fun browserAwait(address: String, title: String?, refetch: Boolean, html: String?): SourceResponse {
        checkNetworkAccess()
        val request = browserRequest(address, title, html)
        val http = SourceNetwork.url(request.url)
        val join = if (refetch && html == null) "${source["bookSourceUrl"]}\n${http.scheme}://${http.host}:${http.port}" else null
        val reply = SourceVerification.await(join, run) {
            run.countRequest()
            (run.web ?: error("书源网页脚本服务不可用"))(request)
        }
        run.check()
        return if (refetch) {
            if (html != null) SourceResponse((reply ?: SourceReply(request.url, html)).copy(body = html))
            else { val plan = prepareRequest(address); SourceResponse(finishResponse(plan, fetchPlan(plan, forceHttp = true))) }
        } else SourceResponse(reply ?: error("书源网页验证未返回内容"))
    }
    private fun verificationCode(address: String): String {
        checkNetworkAccess()
        val image = if (address.startsWith("data:")) org.mewx.wenku8_flutter.legado.SourceTextHelpers.base64Bytes(address.substringAfter("base64,"))
            ?: error("书源验证码图片为空") else resourceBytes(address)
        return run.awaitUser { (run.verifyCode ?: error("书源当前宿主未提供验证码输入"))(image) }
            ?.takeIf { it.isNotBlank() } ?: throw CancellationException("书源验证码已取消")
    }
    private fun archiveBytes(address: String): ByteArray {
        checkNetworkAccess()
        return if (address.startsWith("http://", true) || address.startsWith("https://", true)) resourceBytes(address)
        else {
            require(address.length <= 16 * 1024 * 1024) { "书源压缩文件超过 8 MiB" }
            cn.hutool.core.util.HexUtil.decodeHex(address)
        }
    }
    private fun downloadResource(address: String, hex: String? = null): String {
        checkNetworkAccess()
        val storage = resources // Reject missing file authority before any fetch.
        // Resolve scripts only once; filename and bytes use exactly this plan.
        val plan = prepareRequest(address)
        val type = plan.spec.type ?: if (hex != null) return "" else
            URI(plan.spec.requestUrl()).path.substringAfterLast('/').substringAfterLast('.', "")
                .takeIf { it.length in 1..5 && it.all { char -> char.isLetterOrDigit() && char.code < 128 } } ?: "ext"
        val bytes = if (hex != null) {
            require(hex.length <= 16 * 1024 * 1024) { "书源文件超过 8 MiB" }
            cn.hutool.core.util.HexUtil.decodeHex(hex)
        } else {
            val reply = fetchPlan(plan, binary = true)
            require(reply.status in 200..299) { "书源资源请求未完成（HTTP ${reply.status}）" }
            reply.data ?: reply.body.toByteArray()
        }
        return storage.save(address, type, bytes)
    }
    private fun checkNetworkAccess() { if (inspectingScript) throw SecurityException("书源预览不允许网络请求") }
    private fun expand(template: String, url: Boolean = false, charset: String = "UTF-8"): String =
        Regex("\\{\\{(.*?)\\}\\}", RegexOption.DOT_MATCHES_ALL).replace(template) { m ->
            val expression = m.groupValues[1].trim()
            val value = when (expression) { "key" -> key; "page", "searchPage" -> page.toString(); else -> string(js(expression, "")) }
            value
        }

    fun evaluate(rule: String, input: Any?, elements: Boolean = false, content: Boolean = false): Any? {
        run.check()
        if (rule.isBlank() || input == null) return if (elements) emptyList<Any>() else ""
        analyzer.setContent(input, base)
        analyzer.setRedirectUrl(base)
        return if (elements) analyzer.getElements(rule) else analyzer.getString(rule)
    }
    private fun string(value: Any?, content: Boolean = false): String = when (value) {
        null, is Undefined -> ""
        is Element -> if (content) markup(value.outerHtml(), base) else value.text()
        is org.htmlunit.corejs.javascript.Wrapper -> string(value.unwrap(), content)
        is org.htmlunit.corejs.javascript.NativeArray -> (0 until value.length.toInt()).joinToString("\n") { string(value.get(it, value), content) }
        is List<*> -> value.joinToString("\n") { string(it, content) }
        is Map<*, *> -> gson.toJson(value)
        is Double -> if (value % 1 == 0.0) value.toLong().toString() else value.toString()
        else -> value.toString()
    }
    private fun runtimeBindings(cx: Context): TopLevel {
        val library = source["jsLib"]?.toString()?.trim().orEmpty()
        require(library.length <= 1024 * 1024) { "脚本超过 1 MiB" }
        return SourceScriptScopes.bindings(library, source["bookSourceUrl"].orEmptyString()) {
            val root = cx.initSafeStandardObjects()
            for (name in listOf("Packages", "java", "javax", "org", "com", "JavaAdapter", "getClass")) root.delete(name)
            evaluateScript(cx, root, cryptoJs, "legado-cryptojs")
            ScriptableObject.putProperty(root, "__legadoSecureRandomInt", object : BaseFunction(root, ScriptableObject.getFunctionPrototype(root)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>) = secureRandom.nextInt().toDouble()
            })
            evaluateScript(cx, root, "CryptoJS.lib.WordArray.random=(function(nextInt){return function(nBytes){var words=[];for(var i=0;i<nBytes;i+=4){words.push(nextInt())}return CryptoJS.lib.WordArray.create(words,nBytes)}})(__legadoSecureRandomInt);", "legado-secure-random")
            root.delete("__legadoSecureRandomInt")
            val libraries = if (library.startsWith('{')) runCatching { gson.fromJson(library, Map::class.java).values.filterIsInstance<String>() }.getOrNull() else null
            if (libraries != null) for (url in libraries.filter { it.startsWith("https://") || it.startsWith("http://") }) {
                val text = run.state.get("library", url).ifEmpty {
                    run.countRequest(); run.fetch(url, "GET", emptyMap(), null).also { require(it.status in 200..299) { "书源共享脚本请求未完成" } }.body
                        .also { run.state.put("library", url, it) }
                }
                require(text.length <= 1024 * 1024) { "脚本超过 1 MiB" }
                evaluateScript(cx, root, text, "source-library")
            } else if (library.isNotEmpty()) evaluateScript(cx, root, library, "source-library")
            root.globalThis.preventExtensions()
            root
        }
    }
    private fun js(code: String, result: Any?, content: Any? = result, baseUrl: String? = base): Any? {
        require(code.length <= 1024 * 1024) { "脚本超过 1 MiB" }
        return factory.call { cx ->
            val runtime = cx as org.mewx.wenku8_flutter.legado.runtime.RhinoContext
            runtime.recursiveCount++
            val previousResult = currentResult
            var restoreTarget: TopLevel? = null
            var restoreBindings: Map<String, Any?>? = null
            try {
            runtime.checkRecursive()
            run.check()
            if (runtime.recursiveCount > 1) scope?.let { existing ->
                restoreTarget = existing
                restoreBindings = (listOf("result", "src", "baseUrl", "key", "page", "searchPage", "source", "sourceApi", "book", "chapter", "title", "java") + extraBindings.keys)
                    .associateWith { ScriptableObject.getProperty(existing, it) }
            }
            val target = scope ?: runtimeBindings(cx).also { safe ->
                scope = safe
                for (name in listOf("Packages", "java", "javax", "org", "com", "JavaAdapter", "getClass")) safe.delete(name)
                val java = cx.newObject(safe)
                fun function(name: String, action: (Array<out Any>) -> Any?) {
                    ScriptableObject.putProperty(java, name, object : BaseFunction(safe, ScriptableObject.getFunctionPrototype(safe)) {
                        override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? {
                            run.check()
                            return try {
                                toJs(cx, safe, action(args))
                            } catch (failure: Exception) {
                                // Checked network exceptions must cross Rhino's
                                // native-function boundary as script exceptions.
                                // Passing them through raw loses the real cause.
                                if (failure is RuntimeException) throw failure
                                throw Context.throwAsScriptRuntimeEx(failure)
                            }
                        }
                    })
                }
                fun arg(args: Array<out Any>, index: Int = 0) = args.getOrNull(index)?.let(Context::toString) ?: ""
                fun urls(args: Array<out Any>): List<String> = (fromJs(args.getOrNull(0)) as? List<*>
                    ?: throw IllegalArgumentException("书源批量请求需要地址数组")).map { it.toString() }
                function("getSource") { _ -> ScriptableObject.getProperty(safe, "sourceApi") }
                function("getTag") { _ -> source["bookSourceName"]?.toString().orEmpty() }
                function("toNumChapter") { args -> org.mewx.wenku8_flutter.legado.SourceTextHelpers.toNumChapter(fromJs(args.firstOrNull())?.toString()) }
                function("t2s") { args -> SourceChinese.t2s(arg(args)).also { run.check() } }
                function("s2t") { args -> SourceChinese.s2t(arg(args)).also { run.check() } }
                for (name in listOf("lock", "singleFlight")) function(name) { args ->
                    val action = args.getOrNull(1) as? org.htmlunit.corejs.javascript.Function
                        ?: throw IllegalArgumentException("书源并发操作需要函数")
                    SourceLocks.execute(SourceLocks.key(if (name == "singleFlight" && arg(args) == "novelia-refresh") SourceSessionIdentity.key(source["bookSourceUrl"].orEmptyString()) else source["bookSourceUrl"].orEmptyString(), arg(args)),
                        (args.getOrNull(2) as? Number)?.toLong() ?: 15000, name == "singleFlight", run) {
                        val parent = action.parentScope ?: safe
                        val root = ScriptableObject.getTopLevelScope(parent)
                        action.call(Context.getCurrentContext(), parent, root.globalThis ?: Undefined.SCRIPTABLE_UNDEFINED, emptyArray())
                    }
                    Undefined.instance
                }
                function("tick") { args -> SourceLocks.tick(SourceLocks.key(source["bookSourceUrl"].orEmptyString(), arg(args))) }
                function("sha256Encode") { args -> MessageDigest.getInstance("SHA-256").digest(arg(args).toByteArray()).joinToString("") { "%02x".format(it) } }
                function("decodeCompressed") { args -> SourceProtocolCodec.compressedText(arg(args), arg(args, 1)) }
                function("signalRInvoke") { args ->
                    checkNetworkAccess()
                    val parameters = if (arg(args, 3) == "null") null else SourceLoginUi.objectValue(arg(args, 3), "SignalR 参数须为 JSON 对象")
                    fun permit() {
                        run.countRequest()
                        SourceRateLimit.await(source["bookSourceUrl"].toString(), run.state.get("source", "__concurrentRate").ifEmpty { source["concurrentRate"]?.toString().orEmpty() }, run)
                    }
                    try { SourceSignalR.invoke(arg(args), arg(args, 1), arg(args, 2), parameters, run, requestHeaders(), ::permit) { address, verb, headers, body ->
                        permit()
                        val options = SourceHttpOptions(timeout = 15000, followRedirects = false,
                            cookieJar = source["enabledCookieJar"] != false, callTimeout = 15000)
                        SourceNetwork.url(address)
                        val request = run.fetchBytes ?: run.fetchOptions
                        request?.invoke(address, verb, requestHeaders() + headers, body, options)
                            ?: run.fetch(address, verb, requestHeaders() + headers, body)
                    } } catch (failure: IllegalStateException) {
                        if (failure.message != "轻书架登录已过期，请重新登录") throw failure
                        throw org.htmlunit.corejs.javascript.JavaScriptException(failure.message, "signalRInvoke", 0)
                    }
                }
                function("cleanFontText") { args ->
                    checkNetworkAccess()
                    SourceFontText.clean(arg(args), sourceFontBytes(arg(args, 1)), run::check)
                }
                function("ajax") { args ->
                    val raw = fromJs(args.getOrNull(0))
                    scriptResponse(if (raw is List<*>) raw.firstOrNull().toString() else arg(args), timeout = (args.getOrNull(1) as? Number)?.toLong()).body
                }
                function("ajaxAll") { args -> scriptResponses(urls(args), null, args.getOrNull(1) == true).toTypedArray() }
                function("ajaxTestAll") { args -> scriptResponses(urls(args), (args.getOrNull(1) as? Number)?.toLong(), args.getOrNull(2) == true).toTypedArray() }
                function("get") { args ->
                    if (args.size < 2) return@function getVariable(arg(args))
                    try { directRequest(arg(args), "GET", scriptHeaders(fromJs(args.getOrNull(1))), null, (args.getOrNull(2) as? Number)?.toLong()) }
                    catch (failure: org.jsoup.HttpStatusException) {
                        throw org.htmlunit.corejs.javascript.JavaScriptException("书源返回 HTTP ${failure.statusCode}", "get", 0).apply { initCause(failure) }
                    }
                }
                function("connect") { args ->
                    val raw = fromJs(args.getOrNull(1))
                    val headers = if (raw is String) runCatching { scriptHeaders(raw) }.getOrDefault(emptyMap()) else scriptHeaders(raw)
                    scriptResponse(arg(args), headers, (args.getOrNull(2) as? Number)?.toLong())
                }
                function("post") { args -> directRequest(arg(args), "POST", scriptHeaders(fromJs(args.getOrNull(2))), arg(args, 1), (args.getOrNull(3) as? Number)?.toLong()) }
                function("head") { args -> directRequest(arg(args), "HEAD", scriptHeaders(fromJs(args.getOrNull(1))), null, (args.getOrNull(2) as? Number)?.toLong()) }
                function("put") { args -> putVariable(arg(args), arg(args, 1)) }
                function("getStr") { args -> getVariable(arg(args)) }
                function("getString") { args ->
                    val split = fromJs(args.firstOrNull()) as? List<*>
                    if (split != null && split.all { it is AnalyzeRule.SourceRule }) {
                        @Suppress("UNCHECKED_CAST")
                        analyzer.getString(split as List<AnalyzeRule.SourceRule>, fromJs(args.getOrNull(1)), args.getOrNull(2) == true, args.getOrNull(3) != false)
                    } else if (args.getOrNull(1) is Boolean && args.size == 2) analyzer.getString(arg(args), args[1] as Boolean)
                    else analyzer.getString(arg(args), args.getOrNull(1)?.let(::fromJs), args.getOrNull(2) == true)
                }
                function("getStringList") { args ->
                    val split = fromJs(args.firstOrNull()) as? List<*>
                    if (split != null && split.all { it is AnalyzeRule.SourceRule }) {
                        @Suppress("UNCHECKED_CAST")
                        analyzer.getStringList(split as List<AnalyzeRule.SourceRule>,fromJs(args.getOrNull(1)),args.getOrNull(2)==true)
                    } else analyzer.getStringList(arg(args), fromJs(args.getOrNull(1)), args.getOrNull(2) == true)
                }
                function("getElement") { args -> analyzer.getElement(arg(args)) }
                function("getElements") { args -> analyzer.getElements(arg(args)) }
                function("setContent") { args -> analyzer.setContent(fromJs(args.getOrNull(0)), fromJs(args.getOrNull(1))?.toString()); ScriptableObject.getProperty(safe,"java") }
                function("setBaseUrl") { args -> analyzer.setBaseUrl(fromJs(args.firstOrNull())?.toString()); ScriptableObject.getProperty(safe,"java") }
                function("setRedirectUrl") { args -> Context.javaToJS(analyzer.setRedirectUrl(arg(args)),safe) }
                function("splitSourceRule") { args -> analyzer.splitSourceRule(fromJs(args.firstOrNull())?.toString(),args.getOrNull(1)==true) }
                function("evalJS") { args -> analyzer.evalJS(arg(args),fromJs(args.getOrNull(1))) }
                fun refreshBook(search: Boolean) {
                    check(preUpdating) { "书源只能在 preUpdateJs 中调用此方法" }
                    val oldAddress = book["bookUrl"].orEmptyString()
                    var selected = book
                    if (search) {
                        var next: String? = null
                        var found: Map<String, Any?>? = null
                        for (searchPage in 1..64) {
                            val result = BookSourceEngine(source,run).execute("search",next,key=book["name"].orEmptyString(),page=searchPage) as Map<*, *>
                            @Suppress("UNCHECKED_CAST") val rows = result["items"] as? List<Map<String, Any?>> ?: emptyList()
                            found = rows.firstOrNull { it["name"] == book["name"] && it["author"].orEmptyString() == book["author"].orEmptyString() }
                            if (found != null || rows.isEmpty() || result["hasMore"] != true) break
                            next = result["nextUrl"]?.toString()
                        }
                        selected = book + (found ?: error("书源未搜索到对应书名和作者"))
                        run.state.copyRuleVariables("book:${selected["bookUrl"]}", run.state, "book:$oldAddress")
                    }
                    @Suppress("UNCHECKED_CAST")
                    val updated = BookSourceEngine(source,run).execute("detail",selected["bookUrl"].orEmptyString(),book=selected) as Map<String, Any?>
                    book = book + updated
                    if (oldAddress.isNotBlank()) run.state.put("book-resolution",oldAddress,gson.toJson(book))
                    val bound = ScriptableObject.getProperty(safe,"book") as Scriptable
                    for ((name,value) in book) ScriptableObject.putProperty(bound,name,toJs(Context.getCurrentContext(),safe,value))
                }
                function("reGetBook") { refreshBook(true); null }
                function("refreshTocUrl") { refreshBook(false); null }
                function("base64Decode") { args ->
                    val raw = fromJs(args.firstOrNull())?.toString()
                    val flags = args.getOrNull(1) as? Number
                    if (flags != null) org.mewx.wenku8_flutter.legado.SourceTextHelpers.base64Decode(raw, flags = flags.toInt())
                    else cn.hutool.core.codec.Base64.decodeStr(raw, charset((args.getOrNull(1) as? CharSequence)?.toString() ?: "UTF-8"))
                }
                function("base64Encode") { args -> org.mewx.wenku8_flutter.legado.SourceTextHelpers.base64Encode(arg(args), (args.getOrNull(1) as? Number)?.toInt() ?: 2) }
                function("encodeURI") { args ->
                    val value = arg(args); val encoding = args.getOrNull(1)?.let(Context::toString) ?: "UTF-8"
                    try { URLEncoder.encode(value, encoding) } catch (_: UnsupportedEncodingException) { "" }
                }
                function("md5Encode") { args -> MessageDigest.getInstance("MD5").digest(arg(args).toByteArray()).joinToString("") { "%02x".format(it) } }
                function("log") { args -> args.firstOrNull() } // Value passthrough, never a credential-bearing application log.
                function("logType") { args ->
                    val value = args.firstOrNull()
                    val type = when (value) {
                        null -> "null"
                        is Undefined -> "undefined"
                        is org.htmlunit.corejs.javascript.Wrapper -> value.unwrap().javaClass.name
                        is Scriptable -> value.className
                        else -> value.javaClass.name
                    }
                    run.diagnostic?.invoke("script value type: $type")
                    Undefined.instance
                }
                function("toast") { args -> run.notice?.invoke(arg(args), false); Undefined.instance }
                function("longToast") { args -> run.notice?.invoke(arg(args), true); Undefined.instance }
                function("androidId") { _ -> run.installationId }
                function("openUrl") { args ->
                    checkNetworkAccess()
                    (run.openExternal ?: error("书源当前宿主未提供外部应用确认"))(arg(args), fromJs(args.getOrNull(1))?.toString())
                    Undefined.instance
                }
                function("getReadBookConfig") { _ -> gson.toJson(run.appConfig["reader"] ?: emptyMap<String, Any?>()) }
                function("getReadBookConfigMap") { _ -> Context.javaToJS(LinkedHashMap(run.appConfig["reader"] as? Map<*, *> ?: emptyMap<Any, Any>()), safe) }
                function("getThemeMode") { _ -> run.appConfig["themeMode"]?.toString() ?: "0" }
                function("getThemeConfig") { _ -> gson.toJson(run.appConfig["theme"] ?: emptyMap<String, Any?>()) }
                function("getThemeConfigMap") { _ -> Context.javaToJS(LinkedHashMap(run.appConfig["theme"] as? Map<*, *> ?: emptyMap<Any, Any>()), safe) }
                function("upLoginData") { args ->
                    loginUiChanged = true
                    val data = fromJs(args.getOrNull(0)) as? Map<*, *>
                    if (data == null) { loginUiReset = true; loginUiUpdates.clear() }
                    else data.forEach { (name, value) -> loginUiUpdates[name.toString()] = value }
                    null
                }
                function("reLoginView") { _ -> loginUiRebuild = true; null }
                function("refreshExplore") { _ -> refreshExplore = true; null }
                function("randomUUID") { _ -> UUID.randomUUID().toString() }
                function("strToBytes") { args -> arg(args).toByteArray(charset(arg(args, 1).ifEmpty { "UTF-8" })) }
                function("bytesToStr") { args -> (fromJs(args.getOrNull(0)) as ByteArray).toString(charset(arg(args, 1).ifEmpty { "UTF-8" })) }
                function("base64DecodeToByteArray") { args -> org.mewx.wenku8_flutter.legado.SourceTextHelpers.base64Bytes(fromJs(args.firstOrNull())?.toString(), (args.getOrNull(1) as? Number)?.toInt() ?: 0) }
                function("hexDecodeToByteArray") { args -> cn.hutool.core.util.HexUtil.decodeHex(arg(args)) }
                function("hexDecodeToString") { args -> String(cn.hutool.core.util.HexUtil.decodeHex(arg(args))) }
                function("hexEncodeToString") { args -> cn.hutool.core.util.HexUtil.encodeHexStr(arg(args).toByteArray()) }
                function("htmlFormat") { args -> org.mewx.wenku8_flutter.legado.HtmlFormatter.formatKeepImg(arg(args),
                    fromJs(args.getOrNull(1))?.let { runCatching { URL(it.toString()) }.getOrNull() }) }
                function("toURL") { args -> Context.javaToJS(org.mewx.wenku8_flutter.legado.JsURL(arg(args),
                    fromJs(args.getOrNull(1))?.toString()), safe) }
                function("timeFormatUTC") { args -> SimpleDateFormat(arg(args, 1), Locale.getDefault()).apply {
                    timeZone = SimpleTimeZone((Context.jsToJava(args.getOrNull(2) ?: 0, Int::class.javaPrimitiveType) as Number).toInt(), "UTC")
                }.format(Date((Context.jsToJava(args.getOrNull(0), Long::class.javaPrimitiveType) as Number).toLong())) }
                function("timeFormat") { args -> SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault())
                    .format(Date((Context.jsToJava(args.getOrNull(0), Long::class.javaPrimitiveType) as Number).toLong())) }
                function("getWebViewUA") { _ -> run.webUserAgent?.invoke() ?: run.userAgent }
                function("startBrowser") { args ->
                    checkNetworkAccess()
                    (run.openBrowser ?: error("书源当前宿主未提供交互浏览器"))(browserRequest(arg(args), fromJs(args.getOrNull(1))?.toString(), fromJs(args.getOrNull(2))?.toString()))
                    Undefined.instance
                }
                function("startBrowserAwait") { args -> browserAwait(arg(args), fromJs(args.getOrNull(1))?.toString(), args.getOrNull(2) != false, fromJs(args.getOrNull(3))?.toString()) }
                function("showBrowser") { args ->
                    checkNetworkAccess()
                    val config = fromJs(args.getOrNull(3))?.toString()
                    require(config == null || config.length <= 64 * 1024) { "书源浏览器配置过大" }
                    (run.openBrowser ?: error("书源当前宿主未提供交互浏览器"))(browserRequest(arg(args), "书源网页", fromJs(args.getOrNull(1))?.toString(), fromJs(args.getOrNull(2))?.toString())
                        .copy(browserSheet = true, browserConfig = config))
                    Undefined.instance
                }
                function("getVerificationCode") { args -> verificationCode(arg(args)) }
                function("cacheFile") { args -> cachedScript(arg(args), (args.getOrNull(1) as? Number)?.toInt() ?: 0) }
                function("importScript") { args ->
                    checkNetworkAccess()
                    val path = arg(args)
                    (if (path.startsWith("http://", true) || path.startsWith("https://", true)) cachedScript(path, 0)
                    else resources.readText(path)).also { require(it.isNotBlank()) { "书源脚本内容为空" } }
                }
                function("getFile") { args -> checkNetworkAccess(); resources.file(arg(args)) }
                function("readFile") { args -> checkNetworkAccess(); resources.read(arg(args)) }
                function("readTxtFile") { args -> checkNetworkAccess(); resources.readText(arg(args), fromJs(args.getOrNull(1))?.toString()) }
                function("deleteFile") { args -> checkNetworkAccess(); resources.delete(arg(args)) }
                function("downloadFile") { args -> if (args.size > 1) downloadResource(arg(args, 1), arg(args)) else downloadResource(arg(args)) }
                function("unzipFile") { args -> checkNetworkAccess(); resources.unzip(arg(args)) }
                function("unArchiveFile") { args -> checkNetworkAccess(); resources.unzip(arg(args)) }
                function("unrarFile") { args -> checkNetworkAccess(); resources.unzip(arg(args)) }
                function("un7zFile") { args -> checkNetworkAccess(); resources.unzip(arg(args)) }
                function("getTxtInFolder") { args -> checkNetworkAccess(); resources.folderText(arg(args)) }
                function("getZipByteArrayContent") { args -> org.mewx.wenku8_flutter.legado.SourceResources.zipEntry(archiveBytes(arg(args)), arg(args, 1), run::check) }
                function("getZipStringContent") { args ->
                    org.mewx.wenku8_flutter.legado.SourceResources.zipEntry(archiveBytes(arg(args)), arg(args, 1), run::check)
                        ?.let { org.mewx.wenku8_flutter.legado.SourceResources.text(it, fromJs(args.getOrNull(2))?.toString()) }.orEmpty()
                }
                for (format in listOf("Rar", "7z")) {
                    function("get${format}ByteArrayContent") { args -> org.mewx.wenku8_flutter.legado.SourceResources.archiveEntry(archiveBytes(arg(args)), arg(args, 1), run.archiveBackend, run::check) }
                    function("get${format}StringContent") { args ->
                        org.mewx.wenku8_flutter.legado.SourceResources.archiveEntry(archiveBytes(arg(args)), arg(args, 1), run.archiveBackend, run::check)
                            ?.let { org.mewx.wenku8_flutter.legado.SourceResources.text(it, fromJs(args.getOrNull(2))?.toString()) }.orEmpty()
                    }
                }
                function("queryTTF") { args -> checkNetworkAccess(); SourceFonts.query(fromJs(args.getOrNull(0)), args.getOrNull(1) != false, run, ::resourceBytes) }
                function("queryBase64TTF") { args -> checkNetworkAccess(); SourceFonts.query(fromJs(args.getOrNull(0)), true, run, ::resourceBytes) }
                function("replaceFont") { args -> SourceFonts.replace(arg(args), fromJs(args.getOrNull(1)) as? org.mewx.wenku8_flutter.legado.QueryTTF,
                    fromJs(args.getOrNull(2)) as? org.mewx.wenku8_flutter.legado.QueryTTF, args.getOrNull(3) == true, run::check) }
                function("webView") { args ->
                    checkNetworkAccess()
                    run.countRequest()
                    (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(fromJs(args.getOrNull(1))?.toString()?.takeIf { it.isNotBlank() } ?: base,
                        html = arg(args).takeIf { it.isNotBlank() && it != "null" }, script = arg(args, 2).takeIf { it.isNotBlank() && it != "null" },
                        headers = requestHeaders(), cacheFirst = args.getOrNull(3) == true)).body
                }
                function("webViewGetSource") { args ->
                    checkNetworkAccess()
                    run.countRequest()
                    (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(fromJs(args.getOrNull(1))?.toString()?.takeIf { it.isNotBlank() } ?: base,
                        html = arg(args).takeIf { it.isNotBlank() && it != "null" }, script = arg(args, 2).takeIf { it.isNotBlank() && it != "null" },
                        headers = requestHeaders(), sourceRegex = arg(args, 3), cacheFirst = args.getOrNull(4) == true,
                        delay = (args.getOrNull(5) as? Number)?.toLong()?.coerceAtLeast(0) ?: 0)).body
                }
                function("webViewGetOverrideUrl") { args ->
                    checkNetworkAccess()
                    run.countRequest()
                    (run.web ?: error("书源网页脚本服务不可用"))(SourceWebRequest(fromJs(args.getOrNull(1))?.toString()?.takeIf { it.isNotBlank() } ?: base,
                        html = arg(args).takeIf { it.isNotBlank() && it != "null" }, script = arg(args, 2).takeIf { it.isNotBlank() && it != "null" },
                        headers = requestHeaders(), overrideUrlRegex = arg(args, 3), cacheFirst = args.getOrNull(4) == true,
                        delay = (args.getOrNull(5) as? Number)?.toLong()?.coerceAtLeast(0) ?: 0)).body
                }
                function("getCookie") { args -> run.cookieRead(arg(args)).let { cookies ->
                    if (arg(args, 1).isBlank()) cookies else cookies.split(';').firstOrNull { it.trim().startsWith("${arg(args, 1)}=") }?.substringAfter('=')?.trim().orEmpty()
                } }
                val crypto = Context.javaToJS(org.mewx.wenku8_flutter.legado.SourceCrypto(), safe) as Scriptable
                for (name in org.mewx.wenku8_flutter.legado.JsEncodeUtils::class.java.methods.map { it.name }.toSet()) {
                    val method = ScriptableObject.getProperty(crypto, name) as? org.htmlunit.corejs.javascript.Function ?: continue
                    ScriptableObject.putProperty(java, name, object : BaseFunction(safe, ScriptableObject.getFunctionPrototype(safe)) {
                        override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? {
                            run.check(); return method.call(cx, safe, crypto, args)
                        }
                    })
                }
                fun objectFunctions(name: String, functions: Map<String, (Array<out Any>) -> Any?>) {
                    val obj = cx.newObject(safe)
                    for ((key, action) in functions) ScriptableObject.putProperty(obj, key, object : BaseFunction(safe, ScriptableObject.getFunctionPrototype(safe)) {
                        override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? {
                            run.check(); return toJs(cx, safe, action(args))
                        }
                    })
                    ScriptableObject.putProperty(safe, name, obj)
                }
                objectFunctions("cookie", mapOf(
                    "getCookie" to { args -> run.cookieRead(arg(args)) },
                    "setCookie" to { args -> run.cookieWrite(arg(args), arg(args, 1)); null },
                    "replaceCookie" to { args -> run.cookieRemove(arg(args)); run.cookieWrite(arg(args), arg(args, 1)); null },
                    "removeCookie" to { args -> run.cookieRemove(arg(args)); null },
                    "getKey" to { args -> run.cookieRead(arg(args)).split(';').firstOrNull { it.trim().startsWith("${arg(args, 1)}=") }?.substringAfter('=')?.trim().orEmpty() },
                ))
                objectFunctions("cache", mapOf(
                    "get" to { args -> cacheValue(arg(args), args.getOrNull(1) == true) },
                    "put" to { args ->
                        val seconds = (args.getOrNull(2) as? Number)?.toLong() ?: 0
                        val value = fromJs(args.getOrNull(1))
                        if (value is ByteArray) cachePut("cache-bytes", arg(args), Base64.getEncoder().encodeToString(value), seconds)
                        else { cachePut("cache", arg(args), arg(args, 1), seconds)
                            if (seconds == 0L) run.state.putMemory(arg(args), arg(args, 1)) else run.state.deleteMemory(arg(args)) }; null },
                    "getInt" to { args -> (run.state.memory(arg(args)) as? Int) ?: cacheValue(arg(args), true)?.toIntOrNull() },
                    "getLong" to { args -> (run.state.memory(arg(args)) as? Long) ?: cacheValue(arg(args), true)?.toLongOrNull() },
                    "getDouble" to { args -> (run.state.memory(arg(args)) as? Double) ?: cacheValue(arg(args), true)?.toDoubleOrNull() },
                    "getFloat" to { args -> (run.state.memory(arg(args)) as? Float) ?: cacheValue(arg(args), true)?.toFloatOrNull() },
                    "getByteArray" to { args -> cacheValue(arg(args), true, "cache-bytes")?.let { Base64.getDecoder().decode(it) } },
                    "putFile" to { args -> cachePut("cache-file", arg(args), arg(args, 1), (args.getOrNull(2) as? Number)?.toLong() ?: 0); null },
                    "getFile" to { args -> cacheValue(arg(args), true, "cache-file") },
                    "putMemory" to { args -> args.getOrNull(1)?.let { run.state.putMemory(arg(args), if (it is org.htmlunit.corejs.javascript.Wrapper) it.unwrap() else it) }; null },
                    "getFromMemory" to { args -> run.state.memory(arg(args))?.also { run.metrics.cacheHits.incrementAndGet() } },
                    "deleteMemory" to { args -> run.state.deleteMemory(arg(args)); null },
                    "delete" to { args -> for (area in listOf("cache", "cache-bytes", "cache-file")) {
                        run.state.remove(area, arg(args)); run.state.remove("$area-expiry", arg(args))
                    }; run.state.deleteMemory(arg(args)); null },
                ))
                val jsoup = cx.newObject(safe)
                ScriptableObject.putProperty(jsoup, "parse", object : BaseFunction(safe, ScriptableObject.getFunctionPrototype(safe)) {
                    override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any =
                        Context.javaToJS(Jsoup.parse(arg(args), arg(args, 1)), safe)
                })
                val namespace = cx.newObject(safe); ScriptableObject.putProperty(namespace, "Jsoup", jsoup)
                val org = cx.newObject(safe); ScriptableObject.putProperty(org, "jsoup", namespace)
                ScriptableObject.putProperty(safe, "org", org)
                ScriptableObject.putProperty(safe, "java", java)
                ScriptableObject.defineProperty(safe, "__sourceJavaHelpers", java,
                    ScriptableObject.DONTENUM or ScriptableObject.READONLY or ScriptableObject.PERMANENT)
            }
            currentResult = result
            val bindings = mapOf("result" to result, "src" to content, "baseUrl" to baseUrl,
                "key" to key, "page" to page, "searchPage" to page,
                "source" to source, "book" to book, "chapter" to chapter, "title" to chapter["title"]) + extraBindings
            for ((name, value) in bindings) ScriptableObject.putProperty(target, name, toJs(cx, target, value))
            installEntityBindings(cx, target)
            if (javaUsesSource) ScriptableObject.putProperty(target, "java", ScriptableObject.getProperty(target, "sourceApi"))
            libraryLoaded = true
            val value = evaluateScript(cx, target, code, "source-rule")
            captureEntity(target, "book", true)
            captureEntity(target, "chapter", false)
            if (value is Undefined) null else value
            } finally {
                restoreTarget?.let { previous -> restoreBindings?.forEach { (name, value) ->
                    if (value === Scriptable.NOT_FOUND) previous.delete(name) else ScriptableObject.putProperty(previous, name, value)
                }; currentResult = previousResult }
                runtime.recursiveCount--
            }
        }
    }
    private fun cacheValue(key: String, diskOnly: Boolean = false, area: String = "cache"): String? {
        if (!diskOnly && area == "cache") (run.state.memory(key) as? String)?.let { return it }
        val expiry = run.state.get("$area-expiry", key).toLongOrNull()
        if (expiry != null && expiry <= System.currentTimeMillis() || !run.state.contains(area, key)) return null
        return run.state.get(area, key)
    }
    private fun cachePut(area: String, key: String, value: String, seconds: Long) {
        run.state.put(area, key, value)
        if (seconds == 0L) run.state.remove("$area-expiry", key)
        else run.state.put("$area-expiry", key, "${System.currentTimeMillis() + seconds * 1000}")
    }
    private fun toJs(cx: Context, scope: VarScope, value: Any?): Any? = when (value) {
        is Scriptable -> value
        is SourceReply -> Context.javaToJS(SourceResponse(value), scope)
        is SourceResponse, is SourceJsoupResponse, is ByteArray -> Context.javaToJS(value, scope)
        is org.mewx.wenku8_flutter.legado.QueryTTF, is org.mewx.wenku8_flutter.legado.SourceScriptFile -> Context.javaToJS(value, scope)
        is org.jsoup.nodes.Node -> Context.javaToJS(value, scope)
        is Array<*> -> cx.newArray(scope, value.map { toJs(cx, scope, it) }.toTypedArray())
        is List<*> -> Context.javaToJS(java.util.ArrayList<Any?>(value), scope)
        is Map<*, *> -> cx.newObject(scope).also { obj -> value.forEach { (k, v) -> ScriptableObject.putProperty(obj, k.toString(), toJs(cx, scope, v)) } }
        else -> value
    }
    private fun fromJs(value: Any?, depth: Int = 0): Any? {
        require(depth < 32) { "脚本结果嵌套过深" }
        return when (value) {
            null, is Undefined -> null
            is org.htmlunit.corejs.javascript.Wrapper -> fromJs(value.unwrap(), depth + 1)
            is org.htmlunit.corejs.javascript.NativeArray -> {
                require(value.length <= 100000)
                (0 until value.length.toInt()).map { fromJs(value.get(it, value), depth + 1) }
            }
            is Scriptable -> value.ids.associate { id -> id.toString() to fromJs(ScriptableObject.getProperty(value, id.toString()), depth + 1) }
            is CharSequence -> value.toString().also { require(it.length <= 4 * 1024 * 1024) }
            else -> value
        }
    }
    private fun responseFromJs(value: Any?, fallback: SourceReply): SourceReply = when (val raw = fromJs(value)) {
        is SourceResponse -> raw.reply()
        is SourceReply -> raw
        else -> throw IllegalStateException("书源 loginCheckJs 必须返回响应对象")
    }
    private fun inlineScript(value: String): String {
        val matcher = org.mewx.wenku8_flutter.legado.JS_PATTERN.matcher(value.trim())
        return if (matcher.matches()) matcher.group(2) ?: matcher.group(1) else value
    }
    private fun callMain(name: String, args: Map<String, Any?>, optional: Boolean = false): Any? {
        val missing = if (optional) "null" else "(function(){throw new Error('书源 JS 缺少函数 $name')})()"
        val result = scriptValue("${mainScript ?: error("书源 mainJs 为空")}\n" +
            "(function(__inputBook){var __value=typeof $name==='function'?$name(${args.keys.joinToString(",")}):$missing;" +
            "return {value:__value,book:__inputBook};})(book)", args)
        val output = SourceLoginUi.objectValue(result, "书源 JS 函数结果无效")
        @Suppress("UNCHECKED_CAST")
        (output["book"] as? Map<String, Any?>)?.let { book = it }
        return output["value"]
    }
    private fun scriptMap(raw: Any?, stage: String) = SourceLoginUi.objectValue(raw, "书源 JS $stage 必须返回对象")
    private fun scriptVariables(raw: Any?, owner: String) {
        val value = if (raw is String) runCatching { gson.fromJson(raw, Map::class.java) }.getOrNull() else raw
        if (value is Map<*, *>) {
            run.state.put("entity-variable", owner, "1")
            for ((key, v) in value) run.state.putRuleVariable(owner, key.toString(), v?.toString())
        }
    }
    private fun executeScriptBook(operation: String, url: String?): Any = when (operation) {
        "search", "explore" -> {
            val args = if (operation == "search") linkedMapOf("key" to key, "page" to page)
                else linkedMapOf("url" to url.orEmpty(), "page" to page)
            val raw = callMain(operation, args)
            val model = scriptSource()
            val decoded = com.google.gson.JsonParser.parseString(scriptJson(raw))
            val metadata = if (decoded.isJsonObject) decoded.asJsonObject else null
            require(metadata == null || metadata.get("items")?.isJsonArray == true &&
                metadata.get("hasMore")?.isJsonPrimitive == true && metadata.get("hasMore").asJsonPrimitive.isBoolean) { "书源分页结果缺少 items 或 hasMore" }
            val rows = JsSourceMarshaller.parseSearchBooks((metadata?.get("items") ?: decoded).toString(), model)
            require(rows.size <= 1000) { "书源 JS 单页书目超过 1000 项" }
            val items = rows.filter { it.type and 8 != 0 && it.type and (4 or 32 or 64 or 128) == 0 }.map { row ->
                val value = scriptMap(gson.toJson(row), operation)
                scriptVariables(row.variable, "book:${row.bookUrl}")
                saveEntity(value, true)
                (value - "variable") + mapOf("author" to SourceDocumentMetadata.authorName(row.author),
                    "lastChapter" to row.latestChapterTitle.orEmpty())
            }
            fun cursor(name: String) = metadata?.get(name)?.takeUnless { it.isJsonNull }?.asString
            mapOf("items" to items, "hasMore" to (metadata?.get("hasMore")?.asBoolean ?: rows.isNotEmpty()),
                "pageUrl" to (cursor("pageUrl") ?: url), "nextUrl" to cursor("nextUrl"))
        }
        "epub" -> {
            val address = callMain("getEpub", mapOf("book" to book)) as String
            val plan = prepareRequest(address, callTimeout = 120000)
            val reply = fetchPlan(plan.copy(options = plan.options.copy(timeout = 120000, maxResponseBytes = 32 * 1024 * 1024)), download = true)
            if (reply.status !in 200..299) {
                reply.file?.let { java.io.File(it).delete() }
                error("文库卷册下载未完成（HTTP ${reply.status}）")
            }
            mapOf("path" to (reply.file ?: error("文库卷册缺少文件内容")))
        }
        "detail" -> {
            val value = callMain("getBookInfo", mapOf("book" to book), optional = true)
            val model = scriptSource()
            val target = gson.fromJson(gson.toJson(book.filterValues { it != null }), ScriptBook::class.java)
            if (book["type"] == null) target.type = model.getBookType()
            JsSourceMarshaller.mergeBookInfo(target, scriptJson(value), model, true)
            require(target.type and 8 != 0 && target.type and (4 or 32 or 64 or 128) == 0) { "书源返回非小说内容，本版仅支持文本小说" }
            val details = scriptMap(gson.toJson(target), "getBookInfo")
            val address = url ?: target.bookUrl
            scriptVariables(target.variable, "book:$address")
            saveEntity(details + ("bookUrl" to address), true)
            (details - "downloadUrls" - "variable") + mapOf("bookUrl" to address, "tocUrl" to target.tocUrl.ifBlank { address },
                "author" to SourceDocumentMetadata.authorName(target.author), "lastChapter" to target.latestChapterTitle.orEmpty())
        }
        "toc" -> {
            val raw = callMain("getChapters", mapOf("book" to book))
            val model = scriptSource()
            val target = gson.fromJson(gson.toJson(book.filterValues { it != null }), ScriptBook::class.java).also { if (it.tocUrl.isBlank()) it.tocUrl = url.orEmpty() }
            val rows = JsSourceMarshaller.parseChapters(scriptJson(raw), target, model)
            require(rows.size <= 100000) { "书源 JS 目录超过 100000 章" }
            var volume = ""
            rows.map { row ->
                if (row.isVolume) volume = row.title
                scriptVariables(row.variable, "chapter:${row.url}")
                val metadata = scriptMap(gson.toJson(row), "getChapters")
                saveEntity(metadata, false)
                (metadata - "variable") + mapOf("name" to row.title, "volumeTitle" to volume)
            }
        }
        "content" -> {
            val value = callMain("getContent", linkedMapOf("chapter" to chapter, "book" to book,
                "nextChapterUrl" to chapter["nextChapterUrl"]))
            val contentBase = ((source["engine"] as? Map<*, *>)?.get("content") as? Map<*, *>)?.get("baseUrl") as? String ?: url ?: base
            val text = string(if (value is Map<*, *>) value["content"] else value).also { require(it.length <= 4 * 1024 * 1024) { "单章正文超过 4 MiB" } }
            val body = if (text.contains(Regex("<(?:p|div|br|img|span)\\b", RegexOption.IGNORE_CASE))) {
                val formatted = org.mewx.wenku8_flutter.legado.HtmlFormatter.formatKeepImg(text, URL(contentBase))
                SourceImageMarkup.readerImages(org.mewx.wenku8_flutter.legado.HtmlFormatter.readerImages(org.apache.commons.text.StringEscapeUtils.unescapeHtml4(formatted)) {
                    absolute(it, contentBase)
                }) { absolute(it, contentBase) }.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n")
            } else SourceImageMarkup.readerImages(text) { absolute(it, contentBase) }
            if (value is Map<*, *>) mapOf("text" to body, "font" to sourceFontBytes(value["fontUrl"] as String)) else body
        }
        else -> error("书源 JS 操作不支持")
    }
    private fun scriptJson(value: Any?): String? = when (value) {
        null -> null
        is String -> value
        else -> gson.toJson(value)
    }
    private fun inspectScript(text: String): Map<String, Any?> {
        require(text.length <= 1024 * 1024) { "脚本超过 1 MiB" }
        val raw = scriptValue(text + "\n(function(){" +
            "var c=typeof config==='object'&&config!==null&&config.bookSourceUrl&&config.bookSourceName?config:" +
            "typeof source==='object'?source:null;" +
            "if(!c||!c.bookSourceUrl||!c.bookSourceName)throw new Error('书源 JS 缺少 config 配置');" +
            "if(typeof search!=='function')throw new Error('书源 JS 缺少函数 search');" +
            "if(typeof getChapters!=='function')throw new Error('书源 JS 缺少函数 getChapters');" +
            "if(typeof getContent!=='function')throw new Error('书源 JS 缺少函数 getContent');" +
            "if((c.exploreUrl||Array.isArray(c.homeSections)&&c.homeSections.some(function(s){return !s.operation||s.operation==='explore';}))&&typeof explore!=='function')throw new Error('书源 JS 缺少 explore 函数');" +
            "var out=JSON.parse(JSON.stringify(c));" +
            "if(typeof loginUi==='function'){if(out.loginUi)throw new Error('书源 JS 重复声明 loginUi');" +
            "if(typeof loginAction!=='function')throw new Error('书源 JS 缺少 loginAction');out.loginUi='{\"version\":2}';}" +
            "return out;})()", emptyMap())
        val config = scriptMap(raw, "config").toMutableMap()
        for (name in listOf("ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview")) config.remove(name)
        for (name in listOf("exploreUrl", "loginUi")) if (config[name] is List<*>) config[name] = gson.toJson(config[name])
        config["mainJs"] = text
        return config
    }
    private fun loginUi(): Map<String, Any?> {
        if (SourceLoginUi.isV2(source["loginUi"])) {
            val state = book["loginState"] as? Map<*, *> ?: emptyMap<String, Any?>()
            return renderLoginV2(state)
        }
        val raw = source["loginUi"]?.toString()?.trim().orEmpty()
        val json = if (raw.startsWith("@js:", true) || raw.startsWith("<js>", true)) {
            val code = loginScript() + "\n" + inlineScript(raw)
            val result = fromJs(js(code, null))
            if (result is String) result else gson.toJson(result)
        } else raw
        val rows = if (json.isBlank()) emptyList<Any>() else gson.fromJson(json, List::class.java)
        check(rows.size <= 200) { "书源登录表单超过 200 项" }
        var info = run.state.get("login", "info")
        if (info.isBlank()) {
            info = gson.toJson(rows.filterIsInstance<Map<*, *>>().filter { it["type"] != "button" }
                .associate { it["name"].toString() to (it["default"]?.toString()
                    ?: (it["chars"] as? List<*>)?.firstOrNull()?.toString() ?: "") })
            run.state.put("login", "info", info)
        }
        val fields = gson.fromJson(info, Map::class.java).entries.associate { it.key.toString() to it.value }.toMutableMap()
        if (loginUiChanged) {
            for (row in rows.filterIsInstance<Map<*, *>>()) {
                val name = row["name"]?.toString().orEmpty()
                if (row["type"] == "button") continue
                val fallback = row["default"] ?: (row["chars"] as? List<*>)?.firstOrNull() ?: ""
                if (loginUiReset) fields[name] = fallback
                if (loginUiUpdates.containsKey(name)) fields[name] = loginUiUpdates[name] ?: fallback
            }
            run.state.put("login", "info", gson.toJson(fields))
        }
        val prepared = rows.filterIsInstance<Map<*, *>>().map { row ->
            val name = row["name"]?.toString().orEmpty()
            val viewName = row["viewName"]?.toString()
            val callbackLabel = if (row["type"] == "button" && loginUiUpdates.containsKey(name)) loginUiUpdates[name]?.toString() ?: row["default"]?.toString() else null
            val label = callbackLabel ?: if (viewName.isNullOrBlank()) name else if (viewName.startsWith("'") && viewName.endsWith("'")) viewName.substring(1, viewName.length - 1)
                else string(js("${loginScript()}\n$viewName", fields))
            row.entries.associate { it.key.toString() to it.value } + ("label" to label)
        }
        return mapOf("rows" to prepared, "info" to fields,
            "webUrl" to (source["loginUrl"]?.toString()?.takeIf { it.startsWith("http") }
                ?: ((source["engine"] as? Map<*, *>)?.get("login") as? Map<*, *>)?.get("webUrl")))
    }
    private fun loginScript(): String = mainScript ?: source["loginUrl"]?.toString().orEmpty().let {
        if (it.startsWith("http")) "" else inlineScript(it)
    }
    private fun isolatedScriptValue(code: String, bindings: Map<String, Any?> = emptyMap()): Any? {
        val previousScope = scope; val previousLibrary = libraryLoaded
        val previousBindings = extraBindings; val previousResult = currentResult
        val previousJava = javaUsesSource
        try { javaUsesSource = true; return scriptValue(code, mapOf("book" to null, "chapter" to null,
            "baseUrl" to source["bookSourceUrl"].orEmptyString()) + bindings) }
        finally { scope = previousScope; libraryLoaded = previousLibrary; extraBindings = previousBindings; currentResult = previousResult; javaUsesSource = previousJava }
    }
    private fun savedLoginInfo(): Map<String, Any?> {
        val saved = run.state.get("login", "info")
        if (saved.isNotBlank()) return gson.fromJson(saved, Map::class.java).entries.associate { it.key.toString() to it.value }
        if (initializingLoginInfo || SourceLoginUi.isV2(source["loginUi"])) return emptyMap()
        val raw = source["loginUi"]?.toString()?.takeIf { it.isNotBlank() } ?: return emptyMap()
        initializingLoginInfo = true
        try {
            val value = if (raw.trim().startsWith("@js:", true) || raw.trim().startsWith("<js>", true)) {
                isolatedScriptValue(loginScript() + "\n" + inlineScript(raw), mapOf("result" to emptyMap<String, Any?>()))
            } else raw
            val rows = if (value is String) gson.fromJson(value, List::class.java) else value as? List<*>
            val defaults = rows.orEmpty().filterIsInstance<Map<*, *>>().filter { it["type"] != "button" }
                .associate { it["name"].toString() to (it["default"] ?: "") }
            if (defaults.isNotEmpty()) run.state.put("login", "info", gson.toJson(defaults))
            return defaults
        } finally { initializingLoginInfo = false }
    }
    private fun scriptValue(code: String, bindings: Map<String, Any?>): Any? {
        // Upstream JsSourceEngine builds a fresh scope for each entry point.
        // Do not leak lexical variables from loginAction into loginUi rendering.
        scope = null
        libraryLoaded = false
        extraBindings = bindings
        try {
            val raw = js(code, null)
            return factory.call { cx ->
                val unwrapped = if (raw is org.htmlunit.corejs.javascript.Wrapper) raw.unwrap() else raw
                when (unwrapped) {
                    null, is Undefined -> null
                    is CharSequence -> unwrapped.toString()
                    is Scriptable -> org.htmlunit.corejs.javascript.NativeJSON.stringify(cx, scope, unwrapped, null, null)
                        ?.let { gson.fromJson(it.toString(), Any::class.java) }
                    else -> unwrapped
                }
            }
        } finally { extraBindings = emptyMap() }
    }
    private fun renderLoginV2(state: Map<*, *>): Map<String, Any?> {
        val rows = SourceLoginUi.rows(scriptValue("${loginScript()}\nloginUi(__loginState)", mapOf("__loginState" to state)))
        return mapOf("version" to 2, "rows" to rows, "state" to state,
            "info" to gson.fromJson(run.state.get("login", "info").ifEmpty { "{}" }, Map::class.java), "webUrl" to null)
    }
    private fun loginActionV2(action: String, input: Map<String, Any?>): Map<String, Any?> {
        val state = input["loginState"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val form = input["loginInfo"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val command = SourceLoginUi.command(scriptValue("${loginScript()}\nloginAction(__loginAction, __loginState, __loginForm)",
            mapOf("__loginAction" to action, "__loginState" to state, "__loginForm" to form)))
        command["login"]?.let { run.state.put("login", "info", gson.toJson(it)) }
        if (command["close"] == true) return command + ("version" to 2)
        val nextState = command["state"] as? Map<*, *>
        return (if (nextState != null) renderLoginV2(nextState) else mapOf("version" to 2)) + command
    }
    fun loginWebRequest(): SourceWebRequest {
        val login = (source["engine"] as? Map<*, *>)?.get("login") as? Map<*, *>
        val url = login?.get("webUrl") as? String ?: source["loginUrl"]?.toString().orEmpty()
        require(url.startsWith("http")) { "书源没有提供网页登录地址" }
        return SourceWebRequest(url, headers = requestHeaders(), interactive = true,
            thirdPartyCookies = login?.get("thirdPartyCookies") == true)
    }
    private fun installEntityBindings(cx: Context, target: TopLevel) {
        fun add(obj: Scriptable, name: String, work: (Array<out Any>) -> Any?) {
            val fn = object : BaseFunction(target, ScriptableObject.getFunctionPrototype(target)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? {
                    run.check(); return toJs(cx, target, work(args))
                }
            }
            ScriptableObject.defineProperty(obj, name, fn, ScriptableObject.DONTENUM)
        }
        fun arg(args: Array<out Any>, index: Int = 0) = args.getOrNull(index)?.let(Context::toString).orEmpty()
        fun scriptingMap(values: Map<String, Any?>): Scriptable {
            val obj = toJs(cx, target, values) as Scriptable
            fun get(name: String): Any? = ScriptableObject.getProperty(obj, name).takeUnless { it === Scriptable.NOT_FOUND }
            add(obj, "get") { args -> get(arg(args)) }
            add(obj, "put") { args -> val old = get(arg(args)); ScriptableObject.putProperty(obj, arg(args), args.getOrNull(1)); old }
            add(obj, "containsKey") { args -> ScriptableObject.hasProperty(obj, arg(args)) }
            add(obj, "remove") { args -> val old = get(arg(args)); ScriptableObject.deleteProperty(obj, arg(args)); old }
            add(obj, "size") { obj.ids.size }
            add(obj, "isEmpty") { obj.ids.isEmpty() }
            add(obj, "keySet") { obj.ids.map { it.toString() } }
            return obj
        }
        val obj = ScriptableObject.getProperty(target, "source") as Scriptable
        fun ruleValue(field: String, create: Boolean = false): Any? {
            if (source[field] !is Map<*, *>) {
                if (!create) return null
                source[field] = emptyMap<String, Any?>()
            }
            val value = cx.newObject(target) as ScriptableObject
            val fields = ruleFields[field].orEmpty() + (source[field] as Map<*, *>).keys.map { it.toString() }
            for (name in fields) {
                fun read() = (source[field] as? Map<*, *>)?.get(name)
                fun write(raw: Any?) {
                    @Suppress("UNCHECKED_CAST")
                    val data = source[field] as? MutableMap<String,Any?> ?: mutableMapOf<String,Any?>().also { source[field] = it }
                    data[name] = fromJs(raw)
                }
                val descriptor = cx.newObject(target) as ScriptableObject
                ScriptableObject.putProperty(descriptor, "get", object : BaseFunction(target, ScriptableObject.getFunctionPrototype(target)) {
                    override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { run.check(); return toJs(cx,target,read()) }
                })
                ScriptableObject.putProperty(descriptor, "set", object : BaseFunction(target, ScriptableObject.getFunctionPrototype(target)) {
                    override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { run.check(); write(args.firstOrNull()); return Undefined.instance }
                })
                ScriptableObject.putProperty(descriptor,"enumerable",true);value.defineOwnProperty(cx,name,descriptor)
                val suffix = name.replaceFirstChar { it.uppercaseChar() }
                add(value,"get$suffix") { read() };add(value,"set$suffix") { args -> write(args.firstOrNull()); null }
            }
            return value
        }
        fun sourceValue(field: String) = if (field in ruleFields) ruleValue(field) else source[field]
        // Source properties and their Java-style accessors refer to one live
        // definition within this run; rules may adjust headers or endpoints.
        for (field in sourceFields) {
            val descriptor = cx.newObject(target) as ScriptableObject
            ScriptableObject.putProperty(descriptor, "get", object : BaseFunction(target, ScriptableObject.getFunctionPrototype(target)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { run.check(); return toJs(cx, target, sourceValue(field)) }
            })
            ScriptableObject.putProperty(descriptor, "set", object : BaseFunction(target, ScriptableObject.getFunctionPrototype(target)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { run.check(); source[field] = fromJs(args.firstOrNull()); return Undefined.instance }
            })
            ScriptableObject.putProperty(descriptor, "enumerable", true)
            (obj as ScriptableObject).defineOwnProperty(cx, field, descriptor)
            val suffix = field.replaceFirstChar { it.uppercaseChar() }
            add(obj, "get$suffix") { sourceValue(field) }
            add(obj, "set$suffix") { args -> source[field] = fromJs(args.firstOrNull()); Undefined.instance }
        }
        // BaseSource inherits JsExtensions. These are the same helpers, not a
        // separate subset with different response or cache semantics.
        val javaApi = ScriptableObject.getProperty(target, "__sourceJavaHelpers") as Scriptable
        for (id in javaApi.ids) ScriptableObject.defineProperty(obj, id.toString(),
            ScriptableObject.getProperty(javaApi, id.toString()), ScriptableObject.DONTENUM)
        add(obj, "getSource") { obj }
        add(obj, "getKey") { source["bookSourceUrl"] ?: "" }
        add(obj, "getTag") { source["bookSourceName"] ?: "" }
        for ((alias, field) in mapOf("Search" to "ruleSearch", "Explore" to "ruleExplore", "BookInfo" to "ruleBookInfo", "Toc" to "ruleToc", "Content" to "ruleContent")) {
            add(obj,"get${alias}Rule") { ruleValue(field, true) }
        }
        add(obj,"isJsSource") { !mainScript.isNullOrBlank() }
        add(obj,"getDisPlayNameGroup") { source["bookSourceName"].orEmptyString() + source["bookSourceGroup"].orEmptyString().takeIf { it.isNotBlank() }?.let { " ($it)" }.orEmpty() }
        add(obj,"getDisplayVariableComment") { args -> source["variableComment"].orEmptyString().takeIf { it.isNotBlank() }?.let { "$it\n${arg(args)}" } ?: arg(args) }
        add(obj,"getCheckKeyword") { args -> (source["ruleSearch"] as? Map<*, *>)?.get("checkKeyWord")?.toString()?.takeIf {
            it.isNotBlank() && !it.contains("http") && !it.contains("::") && !it.contains("++") && !it.contains("--") } ?: arg(args) }
        add(obj, "hasLoginForm") { source["loginUi"].orEmptyString().filterNot { it.isWhitespace() }.let { it.isNotEmpty() && it != "[]" } }
        add(obj, "hasLogin") { !source["loginUrl"].orEmptyString().isBlank() || source["loginUi"].orEmptyString().filterNot { it.isWhitespace() }.let { it.isNotEmpty() && it != "[]" } }
        add(obj, "getLoginJs") { mainScript ?: source["loginUrl"]?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let(::inlineScript) }
        add(obj, "getLoginUiJs") { source["loginUi"]?.toString()?.trim()?.takeIf { it.startsWith("@js:", true) || it.startsWith("<js>", true) }?.let(::inlineScript) }
        add(obj, "isLoginUiV2") { SourceLoginUi.isV2(source["loginUi"]) }
        add(obj, "evalLoginUiV2") { args -> gson.toJson(SourceLoginUi.rows(isolatedScriptValue(loginScript() + "\nloginUi(JSON.parse(String(__loginState)))", mapOf("__loginState" to arg(args))))) }
        add(obj, "evalLoginActionV2") { args -> gson.toJson(SourceLoginUi.command(isolatedScriptValue(loginScript() + "\nloginAction(String(__loginAction),JSON.parse(String(__loginState)),JSON.parse(String(__loginForm)))",
            mapOf("__loginAction" to arg(args), "__loginState" to arg(args, 1), "__loginForm" to arg(args, 2))))) }
        add(obj, "get") { args -> if (args.size < 2) run.state.get("source", arg(args))
            else directRequest(arg(args), "GET", scriptHeaders(fromJs(args.getOrNull(1))), null, (args.getOrNull(2) as? Number)?.toLong()) }
        add(obj, "put") { args -> run.state.put("source", arg(args), arg(args, 1)) }
        add(obj, "getVariable") { run.state.get("source", "__variable") }
        fun putSourceVariable(args: Array<out Any>): Any? {
            val raw = fromJs(args.firstOrNull())
            if (raw == null) run.state.remove("source", "__variable") else run.state.put("source", "__variable", raw.toString())
            return null
        }
        add(obj, "putVariable", ::putSourceVariable)
        add(obj, "setVariable", ::putSourceVariable)
        add(obj, "getLoginInfo") { run.state.get("login", "info").ifEmpty { null } }
        add(obj, "getLoginInfoMap") { scriptingMap(savedLoginInfo()) }
        add(obj, "putLoginInfo") { args ->
            val raw = fromJs(args.getOrNull(0)); val text = if (raw is String) raw else gson.toJson(raw)
            require(gson.fromJson(text, Map::class.java) != null) { "书源登录信息必须为 JSON 对象" }
            run.state.put("login", "info", text); true
        }
        add(obj, "removeLoginInfo") { run.state.remove("login", "info"); null }
        add(obj, "getLoginHeader") { run.state.get("login", "header").ifEmpty { null } }
        add(obj, "getLoginHeaderMap") { scriptingMap(headerMap(run.state.get("login", "header"))) }
        add(obj, "putLoginHeader") { args ->
            val raw = fromJs(args.getOrNull(0)); val text = if (raw is String) raw else gson.toJson(raw)
            val headers = headerMap(text)
            headers.entries.firstOrNull { it.key.equals("Cookie", true) }?.let { run.cookieWrite(source["bookSourceUrl"].toString(), it.value) }
            run.state.put("login", "header", text); null
        }
        add(obj, "removeLoginHeader") { run.state.remove("login", "header"); run.cookieRemove(source["bookSourceUrl"].toString()); null }
        add(obj, "getHeaderMap") { args -> scriptingMap(if (args.getOrNull(0) == true) requestHeaders() else headerMap(source["header"]).apply {
            if (keys.none { it.equals("User-Agent", true) }) put("User-Agent", run.userAgent)
        }) }
        add(obj, "login") { if (loginScript().isNotBlank()) isolatedScriptValue(loginScript() + "\nif(typeof login==='function'){login.apply(this)}else{throw 'Function login not implements!!!'}"); Undefined.instance }
        add(obj, "evalJS") { args -> isolatedScriptValue(arg(args), (fromJs(args.getOrNull(1)) as? Map<*, *>)
            ?.entries?.associate { it.key.toString() to it.value } ?: emptyMap()) }
        add(obj, "refreshJSLib") { run.state.clear("library"); SourceScriptScopes.refresh(source["jsLib"].orEmptyString().trim()); null }
        add(obj, "refreshExplore") { refreshExplore = true; null }
        add(obj, "putConcurrent") { args -> run.state.put("source", "__concurrentRate", arg(args)) }
        ScriptableObject.putProperty(target, "sourceApi", obj)
        for ((name, data, isBook) in listOf(Triple("book", book, true), Triple("chapter", chapter, false))) {
            val entity = ScriptableObject.getProperty(target, name) as? Scriptable ?: continue
            val rowState = rowVariables?.takeIf { rowEntity == name }
            val owner = if (rowState != null) "row" else (if (isBook) "book:" else "chapter:") + data[if (isBook) "bookUrl" else "url"].orEmptyString()
            SourceEntity.install(cx, target, entity, isBook, owner, rowState ?: run.state, run::check,
                plain = { fromJs(it) }, persist = { captureEntity(target, name, isBook); saveEntity(if (isBook) book else chapter, isBook) },
                toJs = { toJs(cx, target, it) })
        }
    }
    private fun hydrateEntity(data: Map<String, Any?>, isBook: Boolean): Map<String, Any?> {
        val address = data[if (isBook) "bookUrl" else "url"]?.toString().orEmpty()
        val saved = run.state.get(if (isBook) "book-metadata" else "chapter-metadata", address).takeIf { it.isNotBlank() }
            ?.let { gson.fromJson(it, Map::class.java).entries.associate { it.key.toString() to it.value } }.orEmpty()
        val resolution = if (isBook) run.state.get("book-resolution",address).takeIf { it.isNotBlank() }
            ?.let { gson.fromJson(it,Map::class.java).entries.associate { row -> row.key.toString() to row.value } }.orEmpty() else emptyMap()
        val fields = (if (isBook) SourceEntity.bookDefaults else SourceEntity.chapterDefaults) + saved + data.filterValues { it != null } + resolution
        // The UI's readable chapter array omits volume headings. Scripts retain
        // the parsed upstream chapter index, rather than that display index.
        return if (!isBook && saved.containsKey("index")) fields + ("index" to saved["index"]) else fields
    }
    private fun saveEntity(data: Map<String, Any?>, isBook: Boolean) {
        val address = data[if (isBook) "bookUrl" else "url"]?.toString().orEmpty()
        if (address.isBlank()) return
        val defaults = if (isBook) SourceEntity.bookDefaults else SourceEntity.chapterDefaults
        val fields = defaults.keys
        val metadata = data.filter { (key, value) -> key in fields && key != (if (isBook) "bookUrl" else "url") &&
            (if (value is Number && defaults[key] is Number) value.toDouble() != (defaults[key] as Number).toDouble() else value != defaults[key]) }
        run.state.put(if (isBook) "book-metadata" else "chapter-metadata", address,
            gson.toJson(metadata))
    }
    private fun captureEntity(target: TopLevel, name: String, isBook: Boolean) {
        val obj = ScriptableObject.getProperty(target, name) as? Scriptable ?: return
        val fields = (if (isBook) SourceEntity.bookDefaults else SourceEntity.chapterDefaults).keys
        val updates = fields.mapNotNull { field ->
            ScriptableObject.getProperty(obj, field).takeUnless { it === Scriptable.NOT_FOUND || it is Undefined }
                ?.let { field to fromJs(it) }
        }.toMap()
        if (isBook) book = book + updates
        else chapter = chapter + updates
    }
    private fun Any?.orEmptyString() = this?.toString().orEmpty()
    fun image(url: String, isCover: Boolean, referrer: String? = null, book: Map<String, Any?> = emptyMap()): ByteArray {
        this.book = hydrateEntity(book,true)
        base = referrer?.takeIf { it.startsWith("http") } ?: base
        mainScript?.let { js(it, null) }
        val bytes = if (url.startsWith("data:image/", true)) {
            require(absolute(url, base).isNotBlank()) { "书源图片数据无效或过大" }
            Base64.getMimeDecoder().decode(url.substringAfter("base64,", ""))
        } else {
            val spec = org.mewx.wenku8_flutter.legado.AnalyzeUrl(url, baseUrl = base, headers = requestHeaders()) { code, result, root -> js(code, result, baseUrl = root) }
            val body = spec.requestBody()
            val headers = spec.headerMap.toMutableMap()
            // Reading's BookHelp.saveImage uses only the source/locator headers.
            // The chapter remains the relative-URL/JS base, not an implicit
            // Referer: adding one changes CDN authorization for imported rules.
            run.countRequest()
            SourceRateLimit.await(source["bookSourceUrl"].toString(), source["concurrentRate"]?.toString().orEmpty(), run)
            val options = SourceHttpOptions(spec.readTimeoutMs, spec.followRedirects != false, spec.dnsIp, headers.remove("proxy"), source["enabledCookieJar"] != false)
            val reply = run.fetchBytes?.invoke(spec.requestUrl(), spec.method.name, headers, body, options)
                ?: run.fetch(spec.requestUrl(), spec.method.name, headers, body)
            if (reply.status !in 200..299) throw SourceImageHttpFailure(reply.status)
            reply.data ?: reply.body.toByteArray()
        }
        val decode = (if (isCover) source["coverDecodeJs"] else rules("ruleContent")["imageDecode"])?.toString()?.takeIf { it.isNotBlank() }
        return if (decode == null) bytes else fromJs(js(inlineScript(decode), bytes, url)) as? ByteArray
            ?: throw IllegalStateException("书源图片解密规则未返回字节数组")
    }
    companion object {
        private val sourceFields = setOf("bookSourceUrl", "bookSourceName", "bookSourceGroup", "bookSourceType", "enabled", "enabledExplore", "enabledCookieJar",
            "customOrder", "loginUrl", "loginUi", "header", "jsLib", "searchUrl", "exploreUrl", "concurrentRate", "respondTime", "weight", "bookUrlPattern", "loginCheckJs", "comment", "coverDecodeJs",
            "ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview", "bookSourceComment", "variableComment", "lastUpdateTime", "exploreScreen", "mainJs", "eventListener", "customButton")
        private val bookListFields = setOf("bookList","name","author","intro","kind","lastChapter","updateTime","bookUrl","coverUrl","wordCount")
        private val ruleFields = mapOf("ruleSearch" to (bookListFields + "checkKeyWord"), "ruleExplore" to bookListFields,
            "ruleBookInfo" to setOf("init","name","author","intro","kind","lastChapter","updateTime","coverUrl","tocUrl","wordCount","canReName","downloadUrls"),
            "ruleToc" to setOf("preUpdateJs","chapterList","chapterName","chapterUrl","formatJs","isVolume","isVip","isPay","updateTime","nextTocUrl"),
            "ruleContent" to setOf("content","subContent","title","nextContentUrl","webJs","sourceRegex","replaceRegex","imageStyle","imageDecode","payAction","callBackJs"))
        private val secureRandom = java.security.SecureRandom()
        private val scriptCollectionPrefixes=listOf("java.util.HashMap\$","java.util.LinkedHashMap\$","java.util.ArrayList\$","java.util.Collections\$","java.util.AbstractMap\$")
        private val scriptClasses = setOf(
            "java.lang.String", "java.util.ArrayList", "java.util.HashMap", "java.util.LinkedHashMap", "java.util.HashSet", "java.util.LinkedHashSet", "java.net.URL", "java.net.URI",
            "org.mewx.wenku8_flutter.SourceResponse", "org.mewx.wenku8_flutter.SourceJsoupResponse",
            "org.mewx.wenku8_flutter.SourceHeaders", "org.mewx.wenku8_flutter.SourceRawResponse",
            "org.mewx.wenku8_flutter.SourceResponseBody", "org.mewx.wenku8_flutter.SourceResponseRequest",
            "[B", "[Ljava.lang.String;", "[Ljava.lang.Object;", "[Lorg.mewx.wenku8_flutter.legado.SourceScriptFile;",
        )
        private val httpWorkers = java.util.concurrent.Executors.newFixedThreadPool(4) { task ->
            Thread(task, "source-http-batch").apply { isDaemon = true }
        }
        // Same bounded compiled-script reuse as upstream JsSourceEngine. Runtime
        // scopes remain per request; neither cookies nor mutable JS globals are
        // shared by this cache.
        private val compiledScripts = object : LinkedHashMap<String, org.htmlunit.corejs.javascript.Script>(64, .75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, org.htmlunit.corejs.javascript.Script>?) = size > 64
        }
        private val cryptoJs by lazy {
            checkNotNull(BookSourceEngine::class.java.getResourceAsStream("/legado/cryptojs.min.js")) {
                "书源 CryptoJS 运行库未打包"
            }.bufferedReader().use { it.readText() }
        }
        private fun evaluateScript(cx: Context, scope: VarScope, code: String, name: String): Any? {
            val script = synchronized(compiledScripts) {
                compiledScripts[code] ?: cx.compileString(code, name, 1, null).also { compiledScripts[code] = it }
            }
            return script.exec(cx, scope, ScriptableObject.getTopLevelScope(scope).globalThis)
        }
        private fun losesTemplateFilters(template: String, current: String, next: String): Boolean = runCatching {
            val raw = org.mewx.wenku8_flutter.legado.AnalyzeUrl.paramPattern.split(template, 2)[0]
                .substringAfter('?', "")
            val fields = raw.split('&').filter { it.isNotBlank() }.map {
                it.substringBefore('=') to it.substringAfter('=', "")
            }
            val pageRule = Regex("\\{\\{[\\s\\S]*?\\b(?:page|searchPage)\\b[\\s\\S]*?\\}\\}|<[^>]*,[^>]*>")
            val pageKeys = fields.filter { pageRule.containsMatchIn(it.second) }.map { it.first }.toSet()
            if (pageKeys.isEmpty()) return@runCatching false
            fun names(url: String) = URI(url).rawQuery.orEmpty().split('&').map { it.substringBefore('=') }.toSet()
            val currentNames = names(current); val nextNames = names(next)
            fields.any { (name, _) -> name !in pageKeys && name in currentNames && name !in nextNames }
        }.getOrDefault(false)
        fun absolute(value: String, base: String): String {
            if (value.isBlank()) return ""
            if (value.startsWith("data:image/", true)) return value.takeIf {
                it.length <= 12 * 1024 * 1024 && it.matches(Regex("(?i)^data:image/(?:png|jpe?g|webp|gif|bmp|avif);base64,[a-z0-9+/=\\s]+$"))
            }.orEmpty()
            return try {
                val parts = org.mewx.wenku8_flutter.legado.AnalyzeUrl.paramPattern.split(value, 2)
                val resolved = SourceNetwork.resolve(base, parts[0].trim())
                SourceNetwork.url(resolved.toString())
                resolved.toString() + if (parts.size > 1) ",${parts[1]}" else ""
            } catch (_: Exception) { "" }
        }
        fun markup(html: String, base: String): String {
            val root = Jsoup.parseBodyFragment(html, base).body()
            root.select("script, style, noscript").remove()
            val out = StringBuilder()
            NodeTraversor.traverse(object : NodeVisitor {
                override fun head(node: Node, depth: Int) {
                    when (node) {
                        is TextNode -> out.append(node.wholeText)
                        is Element -> when {
                            node.tagName() == "img" -> {
                                val url = absolute(node.attr("data-src").ifBlank { node.attr("data-original") }.ifBlank { node.attr("src") }, base)
                                if (url.isNotEmpty()) out.append("\n\n<!--image-->$url<!--image-->\n\n")
                            }
                            node.tagName() == "br" || node.isBlock -> out.append('\n')
                        }
                    }
                }
                override fun tail(node: Node, depth: Int) { if (node is Element && node.isBlock) out.append('\n') }
            }, root)
            return out.toString()
        }
        /** Delimit only at top level: quoted JSON and CSS predicates may contain @, && or ||. */
        fun splitRules(text: String, delimiter: String): List<String> {
            val result = mutableListOf<String>(); var start = 0; var depth = 0; var quote = '\u0000'; var escaped = false; var i = 0
            while (i < text.length) {
                val c = text[i]
                if (escaped) escaped = false
                else if (c == '\\') escaped = true
                else if (quote != '\u0000') { if (c == quote) quote = '\u0000' }
                else if (c == '\'' || c == '"') quote = c
                else if (c in "([{") depth++
                else if (c in ")]}") depth--
                else if (depth == 0 && text.startsWith(delimiter, i)) {
                    result.add(text.substring(start, i)); i += delimiter.length; start = i; continue
                }
                i++
            }
            result.add(text.substring(start)); return result
        }
    }
}
