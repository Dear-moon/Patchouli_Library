package org.mewx.wenku8_flutter.legado

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.net.URI
import java.net.URL
import java.util.regex.Pattern

/** Application services are separate from the upstream rule grammar. */
interface RuleHost {
    fun check()
    fun put(key: String, value: String): String
    fun get(key: String): String
    fun evalJS(code: String, result: Any?, content: Any?, baseUrl: String?): Any?
    fun webJS(code: String, result: Any?, content: Any?, baseUrl: String?): String
}

internal val GSON = org.mewx.wenku8_flutter.legado.js.SourceGson.gson
internal val JS_PATTERN: Pattern = Pattern.compile("<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", Pattern.CASE_INSENSITIVE)
internal val WebJS_PATTERN: Pattern = Pattern.compile("@webjs:([\\w\\W]{5,})", Pattern.CASE_INSENSITIVE)
internal inline fun <reified T> Gson.fromJsonObject(text: String?): Result<T> =
    runCatching { fromJson<T>(text, object : TypeToken<T>() {}.type) }
internal inline fun <reified T> Gson.fromJsonArray(text: String?): Result<List<T>> =
    runCatching { fromJson<List<T>>(text, object : TypeToken<List<T>>() {}.type) }
internal fun String.isJson(): Boolean = trim().let { it.startsWith('{') && it.endsWith('}') || it.startsWith('[') && it.endsWith(']') }
internal fun String.isDataUrl(): Boolean = startsWith("data:", true)
internal fun String.splitNotBlank(delimiter: String): Array<String> = split(delimiter).filter { it.isNotBlank() }.toTypedArray()
internal inline fun <K, V> MutableMap<K, V>.getOrPutLimit(key: K, limit: Int, value: () -> V): V {
    if (containsKey(key)) return getValue(key)
    if (size >= limit) remove(keys.first())
    return value().also { put(key, it) }
}

internal object NetworkUtils {
    fun getAbsoluteURL(base: URL?, relative: String): String = getAbsoluteURL(base?.toString().orEmpty(), relative)
    fun getAbsoluteURL(base: String, relative: String): String {
        val value = relative.trim()
        if (value.isEmpty()) return ""
        if (value.startsWith("data:", true)) return value
        return try {
            val parts = value.split(Regex(",\\s*(?=\\{)"), limit = 2)
            val root = base.split(Regex(",\\s*(?=\\{)"), limit = 2)[0]
            val resolved = if (root.isBlank()) parts[0] else URL(URL(root), parts[0]).toString()
            resolved + if (parts.size > 1) ",${parts[1]}" else ""
        } catch (_: Exception) { value }
    }
}
