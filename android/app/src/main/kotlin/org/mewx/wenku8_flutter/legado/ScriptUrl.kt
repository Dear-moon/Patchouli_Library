package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import java.net.URL
import java.util.Locale

/** URL inspection without Java URL's hidden DNS/stream side effects.
 * Remains safe when passed back into a Java collection as a key. */
@Keep
class ScriptUrl(private val value: URL) {
    fun getProtocol()=value.protocol
    fun getHost()=value.host
    fun getPort()=value.port
    fun getDefaultPort()=value.defaultPort
    fun getAuthority()=value.authority
    fun getUserInfo()=value.userInfo
    fun getPath()=value.path
    fun getFile()=value.file
    fun getQuery()=value.query
    fun getRef()=value.ref
    fun toURI()=value.toURI()
    fun toExternalForm()=value.toExternalForm()
    private fun identity(fragment:Boolean)=listOf(getProtocol().lowercase(Locale.ROOT),getHost().lowercase(Locale.ROOT),
        if(getPort()==-1)getDefaultPort() else getPort(),getFile(),if(fragment)getRef() else null)
    fun sameFile(other:ScriptUrl)=identity(false)==other.identity(false)
    override fun equals(other:Any?)=other is ScriptUrl && identity(true)==other.identity(true)
    override fun hashCode()=identity(true).hashCode()
    override fun toString()=toExternalForm()
}
