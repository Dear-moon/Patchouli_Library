package org.mewx.wenku8_flutter

import org.htmlunit.corejs.javascript.*
import org.htmlunit.corejs.javascript.lc.type.TypeInfo
import java.net.URL

/** Parsing/URL inspection remain available; all I/O goes through SourceRun. */
internal class SourceJavaBoundary : WrapFactory() {
    init { isJavaPrimitiveWrap = false }
    override fun wrapAsJavaObject(cx: Context, scope: VarScope, value: Any, staticType: TypeInfo): Scriptable {
        if (value is org.jsoup.Connection || value is java.io.File || value is java.io.InputStream ||
            value is java.io.OutputStream || value is java.net.URLConnection || value is Class<*> || value is ClassLoader) {
            throw SecurityException("书源请使用受控请求和文件接口")
        }
        if (value is URL) return wrapAsJavaObject(cx,scope,
            org.mewx.wenku8_flutter.legado.ScriptUrl(value),org.mewx.wenku8_flutter.legado.ScriptUrl::class.java)
        return super.wrapAsJavaObject(cx, scope, value, staticType)
    }
}
