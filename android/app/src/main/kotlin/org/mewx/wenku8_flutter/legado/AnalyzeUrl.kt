/* Adapted from Legado 3.0, GPL-3.0, gedoor and contributors.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Modified 2026-10-18: platform-independent request specification; host performs IO.
 */
package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import cn.hutool.core.codec.PercentCodec
import cn.hutool.core.net.RFC3986
import com.google.gson.annotations.SerializedName
import java.net.URLEncoder
import java.nio.charset.Charset
import java.util.regex.Pattern
import kotlin.math.max

enum class RequestMethod { GET, POST, HEAD }

class AnalyzeUrl(
    private val mUrl: String,
    private val key: String? = null,
    private val page: Int? = null,
    private var baseUrl: String = "",
    headers: Map<String, String> = emptyMap(),
    private val eval: (String, Any?, String) -> Any?,
) {
    var ruleUrl = ""; private set
    var url = ""; private set
    var urlNoQuery = ""; private set
    var type: String? = null; private set
    val headerMap = LinkedHashMap(headers)
    private var body: String? = null
    private var encodedForm: String? = null
    private var encodedQuery: String? = null
    private var charset: String? = null
    var method = RequestMethod.GET; private set
    var retry = 0; private set
    var useWebView = false; private set
    var webJs: String? = null; private set
    var bodyJs: String? = null; private set
    var readTimeoutMs: Long? = null; private set
    private var urlTimeoutConfigured = false
    var followRedirects: Boolean? = null; private set
    var dnsIp: String? = null; private set
    var serverID: Long? = null; private set
    var webViewDelayTime = 0L; private set

    init {
        val matcher = paramPattern.matcher(baseUrl)
        if (matcher.find()) baseUrl = baseUrl.substring(0, matcher.start())
        initUrl()
    }
    fun evalJS(code: String, result: Any? = null): Any? = eval(code, result, baseUrl)
    private fun log(message: String) { /* Do not log source credentials. */ }
    fun requestUrl(): String = if (method == RequestMethod.POST || encodedQuery == null) url else "$urlNoQuery?$encodedQuery"
    fun requestBody(): ByteArray? {
        if (method != RequestMethod.POST) return null
        val text = if (!encodedForm.isNullOrEmpty() || body.isNullOrBlank()) {
            if (headerMap.keys.none { it.equals("Content-Type", true) }) headerMap["Content-Type"] = "application/x-www-form-urlencoded"
            encodedForm.orEmpty()
        } else {
            if (headerMap.keys.none { it.equals("Content-Type", true) }) headerMap["Content-Type"] = "application/json; charset=utf-8"
            body.orEmpty()
        }
        return text.toByteArray(Charsets.UTF_8)
    }

    fun initUrl() {
        ruleUrl = mUrl
        //执行@js,<js></js>
        analyzeJs()
        //替换参数
        replaceKeyPageJs()
        //处理URL
        analyzeUrl()
    }

    /**
     * 执行@js,<js></js>
     */
    private fun analyzeJs() {
        var start = 0
        val jsMatcher = JS_PATTERN.matcher(ruleUrl)
        var result = ruleUrl
        while (jsMatcher.find()) {
            if (jsMatcher.start() > start) {
                ruleUrl.substring(start, jsMatcher.start()).trim().let {
                    if (it.isNotEmpty()) {
                        result = it.replace("@result", result)
                    }
                }
            }
            result = evalJS(jsMatcher.group(2) ?: jsMatcher.group(1), result).toString()
            start = jsMatcher.end()
        }
        if (ruleUrl.length > start) {
            ruleUrl.substring(start).trim().let {
                if (it.isNotEmpty()) {
                    result = it.replace("@result", result)
                }
            }
        }
        ruleUrl = result
    }

    /**
     * 替换关键字,页数,JS
     */
    private fun replaceKeyPageJs() { //先替换内嵌规则再替换页数规则，避免内嵌规则中存在大于小于号时，规则被切错
        //js
        if (ruleUrl.contains("{{") && ruleUrl.contains("}}")) {
            val analyze = RuleAnalyzer(ruleUrl) //创建解析
            //替换所有内嵌{{js}}
            val url = analyze.innerRule("{{", "}}") {
                val jsEval = evalJS(it) ?: ""
                when (jsEval) {
                    is String -> jsEval
                    is Double -> if (jsEval % 1.0 == 0.0) String.format(java.util.Locale.ROOT, "%.0f", jsEval) else jsEval.toString()
                    else -> jsEval.toString()
                }
            }
            if (url.isNotEmpty()) ruleUrl = url
        }
        //page
        page?.let {
            val matcher = pagePattern.matcher(ruleUrl)
            while (matcher.find()) {
                val pages = matcher.group(1)!!.split(",")
                ruleUrl = if (page < pages.size) { //pages[pages.size - 1]等同于pages.last()
                    ruleUrl.replace(matcher.group(), pages[page - 1].trim { it <= ' ' })
                } else {
                    ruleUrl.replace(matcher.group(), pages.last().trim { it <= ' ' })
                }
            }
        }
    }

    /**
     * 解析Url
     */
    private fun analyzeUrl() {
        //replaceKeyPageJs已经替换掉额外内容，此处url是基础形式，可以直接切首个‘,’之前字符串。
        val urlMatcher = paramPattern.matcher(ruleUrl)
        val urlNoOption =
            if (urlMatcher.find()) ruleUrl.substring(0, urlMatcher.start()) else ruleUrl
        url = NetworkUtils.getAbsoluteURL(baseUrl, urlNoOption)
        runCatching { java.net.URL(url).let { "${it.protocol}://${it.authority}" } }.getOrNull()?.let {
            baseUrl = it
        }
        if (urlNoOption.length != ruleUrl.length) {
            val urlOptionStr = ruleUrl.substring(urlMatcher.end())
            var urlOption = GSON.fromJsonObject<UrlOption>(urlOptionStr).getOrNull()
            if (urlOption == null) {
                urlOption = GSON.fromJsonObject<UrlOption>(urlOptionStr).getOrNull()
                if (urlOption != null) {
                    log("链接参数 JSON 格式不规范，请改为规范格式")
                }
            }
            urlOption?.let { option ->
                option.getMethod()?.let {
                    method = when (it.uppercase()) {
                        "POST" -> RequestMethod.POST
                        "HEAD" -> RequestMethod.HEAD
                        else -> RequestMethod.GET
                    }
                }
                option.getHeaderMap()?.forEach { entry ->
                    headerMap[entry.key.toString()] = entry.value.toString()
                }
                option.getBody()?.let {
                    body = it
                }
                type = option.getType()
                charset = option.getCharset()
                retry = option.getRetry()
                useWebView = option.useWebView()
                webJs = option.getWebJs()
                bodyJs = option.getBodyJs()
                option.getTimeout()?.let {
                    readTimeoutMs = it
                    urlTimeoutConfigured = true
                }
                followRedirects = option.getFollowRedirects()
                dnsIp = option.getDnsIp()
                option.getJs()?.let { jsStr ->
                    evalJS(jsStr, url)?.toString()?.let {
                        url = it
                    }
                }
                serverID = option.getServerID()
                webViewDelayTime = max(0, option.getWebViewDelayTime() ?: 0)
            }
        }
        urlNoQuery = url
        when (method) {
            RequestMethod.POST -> body?.let {
                if (!it.isJson() && !it.isXml() && headerMap["Content-Type"].isNullOrEmpty()) {
                    analyzeFields(it)
                }
            }

            else -> {
                val pos = url.indexOf('?')
                if (pos != -1) {
                    analyzeQuery(url.substring(pos + 1))
                    urlNoQuery = url.substring(0, pos)
                }
            }
        }
    }

    /**
     * 解析QueryMap <key>=<value>
     * name=
     * name=name
     * name=<BASE64> eg name=bmFtZQ==
     */
    private fun analyzeFields(fieldsTxt: String) {
        encodedForm = encodeParams(fieldsTxt, charset, false)
    }

    private fun analyzeQuery(query: String) {
        encodedQuery = encodeParams(query, charset, true)
    }

    private fun encodeParams(params: String, charset: String?, isQuery: Boolean): String {
        val checkEncoded = charset.isNullOrEmpty()
        val charset = when {
            charset.isNullOrEmpty() -> Charsets.UTF_8
            charset == "escape" -> null
            else -> charset(charset)
        }
        if (isQuery && charset != null) {
            if (UrlCodecs.encodedQuery(params)) {
                return params
            }
            return queryEncoder.encode(params, charset)
        }
        val len = params.length
        val sb = StringBuilder()
        var pos = 0
        while (pos <= len) {
            if (sb.isNotEmpty()) {
                sb.append("&")
            }
            var ampOffset = params.indexOf("&", pos)
            if (ampOffset == -1) {
                ampOffset = len
            }
            val eqOffset = params.indexOf("=", pos)
            val key: String
            val value: String?
            if (eqOffset == -1 || eqOffset > ampOffset) {
                key = params.substring(pos, ampOffset)
                value = null
            } else {
                key = params.substring(pos, eqOffset)
                value = params.substring(eqOffset + 1, ampOffset)
            }
            sb.appendEncoded(key, checkEncoded, charset)
            if (value != null) {
                sb.append("=")
                sb.appendEncoded(value, checkEncoded, charset)
            }
            pos = ampOffset + 1
        }
        return sb.toString()
    }

    private fun StringBuilder.appendEncoded(
        value: String,
        checkEncoded: Boolean,
        charset: Charset?
    ) {
        if (checkEncoded && UrlCodecs.encodedForm(value)) {
            append(value)
        } else if (charset == null) {
            append(EncoderUtils.escape(value))
        } else {
            append(URLEncoder.encode(value, charset))
        }
    }



    companion object {
        val paramPattern: Pattern = Pattern.compile("\\s*,\\s*(?=\\{)")
        private val pagePattern = Pattern.compile("<(.*?)>")
        private val queryEncoder = RFC3986.UNRESERVED.orNew(PercentCodec.of("!$%&()*+,/:;=?@[\\]^`{|}"))
    }
    @Keep
    data class UrlOption(
        private var method: String? = null,
        private var charset: String? = null,
        private var headers: Any? = null,
        private var body: Any? = null,
        /**
         * 源Url
         **/
        private var origin: String? = null,
        /**
         * 重试次数
         **/
        private var retry: Int? = null,
        /**
         * 类型
         **/
        private var type: String? = null,
        /**
         * 是否使用webView
         **/
        private var webView: Any? = null,
        /**
         * webView中执行的js
         **/
        private var webJs: String? = null,
        /**
         * 读取超时（毫秒）
         **/
        private var timeout: Any? = null,
        /**
         * 是否跟随重定向
         **/
        private var followRedirects: Any? = null,
        /**
         * 自定义的域名ip
         **/
        @SerializedName(value = "dnsIp", alternate = ["resolveIp"])
        private var dnsIp: String? = null,
        /**
         * 解析完url参数时执行的js
         * 执行结果会赋值给url
         */
        private var js: String? = null,
        /**
         * 得到访问结果后执行的js,对结果进行二次处理
         * 执行结果返回为body
         */
        private var bodyJs: String? = null,
        /**
         * 服务器id
         */
        private var serverID: Long? = null,
        /**
         * webview等待页面加载完毕的延迟时间（毫秒）
         */
        private var webViewDelayTime: Long? = null,
    ) {
        fun setMethod(value: String?) {
            method = if (value.isNullOrBlank()) null else value
        }

        fun getMethod(): String? {
            return method
        }

        fun setCharset(value: String?) {
            charset = if (value.isNullOrBlank()) null else value
        }

        fun getCharset(): String? {
            return charset
        }

        fun setOrigin(value: String?) {
            origin = if (value.isNullOrBlank()) null else value
        }

        fun getOrigin(): String? {
            return origin
        }

        fun setRetry(value: String?) {
            retry = if (value.isNullOrEmpty()) null else value.toIntOrNull()
        }

        fun getRetry(): Int {
            return retry ?: 0
        }

        fun setType(value: String?) {
            type = if (value.isNullOrBlank()) null else value
        }

        fun getType(): String? {
            return type
        }

        fun useWebView(): Boolean {
            return when (webView) {
                null, "", false, "false" -> false
                else -> true
            }
        }

        fun useWebView(boolean: Boolean) {
            webView = if (boolean) true else null
        }

        fun setHeaders(value: String?) {
            headers = if (value.isNullOrBlank()) {
                null
            } else {
                GSON.fromJsonObject<Map<String, Any>>(value).getOrNull()
            }
        }

        fun getHeaderMap(): Map<*, *>? {
            return when (val value = headers) {
                is Map<*, *> -> value
                is String -> GSON.fromJsonObject<Map<String, Any>>(value).getOrNull()
                else -> null
            }
        }

        fun setBody(value: String?) {
            body = when {
                value.isNullOrBlank() -> null
                value.isJsonObject() -> GSON.fromJsonObject<Map<String, Any>>(value).getOrNull()
                value.isJsonArray() -> GSON.fromJsonArray<Map<String, Any>>(value).getOrNull()
                else -> value
            }
        }

        fun getBody(): String? {
            return body?.let {
                it as? String ?: GSON.toJson(it)
            }
        }

        fun setWebJs(value: String?) {
            webJs = if (value.isNullOrBlank()) null else value
        }

        fun getWebJs(): String? {
            return webJs
        }

        fun setTimeout(value: String?) {
            timeout = value
        }

        fun getTimeout(): Long? {
            return parseRequestTimeoutMillis(timeout)
        }

        fun setFollowRedirects(value: String?) {
            followRedirects = value
        }

        fun getFollowRedirects(): Boolean? {
            return parseBooleanOption(followRedirects)
        }

        fun setDnsIp(value: String?) {
            dnsIp = if (value.isNullOrBlank()) null else value.trim()
        }

        fun getDnsIp(): String? {
            return dnsIp
        }

        fun setJs(value: String?) {
            js = if (value.isNullOrBlank()) null else value
        }

        fun getJs(): String? {
            return js
        }

        fun setBodyJs(value: String?) {
            bodyJs = if (value.isNullOrBlank()) null else value
        }

        fun getBodyJs(): String? {
            return bodyJs
        }

        fun setServerID(value: String?) {
            serverID = if (value.isNullOrBlank()) null else value.toLong()
        }

        fun getServerID(): Long? {
            return serverID
        }

        fun setWebViewDelayTime(value: String?) {
            webViewDelayTime = if (value.isNullOrBlank()) null else value.toLong()
        }

        fun getWebViewDelayTime(): Long? {
            return webViewDelayTime
        }
    }

}

private const val MAX_OKHTTP_TIMEOUT_MILLIS = Int.MAX_VALUE.toLong()

internal fun parseRequestTimeoutMillis(value: Any?): Long? {
    val timeout = when (value) {
        is Byte, is Short, is Int, is Long -> (value as Number).toLong()
        is Float, is Double -> value.toDouble().takeIf {
            it.isFinite() && it % 1.0 == 0.0 && it <= Long.MAX_VALUE.toDouble()
        }?.toLong()
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull()
        else -> null
    }
    return timeout?.takeIf { it in 1..MAX_OKHTTP_TIMEOUT_MILLIS }
}

internal fun parseBooleanOption(value: Any?): Boolean? {
    return when (value) {
        is Boolean -> value
        is Number -> when (value.toDouble()) {
            0.0 -> false
            1.0 -> true
            else -> null
        }
        is String -> when (value.trim().lowercase()) {
            "true", "1" -> true
            "false", "0" -> false
            else -> null
        }
        else -> null
    }
}


internal fun String.isJsonObject() = trim().let { it.startsWith('{') && it.endsWith('}') }
internal fun String.isJsonArray() = trim().let { it.startsWith('[') && it.endsWith(']') }
internal fun String.isXml() = trim().startsWith('<')
