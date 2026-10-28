/* Adapted from Legado 3.26082823, 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Copyright Legado contributors. GPL-3.0; see third_party/legado.
 * Source: model/webBook/BookInfo.kt, BookHelp formatBookName/Author,
 * HtmlFormatter.formatIntro and StringUtils.wordCountFormat.
 * Changes: app-independent map model; SourceRun cancellation and safe warnings
 * replace coroutine/Debug dependencies. Text sources only; no file download. */
package org.mewx.wenku8_flutter.legado.book

import org.mewx.wenku8_flutter.legado.AnalyzeRule
import java.text.DecimalFormat
import java.util.concurrent.CancellationException

internal object BookInfo {
    fun analyze(
        book: Map<String, Any?>,
        rule: Map<String, Any?>,
        analyzeRule: AnalyzeRule,
        body: String,
        baseUrl: String,
        redirectUrl: String,
        check: () -> Unit,
        strict: (String, () -> String) -> String,
        warning: (String, Exception) -> String,
        absolute: (String, String) -> String,
        onUpdate: (Map<String, Any?>) -> Unit,
        currentBook: () -> Map<String, Any?>,
    ): Map<String, Any?> {
        val result = LinkedHashMap(book)
        val warnings = mutableListOf<String>()
        fun refresh() { result.putAll(currentBook()) }
        fun text(name: String) = strict(name) { analyzeRule.getString(rule[name]?.toString()).also { refresh() } }
        fun optional(name: String, action: () -> Unit) {
            check()
            try { action() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { check(); warnings.add(warning(name, failure)) }
            onUpdate(result)
        }
        analyzeRule.setContent(body).setBaseUrl(baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        rule["init"]?.toString()?.takeIf { it.isNotBlank() }?.let {
            check()
            analyzeRule.setContent(analyzeRule.getElement(it), baseUrl)
            analyzeRule.setRedirectUrl(redirectUrl)
            refresh(); onUpdate(result)
        }
        val canReName = !rule["canReName"]?.toString().isNullOrBlank()
        check()
        text("name").replace(Regex("\\s+作\\s*者.*|\\s+\\S+\\s+著"), "").trim { it <= ' ' }.let {
            if (it.isNotEmpty() && (canReName || book["name"].isNullOrEmptyText())) result["name"] = it
        }
        onUpdate(result)
        check()
        text("author").replace(Regex("^\\s*作\\s*者[:：\\s]+|\\s+著"), "").trim { it <= ' ' }.let {
            if (it.isNotEmpty() && (canReName || book["author"].isNullOrEmptyText())) result["author"] = it
        }
        onUpdate(result)
        optional("kind") {
            val value = analyzeRule.getStringList(rule["kind"]?.toString()).also { refresh() }
            value?.joinToString(",")?.takeIf { it.isNotEmpty() }?.let { result["kind"] = it }
        }
        optional("wordCount") {
            val value = text("wordCount")
            val formatted = if (value.matches(Regex("[0-9]+"))) {
                val count = value.toInt()
                if (count > 10000) DecimalFormat("#.#").format(count * 1.0f / 10000f.toDouble()) + "万字"
                else if (count > 0) "${count}字" else ""
            } else value
            if (formatted.isNotEmpty()) result["wordCount"] = formatted
        }
        optional("lastChapter") { text("lastChapter").takeIf { it.isNotEmpty() }?.let { result["lastChapter"] = it } }
        optional("intro") {
            val intro = text("intro").trimStart()
            val formatted = if (listOf("<usehtml>", "<md>", "<useweb>").any { intro.startsWith(it) }) intro else formatIntro(intro)
            if (formatted.isNotEmpty()) result["intro"] = formatted
        }
        optional("coverUrl") {
            text("coverUrl").takeIf { it.isNotEmpty() }?.let { result["coverUrl"] = absolute(it, redirectUrl) }
        }
        check()
        result["tocUrl"] = strict("tocUrl") {
            analyzeRule.getString(rule["tocUrl"]?.toString(), isUrl = true).also { refresh() }
        }.ifEmpty { baseUrl }
        result["ruleWarnings"] = warnings
        // Session variables are owned by the native vault, never rule sharing.
        result.remove("variable")
        onUpdate(result)
        return result
    }

    private fun Any?.isNullOrEmptyText() = this == null || toString().isEmpty()
    private fun formatIntro(html: String) = html
        .replace(Regex("(&nbsp;)+"), " ")
        .replace(Regex("(&ensp;|&emsp;)"), " ")
        .replace(Regex("(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)"), "")
        .replace(Regex("</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>"), "\n")
        .replace(Regex("<!--[^>]*-->"), "")
        .replace(Regex("</?[a-zA-Z]+(?=[ >])[^<>]*>"), "")
        .replace(Regex("\\s*\\n+\\s*"), "\n")
        .replace(Regex("^[\\n\\s]+"), "")
        .replace(Regex("[\\n\\s]+$"), "")
}
