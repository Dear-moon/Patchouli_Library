package org.mewx.wenku8_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

/** Engine-owned inbox. UI recreation must not lose a pending ACTION_VIEW or
 * replay it. No incoming URI/path is exposed to Dart or diagnostic messages. */
internal class BookOpenRequests(private val context: Context) {
    private data class Request(val id: String, val uri: Uri, val flags: Int, val mime: String?) {
        var newGrant = false
        var linked: Link? = null
    }
    private data class Link(val uri: Uri, val grant: Uri? = null)
    private val requests = linkedMapOf<String, Request>()

    @Synchronized fun offer(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_VIEW) return false
        val uri = intent.data ?: return false
        if (uri.scheme !in setOf("content", "file")) return false
        if (requests.values.none { it.uri == uri }) {
            val id = UUID.randomUUID().toString()
            requests[id] = Request(id, uri, intent.flags, intent.type)
        }
        return true
    }

    @Synchronized private fun request(id: String): Request = requests[id]
        ?: error("文件打开请求已结束，请从文件管理器重新打开")

    private fun valid(uri: Uri) {
        require(uri.scheme in setOf("content", "file")) { "请从文件管理器打开本地书籍" }
        if (uri.scheme == "file") {
            val file = File(uri.path ?: "").canonicalFile
            val shared = Environment.getExternalStorageDirectory().canonicalFile
            require(file.path.startsWith(shared.path + File.separator)) { "请通过系统文件选择器授权这本书" }
        } else {
            require(!uri.authority.isNullOrBlank() && uri.authority != "${context.packageName}.updates") {
                "这个文件位置不支持阅读，请重新选择书籍"
            }
        }
    }

    private fun name(request: Request): String {
        valid(request.uri)
        val display = if (request.uri.scheme == "content") context.contentResolver.query(request.uri,
            arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst() && !it.isNull(0)) it.getString(0) else null
        } else null
        return BookOpenNames.resolve(display ?: request.uri.lastPathSegment.orEmpty(), request.mime)
    }

    private fun hasGrant(uri: Uri) = context.contentResolver.persistedUriPermissions.any {
        it.isReadPermission && it.uri == uri
    }

    private fun link(request: Request): Link {
        request.linked?.let { return it }
        if (request.uri.scheme == "file") {
            check(File(request.uri.path!!).canRead()) { "无法读取这本书，请重新定位原文件" }
            return Link(request.uri).also { request.linked = it }
        }
        if (hasGrant(request.uri)) return Link(request.uri, request.uri).also { request.linked = it }
        if (request.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0) {
            try {
                context.contentResolver.takePersistableUriPermission(request.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                request.newGrant = true
            } catch (_: SecurityException) { /* Ordinary VIEW grants are often temporary. */ }
        }
        if (hasGrant(request.uri)) return Link(request.uri, request.uri).also { request.linked = it }
        // Some file managers grant VIEW access but not a persistable URI. If
        // this app already has shared-file access, retain that original path;
        // never ask for broader access or copy the book as a side effect.
        context.contentResolver.openAssetFileDescriptor(request.uri, "r")?.use { descriptor ->
            if (descriptor.startOffset == 0L) {
                val local = runCatching {
                    val target = File(android.system.Os.readlink("/proc/self/fd/${descriptor.parcelFileDescriptor.fd}")).canonicalFile
                    val shared = Environment.getExternalStorageDirectory().canonicalFile
                    if (!target.path.startsWith(shared.path + File.separator) || !target.canRead()) null
                    else target.inputStream().use { input ->
                        val source = android.system.Os.fstat(descriptor.fileDescriptor)
                        val reopened = android.system.Os.fstat(input.fd)
                        target.takeIf { source.st_dev == reopened.st_dev && source.st_ino == reopened.st_ino }
                    }
                }.getOrNull()
                if (local != null) return Link(Uri.fromFile(local)).also { request.linked = it }
            }
        } ?: error("文件应用未授予读取权限，请重新打开原文件")
        // A temporary grant is sufficient to read now. Keep the source URI,
        // not a hidden original copy; normal relinking handles actual expiry.
        return Link(request.uri).also { request.linked = it }
    }

    fun pending(): Map<String, Any>? {
        val request = synchronized(this) { requests.values.firstOrNull() } ?: return null
        return try {
            val display = name(request)
            link(request)
            mapOf("id" to request.id, "name" to display, "canLink" to true)
        } catch (error: Exception) {
            mapOf("id" to request.id, "name" to "所选书籍", "canLink" to false, "error" to bookImportMessage(error))
        }
    }

    fun initialUri(id: String): Uri = request(id).uri

    fun resolve(id: String, copy: Boolean, links: BookTextLinks,
        imports: BookDocumentImportSession<Uri>): Map<String, String> {
        val request = request(id)
        val display = name(request)
        return if (copy) imports.queue.select(request.uri, display, BookArchiveImport.limit(display))
        else {
            val source = link(request)
            mapOf("name" to display, "reference" to links.remember(source.uri, source.grant))
        }
    }

    fun finish(id: String, links: BookTextLinks) {
        val request = synchronized(this) { requests.remove(id) } ?: return
        if (request.newGrant && !links.usesGrant(request.uri)) {
            try { context.contentResolver.releasePersistableUriPermission(request.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (_: SecurityException) { /* Revoked already. */ }
        }
    }
}

internal object BookOpenNames {
    private val extensions = mapOf(
        "text/plain" to "txt", "application/epub+zip" to "epub",
        "application/x-mobipocket-ebook" to "mobi", "application/vnd.amazon.ebook" to "azw",
        "application/vnd.amazon.mobi8-ebook" to "azw3",
        "application/x-fictionbook+xml" to "fb2", "application/fb2+xml" to "fb2",
        "application/pdf" to "pdf", "application/rtf" to "rtf", "text/rtf" to "rtf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" to "docx",
        "application/msword" to "doc",
        "text/html" to "html", "application/xhtml+xml" to "xhtml",
        "text/markdown" to "md", "text/x-markdown" to "md",
        "application/zip" to "zip", "application/x-zip-compressed" to "zip",
    )
    fun resolve(raw: String, mime: String?): String {
        var name = raw.replace('\\', '/').substringAfterLast('/').trim()
        require(name.length <= 1024 && name.none { it.code < 32 || it.code == 127 }) { "书籍文件名有误，请重新选择" }
        if ('.' !in name || !BookArchiveImport.supported(name)) {
            val extension = extensions[mime?.substringBefore(';')?.trim()?.lowercase()]
            require(extension != null && (name.isBlank() || '.' !in name)) { "请选择支持的电子书或文档" }
            name = "${name.ifBlank { "所选书籍" }}.$extension"
        }
        return name
    }
}
