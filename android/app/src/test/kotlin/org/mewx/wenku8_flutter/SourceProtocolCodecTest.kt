package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.Base64
import java.util.zip.GZIPOutputStream
import java.util.zip.DeflaterOutputStream

class SourceProtocolCodecTest {
    @Test fun fragmentedFramesPreserveBinaryPayloadAndUnicode() {
        val value = listOf(3L, emptyMap<String, Any>(), "1", 3L,
            mapOf("Success" to true, "Response" to byteArrayOf(0, -1, 7), "title" to "书籍😀", "count" to 70000L))
        val frame = SourceProtocolCodec.frame(value)
        val frames = SourceProtocolCodec.Frames()
        assertTrue(frames.append(frame.copyOfRange(0, 2)).isEmpty())
        val result = frames.append(frame.copyOfRange(2, frame.size)).single() as List<*>
        val response = result[4] as Map<*, *>
        assertEquals("书籍😀", response["title"])
        assertArrayEquals(byteArrayOf(0, -1, 7), response["Response"] as ByteArray)
        assertEquals(70000L, response["count"])
        assertTrue(frames.append(SourceProtocolCodec.frame(listOf(6L)) + SourceProtocolCodec.frame(listOf(6L))).size == 2)
    }

    @Test fun gzipAndZlibDecodeToTheSameJson() {
        val text = "{\"title\":\"固定样本😀\"}"
        for (format in listOf("gzip", "zlib")) {
            val bytes = ByteArrayOutputStream()
            val stream = if (format == "gzip") GZIPOutputStream(bytes) else DeflaterOutputStream(bytes)
            stream.use { it.write(text.toByteArray()) }
            assertEquals(text, SourceProtocolCodec.compressedText(Base64.getEncoder().encodeToString(bytes.toByteArray()), format))
        }
    }

    @Test fun longLengthPrefixCanArriveInSeparatePolls() {
        val text = "x".repeat(500)
        val frame = SourceProtocolCodec.frame(listOf(text))
        val frames = SourceProtocolCodec.Frames()
        assertTrue(frames.append(frame.copyOfRange(0, 1)).isEmpty())
        assertEquals(listOf(text), frames.append(frame.copyOfRange(1, frame.size)).single())
    }
}
