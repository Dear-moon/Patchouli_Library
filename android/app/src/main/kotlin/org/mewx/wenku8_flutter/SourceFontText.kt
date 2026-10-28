package org.mewx.wenku8_flutter

import org.brotli.dec.BrotliInputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

internal object SourceFontText {
    private val tags = ("cmap head hhea hmtx maxp name OS/2 post cvt_ fpgm glyf loca prep CFF_ VORG EBDT EBLC gasp hdmx kern " +
        "LTSH PCLT VDMX vhea vmtx BASE GDEF GPOS GSUB EBSC JSTF MATH CBDT CBLC COLR CPAL SVG_ sbix acnt avar " +
        "bdat bloc bsln cvar fdsc feat fmtx fvar gvar hsty just lcar mort morx opbd prop trak Zapf Silf Glat Gloc Feat Sill")
        .split(' ').map { it.replace('_', ' ') }
    private data class Table(val bytes: ByteArray, val transformed: Boolean = false)
    private const val LIMIT = 16 * 1024 * 1024

    fun clean(text: String, font: ByteArray, check: () -> Unit = {}): String {
        require(font.size <= 8 * 1024 * 1024) { "书源字体超过 8 MiB" }
        val tables = if (font.take(4).toByteArray().toString(Charsets.US_ASCII) == "wOF2") woff2(font) else sfnt(font)
        val glyphs = u16(tables.getValue("maxp").bytes, 4)
        val metrics = u16(tables.getValue("hhea").bytes, 34)
        require(metrics in 1..glyphs) { "字体水平度量无效" }
        val hmtx = tables.getValue("hmtx")
        val advances = IntArray(glyphs) { index ->
            val metric = index.coerceAtMost(metrics - 1)
            u16(hmtx.bytes, if (hmtx.transformed) 1 + metric * 2 else metric * 4)
        }
        val glyf = tables.getValue("glyf")
        val empty = if (glyf.transformed) {
            require(u16(glyf.bytes, 4) == glyphs) { "字体轮廓数量无效" }
            BooleanArray(glyphs) { u16(glyf.bytes, 36 + it * 2) == 0 }
        } else {
            val loca = tables.getValue("loca").bytes
            val short = u16(tables.getValue("head").bytes, 50) == 0
            fun offset(index: Int) = if (short) u16(loca, index * 2) * 2 else u32(loca, index * 4)
            BooleanArray(glyphs) { index ->
                val start = offset(index)
                start == offset(index + 1) || u16(glyf.bytes, start) == 0
            }
        }
        val cmap = tables.getValue("cmap").bytes
        val subtables = (0 until u16(cmap, 2)).mapNotNull { index ->
            val entry = 4 + index * 8
            val platform = u16(cmap, entry)
            val encoding = u16(cmap, entry + 2)
            val offset = u32(cmap, entry + 4)
            if (platform != 0 && !(platform == 3 && encoding in setOf(1, 10))) null
            else offset.takeIf { u16(cmap, it) in setOf(0, 4, 6, 12, 13) }
        }.sortedByDescending { when (u16(cmap, it)) { 12 -> 5; 13 -> 4; 4 -> 3; 6 -> 2; else -> 1 } }
        require(subtables.isNotEmpty()) { "字体未提供 Unicode 字符映射" }
        val subtable = subtables.first()
        val invisible = HashMap<Int, Boolean>()
        val result = StringBuilder(text.length)
        var offset = 0
        while (offset < text.length) {
            check()
            val code = text.codePointAt(offset)
            offset += Character.charCount(code)
            val hidden = invisible.getOrPut(code) {
                val glyph = glyph(cmap, subtable, code)
                code != 0 && glyph > 0 && empty[glyph] && advances[glyph] == 0
            }
            if (!hidden) result.appendCodePoint(code)
        }
        return result.toString()
    }

