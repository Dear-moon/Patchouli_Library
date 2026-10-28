package org.mewx.wenku8_flutter

import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import java.net.URI
import java.text.Normalizer

/** Optional HTML structure checks for proven over-selection by source rules. */
internal class SourceDocumentMetadata private constructor(private val document: Document, private val url: String) {
    private val introHeading by lazy { document.select(HEADINGS).firstOrNull { label(it) in INTRO_LABELS } }
    private val reviewRoots by lazy {
        val roots = document.select(REVIEW_CONTAINERS).toMutableList()
        for (heading in document.select(HEADINGS).filter { label(it) in REVIEW_LABELS }) {
            // A review heading can share the book's card with its synopsis and
            // directory. Never discard that whole card just because of its title.
            val container = introHeading?.parent() ?: heading.parent() ?: continue
            val boundary = childWithin(container, heading) ?: continue
            var next = boundary.nextElementSibling()
            while (next != null && !startsSection(next, level(heading))) {
                roots.add(next)
                next = next.nextElementSibling()
            }
            roots.add(boundary)
        }
        roots.distinct()
    }

    fun bookName(raw: String, known: String): String {
        val expected = compact(known)
        val extracted = compact(raw)
        if (extracted.isEmpty()) return raw
        val candidates = document.select("h1, h2, h3, h4, h5, h6, b, strong, a, [itemprop=name]")
        val selectedNodes = candidates.filter { compact(it.text()) == extracted }
        if (selectedNodes.isEmpty()) return raw
        val foreign = selectedNodes.all { node ->
            val link = node.closest("a[href]")
            val secondary = node.closest("aside, nav, footer, [itemprop=review], .recommend, .recommendations, .related-books") != null || inReviews(node)
            secondary || (link != null && linksAwayFromPage(link.attr("href")))
        }

        // Do not replace a custom/alternate title merely because it differs from
        // a listing. Require the current document to confirm the known name.
        val names = document.select("meta[property=og:novel:book_name], meta[name=og:novel:book_name], meta[property=book:name]")
            .map { it.attr("content").trim() }.filter { it.isNotEmpty() }.distinctBy(::compact)
        if (names.size == 1 && compact(names.single()) != extracted &&
            (compact(names.single()) == expected || foreign)) return names.single()
        if (foreign) {
            val page = titleKey(document.title())
            // Listings may truncate long titles. Recover the complete primary
            // heading only when both the page title and the selected listing
            // identify it. This also repairs a previously stored ad title.
            val primary = candidates.asSequence()
                .filter { it.tagName() != "a" && it.closest("a[href], $SECONDARY_CONTAINERS") == null && !inReviews(it) }
                .map { it.text().trim() }
                .filter { candidate ->
                    val key = titleKey(candidate)
                    key.length >= 2 && page.startsWith(key) &&
                        (page.length == key.length || page[key.length] in "-—–|｜_·:：") &&
                        (expected.isEmpty() || expected == extracted || titlesAgree(known, candidate))
                }
                .distinctBy(::titleKey).sortedByDescending { titleKey(it).length }.firstOrNull()
            if (primary != null) return primary
        }
        if (expected.isEmpty() || expected == extracted) return raw
        val pageTitle = compact(document.title())
        if (!pageTitle.contains(expected) || pageTitle.contains(extracted)) return raw
        val knownInBody = candidates.any { compact(it.text()) == expected && !inReviews(it) }
        if (!knownInBody) return raw
        // A global indexed selector can pick a recommended book before reaching
        // the actual heading. Every occurrence must belong to a foreign link or
        // a secondary region; a legitimate current-book heading wins otherwise.
        return if (foreign) known else raw
    }

