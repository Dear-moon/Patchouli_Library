/* Adapted from Legado ScriptBindings/SharedJsScope, GPL-3.0,
 * 3046111c1718e7b67c2ad468e54edf295ec05820. Safe roots replace JVM globals. */
package org.mewx.wenku8_flutter

import org.htmlunit.corejs.javascript.ConcurrentNativeObject
import org.htmlunit.corejs.javascript.NativeObject
import org.htmlunit.corejs.javascript.Scriptable
import org.htmlunit.corejs.javascript.ScriptableObject
import org.htmlunit.corejs.javascript.TopLevel

internal class SourceScriptBindings(parent: TopLevel, shared: Scriptable? = null) : TopLevel(NativeObject().apply {
    prototype = shared ?: parent.globalThis; parentScope = null
    put("globalThis", this, shared ?: this); setAttributes("globalThis", ScriptableObject.DONTENUM)
    put("global", this, shared ?: this); setAttributes("global", ScriptableObject.DONTENUM)
}) {
    init { copyBuiltins(parent, false); copyAssociatedValue(parent) }
}

/** Library definitions are shared; explicit global/globalThis state is per source. */
internal object SourceScriptScopes {
    private val roots = LinkedHashMap<String, TopLevel>(16, .75f, true)
    private val globals = LinkedHashMap<Pair<String, String>, Scriptable>(32, .75f, true)
    private val monitor = Any()
    // Only library creation for the same definitions is serialized. No lock
    // spans source networking, user verification or source execution.
    private class Creation(val monitor: Any = Any(), var users: Int = 0)
    private val creations = mutableMapOf<String, Creation>()
    fun bindings(library: String, key: String, create: () -> TopLevel): TopLevel {
        if (library.isBlank()) return SourceScriptBindings(create())
        val creation = synchronized(monitor) { creations.getOrPut(library) { Creation() }.also { it.users++ } }
        val parent = try { synchronized(creation.monitor) {
            synchronized(monitor) { roots[library] } ?: create().also { root -> synchronized(monitor) {
                roots[library] = root
                while (roots.size > 16) { val old = roots.keys.first(); roots.remove(old); globals.keys.removeAll { it.first == old } }
            } }
        } } finally { synchronized(monitor) { if (--creation.users == 0) creations.remove(library, creation) } }
        val shared = synchronized(monitor) { globals.getOrPut(library to key) {
            ConcurrentNativeObject().apply {
                prototype = parent.globalThis; parentScope = null
                put("globalThis", this, this); setAttributes("globalThis", ScriptableObject.DONTENUM)
                put("global", this, this); setAttributes("global", ScriptableObject.DONTENUM)
            }
        }.also { while (globals.size > 128) globals.remove(globals.keys.first()) } }
        return SourceScriptBindings(parent, shared)
    }
    fun clearSource(key: String) = synchronized(monitor) { globals.keys.removeAll { it.second == key }; Unit }
    fun refresh(library: String) = synchronized(monitor) { roots.remove(library); globals.keys.removeAll { it.first == library }; Unit }
}
