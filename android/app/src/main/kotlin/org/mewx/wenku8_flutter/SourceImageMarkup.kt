package org.mewx.wenku8_flutter

import org.commonmark.node.Image
import org.commonmark.node.Node
import org.commonmark.parser.IncludeSourceSpans
import org.commonmark.parser.Parser

/** Converts image syntax only. Story prose is copied from its exact source
 * offsets, not regenerated as Markdown/HTML or consumed by a greedy URL regex. */
internal object SourceImageMarkup {
    private val parser by lazy { Parser.builder().includeSourceSpans(IncludeSourceSpans.BLOCKS_AND_INLINES).build() }
    private val wrapper = Regex("!\\[[^\\]\\n]{0,128}\\]\\(\\s*(<!--image-->[^\\n]*?<!--image-->)(?:\\s*(?:\"[^\"\\n]{0,256}\"|'[^'\\n]{0,256}')?\\s*\\))?")
    fun readerImages(text: String, resolve: (String) -> String): String {
        if (!text.contains("![")) return text
        val replacements = mutableListOf<Triple<Int, Int, String>>()
        fun visit(node: Node) {
            if (node is Image) {
                val spans = node.sourceSpans
                val first = spans.firstOrNull() ?: return
                val last = spans.last()
                val start = first.inputIndex; val end = last.inputIndex + last.length
                if (start < 0 || end > text.length || start >= end) return
                val url = resolve(node.destination)
                if (url.isNotBlank()) replacements.add(Triple(start, end, "\n\n<!--image-->$url<!--image-->\n\n"))
                return
            }
            var child = node.firstChild
            while (child != null) { visit(child); child = child.next }
        }
        visit(parser.parse(text))
        val out = StringBuilder(); var position = 0
        for ((start, end, image) in replacements.sortedBy { it.first }) {
            if (start < position) continue
            out.append(text, position, start).append(image); position = end
        }
        out.append(text, position, text.length)
        return wrapper.replace(out.toString()) { it.groupValues[1] }
    }
}
