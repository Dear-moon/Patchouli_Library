package org.mewx.wenku8_flutter

import java.util.concurrent.atomic.AtomicLong

internal class SourceRunMetrics {
    val queuedNanos = AtomicLong()
    val rateNanos = AtomicLong()
    val httpNanos = AtomicLong()
    val bridgeNanos = AtomicLong()
    val httpCalls = AtomicLong()
    val rpcCalls = AtomicLong()
    val hubNanos = AtomicLong()
    val decodeNanos = AtomicLong()
    val cacheHits = AtomicLong()
    val socketOpens = AtomicLong()
    private val started = System.nanoTime()

    fun report(operation: String, source: String, requests: Int, background: Boolean = false): String {
        val platform = when {
            source == "builtin:wenku8" -> "wenku"
            source.startsWith("https://n.novelia.cc#") -> "novelia"
            source == "https://www.lightnovel.app" -> "lightnovel"
            source == "https://www.lightnovel.fun" -> "qingguo"
            source == "https://www.bilinovel.com" -> "bilinovel"
            else -> "custom"
        }
        val action = operation.takeIf { it in operations } ?: "custom"
        fun AtomicLong.ms() = get() / 1_000_000
        return "platform=$platform operation=$action total_ms=${(System.nanoTime() - started) / 1_000_000}" +
            " queue_ms=${queuedNanos.ms()} rate_ms=${rateNanos.ms()} http_ms=${httpNanos.ms()} bridge_ms=${bridgeNanos.ms()}" +
            " hub_ms=${hubNanos.ms()} decode_ms=${decodeNanos.ms()} budget_requests=$requests http_calls=${httpCalls.get()} rpc_calls=${rpcCalls.get()}" +
            " cache_hits=${cacheHits.get()} socket_opens=${socketOpens.get()} priority=${if (background) "background" else "foreground"}"
    }

    companion object {
        private val operations = setOf("epub", "search", "explore", "detail", "toc", "content", "cloudShelf", "accountVerify", "accountCheckIn", "accountShelf", "login", "openLogin", "image", "nativeTransport")
    }
}
