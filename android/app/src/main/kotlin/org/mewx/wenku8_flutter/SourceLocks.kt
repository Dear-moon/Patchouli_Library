/* Adapted from Legado SourceLock, GPL-3.0, 3046111c1718e7b67c2ad468e54edf295ec05820. */
package org.mewx.wenku8_flutter

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

internal object SourceLocks {
    private open class Entry { val lock = ReentrantLock(); var users = 0; @Volatile var epoch = 0L }
    private val flights = ConcurrentHashMap<String, Entry>()
    private val locks = ConcurrentHashMap<String, Entry>()
    private val counters = object : LinkedHashMap<String, Int>(16, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Int>?) = size > 4096
    }
    fun key(source: String, name: String): String {
        require(source.isNotEmpty() && name.isNotBlank() && name.length <= 256) { "书源并发名称不能为空且长度不能超过 256" }
        return "$source@$name"
    }
    fun tick(key: String): Int = synchronized(counters) { val value = counters[key] ?: 0; counters[key] = if (value == Int.MAX_VALUE) 0 else value + 1; value }
    fun execute(key: String, waitMs: Long, singleFlight: Boolean, run: SourceRun, action: () -> Unit) {
        require(waitMs in 0..300000L) { "书源 timeoutMs 必须在 0..300000 之间" }
        val entries = if (singleFlight) flights else locks
        val entry = entries.compute(key) { _, old -> (old ?: Entry()).also { it.users++ } }!!
        try {
            if (singleFlight && entry.lock.isHeldByCurrentThread) return
            val epoch = entry.epoch
            val end = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(waitMs)
            while (true) {
                run.check()
                if (entry.lock.tryLock(minOf((end - System.nanoTime()).coerceAtLeast(0), TimeUnit.MILLISECONDS.toNanos(50)), TimeUnit.NANOSECONDS)) break
                check(System.nanoTime() < end) { "书源并发操作等待超时" }
            }
            try { run.check(); if (!singleFlight || epoch == entry.epoch) { action(); if (singleFlight) entry.epoch++ } }
            finally { entry.lock.unlock() }
        } finally { entries.computeIfPresent(key) { _, current -> if (current !== entry) current else current.also { it.users-- }.takeIf { it.users > 0 } } }
    }
}
