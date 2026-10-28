package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.charset.Charset
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/** JsExtensions file contracts in a source-private cache, never the user's books. */
internal class SourceResources(root: File, private val lock: Any, private val check: () -> Unit,
    private val archive: org.mewx.wenku8_flutter.SourceArchiveBackend?) {
    constructor(root: File, lock: Any, check: () -> Unit) : this(root, lock, check, null)
    private val root = root.canonicalFile
    init { synchronized(lock) { check(); check(this.root.mkdirs() || this.root.isDirectory) { "书源缓存目录不可用" } } }
    companion object {
        const val MAX_FILE = 8 * 1024 * 1024
        private const val MAX_EXPANDED = 32 * 1024 * 1024
        private const val MAX_CACHE = 64L * 1024 * 1024
        private const val MAX_ENTRIES = 4096

        /** Undo this facade's permission flags when removing its own cache.
         * Links are deleted, never followed outside this source root. */
        fun clear(root: File): Boolean {
            if (Files.isSymbolicLink(root.toPath())) return root.delete()
            if (!root.exists()) return true
            root.setReadable(true,true); root.setWritable(true,true)
            if (root.isDirectory) {
                root.setExecutable(true,true)
                for (child in root.listFiles() ?: return false) if (!clear(child)) return false
            }
            return root.delete()
        }

        fun text(bytes: ByteArray, encoding: String? = null): String {
            if (encoding != null) return bytes.toString(Charset.forName(encoding))
            val name = org.mewx.wenku8_flutter.sourceinternal.icu4j.CharsetDetector().setText(bytes).detect()?.name ?: "UTF-8"
            return bytes.toString(Charset.forName(name))
        }

        fun zipEntry(bytes: ByteArray, path: String, check: () -> Unit): ByteArray? {
            require(bytes.size <= MAX_FILE) { "书源压缩文件超过 8 MiB" }
            var count = 0
            var expanded = 0
            ZipInputStream(ByteArrayInputStream(bytes), Charset.forName("GB18030")).use { zip ->
                while (true) {
                    check()
                    val entry = zip.nextEntry ?: return null
                    require(++count <= MAX_ENTRIES) { "书源压缩包文件过多" }
                    // Consume every entry with a bound. closeEntry() otherwise
                    // expands arbitrary skipped data outside cancellation checks.
                    val data = bounded(zip, minOf(MAX_FILE, MAX_EXPANDED - expanded), check)
                    expanded += data.size
                    if (!entry.isDirectory && entry.name == path) return data
                    zip.closeEntry()
                }
            }
        }
        fun archiveEntry(bytes: ByteArray, path: String, backend: org.mewx.wenku8_flutter.SourceArchiveBackend?, check: () -> Unit): ByteArray? {
            if (isZip(bytes)) return zipEntry(bytes, path, check)
            var result: ByteArray? = null
            var expanded = 0
            walk(bytes, backend, check) { name, directory, input ->
                val data = bounded(input, minOf(MAX_FILE, MAX_EXPANDED - expanded), check)
                expanded += data.size
                if (!directory && name == path) { result = data; false } else true
            }
            return result
        }
        private fun isZip(bytes: ByteArray) = bytes.size >= 4 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte()
        private fun walk(bytes: ByteArray, backend: org.mewx.wenku8_flutter.SourceArchiveBackend?, check: () -> Unit,
                         entry: (String, Boolean, InputStream) -> Boolean) {
            require(bytes.size <= MAX_FILE) { "书源压缩文件超过 8 MiB" }
            if (isZip(bytes)) ZipInputStream(ByteArrayInputStream(bytes), Charset.forName("GB18030")).use { zip ->
                while (true) { check(); val next = zip.nextEntry ?: break
                    if (!entry(next.name, next.isDirectory, zip)) break
                    zip.closeEntry()
                }
            } else (backend ?: error("书源当前宿主未提供 RAR／7z 解压服务")).walk(bytes, check, entry)
        }

        private fun bounded(input: InputStream, limit: Int, check: () -> Unit): ByteArray {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            while (true) {
                check()
                val read = input.read(buffer)
                if (read < 0) return output.toByteArray()
                require(output.size().toLong() + read <= limit) { "书源文件解压后超过大小限制" }
                output.write(buffer, 0, read)
            }
        }

        private fun md5Name(value: String) = MessageDigest.getInstance("MD5").digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }.substring(8, 24)
    }

    private fun resolve(path: String): File {
        check()
        require(path.length <= 4096 && '\u0000' !in path && '\\' !in path) { "书源文件路径无效" }
        val base = root.canonicalFile
        // Leading '/' is relative in Reading's file API. Also accept paths
        // obtained from this facade's getPath()/getAbsolutePath().
        val raw = if (path == base.path || path.startsWith(base.path + File.separator)) File(path)
            else File(base, path.trimStart('/'))
        val file = raw.canonicalFile
        if (file != base && !file.path.startsWith(base.path + File.separator)) throw SecurityException("书源文件路径超出本书源缓存目录")
        // Do not follow symlinks, including links which point back inside root.
        var part: File? = raw.absoluteFile
        while (part != null && part != base) {
            if (Files.isSymbolicLink(part.toPath())) throw SecurityException("书源缓存不允许符号链接")
            part = part.parentFile
        }
        return file
    }

    private fun relative(file: File) = file.relativeTo(root.canonicalFile).invariantSeparatorsPath
    fun file(path: String): SourceScriptFile { resolve(path); return SourceScriptFile(this, path) }
    fun read(path: String): ByteArray? = synchronized(lock) {
        val file = resolve(path)
        if (!file.exists()) null else {
            require(file.isFile && file.length() <= MAX_FILE) { "书源文件超过 8 MiB 或不是文件" }
            file.inputStream().use { bounded(it, MAX_FILE, check) }
        }
    }
    fun readText(path: String, encoding: String? = null): String = read(path)?.let { text(it, encoding) }.orEmpty()
    fun delete(path: String, recursive: Boolean = true): Boolean = synchronized(lock) {
        val file = resolve(path)
        require(file != root.canonicalFile) { "书源不可删除缓存根目录" }
        if (recursive) remove(file) else file.delete()
    }
    private fun remove(file: File): Boolean {
        check()
        if (file.isDirectory) for (child in file.listFiles().orEmpty()) {
            if (!remove(resolve(relative(child)))) return false
        }
        return !file.exists() || file.delete()
    }
    private fun capacity(extra: Long) {
        var bytes = extra
        var count = 0
        if (root.exists()) for (file in root.walkTopDown()) {
            check(); resolve(relative(file))
            require(++count <= MAX_ENTRIES) { "书源缓存文件过多" }
            if (file.isFile) bytes += file.length()
            require(bytes <= MAX_CACHE) { "书源文件缓存超过 64 MiB，请清理本书源缓存" }
        }
    }
    fun save(address: String, extension: String, bytes: ByteArray): String = synchronized(lock) {
        require(bytes.size <= MAX_FILE) { "书源文件超过 8 MiB" }
        require(extension.isEmpty() || extension.matches(Regex("[A-Za-z0-9_-]{1,32}"))) { "书源文件类型无效" }
        check(); root.mkdirs()
        val name = "${md5Name(address)}.$extension"
        val target = resolve(name)
        capacity((bytes.size - target.length()).coerceAtLeast(0L))
        val temp = File.createTempFile("resource-", ".part", root)
        try {
            temp.outputStream().use { output ->
                for (offset in bytes.indices step 16384) { check(); output.write(bytes, offset, minOf(16384, bytes.size - offset)) }
            }
            check()
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } finally { temp.delete() }
        "/$name"
    }
    fun unzip(path: String): String = synchronized(lock) {
        if (path.isEmpty()) return ""
        val input = read(path) ?: throw IllegalArgumentException("书源压缩文件不存在")
        root.mkdirs()
        val stage = Files.createTempDirectory(root.toPath(), "unpack-").toFile()
        val output = "ArchiveTemp/${md5Name(resolve(path).name)}"
        var count = 0
        var expanded = 0
        try {
            walk(input, archive, check) { name, directory, stream ->
                    check()
                    require(++count <= MAX_ENTRIES && name.isNotEmpty()) { "书源压缩包文件过多或路径为空" }
                    require(!name.startsWith('/') && !name.contains('\\') && !name.contains('\u0000') &&
                        name.split('/').none { it == ".." }) { "书源压缩包包含无效路径" }
                    val dest = File(stage, name).canonicalFile
                    require(dest.path.startsWith(stage.canonicalPath + File.separator)) { "书源压缩包路径越界" }
                    val bytes = bounded(stream, minOf(MAX_FILE, MAX_EXPANDED - expanded), check)
                    expanded += bytes.size
                    if (directory) check(dest.mkdirs() || dest.isDirectory)
                    else {
                        check(dest.parentFile!!.mkdirs() || dest.parentFile!!.isDirectory)
                        dest.writeBytes(bytes)
                    }
                    true
            }
            capacity(0) // Includes staging; no partially expanded result is visible.
            val target = resolve(output)
            if (target.exists()) check(remove(target)) { "书源旧解压目录无法替换" }
            check(target.parentFile!!.mkdirs() || target.parentFile!!.isDirectory)
            check(stage.renameTo(target)) { "书源压缩文件解压未完成" }
            output
        } finally { stage.deleteRecursively() }
    }
    fun folderText(path: String): String = synchronized(lock) {
        if (path.isEmpty()) return ""
        val dir = resolve(path)
        if (!dir.exists()) return ""
        require(dir.isDirectory && dir != root.canonicalFile) { "书源文本目录无效" }
        val output = StringBuilder()
        var first = true
        for (file in dir.listFiles().orEmpty()) {
            check()
            require(file.isFile) { "书源文本目录包含子目录" }
            val value = readText(relative(file))
            require(output.length.toLong() + value.length <= MAX_FILE) { "书源合并文本超过 8 MiB" }
            if (!first) output.append('\n')
            first = false
            output.append(value)
        }
        check(remove(dir)) { "书源临时文本目录无法清理" }
        output.toString()
    }
    internal fun <T> access(path: String, work: (File) -> T): T = synchronized(lock) { work(resolve(path)) }
    internal fun parent(path: String): SourceScriptFile? = access(path) { target ->
        target.parentFile?.takeIf { target != root.canonicalFile }?.let { file(relative(it)) }
    }
    internal fun children(path: String): Array<SourceScriptFile>? = access(path) { target ->
        target.listFiles()?.map { file(relative(it)) }?.toTypedArray()
    }
    internal fun create(path: String, directories: Boolean, recursive: Boolean = false): Boolean = synchronized(lock) {
        capacity(0)
        val target = resolve(path)
        if (directories) { if (recursive) target.mkdirs() else target.mkdir() } else target.createNewFile()
    }
    internal fun rename(path: String, destination: SourceScriptFile): Boolean = synchronized(lock) {
        require(destination.ownedBy(this)) { "书源文件不能移动到其他书源目录" }
        val source = resolve(path); val target = resolve(destination.getPath())
        require(source != root && target != root) { "书源不可重命名缓存根目录" }
        source.renameTo(target)
    }
}

