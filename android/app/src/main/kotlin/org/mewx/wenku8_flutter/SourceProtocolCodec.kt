package org.mewx.wenku8_flutter

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.util.Base64
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream

internal object SourceProtocolCodec {
    private const val LIMIT = 8 * 1024 * 1024

    fun inflate(data: ByteArray, format: String): ByteArray {
        val input = ByteArrayInputStream(data)
        val stream = when (format) {
            "gzip" -> GZIPInputStream(input)
            "zlib" -> InflaterInputStream(input)
            else -> error("不支持的压缩格式")
        }
        return stream.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                require(output.size() + count <= LIMIT) { "书源解压结果超过 8 MiB" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    }

    fun compressedText(base64: String, format: String): String =
        inflate(Base64.getMimeDecoder().decode(base64), format).toString(Charsets.UTF_8)

    fun pack(value: Any?): ByteArray {
        val result = ByteArrayOutputStream()
        DataOutputStream(result).use { write(it, value) }
        return result.toByteArray()
    }

    private fun write(out: DataOutputStream, value: Any?) {
        when (value) {
            null -> out.writeByte(0xc0)
            is Boolean -> out.writeByte(if (value) 0xc3 else 0xc2)
            is ByteArray -> {
                out.writeByte(0xc6); out.writeInt(value.size); out.write(value)
            }
            is String -> {
                val bytes = value.toByteArray(Charsets.UTF_8)
                when {
                    bytes.size < 32 -> out.writeByte(0xa0 or bytes.size)
                    bytes.size <= 255 -> { out.writeByte(0xd9); out.writeByte(bytes.size) }
                    bytes.size <= 65535 -> { out.writeByte(0xda); out.writeShort(bytes.size) }
                    else -> { out.writeByte(0xdb); out.writeInt(bytes.size) }
                }
                out.write(bytes)
            }
            is Number -> {
                val integer = value.toLong()
                if (value.toDouble() != integer.toDouble()) {
                    out.writeByte(0xcb); out.writeDouble(value.toDouble())
                } else when (integer) {
                    in 0..127 -> out.writeByte(integer.toInt())
                    in -32..-1 -> out.writeByte(integer.toInt())
                    in 128..255 -> { out.writeByte(0xcc); out.writeByte(integer.toInt()) }
                    in 256..65535 -> { out.writeByte(0xcd); out.writeShort(integer.toInt()) }
                    in Int.MIN_VALUE..Int.MAX_VALUE -> { out.writeByte(0xd2); out.writeInt(integer.toInt()) }
                    else -> { out.writeByte(0xd3); out.writeLong(integer) }
                }
            }
            is List<*> -> {
                if (value.size < 16) out.writeByte(0x90 or value.size)
                else { out.writeByte(0xdc); out.writeShort(value.size) }
                value.forEach { write(out, it) }
            }
            is Map<*, *> -> {
                if (value.size < 16) out.writeByte(0x80 or value.size)
                else { out.writeByte(0xde); out.writeShort(value.size) }
                value.forEach { (key, item) -> write(out, key); write(out, item) }
            }
            else -> error("MessagePack 值类型不支持")
        }
    }

    fun unpack(data: ByteArray): Any? = DataInputStream(ByteArrayInputStream(data)).use { input ->
        val value = read(input, 0)
        require(input.available() == 0) { "MessagePack 帧包含多余数据" }
        value
    }

    private fun bytes(input: DataInputStream, size: Int): ByteArray {
        require(size in 0..LIMIT && size <= input.available()) { "MessagePack 数据长度无效" }
        return ByteArray(size).also(input::readFully)
    }

    private fun read(input: DataInputStream, depth: Int): Any? {
        require(depth < 64) { "MessagePack 嵌套过深" }
        val tag = input.readUnsignedByte()
        fun array(size: Int): List<Any?> {
            require(size in 0..100000) { "MessagePack 数组过大" }
            return List(size) { read(input, depth + 1) }
        }
        fun map(size: Int): Map<String, Any?> {
            require(size in 0..100000) { "MessagePack 对象过大" }
            return buildMap { repeat(size) { put(read(input, depth + 1) as String, read(input, depth + 1)) } }
        }
        return when (tag) {
            in 0..127 -> tag.toLong()
            in 0xe0..0xff -> tag.toByte().toLong()
            in 0xa0..0xbf -> bytes(input, tag and 31).toString(Charsets.UTF_8)
            in 0x90..0x9f -> array(tag and 15)
            in 0x80..0x8f -> map(tag and 15)
            0xc0 -> null
            0xc2 -> false
            0xc3 -> true
            0xc4 -> bytes(input, input.readUnsignedByte())
            0xc5 -> bytes(input, input.readUnsignedShort())
            0xc6 -> bytes(input, input.readInt())
            0xca -> input.readFloat().toDouble()
            0xcb -> input.readDouble()
            0xcc -> input.readUnsignedByte().toLong()
            0xcd -> input.readUnsignedShort().toLong()
            0xce -> input.readInt().toLong() and 0xffffffffL
            0xcf, 0xd3 -> input.readLong()
            0xd0 -> input.readByte().toLong()
            0xd1 -> input.readShort().toLong()
            0xd2 -> input.readInt().toLong()
            0xd9 -> bytes(input, input.readUnsignedByte()).toString(Charsets.UTF_8)
            0xda -> bytes(input, input.readUnsignedShort()).toString(Charsets.UTF_8)
            0xdb -> bytes(input, input.readInt()).toString(Charsets.UTF_8)
            0xdc -> array(input.readUnsignedShort())
            0xdd -> array(input.readInt())
            0xde -> map(input.readUnsignedShort())
            0xdf -> map(input.readInt())
            else -> error("MessagePack 返回了不支持的类型")
        }
    }

    fun frame(value: Any?): ByteArray {
        val payload = pack(value)
        val output = ByteArrayOutputStream()
        var length = payload.size
        while (length >= 128) { output.write((length and 127) or 128); length = length ushr 7 }
        output.write(length); output.write(payload)
        return output.toByteArray()
    }

    class Frames {
        private var pending = byteArrayOf()
        fun append(bytes: ByteArray): List<Any?> {
            require(pending.size + bytes.size <= LIMIT) { "SignalR 响应超过 8 MiB" }
            pending += bytes
            val messages = mutableListOf<Any?>()
            var offset = 0
            while (offset < pending.size) {
                var length = 0
                var cursor = offset
                var complete = false
                for (shift in 0..28 step 7) {
                    if (cursor == pending.size) break
                    val next = pending[cursor++].toInt() and 255
                    require(shift < 28 || next < 8) { "SignalR 帧长度无效" }
                    length = length or ((next and 127) shl shift)
                    if (next < 128) { complete = true; break }
                }
                if (!complete) break
                require(length in 1..LIMIT) { "SignalR 帧长度无效" }
                if (pending.size - cursor < length) break
                messages.add(unpack(pending.copyOfRange(cursor, cursor + length)))
                offset = cursor + length
            }
            pending = pending.copyOfRange(offset, pending.size)
            return messages
        }
    }
}