    fun genres(raw: String): List<String> {
        val tags = linkedMapOf<String, String>()
        fun add(value: String) {
            for (tag in value.split(TAG_SEPARATORS).map(String::trim).filter(String::isNotEmpty)) {
                tags.putIfAbsent(compact(tag), tag)
            }
        }
        add(raw)
        for (element in document.select("[itemprop=genre], meta[property=og:novel:category], meta[property=book:tag]")) {
            if (element.closest(SECONDARY_CONTAINERS) == null && !inReviews(element)) {
                add(element.attr("content").ifBlank { element.text() })
            }
        }
        for (element in document.allElements) {
            if (!TAG_LABEL.containsMatchIn(element.ownText().trim()) ||
                element.closest(SECONDARY_CONTAINERS) != null || inReviews(element)) continue
            val own = TAG_LABEL.replaceFirst(element.text().trim(), "").trim()
            if (own.isNotEmpty()) { add(own); continue }
            val next = element.nextElementSibling()
            if (element.tagName() == "dt" && next?.tagName() == "dd") { add(next.text()); continue }
            val row = element.parent()
            if (row != null && row.tagName() in setOf("p", "dd", "td", "li", "span") &&
                TAG_LABEL.containsMatchIn(row.text().trim())) {
                add(TAG_LABEL.replaceFirst(row.text().trim(), ""))
            }
        }
        return tags.values.toList()
    }

    fun intro(raw: String): String {
        if (raw.isBlank() || raw.trimStart().startsWith("<usehtml>", true) ||
            raw.trimStart().startsWith("<md>", true) || raw.trimStart().startsWith("<useweb>", true)) return raw
        val heading = introHeading ?: return raw
        val blocks = mutableListOf<String>()
        var sibling = heading.nextElementSibling()
        while (sibling != null && !startsSection(sibling, level(heading))) {
            if (!inReviews(sibling)) {
                val paragraphs = sibling.select("p")
                if (paragraphs.isNotEmpty()) blocks.addAll(paragraphs.map { it.text() })
                else sibling.text().takeIf { it.isNotBlank() }?.let(blocks::add)
            }
            sibling = sibling.nextElementSibling()
        }
        val paragraphs = blocks.map(String::trim).filter(String::isNotEmpty)
        if (paragraphs.isEmpty()) return raw
        val extracted = compact(Jsoup.parseBodyFragment(raw).text())
        // Repair only proven over-selection: the extracted result contains both
        // the synopsis and a paragraph from the document's actual review section.
        if (paragraphs.none { compact(it).length >= 12 && extracted.contains(compact(it)) }) return raw
        val polluted = reviewRoots.any { root ->
            root.select("p, blockquote, [itemprop=reviewBody]").any {
                val text = compact(it.text())
                text.length >= 12 && extracted.contains(text) && paragraphs.none { p -> compact(p).contains(text) }
            }
        }
        return if (polluted) paragraphs.distinct().joinToString("\n\n") else raw
    }

    fun authorUrl(author: String): String? = relatedUrl(author, author = true)
    fun tagUrls(tags: List<String>): Map<String, String> = tags.mapNotNull { tag ->
        relatedUrl(tag, author = false)?.let { tag to it }
    }.toMap()

    private fun relatedUrl(text: String, author: Boolean): String? {
        val name = compact(text)
        if (name.isEmpty()) return null
        return document.select("a[href]").asSequence()
            .filter { compact(it.text()) == name && !inReviews(it) }
            .mapNotNull { anchor ->
                val target = sameOriginUrl(anchor.attr("href")) ?: return@mapNotNull null
                val metadata = anchor.closest("dl, [itemprop=author], [itemprop=genre], .book-info, .bookinfo, .book-meta, .metadata")
                val relAuthor = anchor.attr("rel").split(' ').any { it.equals("author", true) }
                val score = (if (metadata != null) 4 else 0) + (if (author && relAuthor) 8 else 0)
                target to score
            }.sortedByDescending { it.second }.firstOrNull()?.first
    }

