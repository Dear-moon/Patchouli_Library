package org.mewx.wenku8_flutter

import com.google.gson.Gson
import java.util.concurrent.ConcurrentHashMap

internal fun sourceSessionField(scope: String, key: String) =
    scope == "login" || scope == "host-account" || scope == "source" && key == "__variable"

/** Rule variables remain isolated even when translation variants share authentication. */
internal class SourceState(private val big: SourceBigVariables? = null, private val session: SourceState? = null, private val checkOwner: () -> Unit = {}) {
    val fileLock = Any()
    private val values = ConcurrentHashMap<String, String>()
    private val memoryOwner = java.util.UUID.randomUUID().toString()
    private fun sessionFor(scope: String, key: String) = session?.takeIf { sourceSessionField(scope, key) }
    fun get(scope: String, key: String): String = sessionFor(scope, key)?.get(scope, key) ?: values["$scope\n$key"].orEmpty()
    fun contains(scope: String, key: String): Boolean = sessionFor(scope, key)?.contains(scope, key) ?: values.containsKey("$scope\n$key")
    fun entries(scope: String): Map<String, String> = values.filterKeys { it.startsWith("$scope\n") }
        .mapKeys { it.key.removePrefix("$scope\n") } +
        (session?.entries(scope)?.filterKeys { sourceSessionField(scope, it) } ?: emptyMap())
    fun put(scope: String, key: String, value: String): String {
        sessionFor(scope, key)?.let { return it.put(scope, key, value) }
        require(value.length <= 4 * 1024 * 1024) { "书源变量超过 4 MiB" }
        val old = values.put("$scope\n$key", value)
        if (scope == "login" && old != value) SourceAccountState.credentialsChanged(this)
        return value
    }
    fun remove(scope: String, key: String) {
        sessionFor(scope, key)?.let { it.remove(scope, key); return }
        if (values.remove("$scope\n$key") != null && scope == "login") SourceAccountState.credentialsChanged(this)
    }
    fun clear(scope: String) {
        if (scope == "login" || scope == "host-account") session?.clear(scope)
        else if (scope == "source") session?.remove(scope, "__variable")
        if (values.keys.removeAll { it.startsWith("$scope\n") } && scope == "login") SourceAccountState.credentialsChanged(this)
    }
    fun getBig(owner: String, key: String): String? = synchronized(fileLock) {
        checkOwner(); if (big != null) big.get(owner, key) else values["big:$owner\n$key"]
    }
    fun putBig(owner: String, key: String, value: String?) = synchronized(fileLock) {
        checkOwner()
        if (big != null) big.put(owner, key, value)
        else if (value == null) values.remove("big:$owner\n$key") else put("big:$owner", key, value)
        if (value == null) remove("big-keys:$owner",key) else put("big-keys:$owner",key,"1")
    }
    fun ruleVariable(owner: String, key: String): String = values["$owner\n$key"] ?: getBig(owner, key) ?: ""
    /** RuleDataInterface's 10,000-character split; return means small map changed. */
    fun putRuleVariable(owner: String, key: String, value: String?): Boolean = synchronized(fileLock) {
        checkOwner()
        val hadSmall = contains(owner, key)
        val changed = when {
            value == null -> { remove(owner, key); putBig(owner, key, null); hadSmall }
            value.length < 10000 -> { putBig(owner, key, null); put(owner, key, value); true }
            else -> { remove(owner, key); putBig(owner, key, value); hadSmall }
        }
        if (changed) put("entity-variable", owner, "1")
        changed
    }
    fun copyRuleVariables(owner: String, target: SourceState, toOwner: String) {
        entries(owner).forEach { (key, value) -> target.put(toOwner, key, value) }
        // Row parse state is in-memory. Large values follow the final URL too.
        (entries("big-keys:$owner").keys + entries("big:$owner").keys).forEach { key ->
            getBig(owner,key)?.let { target.putBig(toOwner,key,it) }
        }
        if (contains("entity-variable", owner)) target.put("entity-variable", toOwner, "1")
    }
    fun memory(key: String): Any? = synchronized(memoryLock) { memoryValues[memoryOwner to key]?.first }
    fun putMemory(key: String, value: Any) = synchronized(memoryLock) {
        val address = memoryOwner to key
        memoryValues.remove(address)?.let { memoryBytes -= it.second }
        val size = if (value is ByteArray) value.size else value.toString().length * 2
        if (size <= MAX_MEMORY_BYTES) { memoryValues[address] = value to size; memoryBytes += size }
        while (memoryBytes > MAX_MEMORY_BYTES || memoryValues.size > 1024) {
            val oldest = memoryValues.entries.iterator(); val entry = oldest.next()
            memoryBytes -= entry.value.second; oldest.remove()
        }
    }
    fun deleteMemory(key: String) = synchronized(memoryLock) { memoryValues.remove(memoryOwner to key)?.let { memoryBytes -= it.second }; Unit }
    fun clearMemory() = synchronized(memoryLock) {
        val entries = memoryValues.entries.iterator()
        while (entries.hasNext()) { val entry = entries.next()
            if (entry.key.first == memoryOwner) { memoryBytes -= entry.value.second; entries.remove() } }
    }
    fun snapshot(): Map<String, String> = values.toMap()
    fun restore(raw: Map<*, *>) { raw.forEach { (k, v) -> if (k is String && v is String) {
        val owner = k.substringBefore('\n'); val key = k.substringAfter('\n', "")
        if (owner.startsWith("big:")) putBig(owner.removePrefix("big:"), key, v)
        else if ((owner.startsWith("book:") || owner.startsWith("chapter:")) && v.length >= 10000) putRuleVariable(owner, key, v)
        else values[k] = v
    } } }
    companion object {
        // Upstream's process-only cache budget, shared across isolated sources.
        private const val MAX_MEMORY_BYTES = 50 * 1024 * 1024
        private val memoryLock = Any()
        private val memoryValues = LinkedHashMap<Pair<String, String>, Pair<Any, Int>>(32, .75f, true)
        private var memoryBytes = 0
    }
}
