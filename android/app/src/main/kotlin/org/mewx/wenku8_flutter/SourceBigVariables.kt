package org.mewx.wenku8_flutter

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/** Large rule values have their own encrypted files, outside serialized entities. */
internal class SourceBigVariables(private val root: File, private val seal: (String) -> String, private val open: (String) -> String) {
    private fun file(owner: String, key: String): File {
        val name = MessageDigest.getInstance("SHA-256").digest("$owner\n$key".toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(root, name)
    }
    @Synchronized fun get(owner: String, key: String): String? {
        val file = file(owner, key)
        if (!file.isFile) return null
        require(file.length() <= 24L * 1024 * 1024) { "书源大变量文件过大" }
        return open(file.readText())
    }
    @Synchronized fun put(owner: String, key: String, value: String?) {
        val target = file(owner, key)
        if (value == null) { check(!target.exists() || target.delete()) { "书源大变量删除失败" }; return }
        require(value.length <= 4 * 1024 * 1024) { "书源变量超过 4 MiB" }
        check(root.mkdirs() || root.isDirectory)
        val stage = File.createTempFile("value-", ".part", root)
        try { stage.writeText(seal(value)); Files.move(stage.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING) }
        finally { stage.delete() }
    }
}
