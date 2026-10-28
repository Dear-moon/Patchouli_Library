/* Adapted from Legado utils/HtmlFormatter.kt, GPL-3.0.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Changes: package and existing rule-host URL helper. */
package org.mewx.wenku8_flutter.legado

import java.net.URL
import java.util.regex.Pattern

@Suppress("RegExpRedundantEscape")
object HtmlFormatter {
    private val nbspRegex = "(&nbsp;)+".toRegex()
    private val espRegex = "(&ensp;|&emsp;)".toRegex()
    private val noPrintRegex = "(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)".toRegex()
    private val wrapHtmlRegex = "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>".toRegex()
    private val commentRegex = "<!--[^>]*-->".toRegex()
    private val notImgHtmlRegex = "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>".toRegex()
    private val otherHtmlRegex = "</?[a-zA-Z]+(?=[ >])[^<>]*>".toRegex()
    private val formatImagePattern = Pattern.compile(
        "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>|<img[^>]*\\sdata-(?:src|original|srcset)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>|<img[^>]*\\s(?:data-[^=>]*|src)=\\s*['\"]([^'\">]*)['\"][^>]*>",
        Pattern.CASE_INSENSITIVE
    )
    private val indent1Regex = "\\s*\\n+\\s*".toRegex()
    private val indent2Regex = "^[\\n\\s]+".toRegex()
    private val lastRegex = "[\\n\\s]+$".toRegex()
    fun format(html: String?, otherRegex: Regex = otherHtmlRegex): String = formatText(html, otherRegex, "　　")
    fun formatIntro(html: String?): String = formatText(html, otherHtmlRegex, "")
    private fun formatText(html: String?, otherRegex: Regex, paragraphIndent: String): String {
        html ?: return ""
        return html.replace(nbspRegex, " ").replace(espRegex, " ").replace(noPrintRegex, "")
            .replace(wrapHtmlRegex, "\n").replace(commentRegex, "").replace(otherRegex, "")
            .replace(indent1Regex, "\n$paragraphIndent").replace(indent2Regex, paragraphIndent).replace(lastRegex, "")
    }
    fun formatKeepImg(html: String?, redirectUrl: URL? = null): String {
        html ?: return ""
        val keepImgHtml = format(html, notImgHtmlRegex)
        val matcher = formatImagePattern.matcher(keepImgHtml)
        var appendPos = 0
        val sb = StringBuilder()
        while (matcher.find()) {
            var param = ""
            sb.append(keepImgHtml.substring(appendPos, matcher.start()), "<img src=\"${
                NetworkUtils.getAbsoluteURL(redirectUrl, matcher.group(1)?.let {
                    val urlMatcher = AnalyzeUrl.paramPattern.matcher(it)
                    if (urlMatcher.find()) { param = ',' + it.substring(urlMatcher.end()); it.substring(0, urlMatcher.start()) }
                    else it
                } ?: matcher.group(2) ?: matcher.group(3) ?: matcher.group(4)!!) + param
            }\">")
            appendPos = matcher.end()
        }
        if (appendPos < keepImgHtml.length) sb.append(keepImgHtml.substring(appendPos, keepImgHtml.length))
        return sb.toString()
    }
    /** Host boundary only: convert complete upstream img locators after the
     * source's full-content replacement. Parsing this HTML again with Jsoup
     * would truncate locators whose request-option JSON contains quotes. */
    internal fun readerImages(html: String, resolve: (String) -> String): String {
        val matcher = formatImagePattern.matcher(html)
        val out = StringBuffer()
        while (matcher.find()) {
            val raw = matcher.group(1) ?: matcher.group(2) ?: matcher.group(3) ?: matcher.group(4).orEmpty()
            val url = resolve(raw)
            matcher.appendReplacement(out, java.util.regex.Matcher.quoteReplacement(
                if (url.isEmpty()) "" else "\n\n<!--image-->$url<!--image-->\n\n"))
        }
        matcher.appendTail(out)
        return out.toString()
    }
}
