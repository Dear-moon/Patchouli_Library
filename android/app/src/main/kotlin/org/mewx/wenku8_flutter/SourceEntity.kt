package org.mewx.wenku8_flutter

import org.htmlunit.corejs.javascript.BaseFunction
import org.htmlunit.corejs.javascript.Context
import org.htmlunit.corejs.javascript.Scriptable
import org.htmlunit.corejs.javascript.ScriptableObject
import org.htmlunit.corejs.javascript.TopLevel
import org.htmlunit.corejs.javascript.Undefined
import org.htmlunit.corejs.javascript.VarScope
import org.mewx.wenku8_flutter.legado.js.SourceGson
import java.security.MessageDigest

/** Adapted from Legado BaseBook/BookChapter/RuleDataInterface (GPL-3.0),
 * 3046111c1718e7b67c2ad468e54edf295ec05820; Android/Room storage replaced.
 * Script-facing portions of Legado BaseBook/BookChapter/RuleDataInterface.
 * Persistent rule variables stay in the source's encrypted native state, not
 * the Flutter book DTO or exported source definition. No Room or file handle
 * is exposed to scripts. */
internal object SourceEntity {
    val bookDefaults: Map<String, Any?> = linkedMapOf("bookUrl" to "", "tocUrl" to "", "origin" to "",
        "originName" to "", "name" to "", "author" to "", "kind" to "", "wordCount" to "",
        "intro" to "", "coverUrl" to "", "type" to 8, "totalChapterNum" to 0,
        "latestChapterTitle" to "", "durChapterIndex" to 0, "durChapterTitle" to "", "durChapterPos" to 0,
        "infoHtml" to null, "tocHtml" to null)
    val chapterDefaults: Map<String, Any?> = linkedMapOf("url" to "", "title" to "", "isVolume" to false,
        "baseUrl" to "", "bookUrl" to "", "index" to 0, "isVip" to false, "isPay" to false,
        "tag" to null, "wordCount" to null, "resourceUrl" to null, "imgUrl" to null,
        "start" to null, "end" to null, "startFragmentId" to null, "endFragmentId" to null)