    data class Navigation(val nextUrl: String?, val hasPager: Boolean)
    fun navigation(): Navigation {
        val relNext = document.select("link[rel~=next], a[rel~=next]").firstNotNullOfOrNull { anchor ->
            if (disabled(anchor)) null else sameOriginUrl(anchor.attr("href"))
        }
        val pager = document.select(".pagination, .pager, nav[aria-label*=agination]")
        val labelled = document.select("a.next[href], a[aria-label][href], a[title][href]").filter { anchor ->
            listOf(anchor.text(), anchor.attr("aria-label"), anchor.attr("title")).any { pageLabel(it) in NEXT_LABELS }
        }
        val next = relNext ?: (pager.asSequence().flatMap { it.select("a[href]").asSequence() } + labelled.asSequence())
            .firstNotNullOfOrNull { anchor ->
                val labels = listOf(anchor.text(), anchor.attr("aria-label"), anchor.attr("title"))
                if (disabled(anchor) || labels.none { pageLabel(it) in NEXT_LABELS }) null
                else sameOriginUrl(anchor.attr("href"))
            }
        return Navigation(next, pager.isNotEmpty() || labelled.isNotEmpty() || document.select("link[rel~=prev], a[rel~=prev], link[rel~=next], a[rel~=next]").isNotEmpty())
    }

    private fun sameOriginUrl(value: String): String? = runCatching {
        if (value.isBlank() || value.trim().startsWith('#')) return@runCatching null
        val current = URI(url)
        val target = SourceNetwork.resolve(url, value.trim())
        if (target.scheme !in setOf("http", "https") || target.userInfo != null ||
            !target.host.equals(current.host, true) || port(target) != port(current)) return@runCatching null
        val clean = target.toString().substringBefore('#')
        if (clean == url.substringBefore('#')) null else clean
    }.getOrNull()

    private fun linksAwayFromPage(value: String): Boolean = runCatching {
        val current = URI(url)
        val target = SourceNetwork.resolve(url, value.trim())
        if (target.scheme !in setOf("http", "https") || target.userInfo != null) return@runCatching false
        // An ad/recommendation can use another host or downgrade HTTPS to HTTP.
        // Same-origin restrictions belong to collection navigation, not to
        // detecting that a selected title links to a different document.
        !target.host.equals(current.host, true) || target.path != current.path || target.rawQuery != current.rawQuery ||
            (target.port != -1 && target.port != 80 && target.port != 443 && target.port != current.port)
    }.getOrDefault(false)

    private fun inReviews(element: Element): Boolean = reviewRoots.any { root ->
        element === root || element.parents().contains(root)
    }

    private val chapterLinks by lazy {
        document.select("a[href]").mapNotNull { anchor ->
            val group = chapterGroup(anchor)
            if (group.title.isBlank()) null else BookSourceEngine.absolute(anchor.attr("href"), url)
                .takeIf { it.isNotBlank() }?.let { it to (compact(anchor.text()) to group) }
        }.groupBy({ it.first }, { it.second })
    }

    fun chapterGroup(node: Any?, title: String, chapterUrl: String): ChapterGroup {
        val direct = Companion.chapterGroup(node)
        if (direct.title.isNotBlank()) return direct
        // A chained Legado selector may materialize an intermediate fragment.
        // Recover structure from the original page, matching both address and
        // label so a volume link and its first chapter can share one address.
        val candidates = chapterLinks[chapterUrl].orEmpty()
        val labels = listOfNotNull((node as? Element)?.text(), title).map(::compact)
        return candidates.firstOrNull { it.first in labels }?.second ?: direct
    }

