package org.mewx.wenku8_flutter

import androidx.annotation.Keep
import java.net.URL

/** Legado StrResponse surface. Separate from Jsoup's URL-valued response. */
@Keep
internal class SourceResponse(private val response: SourceReply) {
    val body: String get() = response.body
    val url: String get() = response.url
    fun body(): String = response.body
    fun bodyAsBytes(): ByteArray = response.data ?: response.body.toByteArray()
    val raw = SourceRawResponse(response)
    var callTime: Int = response.callTime
    fun url(): String = response.url
    fun code(): Int = response.status
    fun statusCode(): Int = response.status
    fun isSuccessful(): Boolean = response.status in 200..299
    fun header(name: String): String = response.headers.entries.firstOrNull { it.key.equals(name, true) }?.value?.joinToString(", ").orEmpty()
    fun message(): String = response.message
    fun headers(): SourceHeaders = SourceHeaders(response.headers)
    fun cookies(): Map<String, String> = response.headers.entries.filter { it.key.equals("Set-Cookie", true) }
        .flatMap { it.value }.mapNotNull { raw -> runCatching { java.net.HttpCookie.parse(raw) }.getOrNull() }
        .flatten().associate { it.name to it.value }
    fun raw(): SourceRawResponse = raw
    fun errorBody(): SourceResponseBody? = if (response.status >= 400) SourceResponseBody(response) else null
    fun callTime(): Int = callTime
    fun putCallTime(value: Int) { callTime = value }
    internal fun reply(): SourceReply = response
}

@Keep
internal class SourceHeaders(private val headers: Map<String, List<String>>) {
    private val entries get() = headers.flatMap { (name, values) -> values.map { name to it } }
    fun get(name: String): String? = values(name).lastOrNull()
    fun values(name: String): List<String> = java.util.ArrayList(headers.entries.firstOrNull { it.key.equals(name, true) }?.value.orEmpty())
    fun size(): Int = headers.values.sumOf { it.size }
    fun name(index: Int): String = entries[index].first
    fun value(index: Int): String = entries[index].second
    fun toMultimap(): Map<String, List<String>> = headers
    override fun toString(): String = entries.joinToString("\n", postfix = if (headers.isEmpty()) "" else "\n") { "${it.first}: ${it.second}" }
}

@Keep
internal class SourceRawResponse(private val reply: SourceReply) {
    fun code() = reply.status
    fun message() = reply.message
    fun headers() = SourceHeaders(reply.headers)
    fun header(name: String): String? = headers().get(name)
    fun header(name: String, default: String?): String? = header(name) ?: default
    fun isSuccessful() = reply.status in 200..299
    fun request() = SourceResponseRequest(reply.url)
    fun body() = SourceResponseBody(reply)
}

@Keep
internal class SourceResponseRequest(private val address: String) {
    fun url() = URL(address)
}

@Keep
internal class SourceResponseBody(private val reply: SourceReply) {
    fun string() = reply.body
    fun bytes(): ByteArray = reply.data ?: reply.body.toByteArray()
    fun contentLength() = bytes().size.toLong()
    fun close() = Unit
}

/** JsExtensions.get/head/post return Jsoup Connection.Response: url() is URL,
 * headers() is a flat map, and parse() consumes the already fetched body. */
@Keep
internal class SourceJsoupResponse(private val reply: SourceReply, private val verb: String) {
    val body get() = reply.body
    val url get() = reply.url
    fun body() = reply.body
    fun bodyAsBytes(): ByteArray = reply.data ?: reply.body.toByteArray()
    fun url() = URL(reply.url)
    fun statusCode() = reply.status
    fun statusMessage() = reply.message
    fun method(): org.jsoup.Connection.Method = org.jsoup.Connection.Method.valueOf(verb)
    fun headers(): Map<String, String> = reply.headers.mapValues { it.value.joinToString(", ") }
    fun multiHeaders(): Map<String, List<String>> = reply.headers
    fun header(name: String): String = SourceHeaders(reply.headers).get(name).orEmpty()
    fun headers(name: String): List<String> = SourceHeaders(reply.headers).values(name)
    fun hasHeader(name: String): Boolean = SourceHeaders(reply.headers).get(name) != null
    fun hasHeaderWithValue(name: String, value: String): Boolean = headers(name).any { it.equals(value, true) }
    fun contentType(): String? = SourceHeaders(reply.headers).get("Content-Type")
    fun charset(): String? = Regex("charset=([^;\\s]+)", RegexOption.IGNORE_CASE).find(contentType().orEmpty())?.groupValues?.get(1)
    fun cookies(): Map<String, String> = SourceResponse(reply).cookies()
    fun cookie(name: String): String? = cookies()[name]
    fun hasCookie(name: String) = cookies().containsKey(name)
    fun parse(): org.jsoup.nodes.Document = org.jsoup.Jsoup.parse(reply.body, reply.url)
    fun bufferUp(): SourceJsoupResponse = this
}
