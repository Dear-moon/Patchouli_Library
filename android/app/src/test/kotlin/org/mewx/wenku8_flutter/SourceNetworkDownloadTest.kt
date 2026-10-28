package org.mewx.wenku8_flutter

import java.io.File
import java.net.ServerSocket
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Test

class SourceNetworkDownloadTest {
    private fun serve(body: ByteArray, action: (String) -> Unit) {
        ServerSocket(0).use { server ->
            val worker = thread(isDaemon=true) {
                server.accept().use { socket ->
                    val reader = socket.getInputStream().bufferedReader()
                    while (!reader.readLine().isNullOrEmpty()) { }
                    socket.getOutputStream().apply {
                        write("HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray())
                        write(body); flush()
                    }
                }
            }
            action("http://127.0.0.1:${server.localPort}/volume.epub")
            worker.join(5000)
            assertFalse(worker.isAlive)
        }
    }

    @Test fun diskSinkReportsRealBytesWithoutKeepingThePayloadInMemory() {
        val payload = ByteArray(70000) { (it % 251).toByte() }
        val file = File.createTempFile("source-download-", ".epub")
        try {
            serve(payload) { url ->
                val progress = mutableListOf<Pair<Long, Long?>>()
                val reply = SourceNetwork().bytes(null, url, run=SourceRun(fetch={ _, _, _, _ -> error("Unexpected request") }),
                    destination=file, onProgress={ received, total -> progress.add(received to total) })
                assertTrue(reply.data.isEmpty())
                assertArrayEquals(payload, file.readBytes())
                assertEquals(0L to payload.size.toLong(), progress.first())
                assertEquals(payload.size.toLong() to payload.size.toLong(), progress.last())
            }
        } finally { file.delete() }
    }

    @Test fun diskSinkStillEnforcesTheResponseLimit() {
        val file = File.createTempFile("source-download-limit-", ".epub")
        try {
            serve(ByteArray(100)) { url ->
                assertThrows(IllegalStateException::class.java) {
                    SourceNetwork().bytes(null, url, run=SourceRun(fetch={ _, _, _, _ -> error("Unexpected request") }),
                        options=SourceHttpOptions(maxResponseBytes=50), destination=file)
                }
                assertEquals(0L, file.length())
            }
        } finally { file.delete() }
    }
}
