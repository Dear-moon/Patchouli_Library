package org.mewx.wenku8_flutter

import java.net.CookieManager
import java.net.CookiePolicy
import java.net.HttpCookie
import java.net.HttpURLConnection
import java.net.URI
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.GZIPInputStream
import org.jsoup.Jsoup
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.util.concurrent.TimeUnit

/** No global Android cookie jar: one source can never read another source's
 * login. Redirects are manual so credentials are stripped across origins. */
internal class SourceNetwork(private val sessionChanged: (String) -> Unit = {}) {
    private val jars = ConcurrentHashMap<String, CookieManager>()
    private val configuredDns = java.util.concurrent.ConcurrentHashMap<Pair<String, String>, okhttp3.Dns>()
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .connectTimeout(6, TimeUnit.SECONDS).readTimeout(8, TimeUnit.SECONDS).build()
    fun clear(key: String) { jars.remove(key) }
    fun hasCookies(key: String): Boolean = jars[key]?.cookieStore?.cookies?.any { !it.hasExpired() } == true
    fun cookie(key: String, address: String): String {
        val uri = url(address)
        return jars[key]?.get(uri, emptyMap())?.entries?.firstOrNull { it.key.equals("Cookie", true) }?.value?.joinToString("; ").orEmpty()
    }
    fun setCookie(key: String, address: String, value: String) {
        val uri = url(address)
        val previous = cookie(key, address)
        val jar = jars.computeIfAbsent(key) { CookieManager(null, CookiePolicy.ACCEPT_ORIGINAL_SERVER) }
        value.split(';').map(String::trim).filter { '=' in it }.forEach { pair ->
            val parts = pair.split('=', limit = 2)
            jar.cookieStore.add(uri, HttpCookie(parts[0], parts[1]).apply { version = 0; path = "/"; domain = uri.host; maxAge = -1 })
        }
        if (previous != cookie(key, address)) sessionChanged(key)
    }
    fun removeCookie(key: String, address: String) {
        val uri = url(address); val jar = jars[key] ?: return
        val previous = cookie(key, address)
        jar.cookieStore.get(uri).forEach { jar.cookieStore.remove(uri, it) }
        if (previous != cookie(key, address)) sessionChanged(key)
    }
    fun session(key: String): String = com.google.gson.Gson().toJson(jars[key]?.let { jar ->
        jar.cookieStore.cookies.filter { !it.hasExpired() }.map { cookie ->
            val origin = jar.cookieStore.getURIs().firstOrNull { cookie in jar.cookieStore.get(it) }
            mapOf("name" to cookie.name, "value" to cookie.value, "domain" to cookie.domain, "path" to cookie.path,
                "secure" to cookie.secure, "version" to cookie.version, "maxAge" to cookie.maxAge,
                "savedAt" to System.currentTimeMillis(), "origin" to origin?.toString())
        }
    } ?: emptyList<Any>())
    fun restore(key: String, text: String) {
        val jar = jars.computeIfAbsent(key) { CookieManager(null, CookiePolicy.ACCEPT_ORIGINAL_SERVER) }
        val entries = com.google.gson.Gson().fromJson(text, List::class.java)
        for (raw in entries) {
            val item = raw as? Map<*, *> ?: continue
            val age = (item["maxAge"] as? Number)?.toLong() ?: -1
            // Session cookies use server verification instead of an invented local expiry.
            val remaining = if (age < 0) -1 else age - (System.currentTimeMillis() - ((item["savedAt"] as? Number)?.toLong() ?: 0)) / 1000
            if (remaining == 0L || age >= 0 && remaining < 0) continue
            val cookie = HttpCookie(item["name"].toString(), item["value"].toString()).apply {
                version = (item["version"] as? Number)?.toInt()?.coerceIn(0, 1) ?: 0
                domain = item["domain"] as? String; path = item["path"] as? String ?: "/"
                secure = item["secure"] == true; maxAge = remaining
            }
            val origin = item["origin"] as? String
            val domain = cookie.domain?.removePrefix(".")
            val uri = if (origin != null) URI(origin) else {
                if (domain == null) continue
                URI("${if (cookie.secure) "https" else "http"}://$domain")
            }
            if (cookie.domain == null) cookie.domain = uri.host
            jar.cookieStore.add(uri, cookie)
        }
    }
    fun socket(key: String, address: String, headers: Map<String, String>, listener: okhttp3.WebSocketListener): okhttp3.WebSocket {
        val uri = url(address)
        val request = Request.Builder().url(uri.toString()).header("User-Agent", USER_AGENT).apply {
            for ((name, value) in headers) {
                if (name.lowercase() !in setOf("host", "content-length", "connection", "transfer-encoding")) sourceHeader(name, value)
            }
            if (headers.keys.none { it.equals("Cookie", true) }) {
                cookie(key, address).takeIf { it.isNotBlank() }?.let { sourceHeader("Cookie", it) }
            }
        }.build()
        return client.newWebSocket(request, listener)
    }