    fun install(cx: Context, root: TopLevel, obj: Scriptable, isBook: Boolean, owner: String,
                state: SourceState, check: () -> Unit, plain: (Any?) -> Any?, persist: () -> Unit, toJs: (Any?) -> Any?) {
        fun add(target: Scriptable, name: String, work: (Array<out Any>) -> Any?) {
            ScriptableObject.defineProperty(target, name, object : BaseFunction(root, ScriptableObject.getFunctionPrototype(root)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? {
                    check(); return toJs(work(args))
                }
            }, ScriptableObject.DONTENUM)
        }
        fun argument(args: Array<out Any>, index: Int = 0) = args.getOrNull(index)?.let(Context::toString).orEmpty()
        fun nullable(value: Any?) = if (value == null || value is Undefined) null else Context.toString(value)
        fun get(name: String): Any? = ScriptableObject.getProperty(obj, name).let { if (it === Scriptable.NOT_FOUND) null else it }
        fun text(name: String) = get(name)?.let(Context::toString).orEmpty()
        fun set(name: String, value: Any?) { ScriptableObject.putProperty(obj, name, toJs(value)) }
        fun putVariable(key: String, value: Any?): Boolean {
            state.putRuleVariable(owner, key, nullable(value))
            return true // BaseBook and BookChapter override the base return value.
        }
        fun serialized(): String? = state.entries(owner).let { entries ->
            if (entries.isNotEmpty() || state.contains("entity-variable", owner)) SourceGson.gson.toJson(entries) else null
        }
        var installingMethods = true
        val variables = object : ScriptableObject() {
            override fun getClassName() = "Object"
            override fun get(name: String, start: Scriptable): Any? =
                if (state.contains(owner, name)) state.get(owner, name) else super.get(name, start)
            override fun has(name: String, start: Scriptable) = state.contains(owner, name) || super.has(name, start)
            override fun put(name: String, start: Scriptable, value: Any?) {
                if (installingMethods) super.put(name, start, value)
                else nullable(value)?.let { state.put(owner, name, it) } ?: state.remove(owner, name)
            }
            override fun delete(name: String) { state.remove(owner, name) }
            override fun getIds(): Array<Any> = state.entries(owner).keys.toTypedArray<Any>()
        }.apply { parentScope = root; prototype = ScriptableObject.getObjectPrototype(root) }
        add(variables, "get") { args -> state.get(owner, argument(args)).takeIf { state.contains(owner, argument(args)) } }
        add(variables, "put") { args -> val old = state.get(owner, argument(args)).takeIf { state.contains(owner, argument(args)) }
            nullable(args.getOrNull(1))?.let { state.put(owner, argument(args), it) } ?: state.remove(owner, argument(args)); old }
        add(variables, "remove") { args -> val old = state.get(owner, argument(args)).takeIf { state.contains(owner, argument(args)) }
            state.remove(owner, argument(args)); old }
        add(variables, "clear") { state.clear(owner); null }
        add(variables, "containsKey") { args -> state.contains(owner, argument(args)) }
        add(variables, "size") { state.entries(owner).size }
        add(variables, "isEmpty") { state.entries(owner).isEmpty() }
        add(variables, "keySet") { state.entries(owner).keys.toList() }
        add(variables, "values") { state.entries(owner).values.toList() }
        installingMethods = false
        fun property(name: String, getter: () -> Any?, setter: ((Any?) -> Unit)? = null) {
            val descriptor = cx.newObject(root) as ScriptableObject
            ScriptableObject.putProperty(descriptor, "get", object : BaseFunction(root, ScriptableObject.getFunctionPrototype(root)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { check(); return toJs(getter()) }
            })
            if (setter != null) ScriptableObject.putProperty(descriptor, "set", object : BaseFunction(root, ScriptableObject.getFunctionPrototype(root)) {
                override fun call(cx: Context, scope: VarScope, thisObj: Scriptable, args: Array<out Any>): Any? { check(); setter(args.firstOrNull()); return Undefined.instance }
            })
            ScriptableObject.putProperty(descriptor, "enumerable", false)
            (obj as ScriptableObject).defineOwnProperty(cx, name, descriptor)
        }
        property("variableMap", { variables })
        property("variable", { serialized() }, { raw ->
            val values = nullable(raw)?.takeIf { it.isNotBlank() }?.let { SourceGson.gson.fromJson(it, Map::class.java) }
            state.clear(owner)
            if (raw == null || raw is Undefined) state.remove("entity-variable", owner) else state.put("entity-variable", owner, "1")
            values?.forEach { (key, value) -> state.put(owner, key.toString(), nullable(value).orEmpty()) }
        })
        add(obj, "getVariable") { args -> if (args.isEmpty()) serialized()
            else state.ruleVariable(owner, argument(args)) }
        add(obj, "getVariableMap") { variables }
        add(obj, "setVariable") { args -> ScriptableObject.putProperty(obj, "variable", args.firstOrNull()); null }
        add(obj, "putVariable") { args -> putVariable(argument(args), args.getOrNull(1)) }
        add(obj, "getBigVariable") { args -> state.getBig(owner, argument(args)) }
        add(obj, "putBigVariable") { args -> state.putBig(owner, argument(args), nullable(args.getOrNull(1))); null }
        val fields = if (isBook) bookDefaults else chapterDefaults
        for (field in fields.keys) {
            val suffix = field.replaceFirstChar { it.uppercaseChar() }
            add(obj, "get$suffix") { get(field) }
            add(obj, "set$suffix") { args -> set(field, args.firstOrNull()); null }
        }
        if (isBook) {
            add(obj, "putCustomVariable") { args -> putVariable("custom", args.firstOrNull()); null }
            add(obj, "getCustomVariable") { state.ruleVariable(owner, "custom") }
            add(obj, "getKindList") { buildList {
                text("wordCount").takeIf { it.isNotBlank() }?.let(::add)
                addAll(text("kind").split(Regex("[,\\n]")).filter { it.isNotBlank() })
            } }
        } else {
            add(obj, "putLyric") { args -> putVariable("lyric", args.firstOrNull()); persist(); null }
            add(obj, "putDanmaku") { args -> putVariable("danmaku", args.firstOrNull()); persist(); null }
            add(obj, "getDisplayTitle") { args ->
                var title = text("title").replace(Regex("[\r\n]"), "")
                if (args.getOrNull(1) != false) (plain(args.firstOrNull()) as? List<*>)?.forEach { raw ->
                    val rule = raw as? Map<*, *> ?: return@forEach
                    val pattern = rule["pattern"]?.toString().orEmpty()
                    if (pattern.isNotEmpty()) {
                        val replacement = rule["replacement"]?.toString().orEmpty()
                        val changed = if (rule["isRegex"] == true) {
                            val limit = System.nanoTime() + 1_000_000_000L
                            val checked = object : CharSequence {
                                override val length get() = title.length
                                override fun get(index: Int): Char { check(); check(System.nanoTime() < limit) { "章节标题替换超时" }; return title[index] }
                                override fun subSequence(startIndex: Int, endIndex: Int) = title.subSequence(startIndex, endIndex)
                                override fun toString() = title
                            }
                            java.util.regex.Pattern.compile(pattern).matcher(checked).replaceAll(replacement)
                        } else title.replace(pattern, replacement)
                        if (changed.isNotBlank()) title = changed
                    }
                }
                // This app has no global chapter-title conversion preference;
                // the default is the same unconverted title as Reading's 0.
                title
            }
            add(obj, "update") { persist(); null }
            add(obj, "primaryStr") { text("bookUrl") + text("url") }
            add(obj, "getAbsoluteURL") {
                if (get("isVolume") == true && text("url").startsWith(text("title"))) text("baseUrl")
                else BookSourceEngine.absolute(text("url"), text("baseUrl"))
            }
            fun fileName(suffix: String): String {
                val md5 = MessageDigest.getInstance("MD5").digest(text("title").toByteArray()).joinToString("") { "%02x".format(it) }.substring(8, 24)
                return "%05d-%s.%s".format((get("index") as? Number)?.toInt() ?: 0, md5, suffix)
            }
            add(obj, "getFileName") { args -> fileName(argument(args).ifBlank { "nb" }) }
            add(obj, "getFontName") { fileName("ttf") }
            add(obj, "putImgUrl") { args -> set("imgUrl", args.firstOrNull()); persist(); null }
        }
    }
}
