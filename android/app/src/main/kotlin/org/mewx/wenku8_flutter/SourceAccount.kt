package org.mewx.wenku8_flutter

/** Optional host extension, not a redefinition of Legado's loginCheckJs.
 * Every request/action must be explicitly declared by the imported rule. */
internal class SourceAccountRules(raw: Any?) {
    private val rules: Map<*, *> = if (raw == null) emptyMap<Any, Any>() else
        raw as? Map<*, *> ?: throw SourceAccountFailure("书源账号扩展应为规则对象")

    private fun section(name: String, required: List<String>): Map<String, Any?>? {
        val raw = rules[name] ?: return null
        val map = (raw as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }
            ?: throw SourceAccountFailure("书源账号扩展的操作规则无效")
        val native = map["native"] as? String
        if (native != null) throw SourceAccountFailure("书源原生账号驱动不支持")
        val script = map["js"] as? String
        if (script != null && !Regex("[A-Za-z_$][A-Za-z0-9_$]*").matches(script))
            throw SourceAccountFailure("书源账号脚本须为函数名")
        if (native == null && script == null && required.any { (map[it] as? String).isNullOrBlank() })
            throw SourceAccountFailure("书源账号扩展缺少请求地址或结果规则")
        return map
    }
    fun verify() = section("verify", listOf("url", "loggedIn"))
    fun shelf() = section("shelf", listOf("url", "bookList", "name", "bookUrl"))
    fun checkIn() = section("checkIn", listOf("url", "success"))
    fun checkInRevision() = rules["checkInRevision"] as? String
    fun checkInLabel() = rules["checkInLabel"] as? String ?: "账户签到"
    fun checkInExtras(): List<Map<String, Any?>> {
        val raw = rules["checkInExtras"] ?: return emptyList()
        val steps = raw as? List<*> ?: throw SourceAccountFailure("附加签到应为规则列表")
        if (steps.size !in 1..8 || checkInRevision().isNullOrBlank()) throw SourceAccountFailure("附加签到缺少版本或步骤过多")
        val ids = mutableSetOf("primary")
        return steps.map { value ->
            val map = value as? Map<*, *> ?: throw SourceAccountFailure("附加签到步骤无效")
            val id = map["id"] as? String ?: throw SourceAccountFailure("附加签到缺少标识")
            if (!Regex("[A-Za-z0-9_-]{1,64}").matches(id) || !ids.add(id) || (map["label"] as? String).isNullOrBlank())
                throw SourceAccountFailure("附加签到标识或名称无效")
            if (map["native"] != null) throw SourceAccountFailure("附加签到不支持原生驱动")
            SourceAccountRules(mapOf("checkIn" to map)).checkIn()!!
        }
    }
    fun capabilities(): Map<String, Boolean> {
        checkInExtras()
        return mapOf("verify" to (verify() != null), "shelf" to (shelf() != null), "checkIn" to (checkIn() != null))
    }

    companion object {
        fun boolean(value: String): Boolean = when (value.trim().lowercase()) {
            "true", "1" -> true
            "false", "0" -> false
            else -> throw SourceAccountFailure("书源账号结果规则须返回 true／false 或 1／0")
        }
    }
}

internal class SourceAccountFailure(message: String) : RuntimeException(message)

/** Host-owned metadata is encrypted with the existing source session vault.
 * Form values, cookies, and a response-transforming loginCheckJs do not prove login. */
