package org.mewx.wenku8_flutter

import com.google.gson.Gson
import java.io.IOException
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.junit.Assert.*
import org.junit.Test

class SourceHubConnectionsTest {
    private class Harness {
        val hubs = SourceHubConnections()
        val state = SourceState()
        val sockets = mutableListOf<FakeSocket>()
        val invoked = mutableListOf<String>()
        var negotiations = 0
        var failFirst = false
        var hold = false
        var rejectHandshake = false
        val sent = CountDownLatch(1)
        fun run(owner: SourceState = state) = SourceRun(state=owner, hubs=hubs,
            fetch={ _, _, _, _ -> error("Unexpected HTTP") },
            openSocket={ address, _, listener ->
                FakeSocket(address, listener, this).also {
                    sockets.add(it)
                    listener.onOpen(it, Response.Builder().request(it.request()).protocol(Protocol.HTTP_1_1).code(101).message("Switching Protocols").build())
                }
            })
        fun invoke(run: SourceRun = run(), method: String = "GetBookInfo", token: String = "fixture-private-token"): String =
            SourceSignalR.invoke("https://hub.example.test/hub/api", token, method, emptyMap(), run) { url, _, _, _ ->
                negotiations++; run.countRequest()
                SourceReply(url, Gson().toJson(mapOf("connectionToken" to "fixture-private-connection", "availableTransports" to listOf(mapOf("transport" to "WebSockets", "transferFormats" to listOf("Text", "Binary"))))))
            }
    }

    private class FakeSocket(address: String, val listener: WebSocketListener, val harness: Harness) : WebSocket {
        private val request = Request.Builder().url(address).build()
        var stopped = false
        override fun request() = request
        override fun queueSize() = 0L
        override fun send(text: String): Boolean {
            if (harness.rejectHandshake) listener.onMessage(this, "{\"error\":\"Unauthorized\"}\u001e")
            else listener.onMessage(this, "{}\u001e")
            return true
        }
        override fun send(bytes: ByteString): Boolean {
            val frame = SourceProtocolCodec.Frames().append(bytes.toByteArray()).single() as List<*>
            if ((frame[0] as Number).toInt() == 6) return true
            harness.invoked.add(frame[3] as String); harness.sent.countDown()
            if (harness.failFirst) {
                harness.failFirst = false
                listener.onFailure(this, IOException("fixture-private-details"), null)
            } else if (!harness.hold) {
                listener.onMessage(this, SourceProtocolCodec.frame(listOf(3, emptyMap<String, Any>(), frame[2], 3,
                    mapOf("Success" to true, "Response" to mapOf("value" to "fixture")))).toByteString())
            }
            return true
        }
        override fun close(code: Int, reason: String?): Boolean { stopped = true; return true }
        override fun cancel() { stopped = true }
    }

    @Test fun repeatedInvocationsReuseOneNegotiationAndSocket() {
        val h = Harness()
        try {
            val first=h.run(); val second=h.run()
            assertEquals(h.invoke(first), h.invoke(second))
            assertEquals(1,h.negotiations); assertEquals(1,h.sockets.size)
            assertEquals(3,first.requests); assertEquals(1,second.requests)
        } finally { h.hubs.closeAll() }
    }

    @Test fun accountStatesAndChangedTokensNeverShareConnections() {
        val h=Harness()
        try {
            h.invoke(); h.invoke(h.run(SourceState()))
            assertEquals(2,h.sockets.size)
            h.invoke(token="fixture-renewed-token")
            assertEquals(3,h.sockets.size); assertTrue(h.sockets.first().stopped)
        } finally { h.hubs.closeAll() }
    }

    @Test fun clearingOneAccountDoesNotCloseOtherAccounts() {
        val h=Harness();val other=SourceState()
        try {
            h.invoke();h.invoke(h.run(other));h.hubs.close(h.state)
            assertTrue(h.sockets[0].stopped);assertFalse(h.sockets[1].stopped)
            h.invoke(h.run(other));assertEquals(2,h.sockets.size)
        } finally {h.hubs.closeAll()}
    }

    @Test fun readOnlyCallsReconnectOnceAfterTransportFailure() {
        val h=Harness();h.failFirst=true
        try {h.invoke();assertEquals(2,h.negotiations);assertEquals(listOf("GetBookInfo","GetBookInfo"),h.invoked)}
        finally {h.hubs.closeAll()}
    }

