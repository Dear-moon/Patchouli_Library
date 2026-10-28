/* Legado 3.0, GPL-3.0, gedoor and contributors.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Modified 2026-10-18: relocated package and platform-independent codec bindings. */
package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import cn.hutool.crypto.KeyUtil
import cn.hutool.crypto.asymmetric.Sign as HutoolSign

@Keep
@Suppress("unused")
class Sign(algorithm: String): HutoolSign(algorithm) {

    fun setPrivateKey(key: ByteArray): Sign {
        setPrivateKey(KeyUtil.generatePrivateKey(algorithm, key))
        return this
    }

    fun setPrivateKey(key: String): Sign = setPrivateKey(key.encodeToByteArray())

    fun setPublicKey(key: ByteArray): Sign {
        setPublicKey(KeyUtil.generatePublicKey(algorithm, key))
        return this
    }

    fun setPublicKey(key: String): Sign = setPublicKey(key.encodeToByteArray())

}

