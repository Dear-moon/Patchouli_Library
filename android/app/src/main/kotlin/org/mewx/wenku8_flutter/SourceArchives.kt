package org.mewx.wenku8_flutter

import java.io.InputStream
import java.nio.ByteBuffer
import me.zhanghai.android.libarchive.Archive
import me.zhanghai.android.libarchive.ArchiveEntry

/** Caller consumes each stream under its own count/size/cancellation limits. */
internal fun interface SourceArchiveBackend {
    fun walk(bytes: ByteArray, check: () -> Unit, entry: (String, Boolean, InputStream) -> Boolean)
}

/** Same native decoder as pinned Reading, including ZIP, RAR4/RAR5 and 7z. */
internal object SourceNativeArchive : SourceArchiveBackend {
    override fun walk(bytes: ByteArray, check: () -> Unit, entry: (String, Boolean, InputStream) -> Boolean) {
        check()
        val archive = Archive.readNew()
        val input = ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); flip() }
        try {
            Archive.setCharset(archive, "UTF-8".toByteArray())
            Archive.readSupportFilterAll(archive)
            Archive.readSupportFormatAll(archive)
            Archive.readOpenMemory(archive, input)
            var count = 0
            while (true) {
                check()
                val current = Archive.readNextHeader(archive)
                if (current == 0L) break
                require(++count <= 4096) { "书源压缩包文件过多" }
                require(ArchiveEntry.symlink(current) == null && ArchiveEntry.hardlink(current) == null) { "书源压缩包不允许链接" }
                val type = ArchiveEntry.filetype(current)
                require(type == 0 || type == 0x8000 || type == 0x4000) { "书源压缩包包含特殊文件" }
                require(!ArchiveEntry.isEncrypted(current)) { "书源压缩包已加密" }
                require(ArchiveEntry.size(current) <= 8L * 1024 * 1024) { "书源文件解压后超过 8 MiB" }
                val name = ArchiveEntry.pathnameUtf8(current) ?: ArchiveEntry.pathname(current)?.let {
                    org.mewx.wenku8_flutter.legado.SourceResources.text(it)
                } ?: throw IllegalArgumentException("书源压缩包文件名无效")
                val buffer = ByteBuffer.allocateDirect(16 * 1024).apply { limit(0) }
                val stream = object : InputStream() {
                    private fun fill(): Boolean {
                        if (buffer.hasRemaining()) return true
                        check(); buffer.clear(); Archive.readData(archive, buffer); buffer.flip()
                        return buffer.hasRemaining()
                    }
                    override fun read(): Int = if (fill()) buffer.get().toInt() and 255 else -1
                    override fun read(out: ByteArray, offset: Int, length: Int): Int {
                        if (length == 0) return 0
                        if (!fill()) return -1
                        val size = minOf(length, buffer.remaining()); buffer.get(out, offset, size); return size
                    }
                }
                if (!entry(name, type == 0x4000 || name.endsWith('/'), stream)) break
            }
        } finally { Archive.free(archive) }
    }
}
