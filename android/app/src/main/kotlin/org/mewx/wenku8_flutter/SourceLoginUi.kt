package org.mewx.wenku8_flutter

import com.google.gson.Gson
import org.mewx.wenku8_flutter.legado.login.LoginUiV2

/** Adapted from Legado 3.26082823 LoginUiV2 (GPL-3.0).
 * Keep the protocol independent of Android/Flutter presentation. */
internal object SourceLoginUi {
    private val gson = Gson()
    private fun json(raw: Any?) = if (raw is String) raw else gson.toJson(raw)
    fun isV2(raw: Any?): Boolean = LoginUiV2.isV2(json(raw))

    fun rows(raw: Any?): List<Map<String, Any?>> {
        val rows = LoginUiV2.parseRender(json(raw)) ?: error("书源登录 UI V2 渲染结果无效")
        require(rows.size <= 200) { "书源登录 UI V2 表单数量无效" }
        return rows.map { row -> objectValue(gson.toJson(row), "书源登录 UI V2 控件无效") + ("label" to row.name) }
    }

    fun command(raw: Any?): Map<String, Any?> {
        val value = LoginUiV2.parseActionResult(if (raw == null || raw == "") null else json(raw))
        require(!value.malformed) { "书源登录 UI V2 动作结果无效" }
        return mapOf("state" to value.stateJson?.let { objectValue(it, "书源登录状态无效") },
            "error" to value.error, "login" to value.loginJson?.let { objectValue(it, "书源登录结果无效") }, "close" to value.close)
    }

    fun objectValue(raw: Any?, error: String): Map<String, Any?> {
        val map = (if (raw is String) runCatching { gson.fromJson(raw, Any::class.java) }.getOrNull() else raw) as? Map<*, *>
        require(map != null) { error }
        return map.entries.associate { it.key.toString() to it.value }
    }
}
