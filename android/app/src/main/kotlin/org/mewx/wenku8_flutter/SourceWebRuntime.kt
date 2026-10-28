package org.mewx.wenku8_flutter

import android.annotation.SuppressLint
import android.app.Service
import android.content.*
import android.os.*
import android.webkit.*
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.google.gson.Gson
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** A renderer process keeps imported web sources away from cloud-import browser sessions. */
internal class SourceWebRuntime(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    fun render(key: String, request: SourceWebRequest, run: SourceRun): SourceReply {
        check(Looper.myLooper() != Looper.getMainLooper())
        run.check()
        val id = UUID.randomUUID().toString()
        val folder = File(context.cacheDir, "source-web-tasks").apply { mkdirs() }
        val input = File(folder, "$id.input.json")
        val output = File(folder, "$id.output.json")
        input.writeText(Gson().toJson(mapOf("key" to key, "request" to request,
            "cookie" to (request.headers.entries.firstOrNull { it.key.equals("Cookie", true) }?.value ?: run.cookieRead(request.url)))))
        val complete = CountDownLatch(1)
        var remote: Messenger? = null
        var failure: String? = null
        val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
            if (message.data.getString("id") == id) { failure = message.data.getString("error"); complete.countDown() }
            true
        })
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                remote = Messenger(binder)
                remote?.send(Message.obtain(null, 1).apply {
                    replyTo = replies; data = Bundle().apply { putString("id", id) }
                })
            }
            override fun onServiceDisconnected(name: ComponentName) { failure = "书源网页渲染已断开"; complete.countDown() }
            override fun onNullBinding(name: ComponentName) { failure = "书源网页渲染不可用"; complete.countDown() }
        }
        var bound = false
        val unregister = run.onCancel { remote?.send(Message.obtain(null, 2).apply { data = Bundle().apply { putString("id", id) } }) }
        try {
            val flags = Context.BIND_AUTO_CREATE or if (request.interactive && Build.VERSION.SDK_INT >= 34) Context.BIND_ALLOW_ACTIVITY_STARTS else 0
            bound = context.bindService(Intent(context, SourceWebService::class.java), connection, flags)
            check(bound) { "书源网页渲染无法启动" }
            while (!complete.await(100, TimeUnit.MILLISECONDS)) run.check()
            run.check()
            check(failure == null && output.isFile) { failure ?: "书源网页渲染未完成" }
            check(output.length() <= 12 * 1024 * 1024) { "书源网页响应过大" }
            val value = Gson().fromJson(output.readText(), Map::class.java)
            (value["cookies"] as? Map<*, *>)?.forEach { (url, cookie) -> if (url is String && cookie is String) {
                run.cookieRemove(url); run.cookieWrite(url, cookie)
            } }
            val url = value["url"]?.toString() ?: request.url
            return SourceReply(url, value["body"]?.toString().orEmpty())
        } finally {
            unregister()
            remote?.send(Message.obtain(null, 2).apply { data = Bundle().apply { putString("id", id) } })
            if (bound) context.unbindService(connection)
            input.delete(); output.delete()
        }
    }
}

/** Only this process creates its default WebView data directory. It never starts Flutter. */
class SourceWebService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Message>()
    private var active: String? = null
    private var cancel: (() -> Unit)? = null
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        val id = message.data.getString("id")
        when (message.what) {
            1 -> { if (id != null && id.matches(Regex("[a-f0-9-]{36}"))) { queue.add(Message.obtain(message)); next() } }
            2 -> { queue.removeAll { it.data.getString("id") == id }; if (id == active) cancel?.invoke() }
        }
        true
    })
    override fun onBind(intent: Intent): IBinder = messenger.binder
    private fun next() {
        if (active != null || queue.isEmpty()) return
        val message = queue.removeFirst()
        val id = message.data.getString("id")!!
        active = id
        val folder = File(cacheDir, "source-web-tasks")
        val input = File(folder, "$id.input.json")
        fun reply(error: String? = null) {
            try { message.replyTo.send(Message.obtain(null, 1).apply { data = Bundle().apply { putString("id", id); putString("error", error) } }) }
            catch (_: RemoteException) { }
            active = null; cancel = null; next()
        }
        try {
            check(input.isFile && input.length() <= 12 * 1024 * 1024)
            val task = Gson().fromJson(input.readText(), Map::class.java)
            val request = Gson().fromJson(Gson().toJson(task["request"]), SourceWebRequest::class.java)
            if (request.clearProfile) {
                SourceWebProfiles.clear(task["key"].toString()) {
                    File(folder, "$id.output.json").writeText("{\"body\":\"\"}")
                    reply()
                }
                return
            }
            SourceNetwork.url(request.url)
            if (request.interactive) {
                cancel = SourceLoginSessions.open(this, id, task["key"].toString(), request, task["cookie"]?.toString().orEmpty()) { value, error ->
                    if (value != null) File(folder, "$id.output.json").writeText(Gson().toJson(value))
                    reply(error)
                }
                return
            }
            val renderer = SourceWebRenderer(this, task["key"].toString(), request, task["cookie"]?.toString().orEmpty(), complete = { value, error ->
                if (value != null) File(folder, "$id.output.json").writeText(Gson().toJson(value))
                reply(error)
            })
            cancel = renderer::cancel
            renderer.start()
        } catch (_: Exception) { reply("书源网页渲染未完成") }
    }
    override fun onDestroy() { queue.clear(); cancel?.invoke(); super.onDestroy() }
}

