/* Legado 3.0, GPL-3.0, gedoor and contributors.
 * Reference 3046111c1718e7b67c2ad468e54edf295ec05820.
 * Modified 2026-10-18: relocated package and platform-independent codec bindings. */
package org.mewx.wenku8_flutter.legado

import androidx.annotation.Keep
import cn.hutool.core.codec.Base64
import cn.hutool.core.util.HexUtil
import cn.hutool.crypto.symmetric.SymmetricCrypto
import java.io.InputStream
import java.nio.charset.Charset

@Keep
class SymmetricCryptoAndroid(
    algorithm: String,
    key: ByteArray?,
) : SymmetricCrypto(algorithm, key) {

    override fun encryptBase64(data: ByteArray): String {
        return EncoderUtils.base64Encode(encrypt(data))
    }

    override fun encryptBase64(data: String, charset: String?): String {
        return EncoderUtils.base64Encode(encrypt(data, charset))
    }

    override fun encryptBase64(data: String, charset: Charset?): String {
        return EncoderUtils.base64Encode(encrypt(data, charset))
    }

    override fun encryptBase64(data: String): String {
        return EncoderUtils.base64Encode(encrypt(data))
    }

    override fun encryptBase64(data: InputStream): String {
        return EncoderUtils.base64Encode(encrypt(data))
    }

    override fun decrypt(data: String): ByteArray {
        val bytes = if (data.isHex()) {
            HexUtil.decodeHex(data)
        } else {
            Base64.decode(data)
        }
        return decrypt(bytes)
    }

}
