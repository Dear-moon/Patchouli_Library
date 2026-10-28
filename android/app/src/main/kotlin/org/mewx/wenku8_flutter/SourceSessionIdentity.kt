package org.mewx.wenku8_flutter

internal object SourceSessionIdentity {
    private val owners = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val groups = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val members = java.util.concurrent.ConcurrentHashMap<String, List<String>>()
    @Synchronized fun register(source: Map<String, Any?>) {
        val engine = source["engine"] as? Map<*, *> ?: return
        require((engine["version"] as? Number)?.toInt() == 1) { "书源声明版本不支持，请更新应用" }
        val session = engine["session"] as? Map<*, *> ?: return
        val id = session["id"] as String
        val key = source["bookSourceUrl"] as String
        val aliases = (session["members"] as? List<*>)?.map { it as String } ?: listOf(key)
        val origin = java.net.URI(key)
        val owner = "${origin.scheme}://${origin.authority}"
        require(owners.putIfAbsent(id, owner).let { it == null || it == owner }) { "共享登录态不能跨站点复用" }
        require(aliases.all { java.net.URI(it).let { uri -> uri.scheme == origin.scheme && uri.authority == origin.authority } }) { "共享登录态只允许同站点书源" }
        members[id] = (aliases + key).distinct()
        for (alias in members[id]!!) groups[alias] = id
    }
    fun key(source: String) = groups[source] ?: source
    fun members(key: String) = listOf(key) + members[key].orEmpty()
}