    companion object {
        private const val HEADINGS = "h1, h2, h3, h4, h5, h6, [role=heading]"
        private const val REVIEW_CONTAINERS = "[itemprop=review], [itemprop=reviewBody], [itemtype*=Review], #comments, #reviews, .comments, .reviews, .comment-list, .review-list, .comment-body, .review-body"
        private const val SECONDARY_CONTAINERS = "aside, nav, footer, .recommend, .recommendations, .related-books"
        private val TAG_LABEL = Regex("(?i)^(?:作品\\s*tags?|tags?|作品标签|作品標籤|标签|標籤)\\s*(?:[:：]\\s*|$)")
        private val TAG_SEPARATORS = Regex("[\\s\\u3000·,，、;；|/]+")
        private val AUTHOR_LABEL = Regex("(?i)^\\s*(?:作\\s*者|著\\s*者|authors?)\\s*(?:[:：]\\s*|\\s+)")
        fun authorName(raw: String): String = raw.replaceFirst(AUTHOR_LABEL, "").trim()
        private fun titleKey(value: String) = compact(Normalizer.normalize(value, Normalizer.Form.NFKC))
            .removeSuffix("...").trimEnd('…')
        private fun titlesAgree(known: String, candidate: String): Boolean {
            val expected = titleKey(known); val actual = titleKey(candidate)
            return expected == actual || (expected.length >= 6 && actual.startsWith(expected)) ||
                (actual.length >= 6 && expected.startsWith(actual) && expected.drop(actual.length).firstOrNull() in listOf('(', '['))
        }
        private val INTRO_LABELS = setOf("简介", "簡介", "内容简介", "內容簡介", "作品简介", "作品簡介", "故事简介", "故事簡介", "introduction", "synopsis", "description")
        private val REVIEW_LABELS = setOf("评论", "評論", "书评", "書評", "读者评论", "讀者評論", "reviews", "comments", "readerreviews")
        private val OTHER_LABELS = setOf("分卷", "目录", "目錄", "章节目录", "章節目錄", "章节列表", "章節列表", "volumes", "chapters", "contents")
        private val NEXT_LABELS = setOf("下一页", "下一頁", "下页", "下頁", "next", "nextpage", "›", "»", ">", ">>")
        private fun compact(value: String) = value.replace(Regex("[\\s\\u00a0\\u3000]+"), "").lowercase()
        private fun label(element: Element) = compact(element.text()).trimEnd(':', '：')
        private fun pageLabel(value: String) = compact(value).trim(' ', '→', '»', '›', '‹', '«').ifEmpty { compact(value) }
        private fun level(element: Element) = element.tagName().removePrefix("h").toIntOrNull()
            ?: element.attr("aria-level").toIntOrNull() ?: 6
        private fun startsSection(element: Element, atLevel: Int): Boolean =
            (if (element.`is`(HEADINGS)) listOf(element) else element.select(HEADINGS)).any {
                level(it) <= atLevel || label(it) in REVIEW_LABELS || label(it) in OTHER_LABELS
            }
        private fun childWithin(parent: Element, descendant: Element): Element? {
            var node = descendant
            while (node.parent() != parent) node = node.parent() ?: return null
            return node
        }
        private fun port(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme == "https") 443 else 80
        private fun disabled(element: Element) = element.parents().plus(element).any {
            it.hasClass("disabled") || it.attr("aria-disabled").equals("true", true)
        }

        fun parse(html: String, url: String): SourceDocumentMetadata? {
            if (!html.trimStart().startsWith('<')) return null
            return SourceDocumentMetadata(Jsoup.parse(html, url), url)
        }

        data class ChapterGroup(val isHeader: Boolean = false, val title: String = "")
        fun chapterGroup(node: Any?): ChapterGroup {
            val element = node as? Element ?: return ChapterGroup()
            val group = (listOf(element) + element.parents()).firstOrNull {
                it.tagName() == "details" || it.classNames().any { cls ->
                    cls.matches(Regex("(?i)(?:accordion-item|volume(?:[-_]group)?|chapter[-_]group|book[-_]volume|catalog[-_]group)"))
                }
            } ?: return ChapterGroup()
            val heading = group.select(".accordion-header, summary, h2, h3, h4, [role=heading]").firstOrNull()
                ?: return ChapterGroup()
            if (group.select("a[href]").none { it !== heading && !it.parents().contains(heading) }) return ChapterGroup()
            val isHeader = element === group || element === heading || element.parents().contains(heading)
            return ChapterGroup(isHeader, heading.text().trim())
        }
    }
}
