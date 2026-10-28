/* Adapted from Legado utils/JsURL.kt, GPL-3.0.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820; package only. */
package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import java.net.URL
import java.net.URLDecoder

@Keep
class JsURL(url: String, baseUrl: String? = null) {
    val searchParams: Map<String, String>?
    val host: String
    val origin: String
    val pathname: String
    init {
        val mUrl = if (!baseUrl.isNullOrEmpty()) URL(URL(baseUrl), url) else URL(url)
        host = mUrl.host
        origin = if (mUrl.port > 0) "${mUrl.protocol}://$host:${mUrl.port}" else "${mUrl.protocol}://$host"
        pathname = mUrl.path
        searchParams = mUrl.query?.let { query ->
            val map = hashMapOf<String, String>()
            query.split("&").forEach { value ->
                val x = value.split("=", limit = 2)
                if (x.size == 2) map[x[0]] = URLDecoder.decode(x[1], "utf-8")
            }
            map
        }
    }
}
