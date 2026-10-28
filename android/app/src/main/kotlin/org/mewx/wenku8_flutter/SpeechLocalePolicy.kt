package org.mewx.wenku8_flutter

import java.util.Locale

/** Public Android TTS engines and normalized language metadata. */
internal object SpeechLocalePolicy {
    private val chineseLanguages = setOf("zh", "chi", "zho")
    fun supportsEngine(id: String?): Boolean = id == "@default" ||
        (id != null && id.matches(Regex("[a-zA-Z0-9_]+(?:\\.[a-zA-Z0-9_]+)+")))
    fun language(locale: Locale): String = when (val code = locale.language.lowercase(Locale.ROOT)) {
        "chi", "zho" -> "zh"
        "jpn" -> "ja"
        "eng" -> "en"
        "kor" -> "ko"
        else -> code
    }
    fun requestedLocale(tag: String?): Locale? = tag?.takeIf {
        it.matches(Regex("[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8}){0,4}"))
    }?.let(Locale::forLanguageTag)?.takeIf { language(it).isNotEmpty() && language(it) != "und" }
    fun matches(requested: Locale, actual: Locale): Boolean = language(requested) == language(actual)
    fun chineseTag(locale: Locale): String? {
        val language = locale.language.lowercase(Locale.ROOT)
        if (language !in chineseLanguages) return null
        val parts = locale.toLanguageTag().split('-')
        val suffix = parts.drop(1).joinToString("-")
        return if (suffix.isEmpty()) "zh-CN" else "zh-$suffix"
    }
}
