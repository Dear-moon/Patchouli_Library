package org.mewx.wenku8_flutter

import java.util.concurrent.ConcurrentHashMap

/** Legado's concurrentRate is a request count per millisecond window, not thread count. */
internal object SourceRateLimit {
    private data class Window(var started: Long = 0, var count: Int = 0, var foregroundWaiters: Int = 0)
    private val windows = ConcurrentHashMap<String, Window>()
    fun await(key: String, rule: String, run: SourceRun) {
        if (rule.isBlank() || rule == "0") return
        val parts = rule.split('/', limit = 2)
        val limit = if (parts.size == 1) 1 else parts[0].toIntOrNull() ?: 1
        val interval = parts.last().toLongOrNull() ?: return
        if (limit <= 0 || interval <= 0) return
        val window = windows.computeIfAbsent(key) { Window() }
        val started = System.nanoTime()
        var waited = false
        if (!run.lowPriority) synchronized(window) { window.foregroundWaiters++ }
        try { while (true) {
            run.check()
            val wait = synchronized(window) {
                val now = System.nanoTime() / 1_000_000
                if (run.lowPriority && window.foregroundWaiters > 0) 50L
                else if (now - window.started >= interval) { window.started = now; window.count = 1; 0L }
                else if (window.count < limit) { window.count++; 0L }
                else interval - (now - window.started)
            }
            if (wait <= 0) return
            waited = true
            Thread.sleep(minOf(wait, 100))
        } } finally {
            if (!run.lowPriority) synchronized(window) { window.foregroundWaiters-- }
            if (waited) run.metrics.rateNanos.addAndGet(System.nanoTime() - started)
        }
    }
}
