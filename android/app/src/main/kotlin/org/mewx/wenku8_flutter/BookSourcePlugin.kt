package org.mewx.wenku8_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class BookSourcePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var context: Context
    private var channel: MethodChannel? = null
    @Volatile private var environment: Map<String, Any?> = emptyMap()
    private val clearing = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private val hubs = SourceHubConnections()
    private val io = Executors.newFixedThreadPool(4)
    private val searchIo = Executors.newFixedThreadPool(6)
    private val accountChecks = Executors.newSingleThreadExecutor()
    private val imageIo = Executors.newFixedThreadPool(2)
    private val browserIo = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val network = SourceNetwork { key -> states[key]?.let(SourceAccountState::changed) }
    private val accountRunning = ConcurrentHashMap.newKeySet<String>()
    private val cancelled = ConcurrentHashMap<String, AtomicBoolean>()
    private val loaded = ConcurrentHashMap.newKeySet<String>()
    private val states = ConcurrentHashMap<String, SourceState>()
    private val running = ConcurrentHashMap<String, SourceRun>()
    private val runSources = ConcurrentHashMap<String, String>()
    private val sessionEpochs = ConcurrentHashMap<String, java.util.concurrent.atomic.AtomicInteger>()
    private val imageLock = Any()
    private val imageEpoch = java.util.concurrent.atomic.AtomicInteger(0)
    private val imageDiskBudget = SourceImageDiskBudget(256L * 1024 * 1024)
    private class ImageLock(val lock: Any = Any(), var readers: Int = 0)
    private val imageLocks = mutableMapOf<String, ImageLock>()
    private data class Pending(val method: String, val result: MethodChannel.Result, val text: String?)
    private var pending: Pending? = null
    private val alias = "wenku8.sources.session.v1"
    private companion object {
        val cryptoLock=Any()
        @Volatile var cachedKey:SecretKey?=null
    }
    private fun encryptionKey(): SecretKey = cachedKey ?: synchronized(cryptoLock) {
        cachedKey ?: loadEncryptionKey().also { cachedKey=it }
    }
    private fun loadEncryptionKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun cacheKey(text: String) = MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun seal(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(cipher.doFinal(text.toByteArray()), Base64.NO_WRAP)
    }
    private fun openSealed(value: String): String {
        val parts = value.split(':'); require(parts.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
        return cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }
    private fun sourceState(key: String): SourceState {
        val sessionKey = SourceSessionIdentity.key(key)
        val shared = if (sessionKey == key) null else sourceState(sessionKey)
        return states.computeIfAbsent(key) {
        val epoch=sessionEpochs.computeIfAbsent(sessionKey){java.util.concurrent.atomic.AtomicInteger()}.get()
        SourceState(SourceBigVariables(File(context.filesDir, "book-source-variables/${cacheKey(key)}"), ::seal, ::openSealed), session = shared) {
            check(sessionEpochs[sessionKey]?.get()==epoch) { "书源登录信息已清理，请重试" }
        }
        }
    }
    private fun installationId(): String {
        val preferences = context.getSharedPreferences("book_source_host", 0)
        return preferences.getString("id", null)?.take(16) ?: synchronized(this) {
            preferences.getString("id", null)?.take(16) ?: java.util.UUID.randomUUID().toString().replace("-", "").take(16).also {
                check(preferences.edit().putString("id", it).commit())
            }
        }
    }
    private fun requestUi(method: String, payload: Map<String, Any?>, run: SourceRun): Any? {
        val id = java.util.UUID.randomUUID().toString()
        val done = CountDownLatch(1)
        var value: Any? = null; var error: String? = null
        fun cancel() { main.post { channel?.invokeMethod("cancelPrompt", mapOf("id" to id)) }; Unit }
        val unregister = run.onCancel(::cancel)
        main.post {
            val host = channel
            if (host == null || activity == null) { error = "请在应用前台完成书源验证"; done.countDown() }
            else host.invokeMethod(method, payload + ("id" to id), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; done.countDown() }
                override fun error(code: String, message: String?, details: Any?) { error = "书源交互未完成，请在应用前台重试"; done.countDown() }
                override fun notImplemented() { error = "书源交互服务未就绪"; done.countDown() }
            })
        }
        try { while (!done.await(50, TimeUnit.MILLISECONDS)) run.check(); run.check(); check(error == null) { error!! }; return value }
        finally { unregister(); cancel() }
    }
    @Synchronized private fun restoreSession(key: String, preferred: String? = null) {
        if (!loaded.add(key)) return
        val preferences = context.getSharedPreferences("book_source_sessions", 0)
        try {
            var sealed = preferences.getString(cacheKey(key), null)
            if (sealed == null && SourceSessionIdentity.members(key).size > 1) {
                val candidates = (listOfNotNull(preferred) + SourceSessionIdentity.members(key).filter { it != key }).distinct()
                for (candidate in candidates) {
                    val previous = preferences.getString(cacheKey(candidate), null) ?: continue
                    val decoded = openSealed(previous)
                    if (decoded.trim().startsWith('[')) continue
                    val saved = com.google.gson.Gson().fromJson(decoded, Map::class.java)
                    val state = saved["state"] as? Map<*, *> ?: continue
                    if (!(state["login\nheader"] as? String).isNullOrBlank()) {
                        sealed = previous
                        check(preferences.edit().putString(cacheKey(key), previous).commit())
                        break
                    }
                }
            }
            if (sealed == null) return
            val text = openSealed(sealed)
            if (text.trim().startsWith('[')) network.restore(key, text)
            else {
                val saved = com.google.gson.Gson().fromJson(text, Map::class.java)
                network.restore(key, saved["cookies"]?.toString() ?: "[]")
                (saved["state"] as? Map<*, *>)?.let { state ->
                    val values = if (SourceSessionIdentity.members(key).size > 1) state.filterKeys {
                        val address = it as String
                        sourceSessionField(address.substringBefore('\n'), address.substringAfter('\n'))
                    } else state
                    sourceState(key).restore(values)
                }
                // A stored result is not a fresh server verification after restart.
                SourceAccountState.changed(sourceState(key))
            }
        } catch (failure: Exception) {
            loaded.remove(key)
            throw SourceAccountFailure("书源登录信息读取失败，请重试；已保存的数据仍保留")
        }
    }
    @Synchronized private fun restoreSourceRuntime(source: String) {
        if (SourceSessionIdentity.key(source) == source || !loaded.add(source)) return
        val sealed = context.getSharedPreferences("book_source_sessions", 0).getString(cacheKey(source), null) ?: return
        val text = openSealed(sealed)
        if (text.trim().startsWith('[')) return
        val saved = com.google.gson.Gson().fromJson(text, Map::class.java)
        val values = saved["state"] as? Map<*, *> ?: return
        sourceState(source).restore(values.filterKeys {
            val address = it as String
            return@filterKeys !sourceSessionField(address.substringBefore('\n'), address.substringAfter('\n'))
        })
    }
    @Synchronized private fun saveSession(key: String) {
        val text = com.google.gson.Gson().toJson(mapOf("cookies" to network.session(key), "state" to states[key]?.snapshot()))
        val sealed = seal(text)
        val preferences = context.getSharedPreferences("book_source_sessions", 0).edit().putString(cacheKey(key), sealed)
        for (member in SourceSessionIdentity.members(key).filter { it != key }) {
            states[member]?.let { state ->
                val runtime = com.google.gson.Gson().toJson(mapOf("cookies" to "[]", "state" to state.snapshot()))
                preferences.putString(cacheKey(member), seal(runtime))
            }
        }
        check(preferences.commit())
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/book_sources").also { it.setMethodCallHandler(this) }
    }
    private fun background(result: MethodChannel.Result, executor: java.util.concurrent.ExecutorService = io, work: () -> Any?) {
        executor.execute {
            // Result is thread-safe. Encode large directories and image byte
            // buffers on their worker too, rather than copying/serializing them
            // on Android's platform thread during a route or scroll gesture.
            try { result.success(work()) }
            catch (_: CancellationException) { result.error("SOURCE_CANCELLED", "书源请求已取消", null) }
            catch (failure: Exception) {
                android.util.Log.e("BookSources", sourceFailureDiagnostic(failure))
                // Never send script bodies, complete URLs, returned prose, headers
                // or the underlying HTTP exception (which may contain secrets).
                val message = sourceRuleFailureMessage(failure) ?: failure.message?.takeIf { it.startsWith("书源") || it.startsWith("目录") || it.startsWith("正文") || it.startsWith("仅支持") || it.startsWith("远程 JS") || it.startsWith("脚本") || it.startsWith("单章") } ?: "书源规则或请求未完成，请检查后重试"
                result.error("SOURCE_ERROR", message, null)
            }
        }
    }
    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        (call.arguments as? Map<*, *>)?.get("environment")?.let { raw ->
            if (raw is Map<*, *>) environment = raw.entries.associate { it.key.toString() to it.value }
        }
        when (call.method) {
            "cancel" -> { val id = call.arguments as? String; cancelled[id]?.set(true); running[id]?.cancel(); result.success(null) }
            "pauseConnections" -> { hubs.closeIdle(); result.success(null) }
            "pick", "export" -> selectDocument(call, result)
            "clearSession" -> background(result) {
                val key = SourceSessionIdentity.key(call.arguments as String)
                check(clearing.add(key)) { "书源登录信息正在清理，请稍后重试" }
                try {
                sessionEpochs.computeIfAbsent(key) { java.util.concurrent.atomic.AtomicInteger() }.incrementAndGet()
                runSources.filterValues { it == key }.keys.forEach { running[it]?.cancel(); cancelled[it]?.set(true) }
                synchronized(this) {
                    network.clear(key)
                    val preferences = context.getSharedPreferences("book_source_sessions", 0).edit()
                    for (member in SourceSessionIdentity.members(key)) {
                        loaded.remove(member)
                        val state = states.remove(member)
                        state?.let { hubs.close(it); it.clearMemory(); SourceFonts.clear(it) }
                        SourceScriptScopes.clearSource(member)
                        preferences.remove(cacheKey(member))
                        synchronized(state?.fileLock ?: this) {
                            val files = File(context.cacheDir, "book-source-resources/${cacheKey(member)}")
                            check(org.mewx.wenku8_flutter.legado.SourceResources.clear(files)) { "书源缓存清理未完成" }
                            val variables = File(context.filesDir, "book-source-variables/${cacheKey(member)}")
                            check(!variables.exists() || variables.deleteRecursively()) { "书源变量清理未完成" }
                        }
                    }
                    check(preferences.commit())
                }
                SourceWebRuntime(context).render(key, SourceWebRequest("https://source.invalid/", clearProfile = true),
                    SourceRun(fetch = { _, _, _, _ -> error("Clear profile does not fetch") }))
                null
                } finally { clearing.remove(key) }
            }
            "clearImages" -> background(result) { synchronized(imageLock) {
                imageEpoch.incrementAndGet()
                imageDiskBudget.invalidate()
                for (name in listOf("book-source-images-v1", "wenku8-illustrations-v1")) {
                    val folder = File(context.filesDir, name); check(!folder.exists() || folder.deleteRecursively())
                }; null
            } }
            "fetchImport" -> background(result) {
                val raw = call.arguments as String
                val run = SourceRun(fetch = { _, _, _, _ -> error("No nested requests") })
                network.bytes(null, raw, run = run).data.toString(Charsets.UTF_8)
            }
            "inspectScript" -> background(result) {
                // Import inspection cannot use network, files or an existing
                // source session. JSON import still never executes scripts.
                val text = call.arguments as String
                val run = SourceRun(fetch = { _, _, _, _ -> error("书源预览不允许网络请求") })
                BookSourceEngine(emptyMap(), run).execute("inspectScript", key = text)
            }
            "accountStatus" -> background(result) {
                val source = call.arguments as Map<String, Any?>
                SourceSessionIdentity.register(source)
                val sourceKey = source["bookSourceUrl"] as String
                val key = SourceSessionIdentity.key(sourceKey)
                check(!clearing.contains(key)) { "书源登录信息正在清理，请稍后重试" }
                restoreSession(key, sourceKey)
                SourceAccountState.view(source, sourceState(key), network.hasCookies(key))
            }
            "run", "openLogin" -> {
                val args = call.arguments as Map<String, Any?>
                val id = args["requestId"] as? String ?: java.util.UUID.randomUUID().toString()
                val flag = AtomicBoolean(false); cancelled[id] = flag
                val metrics = SourceRunMetrics()
                val queuedAt = System.nanoTime()
                val backgroundCheck = args["background"] == true && args["operation"] == "accountVerify"
                background(result, if (backgroundCheck) accountChecks else if (args["operation"] == "search") searchIo else io) {
                    metrics.queuedNanos.addAndGet(System.nanoTime() - queuedAt)
                    try {
                        val source = args["source"] as Map<String, Any?>
                        SourceSessionIdentity.register(source)
                val sourceKey = source["bookSourceUrl"] as String
                        val key = SourceSessionIdentity.key(sourceKey)
                        val operation = args["operation"] as? String
                        val accountAction = call.method == "openLogin" || operation == "login" || operation == "cloudShelf" || operation?.startsWith("account") == true
                        check(!accountAction || accountRunning.add(key)) { "书源账号操作正在进行，请稍后重试" }
                        try {
                        val epoch = sessionEpochs.computeIfAbsent(key) { java.util.concurrent.atomic.AtomicInteger() }.get()
                        runSources[id] = key
                        restoreSession(key, sourceKey)
                        lateinit var run: SourceRun
                        run = createRun(key, flag, interactive = call.method == "openLogin", label = source["bookSourceName"]?.toString(), sourceKey = sourceKey, metrics = metrics, timeoutMillis = if (operation == "epub") 120000 else ((source["engine"] as? Map<*, *>)?.get("requestTimeoutMs") as? Number)?.toLong() ?: 30000, lowPriority = backgroundCheck, allowBrowser = !backgroundCheck && (call.method == "openLogin" || operation == "login"),
                            progress = if (operation == "epub") { received, total ->
                                main.post { channel?.invokeMethod("downloadProgress", mapOf("id" to id, "received" to received, "total" to total)) }
                                Unit
                            } else null)
                        running[id] = run
                        val engine = BookSourceEngine(source, run)
                        val value = try {
                            if (call.method == "openLogin") {
                                run.web!!.invoke(engine.loginWebRequest()); SourceAccountState.submitted(run.state); true
                            } else engine.execute(args["operation"] as String, args["url"] as? String,
                                args["key"] as? String ?: "", (args["page"] as? Number)?.toInt() ?: 1,
                                args["book"] as? Map<String, Any?> ?: emptyMap(), args["chapter"] as? Map<String, Any?> ?: emptyMap()).also { value ->
                                if (operation == "login" && (value !is Map<*, *> || value["login"] != null ||
                                    value["close"] == true || value["refreshExplore"] == true)) SourceAccountState.submitted(run.state)
                            }
                        } catch (failure: Exception) {
                            val expired = SourceAccountState.authenticationRejected(failure)
                            if (sessionEpochs[key]?.get() == epoch) {
                                if (expired) {
                                    SourceAccountState.verified(run.state, false)
                                    main.post { channel?.invokeMethod("accountChanged", mapOf("source" to sourceKey)) }
                                }
                                saveSession(key)
                            }
                            if (expired) throw SourceAccountFailure("书源登录已失效，请在账号页重新登录")
                            throw failure
                        }
                        run.check()
                        check(sessionEpochs[key]?.get() == epoch) { "书源登录信息已清理，请重试" }
                        saveSession(key); value
                        } finally { if (accountAction) accountRunning.remove(key) }
                    } finally {
                        val completed = running.remove(id)
                        val definition = args["source"] as Map<*, *>
                        val ruleDigest = cacheKey(definition["mainJs"] as? String ?: "").take(12)
                        android.util.Log.d("BookSourcePerf", metrics.report(args["operation"] as? String ?: call.method,
                            definition["bookSourceUrl"].toString(), completed?.requests ?: 0, backgroundCheck) + " rule_sha256=$ruleDigest")
                        cancelled.remove(id, flag); runSources.remove(id)
                    }
                }
            }
            "image" -> background(result, imageIo) { image(call.arguments as Map<String, Any?>) }
            else -> result.notImplemented()
        }
    }
    private fun createRun(key: String, flag: AtomicBoolean = AtomicBoolean(), interactive: Boolean = false, label: String? = null, sourceKey: String = key, metrics: SourceRunMetrics = SourceRunMetrics(), timeoutMillis: Long = 30000, progress: ((Long, Long?) -> Unit)? = null, allowBrowser: Boolean = false, lowPriority: Boolean = false): SourceRun {
        restoreSourceRuntime(sourceKey)
        lateinit var run: SourceRun
        val displayName=label?.takeIf { it.isNotBlank() }?.take(120) ?: Uri.parse(key).host?.takeIf { it.isNotBlank() } ?: "书源"
        val epoch = sessionEpochs.computeIfAbsent(key) { java.util.concurrent.atomic.AtomicInteger() }.get()
        check(!clearing.contains(key)) { "书源登录信息正在清理，请稍后重试" }
        run = SourceRun(
            deadline = System.nanoTime() + if (interactive) 10 * 60_000_000_000L else timeoutMillis * 1_000_000L,
            fetch = { url, method, headers, body -> network.text(key, url, method, headers, body, run) },
            fetchOptions = { url, method, headers, body, options -> network.text(key, url, method, headers, body, run, options) },
            fetchBytes = { url, method, headers, body, options -> network.bytes(key, url, method, headers, body, run, options).let { SourceReply(it.url, "", it.status, it.headers, it.data) } },
            fetchFile = { url, method, headers, body, options ->
                val folder = File(context.cacheDir, "source-epub-downloads").apply { mkdirs() }
                val file = File.createTempFile("volume-", ".epub", folder)
                try {
                    val reply = network.bytes(key, url, method, headers, body, run, options, destination = file, onProgress = progress)
                    SourceReply(reply.url, "", reply.status, reply.headers, file = file.path)
                } catch (failure: Exception) {
                    file.delete()
                    throw failure
                }
            },
            cancelled = { flag.get() || sessionEpochs[key]?.get() != epoch }, state = sourceState(sourceKey),
            cookieRead = { address -> network.cookie(key, address) },
            cookieWrite = { address, value -> run.check(); network.setCookie(key, address, value) },
            cookieRemove = { address -> run.check(); network.removeCookie(key, address) },
            web = { request ->
                if (!allowBrowser && request.interactive) throw SourceVerificationRequired()
                SourceWebRuntime(context).render(key, request, run)
            },
            filesRoot = File(context.cacheDir, "book-source-resources/${cacheKey(sourceKey)}"),
            lowPriority = lowPriority,
            metrics = metrics, hubs = hubs, openSocket = { address, headers, listener -> run.metrics.httpCalls.incrementAndGet(); network.socket(key, address, headers, listener) },
            webUserAgent = { android.webkit.WebSettings.getDefaultUserAgent(context) },
            archiveBackend = SourceNativeArchive,
            appConfig = environment,
            installationId = installationId(),
            diagnostic = { android.util.Log.d("BookSources",it); Unit },
            notice = { message, _ -> main.post { channel?.invokeMethod("notice", mapOf("message" to message.take(400))) }; Unit },
            verifyCode = { bytes -> requestUi("captcha", mapOf("source" to displayName, "image" to bytes), run) as? String },
            openExternal = { address, mime ->
                require(address.length < 64 * 1024) { "书源外部地址过长" }
                val uri = Uri.parse(address)
                require(uri.scheme?.lowercase() !in listOf(null, "file", "content", "data", "javascript", "intent")) { "书源不允许打开此类地址" }
                main.post {
                    // Consent is always requested through the app's existing glass sheet.
                    channel?.invokeMethod("confirmOpenUrl", mapOf("id" to java.util.UUID.randomUUID().toString(), "source" to displayName, "url" to address), object : MethodChannel.Result {
                        override fun success(value: Any?) { if (value == true) try {
                            activity?.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                if (mime == null) data = uri else setDataAndType(uri, mime)
                                addCategory(Intent.CATEGORY_BROWSABLE)
                            })
                        } catch (_: Exception) { channel?.invokeMethod("notice", mapOf("message" to "没有可用的应用打开此地址")) } }
                        override fun error(code: String, message: String?, details: Any?) {
                            channel?.invokeMethod("notice", mapOf("message" to "书源外部操作未完成，请在应用前台重试"))
                        }
                        override fun notImplemented() { channel?.invokeMethod("notice", mapOf("message" to "书源交互服务未就绪")) }
                    })
                }; Unit
            },
            openBrowser = { request ->
                if (!allowBrowser) throw SourceVerificationRequired()
                val id = java.util.UUID.randomUUID().toString()
                val browserRun = createRun(key, interactive = true, label = displayName, sourceKey = sourceKey, allowBrowser = true)
                running[id] = browserRun; runSources[id] = key
                browserIo.execute {
                    try {
                        SourceWebRuntime(context).render(key, request, browserRun); browserRun.check()
                        SourceAccountState.submitted(browserRun.state); saveSession(key)
                        main.post { channel?.invokeMethod("sessionUpdated",mapOf("source" to sourceKey)) }
                    }
                    catch (_: CancellationException) { }
                    catch (_: Exception) { if (sessionEpochs[key]?.get()==epoch) main.post { channel?.invokeMethod("notice", mapOf("message" to "书源网页验证未完成，可重新打开验证")) } }
                    finally { running.remove(id); runSources.remove(id) }
                }
            },
        )
        return run
    }
    private fun image(args: Map<String, Any?>): ByteArray {
        val identity = "${args["sourceKey"]}\n${args["url"]}"
        val owner = synchronized(imageLocks) { imageLocks.getOrPut(identity) { ImageLock() }.also { it.readers++ } }
        try { return synchronized(owner.lock) { readImage(args) } }
        finally { synchronized(imageLocks) { owner.readers--; if (owner.readers == 0) imageLocks.remove(identity) } }
    }
    private fun readImage(args: Map<String, Any?>): ByteArray = run {
        val epoch = imageEpoch.get()
        val url = args["url"] as String
        if (!url.startsWith("data:image/")) SourceNetwork.url(org.mewx.wenku8_flutter.legado.AnalyzeUrl.paramPattern.split(url, 2)[0])
        val source = args["source"] as? Map<*, *>
        val key = source?.get("bookSourceUrl") as? String ?: args["sourceKey"] as? String
        val folder = File(context.filesDir, "book-source-images-v1")
        val file = File(folder, cacheKey("${key ?: ""}\n$url"))
        if (file.isFile && file.length() in 1..8*1024*1024L) {
            try { return@run file.readBytes().also { validateImage(it); file.setLastModified(System.currentTimeMillis()) } }
            catch (_: Exception) { synchronized(imageLock) {
                val length = file.length()
                if (file.delete()) imageDiskBudget.removed(length)
            } }
        }
        if (args["cachedOnly"] == true || key == null) {
            // Read old image cache only. No implicit Wenku fallback remains.
            val legacy = File(File(context.filesDir, "wenku8-illustrations-v1"), cacheKey(url))
            check(legacy.isFile && legacy.length() in 1..8*1024*1024L) { "书源图片未缓存" }
            return@run legacy.readBytes().also(::validateImage)
        }
        val sessionKey = SourceSessionIdentity.key(key)
        restoreSession(sessionKey, key)
        @Suppress("UNCHECKED_CAST")
        val bytes = BookSourceEngine(source as? Map<String, Any?> ?: mapOf("bookSourceUrl" to key), createRun(sessionKey, sourceKey = key, lowPriority = true))
            .image(url, args["isCover"] == true, args["referrer"] as? String,
                args["book"] as? Map<String, Any?> ?: emptyMap())
        saveSession(sessionKey)
        validateImage(bytes)
        synchronized(imageLock) {
            if (epoch == imageEpoch.get()) try {
                folder.mkdirs(); val temp = File(file.path + ".part")
                val previousSize = if (file.isFile) file.length() else 0L
                try { temp.writeBytes(bytes); if (!temp.renameTo(file)) throw java.io.IOException("Image cache write failed") } finally { temp.delete() }
                imageDiskBudget.committed(folder, file, previousSize)
            } catch (_: java.io.IOException) {
                imageDiskBudget.invalidate()
                /* A cache failure does not hide a valid online image. */
            }
        }
        bytes
    }
    private fun validateImage(bytes: ByteArray) {
        require(bytes.size in 1..8*1024*1024)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 50_000_000L)
    }
    private fun selectDocument(call: MethodCall, result: MethodChannel.Result) {
        val host = activity
        if (host == null) { result.error("NO_ACTIVITY", "请在应用前台选择文件", null); return }
        if (pending != null) { result.error("BUSY", "请先完成当前文件选择", null); return }
        val text = call.arguments as? String
        if (call.method == "export" && (text == null || text.toByteArray().size > 8*1024*1024)) { result.error("SIZE", "书源文件超过 8 MiB", null); return }
        val intent = Intent(if (call.method == "pick") Intent.ACTION_GET_CONTENT else Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = if (call.method == "pick") "*/*" else "application/json"
            if (call.method == "export") putExtra(Intent.EXTRA_TITLE, "book-sources.json")
        }
        pending = Pending(call.method, result, text)
        try { @Suppress("DEPRECATION") host.startActivityForResult(Intent.createChooser(intent, "选择文件应用"), 8050) }
        catch (_: Exception) { pending = null; result.error("PICKER", "没有可用的文件应用", null) }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 8050) return false
        val request = pending ?: return true; pending = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { request.result.success(if (request.method == "export") false else null); return true }
        val uri = data.data!!
        background(request.result) {
            if (request.method == "export") {
                context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(request.text!!.toByteArray(Charsets.UTF_8)) }; true
            } else context.contentResolver.openInputStream(uri)!!.use { input ->
                val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(16384)
                while (true) { val count = input.read(buffer); if (count < 0) break
                    require(out.size() + count <= 8*1024*1024); out.write(buffer, 0, count) }
                out.toByteArray().toString(Charsets.UTF_8)
            }
        }
        return true
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { this.binding = binding; activity = binding.activity; binding.addActivityResultListener(this) }
    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this); binding = null; activity = null
        pending?.result?.error("DETACHED", "文件选择已中断，请重试", null); pending = null
    }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null); cancelled.values.forEach { it.set(true) }; running.values.forEach { it.cancel() }
        hubs.closeAll(); io.shutdown(); searchIo.shutdown(); accountChecks.shutdown(); imageIo.shutdown(); browserIo.shutdown()
    }
}
