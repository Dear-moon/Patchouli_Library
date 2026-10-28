/* Adapted contract from Legado JsExtensions/EncoderUtils, GPL-3.0;
 * reference 3046111c1718e7b67c2ad468e54edf295ec05820. */
package org.mewx.wenku8_flutter.legado

import java.nio.charset.Charset
import java.util.Base64

/** JVM/Android-equivalent base64 flags for the JsExtensions/EncoderUtils
 * contract. Android Base64 is not available in plain JVM conformance tests. */
internal object SourceTextHelpers {
    private val chapterNumber = java.util.regex.Pattern.compile("(第)(.+?)(章)")
    private val numbers = buildMap<Char, Int> {
        listOf("零一二三四五六七八九十", "〇壹贰叁肆伍陆柒捌玖拾").forEach { chars -> chars.forEachIndexed { index, c -> put(c, index) } }
        put('两', 2); put('百', 100); put('佰', 100); put('千', 1000); put('仟', 1000); put('万', 10000); put('亿', 100000000)
    }
    // Same integer conversion as upstream StringUtils, including failure -1.
    fun toNumChapter(text: String?): String? {
        text ?: return null
        val match = chapterNumber.matcher(text)
        if (!match.find()) return text
        val raw = match.group(2)!!.map { when {
            it == '\u3000' -> ' '
            it.code in 65281..65374 -> (it.code - 65248).toChar()
            else -> it
        } }.joinToString("").replace(Regex("\\s+"), "")
        val number = raw.toIntOrNull() ?: runCatching {
            var result = 0; var tmp = 0; var billion = 0
            for ((index, c) in raw.withIndex()) {
                val n = numbers[c] ?: error("not a chapter number")
                when {
                    n == 100000000 -> { result += tmp; result *= n; billion = billion * n + result; result = 0; tmp = 0 }
                    n == 10000 -> { result += tmp; result *= n; tmp = 0 }
                    n >= 10 -> { if (tmp == 0) tmp = 1; result += n * tmp; tmp = 0 }
                    else -> { tmp = if (index >= 2 && index == raw.lastIndex && numbers[raw[index - 1]]!! > 10) n * numbers[raw[index - 1]]!! / 10 else tmp * 10 + n }
                }
            }
            result + tmp + billion
        }.getOrDefault(-1)
        return "${match.group(1)}$number${match.group(3)}"
    }
    fun base64Bytes(raw: String?, flags: Int = 0): ByteArray? {
        if (raw.isNullOrBlank()) return null
        val normalized = raw.filterNot { it.isWhitespace() }
        return if (flags and 8 != 0) Base64.getUrlDecoder().decode(normalized) else Base64.getDecoder().decode(normalized)
    }
    fun base64Decode(raw: String?, charset: String = "UTF-8", flags: Int = 0): String =
        base64Bytes(raw, flags)?.toString(Charset.forName(charset)).orEmpty()
    fun base64Encode(raw: String, flags: Int = 2): String {
        var encoder = if (flags and 8 != 0) Base64.getUrlEncoder() else Base64.getEncoder()
        if (flags and 1 != 0) encoder = encoder.withoutPadding()
        val encoded = encoder.encodeToString(raw.toByteArray())
        if (flags and 2 != 0 || encoded.isEmpty()) return encoded
        val separator = if (flags and 4 != 0) "\r\n" else "\n"
        return encoded.chunked(76).joinToString(separator, postfix = separator)
    }
}