internal object SourceAccountState {
    private const val OWNER = "host-account"
    private const val FRESH_MILLIS = 15 * 60_000L
    fun changed(state: SourceState) {
        state.remove(OWNER, "validation")
        state.remove(OWNER, "validationError")
    }
    fun credentialsChanged(state: SourceState) { changed(state) }
    fun submitted(state: SourceState) {
        credentialsChanged(state)
        state.remove(OWNER, "checkInAt")
        state.remove(OWNER, "checkInRevision")
        state.remove(OWNER, "checkInReport")
        state.remove(OWNER, "profile")
        state.put(OWNER, "submittedAt", System.currentTimeMillis().toString())
    }
    fun verified(state: SourceState, loggedIn: Boolean) {
        state.remove(OWNER, "validationError")
        state.put(OWNER, "validation", if (loggedIn) "verified" else "signedOut")
        state.put(OWNER, "checkedAt", System.currentTimeMillis().toString())
    }
    fun profile(state: SourceState, raw: Map<String, Any?>) {
        val safe = mapOf("id" to raw["id"]?.toString().orEmpty(),
            "displayName" to raw["displayName"]?.toString().orEmpty(),
            "avatarUrl" to raw["avatarUrl"]?.toString().orEmpty())
        state.put(OWNER, "profile", com.google.gson.Gson().toJson(safe))
        when (raw["checkedInToday"]) {
            true -> checkedIn(state)
            false -> state.remove(OWNER, "checkInAt")
        }
    }
    fun authenticationRejected(failure: Throwable): Boolean =
        generateSequence(failure) { it.cause }.any { it.message?.contains("SOURCE_AUTH_EXPIRED") == true }
    fun failed(state: SourceState, failure: Exception) {
        state.put(OWNER, "validationError", sourceRuleFailureMessage(failure) ?: "书源账号验证处理异常")
        state.put(OWNER, "validation", "error")
    }
    fun checkedIn(state: SourceState, revision: String? = null) {
        state.put(OWNER, "checkInAt", System.currentTimeMillis().toString())
        if (revision != null) state.put(OWNER, "checkInRevision", revision)
    }
    private fun sameDay(time: Long, now: Long): Boolean {
        fun day(value: Long) = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT).format(java.util.Date(value))
        return day(time) == day(now)
    }
    fun checkedInToday(state: SourceState, now: Long = System.currentTimeMillis()): Boolean =
        state.get(OWNER, "checkInAt").toLongOrNull()?.let { sameDay(it, now) } == true
    fun completedToday(state: SourceState, revision: String?, now: Long = System.currentTimeMillis()): Boolean =
        checkedInToday(state, now) && (revision == null || state.get(OWNER, "checkInRevision") == revision)
    fun legacyCheckInToday(state: SourceState): Boolean =
        state.get(OWNER, "checkInRevision").isBlank() && checkedInToday(state)
    fun checkInReport(state: SourceState, revision: String?, now: Long = System.currentTimeMillis()): List<Map<String, Any?>> {
        val raw = state.get(OWNER, "checkInReport").takeIf { it.isNotBlank() } ?: return emptyList()
        val value = com.google.gson.Gson().fromJson(raw, Map::class.java)
        val at = (value["at"] as Number).toLong()
        if (value["revision"] != revision || !sameDay(at, now)) return emptyList()
        return (value["steps"] as List<*>).map { step -> (step as Map<*, *>).entries.associate { it.key.toString() to it.value } }
    }
    fun saveCheckInReport(state: SourceState, revision: String, steps: List<Map<String, Any?>>) {
        state.put(OWNER, "checkInReport", com.google.gson.Gson().toJson(mapOf(
            "revision" to revision, "at" to System.currentTimeMillis(), "steps" to steps)))
    }
    fun view(source: Map<String, Any?>, state: SourceState, hasCookies: Boolean, now: Long = System.currentTimeMillis()): Map<String, Any?> {
        var configurationError = false
        val capabilities = try { SourceAccountRules(source["ruleAccount"]).capabilities() }
            catch (_: SourceAccountFailure) { configurationError = true; mapOf("verify" to false, "shelf" to false, "checkIn" to false) }
        val submitted = state.get(OWNER, "submittedAt").toLongOrNull()
        val checked = state.get(OWNER, "checkedAt").toLongOrNull()
        val validation = state.get(OWNER, "validation")
        val declaredHeaders = runCatching {
            val raw = source["header"]
            if (raw is Map<*, *>) raw else if (raw is String && raw.trim().startsWith('{'))
                com.google.gson.Gson().fromJson(raw, Map::class.java) else null
        }.getOrNull()
        val hasDeclaredCredential = declaredHeaders?.any { (name, value) ->
            SourceNetwork.sensitive(name.toString()) && !value?.toString().isNullOrBlank()
        } == true
        val hasSession = hasCookies || hasDeclaredCredential || state.get("login", "header").let { it.isNotBlank() && it != "{}" }
        val loginAvailable = !source["loginUrl"]?.toString().isNullOrBlank() ||
            source["loginUi"]?.toString()?.trim()?.let { it.isNotEmpty() && it != "[]" } == true
        val status = when {
            validation == "error" -> "error"
            checked != null && now - checked in 0..FRESH_MILLIS && validation in setOf("verified", "signedOut") -> validation
            hasSession -> "saved"
            submitted != null || checked != null -> "unchecked"
            else -> "none"
        }
        val revision = ((source["ruleAccount"] as? Map<*, *>)?.get("checkInRevision") as? String)
        return mapOf("status" to status, "hasSession" to hasSession, "loginAvailable" to loginAvailable,
            "capabilities" to capabilities, "configurationError" to configurationError,
            "checkedAt" to checked, "submittedAt" to submitted,
            "validationError" to if (status == "error") state.get(OWNER, "validationError") else "",
            "checkInAt" to state.get(OWNER, "checkInAt").toLongOrNull(), "checkedInToday" to completedToday(state, revision, now),
            "checkInSteps" to checkInReport(state, revision, now),
            "profile" to state.get(OWNER, "profile").takeIf { it.isNotBlank() }?.let {
                com.google.gson.Gson().fromJson(it, Map::class.java)
            })
    }
}
