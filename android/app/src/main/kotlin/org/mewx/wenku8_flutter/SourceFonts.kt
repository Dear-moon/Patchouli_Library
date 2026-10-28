package org.mewx.wenku8_flutter

import org.mewx.wenku8_flutter.legado.QueryTTF
import java.security.MessageDigest

/** Same QueryTTF matching contract, with an isolated, bounded four-font LRU. */
internal object SourceFonts {
    private data class Key(val owner: SourceState, val value: String)
    private val fonts = LinkedHashMap<Key, QueryTTF>(4, .75f, true)
    private const val MAX_BYTES = 32L * 1024 * 1024

    fun query(data: Any?, useCache: Boolean, run: SourceRun, fetch: (String) -> ByteArray): QueryTTF? {
        run.check()
        if (data !is String && data !is ByteArray) return null
        val bytes = if (data is ByteArray) data else (data as String).toByteArray()
        require(bytes.size <= 12 * 1024 * 1024) { "书源字体输入过大" }
        // Reading caches by the argument, including an HTTP URL, not by a
        // second fetch. Prefix avoids a String/ByteArray key collision.
        val key = if (useCache) Key(run.state, (if (data is String) "s:" else "b:") +
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }) else null
        if (key != null) synchronized(fonts) { fonts[key] }?.let { return it }
        val content = when (data) {
            is ByteArray -> data
            is String -> if (data.startsWith("http://", true) || data.startsWith("https://", true)) fetch(data)
                else cn.hutool.core.codec.Base64.decode(data)
            else -> return null
        }
        require(content.size <= 8 * 1024 * 1024) { "书源字体超过 8 MiB" }
        val result = QueryTTF(content, run::check)
        run.check()
        if (key != null && result.estimatedBytes() <= MAX_BYTES) synchronized(fonts) {
            fonts[key] = result
            while (fonts.size > 4 || fonts.values.sumOf { it.estimatedBytes() } > MAX_BYTES) fonts.remove(fonts.keys.first())
        }
        return result
    }

    fun clear(owner: SourceState) = synchronized(fonts) { fonts.keys.removeAll { it.owner === owner }; Unit }

    fun replace(text: String, error: QueryTTF?, correct: QueryTTF?, filter: Boolean, check: () -> Unit): String {
        if (error == null || correct == null) return text
        val result = StringBuilder(text.length)
        var index = 0
        var steps = 0
        while (index < text.length) {
            if (steps++ and 1023 == 0) check()
            val code = text.codePointAt(index)
            index += Character.charCount(code)
            if (error.isBlankUnicode(code)) { result.appendCodePoint(code); continue }
            val glyph = if (error.getGlyfIdByUnicode(code) == 0) null else error.getGlyfByUnicode(code)
            if (filter && glyph == null) continue
            val replacement = correct.getUnicodeByGlyf(glyph)
            result.appendCodePoint(if (replacement != 0) replacement else code)
        }
        return result.toString()
    }
}