/** File-shaped script facade; never hands java.io.File/streams to a rule. */
@Keep
class SourceScriptFile internal constructor(private val owner: SourceResources, private val path: String) {
    fun exists() = owner.access(path) { it.exists() }
    fun isFile() = owner.access(path) { it.isFile }
    fun isDirectory() = owner.access(path) { it.isDirectory }
    fun length() = owner.access(path) { it.length() }
    fun lastModified() = owner.access(path) { it.lastModified() }
    fun getName() = owner.access(path) { it.name }
    fun getPath() = owner.access(path) { it.path }
    fun getAbsolutePath() = getPath()
    fun getCanonicalPath() = getPath()
    fun getAbsoluteFile() = this
    fun getCanonicalFile() = this
    fun getParentFile() = owner.parent(path)
    fun getParent() = getParentFile()?.getPath()
    fun canRead() = owner.access(path) { it.canRead() }
    fun canWrite() = owner.access(path) { it.canWrite() }
    fun canExecute() = owner.access(path) { it.canExecute() }
    fun isHidden() = owner.access(path) { it.isHidden }
    fun isAbsolute() = getPath().startsWith('/')
    fun setLastModified(time: Long) = owner.access(path) { it.setLastModified(time) }
    fun setReadOnly() = owner.access(path) { it.setReadOnly() }
    @JvmOverloads fun setReadable(value: Boolean, ownerOnly: Boolean = true) = owner.access(path) { it.setReadable(value, ownerOnly) }
    @JvmOverloads fun setWritable(value: Boolean, ownerOnly: Boolean = true) = owner.access(path) { it.setWritable(value, ownerOnly) }
    @JvmOverloads fun setExecutable(value: Boolean, ownerOnly: Boolean = true) = owner.access(path) { it.setExecutable(value, ownerOnly) }
    fun getTotalSpace() = owner.access(path) { it.totalSpace }
    fun getFreeSpace() = owner.access(path) { it.freeSpace }
    fun getUsableSpace() = owner.access(path) { it.usableSpace }
    fun renameTo(destination: SourceScriptFile) = owner.rename(path, destination)
    fun compareTo(other: SourceScriptFile) = getPath().compareTo(other.getPath())
    internal fun ownedBy(other: SourceResources) = owner === other
    fun list() = owner.access(path) { it.list() }
    fun listFiles() = owner.children(path)
    fun mkdir() = owner.create(path, true)
    fun mkdirs() = owner.create(path, true, true)
    fun createNewFile() = owner.create(path, false)
    fun delete() = owner.delete(path, recursive = false)
    override fun equals(other: Any?) = other is SourceScriptFile && owner === other.owner && getPath() == other.getPath()
    override fun hashCode() = getPath().hashCode()
    override fun toString() = getPath()
}
