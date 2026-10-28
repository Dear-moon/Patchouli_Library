package org.mewx.wenku8_flutter

/** Reading's sniffer returns the captured URL as body, not its fetched bytes. */
internal class SourceWebCapture(private val request: SourceWebRequest) {
    private val resources = request.sourceRegex?.takeIf { it.isNotBlank() }?.toRegex()
    private val navigation = request.overrideUrlRegex?.takeIf { it.isNotBlank() }?.toRegex()
    val active get() = resources != null || navigation != null
    fun resource(url: String) = if (resources?.matches(url) == true) SourceReply(request.url, url) else null
    fun navigation(url: String) = if (navigation?.matches(url) == true) SourceReply(request.url, url) else null
}
