package org.mewx.wenku8_flutter

import java.io.File

/** Caller holds its image-cache write lock. Scan once after process start or
 * invalidation, then maintain the byte budget from actual committed writes.
 * The original least-recently-used eviction order and live-file protection stay.
 */
internal class SourceImageDiskBudget(private val limit: Long) {
    private var bytes: Long? = null
    internal var directoryScans = 0
        private set
    internal val knownBytes: Long? get() = bytes

    fun invalidate() { bytes = null }
    fun removed(length: Long) { bytes = bytes?.let { (it - length).coerceAtLeast(0) } }

    fun committed(folder: File, file: File, previousSize: Long) {
        val currentSize = file.length()
        var total = bytes?.let { (it - previousSize + currentSize).coerceAtLeast(0) }
            ?: entries(folder).sumOf { it.length() }
        if (total > limit) {
            for (old in entries(folder).sortedBy { it.lastModified() }) {
                if (total <= limit) break
                if (old != file) {
                    val length = old.length()
                    if (old.delete()) total -= length
                }
            }
        }
        bytes = total
    }

    private fun entries(folder: File): List<File> {
        directoryScans++
        return folder.listFiles()?.filter { it.isFile && !it.name.endsWith(".part") }
            ?: emptyList()
    }
}
