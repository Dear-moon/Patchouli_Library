package org.mewx.wenku8_flutter.legado.js

/** Android/Room-independent adapters for the upstream JS marshaller. Property
 * names are the public Legado book/chapter contract, not Flutter snapshots. */
internal data class BookSource(val bookSourceUrl: String, val bookSourceName: String, val customOrder: Int = 0) {
    fun getBookType() = 8
}
internal object BookType { const val allBookType = 4 or 8 or 32 or 64 or 128 }
@androidx.annotation.Keep
internal open class SearchBook {
    var bookUrl = ""
    var name = ""
    var author = ""
    var kind: String? = null
    var intro: String? = null
    var coverUrl: String? = null
    var tocUrl = ""
    var latestChapterTitle: String? = null
    var wordCount: String? = null
    var variable: String? = null
    var origin = ""
    var originName = ""
    var originOrder = 0
    var type = 8
}
@androidx.annotation.Keep
internal class Book : SearchBook() {
    var downloadUrls: List<String>? = null
    @Transient val variableMap = linkedMapOf<String, String>()
}
@androidx.annotation.Keep
internal class BookChapter {
    var title = ""
    var url = ""
    var bookUrl = ""
    var baseUrl = ""
    var index = 0
    var isVolume = false
    var isVip = false
    var isPay = false
    var tag: String? = null
    var variable: String? = null
}