internal class SourceWebRenderer(
    private val context: Context, private val key: String, private val request: SourceWebRequest,
    private val cookie: String, private val complete: (Map<String, Any?>?, String?) -> Unit,
    private val attach: ((WebView) -> Unit)? = null,
    private val configure: ((String) -> Unit)? = null,
) {
    private val main = Handler(Looper.getMainLooper())
    private var web: WebView? = null
    private var finished = false
    private var retries = 0
    private var initStage = "create"
    private var cookies: CookieManager? = null
    private val urls = linkedSetOf<String>()
    private val capture = SourceWebCapture(request)
    private val timeout = Runnable { finish(error = "书源网页脚本执行超时") }
    private val trigger = Runnable { if (!finished) web?.evaluateJavascript(request.script.orEmpty(), null) }
    private val evaluate = object : Runnable {
        override fun run() {
            val view = web ?: return
            val script = request.script?.takeIf { it.isNotBlank() } ?: "document.documentElement.outerHTML"
            val code = request.result?.let { "window.result=$it;\n$script" } ?: script
            view.evaluateJavascript(code) { raw ->
                if (finished) return@evaluateJavascript
                if (raw != null && raw != "null" && raw.isNotEmpty()) {
                    val decoded = runCatching { Gson().fromJson(raw, Any::class.java) }.getOrNull()
                    val text = if (decoded is String) decoded else raw
                    if (text.toByteArray().size > 8 * 1024 * 1024) finish(error = "书源网页响应超过 8 MiB")
                    else finish(body = text, url = view.url ?: request.url)
                } else if (++retries <= 30) main.postDelayed(this, minOf(retries * 200L, 1000L))
                else finish(error = "书源网页脚本未返回内容")
            }
        }
    }
    @SuppressLint("SetJavaScriptEnabled")
    fun start() {
        try { startWebView() } catch (failure: Exception) {
            android.util.Log.e("BookSources", "web.init stage=$initStage type=${failure.javaClass.name}")
            finish(error = "书源网页登录初始化失败，请重试")
        }
    }
    @SuppressLint("SetJavaScriptEnabled")
    private fun startWebView() {
        check(Looper.myLooper() == Looper.getMainLooper())
        val view = WebView(context); web = view
        initStage = "profile"
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            val name = SourceWebProfiles.name(key)
            WebViewCompat.setProfile(view, name)
            cookies = ProfileStore.getInstance().getOrCreateProfile(name).cookieManager
        } else {
            check(Build.VERSION.SDK_INT >= 28) { "书源网页需要更新 Android System WebView" }
            cookies = CookieManager.getInstance()
        }
        initStage = "settings"
        cookies!!.setAcceptCookie(true)
        cookies!!.setAcceptThirdPartyCookies(view, request.thirdPartyCookies)
        view.settings.apply {
            javaScriptEnabled = true; domStorageEnabled = true
            allowFileAccess = false; allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = if (request.cacheFirst) WebSettings.LOAD_CACHE_ELSE_NETWORK else WebSettings.LOAD_DEFAULT
            request.headers.entries.firstOrNull { it.key.equals("User-Agent", true) }?.let { userAgentString = it.value }
        }
        if (request.browserSheet) {
            view.addJavascriptInterface(object {
                @JavascriptInterface fun upConfig(config: String) { main.post { if (!finished) runCatching { configure?.invoke(config) } } }
                @JavascriptInterface fun dismiss() { main.post { done() } }
            }, "java")
            view.webChromeClient = object : WebChromeClient() { override fun onCloseWindow(window: WebView?) { done() } }
        }
        val size = context.resources.displayMetrics
        view.measure(android.view.View.MeasureSpec.makeMeasureSpec(size.widthPixels, android.view.View.MeasureSpec.EXACTLY),
            android.view.View.MeasureSpec.makeMeasureSpec(size.heightPixels, android.view.View.MeasureSpec.EXACTLY))
        view.layout(0, 0, size.widthPixels, size.heightPixels)
        view.webViewClient = object : WebViewClient() {
            private fun navigation(url: String): Boolean {
                capture.navigation(url)?.let { finish(body = it.body, url = it.url, sniffed = true); return true }
                return !url.startsWith("http://", true) && !url.startsWith("https://", true)
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = navigation(request.url.toString())
            @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView, url: String) = navigation(url)
            override fun onLoadResource(view: WebView, url: String) {
                if (url.startsWith("http")) urls.add(url)
                capture.resource(url)?.let { finish(body = it.body, url = it.url, sniffed = true) }
            }
            override fun onPageFinished(view: WebView, url: String) {
                urls.add(url); main.removeCallbacks(evaluate)
                if (!finished && attach != null && !request.script.isNullOrBlank()) main.postDelayed(trigger, 100 + request.delay)
                if (!finished && attach == null) {
                    if (!capture.active) main.postDelayed(evaluate, 100 + if (request.script.isNullOrBlank() && request.delay == 0L) 900 else request.delay)
                    else request.script?.takeIf { it.isNotBlank() }?.let {
                        // Sniffers run the trigger script, but do not finish on
                        // its return value or on the page's HTML.
                        main.postDelayed(trigger, 100 + request.delay)
                    }
                }
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) finish(error = "书源网页加载失败")
            }
            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                finish(error = "书源网页渲染进程已退出"); return true
            }
        }
        fun load() {
            if (finished) return
            initStage = "load"
            urls.add(request.url)
            if (request.html != null) view.loadDataWithBaseURL(request.url, request.html, "text/html", "UTF-8", null)
            else view.loadUrl(request.url, request.headers.filterKeys { !it.equals("Cookie", true) })
        }
        initStage = "attach"
        attach?.invoke(view)
        main.postDelayed(timeout, if (attach == null) 28_000 else 10 * 60_000)
        // CookieManager.setCookie accepts ONE Set-Cookie value, not a Cookie
        // request header. Seed all pairs before allowing the document to run.
        initStage = "cookies"
        val pairs = cookie.split(';').map { it.trim() }.filter { it.contains('=') }
        fun seed(index: Int = 0) {
            if (finished) return
            if (index >= pairs.size) load()
            else cookies!!.setCookie(request.url, pairs[index]) { seed(index + 1) }
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            seed()
        } else {
            // The service's private legacy jar is reused sequentially, never with
            // another source or the main app's cloud-login browser session.
            WebStorage.getInstance().deleteAllData()
            cookies!!.removeAllCookies { seed() }
        }
    }
    fun done() {
        if (finished) return
        val view = web
        if (!request.captureBody || view == null) { finish(url = view?.url ?: request.url); return }
        view.evaluateJavascript("document.documentElement.outerHTML") { raw ->
            if (finished) return@evaluateJavascript
            val body = runCatching { Gson().fromJson(raw, String::class.java) }.getOrNull().orEmpty()
            if (body.toByteArray().size > 8 * 1024 * 1024) finish(error = "书源网页响应超过 8 MiB")
            else finish(body = body, url = view.url ?: request.url)
        }
    }
    fun cancel() = finish(error = "书源网页请求已取消")
    private fun finish(body: String = "", url: String = request.url, sniffed: Boolean = false, error: String? = null) {
        if (finished) return; finished = true
        main.removeCallbacks(timeout); main.removeCallbacks(evaluate); main.removeCallbacks(trigger)
        val result = if (error != null) null else mapOf("url" to url, "body" to body, "sniffed" to sniffed,
            "cookies" to urls.mapNotNull { raw -> runCatching { SourceNetwork.url(raw).toString() }.getOrNull() }
                .distinct().associateWith { cookies?.getCookie(it).orEmpty() })
        cookies?.flush()
        web?.apply { stopLoading(); webViewClient = WebViewClient(); destroy() }; web = null
        complete(result, error)
    }
}

internal object SourceWebProfiles {
    fun name(key: String) = "source-" + java.security.MessageDigest.getInstance("SHA-256")
        .digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
    fun clear(key: String, done: () -> Unit) {
        val cookie: CookieManager
        if (WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            val profile = ProfileStore.getInstance().getOrCreateProfile(name(key))
            profile.webStorage.deleteAllData()
            cookie = profile.cookieManager
        } else {
            WebStorage.getInstance().deleteAllData()
            cookie = CookieManager.getInstance()
        }
        cookie.removeAllCookies { cookie.flush(); done() }
    }
}
