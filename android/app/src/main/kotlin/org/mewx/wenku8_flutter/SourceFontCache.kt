package org.mewx.wenku8_flutter

import com.google.gson.Gson
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

internal class SourceFontCache(private val folder: File) {
    private data class Entry(val bytes: ByteArray, val etag: String, val modified: String, val storedAt: Long, val maxAge: Long)
    private val locks = ConcurrentHashMap<String, ReentrantLock>()
    private val budget = SourceImageDiskBudget(64L * 1024 * 1024)
    private val gson = Gson()

    fun load(address: String, identity: String, run: SourceRun, fetch: (Map<String, String>) -> SourceReply): ByteArray {
        val key = MessageDigest.getInstance("SHA-256").digest("$address\n$identity".toByteArray()).joinToString("") { "%02x".format(it) }
        val lock = locks.computeIfAbsent(key) { ReentrantLock() }
        val queued = System.nanoTime()
        while (!lock.tryLock(100, TimeUnit.MILLISECONDS)) run.check()
        run.metrics.queuedNanos.addAndGet(System.nanoTime() - queued)
        try {
            val file = File(folder, "$key.font")
            val cached = synchronized(run.state.fileLock) { run.check(); if (file.isFile) read(file) else null }
            val now = System.currentTimeMillis()
            if (cached != null && cached.maxAge > 0 && now >= cached.storedAt && now - cached.storedAt < cached.maxAge) {
                run.metrics.cacheHits.incrementAndGet(); return cached.bytes
            }
            val conditional = buildMap<String, String> {
                cached?.etag?.takeIf { it.isNotEmpty() }?.let { put("If-None-Match", it) }
                cached?.modified?.takeIf { it.isNotEmpty() }?.let { put("If-Modified-Since", it) }
            }
            val reply = fetch(conditional)
            val data = if (reply.status == 304 && cached != null) {
                run.metrics.cacheHits.incrementAndGet(); cached.bytes
            } else {
                require(reply.status in 200..299) { "书源字体请求未完成（HTTP ${reply.status}）" }
                (reply.data ?: reply.body.toByteArray()).also { require(it.size <= MAX_FILE) { "书源字体超过 8 MiB" } }
            }
            fun header(name: String) = reply.headers.entries.firstOrNull { it.key.equals(name, true) }?.value?.joinToString(",")
            val control = header("Cache-Control")
            val seconds = control?.let { Regex("(?:^|,)\\s*max-age=([0-9]+)", RegexOption.IGNORE_CASE).find(it)?.groupValues?.get(1)?.toLongOrNull() }
            val age = header("Age")?.toLongOrNull()?.coerceAtLeast(0) ?: 0
            val lifetime = if (control?.contains("no-cache", true) == true) 0L else if (seconds != null)
                (TimeUnit.SECONDS.toMillis(seconds) - TimeUnit.SECONDS.toMillis(age)).coerceAtLeast(0)
                else if (reply.status == 304) cached!!.maxAge else 0L
            val entry = Entry(data, header("ETag") ?: if (reply.status == 304) cached!!.etag else "",
                header("Last-Modified") ?: if (reply.status == 304) cached!!.modified else "", now, lifetime)
            synchronized(run.state.fileLock) {
                run.check()
                if (control?.contains("no-store", true) == true) {
                    val length=file.length(); if (file.delete()) budget.removed(length)
                } else if (entry.maxAge > 0 || entry.etag.isNotEmpty() || entry.modified.isNotEmpty()) {
                    folder.mkdirs()
                    val previous = file.length()
                    val pending = File(folder, "$key.part")
                    val metadata = gson.toJson(mapOf("etag" to entry.etag, "modified" to entry.modified,
                        "storedAt" to entry.storedAt, "maxAge" to entry.maxAge)).toByteArray()
                    DataOutputStream(pending.outputStream()).use { output -> output.writeInt(metadata.size); output.write(metadata); output.write(data) }
                    if (file.exists()) check(file.delete()) { "书源字体缓存替换失败" }
                    check(pending.renameTo(file)) { "书源字体缓存写入失败" }
                    budget.committed(folder, file, previous)
                }
            }
            return data
        } finally { lock.unlock() }
    }

    private fun read(file: File): Entry = DataInputStream(file.inputStream()).use { input ->
        val length=input.readInt()
        require(length in 0..MAX_FILE) { "书源字体缓存格式无效" }
        val bytesLength=file.length()-length-4
        require(bytesLength in 0..MAX_FILE.toLong()) { "书源字体缓存大小无效" }
        val metadata=ByteArray(length);input.readFully(metadata)
        val fields=gson.fromJson(metadata.toString(Charsets.UTF_8),Map::class.java)
        val bytes=ByteArray(bytesLength.toInt());input.readFully(bytes)
        Entry(bytes,fields["etag"] as String,fields["modified"] as String,(fields["storedAt"] as Number).toLong(),(fields["maxAge"] as Number).toLong())
    }

    companion object { private const val MAX_FILE=8*1024*1024 }
}