    private fun glyph(data: ByteArray, offset: Int, code: Int): Int = when (u16(data, offset)) {
        0 -> if (code in 0..255) data[offset + 6 + code].toInt() and 255 else 0
        6 -> {
            val index = code - u16(data, offset + 6)
            if (index in 0 until u16(data, offset + 8)) u16(data, offset + 10 + index * 2) else 0
        }
        4 -> {
            val count = u16(data, offset + 6) / 2
            val ends = offset + 14
            val starts = ends + count * 2 + 2
            val deltas = starts + count * 2
            val ranges = deltas + count * 2
            val segment = (0 until count).firstOrNull { code <= u16(data, ends + it * 2) }
            if (segment == null || code < u16(data, starts + segment * 2)) 0
            else {
                val delta = u16(data, deltas + segment * 2)
                val range = u16(data, ranges + segment * 2)
                if (range == 0) (code + delta) and 65535
                else {
                    val id = u16(data, ranges + segment * 2 + range + (code - u16(data, starts + segment * 2)) * 2)
                    if (id == 0) 0 else (id + delta) and 65535
                }
            }
        }
        12, 13 -> {
            val count = u32(data, offset + 12)
            var low = 0
            var high = count - 1
            var result = 0
            while (low <= high) {
                val middle = (low + high) ushr 1
                val group = offset + 16 + middle * 12
                val first = u32(data, group)
                val last = u32(data, group + 4)
                when {
                    code < first -> high = middle - 1
                    code > last -> low = middle + 1
                    else -> { result = u32(data, group + 8) + if (u16(data, offset) == 12) code - first else 0; break }
                }
            }
            result
        }
        else -> error("字体映射格式不支持")
    }

    private fun sfnt(data: ByteArray): Map<String, Table> {
        require(u32(data, 0) == 0x10000) { "目前仅支持 TrueType 字体" }
        return (0 until u16(data, 4)).associate { index ->
            val entry = 12 + index * 16
            val tag = data.copyOfRange(entry, entry + 4).toString(Charsets.US_ASCII)
            val start = u32(data, entry + 8)
            tag to Table(data.copyOfRange(start, start + u32(data, entry + 12)))
        }
    }

    private fun woff2(data: ByteArray): Map<String, Table> {
        require(u32(data, 4) == 0x10000) { "目前仅支持单个 TrueType WOFF2 字体" }
        data class Entry(val tag: String, val length: Int, val transformed: Boolean)
        var cursor = 48
        fun base128(): Int {
            var result = 0L
            repeat(5) {
                val next = data[cursor++].toInt() and 255
                result = (result shl 7) or (next and 127).toLong()
                require(result <= LIMIT) { "WOFF2 表超过大小限制" }
                if (next < 128) return result.toInt()
            }
            error("WOFF2 表长度无效")
        }
        val entries = List(u16(data, 12)) {
            val flags = data[cursor++].toInt() and 255
            val tag = if (flags and 63 == 63) data.copyOfRange(cursor, cursor + 4).toString(Charsets.US_ASCII).also { cursor += 4 }
                else tags[flags and 63]
            val originalLength = base128()
            val version = flags ushr 6
            val transformed = if (tag == "glyf" || tag == "loca") version != 3 else version != 0
            require(!transformed || tag in setOf("glyf", "loca", "hmtx")) { "WOFF2 包含不支持的表变换" }
            Entry(tag, if (transformed) base128() else originalLength, transformed)
        }
        val expected = entries.sumOf { it.length.toLong() }
        require(expected <= LIMIT) { "WOFF2 解压结果过大" }
        val compressed = u32(data, 20)
        val decoded = BrotliInputStream(ByteArrayInputStream(data, cursor, compressed)).use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= expected) { "WOFF2 解压长度无效" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        require(decoded.size.toLong() == expected) { "WOFF2 数据不完整" }
        cursor = 0
        return entries.associate { entry ->
            entry.tag to Table(decoded.copyOfRange(cursor, cursor + entry.length).also { cursor += entry.length }, entry.transformed)
        }
    }

    private fun u16(data: ByteArray, offset: Int): Int = ByteBuffer.wrap(data, offset, 2).order(ByteOrder.BIG_ENDIAN).short.toInt() and 65535
    private fun u32(data: ByteArray, offset: Int): Int {
        val value = ByteBuffer.wrap(data, offset, 4).order(ByteOrder.BIG_ENDIAN).int
        require(value >= 0) { "字体表长度或偏移无效" }
        return value
    }
}