    fun text(key: String?, address: String, method: String, headers: Map<String, String>, body: ByteArray?, run: SourceRun, options: SourceHttpOptions = SourceHttpOptions()): SourceReply {
        val reply = bytes(key, address, method, headers, body, run, options)
        val declared = Regex("charset\\s*=\\s*['\"]?([^;'\"\\s]+)", RegexOption.IGNORE_CASE).find(reply.type)?.groupValues?.get(1)
        val text = try {
            if (declared != null) reply.data.toString(charset(declared))
            else if (reply.type.contains("json", true)) reply.data.toString(Charsets.UTF_8)
            else Jsoup.parse(reply.data.inputStream(), null, reply.url).let {
                // Jsoup detects HTML charset but wrapping JSON/plain text would
                // break JSONPath and regex-only sources.
                reply.data.toString(it.charset())
            }
        } catch (_: Exception) { reply.data.toString(Charsets.UTF_8) }
        return SourceReply(reply.url, text.removePrefix("\uFEFF"), reply.status, reply.headers, reply.data, reply.message)
    }
    data class Bytes(val url: String, val type: String, val data: ByteArray, val status: Int = 200, val headers: Map<String, List<String>> = emptyMap(), val message: String = "OK")
    fun bytes(key: String?, address: String, method: String = "GET", headers: Map<String, String> = emptyMap(), body: ByteArray? = null, run: SourceRun, options: SourceHttpOptions = SourceHttpOptions(), destination: File? = null, onProgress: ((Long, Long?) -> Unit)? = null): Bytes {
        var uri = url(address); val origin = uri
        var verb = method; var payload = body
        require(options.callTimeout == null || options.callTimeout >= 0) { "书源请求超时不可为负数" }
        val started = System.nanoTime()
        val callDeadline = options.callTimeout?.takeIf { it > 0 }?.let {
            minOf(run.deadline, started + TimeUnit.MILLISECONDS.toNanos(it).coerceAtMost(Long.MAX_VALUE - started))
        } ?: run.deadline
        fun remaining() = ((callDeadline - System.nanoTime()) / 1_000_000).coerceAtLeast(1)
        // Legado's flag controls automatic Set-Cookie saving. Cookies explicitly
        // saved by a web login or script must still be sent when it is disabled.
        val jar = key?.let { jars.computeIfAbsent(it) { CookieManager(null, CookiePolicy.ACCEPT_ORIGINAL_SERVER) } }
        val scoped = client.newBuilder().apply {
            options.timeout?.let { readTimeout(it, TimeUnit.MILLISECONDS) }
            callTimeout(remaining(), TimeUnit.MILLISECONDS)
            options.proxy?.takeIf { it.isNotBlank() }?.let {
                require(options.dnsIp.isNullOrBlank()) { "书源不能同时指定代理和 DNS IP" }
                val proxy = URI(it); require(proxy.scheme in setOf("http", "socks", "socks5") && proxy.host != null && proxy.port in 1..65535)
                proxy(java.net.Proxy(if (proxy.scheme == "http") java.net.Proxy.Type.HTTP else java.net.Proxy.Type.SOCKS, java.net.InetSocketAddress(proxy.host, proxy.port)))
            }
            options.dnsIp?.takeIf { it.isNotBlank() }?.let { addresses ->
                val ips = addresses.split(',').map { raw ->
                    val ip = raw.trim().removeSurrounding("[", "]")
                    require(ip.matches(Regex("[0-9.]+")) || ':' in ip && ip.matches(Regex("[0-9a-fA-F:]+"))) { "书源 DNS IP 无效" }
                    java.net.InetAddress.getByName(ip)
                }
                dns(configuredDns.computeIfAbsent(origin.host.lowercase() to addresses) {
                    object : okhttp3.Dns {
                        override fun lookup(hostname: String) = if (hostname.equals(origin.host, true)) ips else okhttp3.Dns.SYSTEM.lookup(hostname)
                    }
                })
            }
        }.build()
        for (hop in 0..5) {
            run.check()
            if (System.nanoTime() >= callDeadline) throw java.net.SocketTimeoutException("书源请求超时")
            val request = Request.Builder().url(uri.toString()).apply {
                header("User-Agent", USER_AGENT)
                for ((name, value) in headers) {
                    if (name.lowercase() in setOf("host", "content-length", "connection", "transfer-encoding")) continue
                    if (!sameOrigin(uri, origin) && sensitive(name)) continue
                    sourceHeader(name, value)
                }
                jar?.get(uri, emptyMap())?.forEach { (name, values) ->
                    if (name.equals("Cookie", true) && values.isNotEmpty() && headers.keys.none { it.equals("Cookie", true) }) sourceHeader(name, values.joinToString("; "))
                }
                val type = headers.entries.firstOrNull { it.key.equals("Content-Type", true) }?.value ?: "application/x-www-form-urlencoded"
                method(verb, if (verb == "POST") (payload ?: byteArrayOf()).toRequestBody(type.toMediaTypeOrNull()) else null)
            }.build()
            val call = (if (hop == 0) scoped else scoped.newBuilder().callTimeout(remaining(), TimeUnit.MILLISECONDS).build()).newCall(request)
            val unregister = run.onCancel(call::cancel)
            run.metrics.httpCalls.incrementAndGet()
            val networkStarted = System.nanoTime()
            try {
                call.execute().use { response ->
                run.check(); val status = response.code
                if (options.cookieJar) {
                    val receivesCookies = response.headers.values("Set-Cookie").isNotEmpty()
                    val previous = if (key != null && receivesCookies) cookie(key, uri.toString()) else null
                    jar?.put(uri, response.headers.toMultimap())
                    if (key != null && previous != null && previous != cookie(key, uri.toString())) sessionChanged(key)
                }
                if (options.followRedirects && status in setOf(301, 302, 303, 307, 308)) {
                    check(hop < 5) { "书源重定向次数过多" }
                    uri = url(resolve(uri.toString(), response.header("Location") ?: error("重定向缺少地址")).toString())
                    if (status == 303 || (status in setOf(301, 302) && verb == "POST")) { verb = "GET"; payload = null }
                } else {
                    val stream = response.body?.byteStream() ?: java.io.ByteArrayInputStream(byteArrayOf())
                    val total = response.body?.contentLength()?.takeIf { it >= 0 }
                    val data = stream.use { input ->
                        val out = destination?.outputStream() ?: ByteArrayOutputStream()
                        var received = 0L
                        var reportedAt = System.nanoTime()
                        onProgress?.invoke(0, total)
                        out.use { output ->
                            val buffer = ByteArray(16384)
                            while (true) {
                                run.check()
                                val count = input.read(buffer)
                                if (count < 0) break
                                received += count
                                check(received <= options.maxResponseBytes) { "书源单次响应超过 ${options.maxResponseBytes / (1024 * 1024)} MiB" }
                                output.write(buffer, 0, count)
                                val now = System.nanoTime()
                                if (now - reportedAt >= 100_000_000L) {
                                    onProgress?.invoke(received, total)
                                    reportedAt = now
                                }
                            }
                        }
                        onProgress?.invoke(received, total)
                        if (out is ByteArrayOutputStream) out.toByteArray() else byteArrayOf()
                    }
                    return Bytes(uri.toString(), response.header("Content-Type").orEmpty(), data, status, response.headers.toMultimap(), response.message)
                }
                }
            } catch (failure: Exception) { run.check(); throw failure }
            finally { run.metrics.httpNanos.addAndGet(System.nanoTime() - networkStarted); unregister() }
        }
        error("书源重定向失败")
    }
    companion object {
        // Keep OkHttp's HTTP validation. Never encode, drop, or echo a malformed
        // credential; the exception message contains its value and stays local.
        private fun Request.Builder.sourceHeader(name: String, value: String) {
            try { header(name, value) } catch (_: IllegalArgumentException) { throw SourceHeaderFailure() }
        }
        const val USER_AGENT = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36"
        fun resolve(base: String, value: String): URI {
            val root = base.substringBefore("##")
            return when {
                value.isEmpty() -> URI(root)
                value.startsWith('?') -> URI(root.substringBefore('#').substringBefore('?') + value)
                else -> URI(root).resolve(value)
            }
        }
        fun url(raw: String): URI {
            val address = raw.substringBefore("##")
            val original = runCatching { URI(address) }.getOrNull()
            require(original?.userInfo == null) { "仅支持 HTTP / HTTPS 地址" }
            // Preserve existing locator spelling (including Unicode paths): it
            // owns persisted chapter IDs. Only repair previously unusable IRIs.
            val uri = original?.takeIf { it.scheme in setOf("http", "https") && !it.host.isNullOrEmpty() }
                ?: address.toHttpUrlOrNull()?.toUri()
                ?: throw IllegalArgumentException("仅支持 HTTP / HTTPS 地址")
            require(uri.scheme in setOf("https", "http") && !uri.host.isNullOrEmpty() && uri.userInfo == null && uri.port in -1..65535) { "仅支持 HTTP / HTTPS 地址" }
            return uri
        }
        private fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
        fun sameOrigin(a: URI, b: URI): Boolean = a.scheme == b.scheme && a.host.equals(b.host, true) && port(a) == port(b)
        fun sensitive(name: String): Boolean = Regex("cookie|authorization|token|api[-_]?key", RegexOption.IGNORE_CASE).containsMatchIn(name)
    }
}