    @Test fun deliveredSignInIsNeverRetriedAfterUncertainCompletion() {
        val h=Harness();h.failFirst=true
        try {
            assertThrows(SourceSignalRFailure::class.java) {h.invoke(method="SignIn")}
            assertEquals(1,h.negotiations);assertEquals(listOf("SignIn"),h.invoked)
        } finally {h.hubs.closeAll()}
    }

    @Test fun handshakeAuthorizationFailureStaysAnAuthenticationFailure() {
        val h=Harness();h.rejectHandshake=true
        try {
            val failure=assertThrows(SourceSignalRFailure::class.java) {h.invoke()}
            assertEquals(401,failure.httpStatus);assertEquals(1,h.negotiations);assertTrue(h.invoked.isEmpty())
        } finally {h.hubs.closeAll()}
    }

    @Test fun cancelInterruptsPendingResultAndInvalidatesTheConnection() {
        val h=Harness();h.hold=true;val run=h.run();val worker=Executors.newSingleThreadExecutor()
        try {
            val result=worker.submit<Boolean> {try {h.invoke(run);false} catch (_:CancellationException) {true}}
            assertTrue(h.sent.await(2,TimeUnit.SECONDS));run.cancel()
            assertTrue(result.get(2,TimeUnit.SECONDS));assertTrue(h.sockets.single().stopped)
            h.hold=false;h.invoke();assertEquals(2,h.sockets.size)
        } finally {h.hubs.closeAll();worker.shutdownNow()}
    }

    @Test fun backgroundTransitionPreservesActiveRequests() {
        val h = Harness()
        h.hold = true
        val worker = Executors.newSingleThreadExecutor()
        val run = h.run()
        try {
            val result = worker.submit<Boolean> {
                try { h.invoke(run); false } catch (_: CancellationException) { true }
            }
            assertTrue(h.sent.await(2, TimeUnit.SECONDS))
            h.hubs.closeIdle()
            assertFalse(h.sockets.single().stopped)
            run.cancel()
            assertTrue(result.get(2, TimeUnit.SECONDS))
        } finally { h.hubs.closeAll(); worker.shutdownNow() }
    }

    @Test fun backgroundTransitionClosesIdleConnections() {
        val h = Harness()
        try {
            h.invoke()
            h.hubs.closeIdle()
            assertTrue(h.sockets.single().stopped)
            h.invoke()
            assertEquals(2, h.sockets.size)
        } finally { h.hubs.closeAll() }
    }

    @Test fun unsupportedTransportUsesPollingWithoutOpeningSocket() {
        val h = Harness()
        var negotiations = 0
        val request: (String, String, Map<String, String>, ByteArray?) -> SourceReply = { url, _, _, _ ->
            negotiations++
            SourceReply(url, Gson().toJson(mapOf("connectionToken" to "fixture",
                "availableTransports" to listOf(mapOf("transport" to "LongPolling", "transferFormats" to listOf("Binary"))))))
        }
        try {
            repeat(2) {
                assertNull(h.hubs.invoke("https://hub.example.test/hub/api", "GetBookInfo", emptyMap(), emptyMap(), h.run(), request) {})
            }
            assertEquals(1, negotiations)
            assertTrue(h.sockets.isEmpty())
        } finally { h.hubs.closeAll() }
    }

    @Test fun rateLimitedNegotiationIsNotRetriedOrDowngraded() {
        val h = Harness()
        var requests = 0
        try {
            val failure = assertThrows(SourceSignalRFailure::class.java) {
                h.hubs.invoke("https://hub.example.test/hub/api", "GetBookInfo", emptyMap(), emptyMap(), h.run(),
                    { url, _, _, _ -> requests++; SourceReply(url, "", 429) }, {})
            }
            assertEquals(429, failure.httpStatus)
            assertEquals(1, requests)
            assertTrue(h.sockets.isEmpty())
        } finally { h.hubs.closeAll() }
    }

    @Test fun safeMetricsNeverEchoUntrustedIdentifiers() {
        val metrics=SourceRunMetrics()
        val line=metrics.report("fixture-private-password", "https://fixture-private-host.invalid/token", 4)
        assertTrue(line.contains("platform=custom operation=custom"))
        assertFalse(line.contains("private"));assertFalse(line.contains("https://"))
    }
}
