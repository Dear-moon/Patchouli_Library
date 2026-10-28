package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep

@Keep
class SourceCrypto : JsEncodeUtils

internal object Base64 {
    const val DEFAULT = 0
    const val NO_PADDING = 1
    const val NO_WRAP = 2
    const val CRLF = 4
    const val URL_SAFE = 8
    fun decode(text: String, flags: Int): ByteArray =
        (if (flags and URL_SAFE != 0) java.util.Base64.getUrlDecoder() else java.util.Base64.getMimeDecoder()).decode(text)
    fun encodeToString(bytes: ByteArray, flags: Int): String {
        var encoder = if (flags and URL_SAFE != 0) java.util.Base64.getUrlEncoder() else java.util.Base64.getEncoder()
        if (flags and NO_PADDING != 0) encoder = encoder.withoutPadding()
        val text = encoder.encodeToString(bytes)
        if (flags and NO_WRAP != 0 || text.isEmpty()) return text
        val line = if (flags and CRLF != 0) "\r\n" else "\n"
        return text.chunked(76).joinToString(line, postfix = line)
    }
}

internal fun String.isHex() = length % 2 == 0 && all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
