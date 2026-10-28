package org.mewx.wenku8_flutter

import com.google.gson.Gson
import java.net.URLEncoder
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.locks.ReentrantLock
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

internal class SourceHubConnections {
    private data class Key(val state: SourceState, val hub: String)
    private class TransportFailure(val delivered: Boolean, val failure: Exception) : RuntimeException(failure)
    private val sessions = ConcurrentHashMap<Key, Session>()

    fun close(state: SourceState) {
        sessions.keys.filter { it.state === state }.forEach { key -> sessions.remove(key)?.stop() }
    }

    fun closeIdle() { sessions.values.forEach { it.stopIfIdle() } }

    fun closeAll() {
        sessions.values.forEach { it.stop() }
        sessions.clear()
    }

    fun invoke(hub: String, method: String, parameters: Map<String, Any?>?, headers: Map<String, String>,
               run: SourceRun, request: (String, String, Map<String, String>, ByteArray?) -> SourceReply,
               permit: () -> Unit): String? {
        val key = Key(run.state, hub)
        for (attempt in 0..1) {
            run.check()
            val session = sessions.compute(key) { _, existing ->
                if (existing != null && existing.headers == headers && (!existing.ended || existing.fallbackUntil > System.nanoTime())) existing
                else {
                    existing?.shutdown()
                    Session(hub, headers) { value -> sessions.remove(key, value) }
                }
            }!!
            try { return session.invoke(method, parameters, run, request, permit) }
            catch (cancelled: java.util.concurrent.CancellationException) {
                run.check()
                sessions.remove(key, session); session.stop()
                if (attempt == 1) throw cancelled
            }
            catch (failure: TransportFailure) {
                sessions.remove(key, session); session.stop()
                val rejected = (failure.failure as? SourceSignalRFailure)?.httpStatus != null
                if (rejected || attempt == 1 || failure.delivered && method !in readOnly) throw failure.failure
            }
        }
        error("SignalR reconnect exhausted")
    }

    private class Session(val hub: String, val headers: Map<String, String>, val remove: (Session) -> Unit) : WebSocketListener() {
        @Volatile var ended = false
        @Volatile var fallbackUntil = 0L
        @Volatile private var lastUsed = System.nanoTime()
        private val lock = ReentrantLock()
        private val ready = CompletableFuture<Unit>()
        private val frames = SourceProtocolCodec.Frames()
        private var handshake = byteArrayOf()
        private var handshaken = false
        private var terminal: Exception? = null
        private var socket: WebSocket? = null
        private var heartbeat: java.util.concurrent.ScheduledFuture<*>? = null
        private data class Pending(val id: String, val result: CompletableFuture<String>, val metrics: SourceRunMetrics)
        private var pending: Pending? = null
        private var sequence = 0L

        fun invoke(method: String, parameters: Map<String, Any?>?, run: SourceRun,
                   request: (String, String, Map<String, String>, ByteArray?) -> SourceReply, permit: () -> Unit): String? {
            val queued = System.nanoTime()
            while (!lock.tryLock(100, TimeUnit.MILLISECONDS)) run.check()
            run.metrics.queuedNanos.addAndGet(System.nanoTime() - queued)
            var delivered = false
            val unregister = run.onCancel { stop() }
            try {
                run.check()
                if (fallbackUntil > System.nanoTime()) return null
                checkOpen()
                if (socket == null) {
                    val response = request("$hub/negotiate?negotiateVersion=1", "POST", headers + mapOf("Content-Type" to "application/json"), "{}".toByteArray())
                    if (response.status !in 200..299) throw SourceSignalRFailure("连接协商", response.status)
                    val negotiation = gson.fromJson((response.data ?: response.body.toByteArray()).toString(Charsets.UTF_8), Map::class.java)
                    if (negotiation["error"] != null) SourceSignalR.protocolFailure("连接协商", negotiation["error"])
                    val transports = negotiation["availableTransports"] as List<*>
                    val supported = transports.any { row ->
                        row as Map<*, *>
                        row["transport"] == "WebSockets" && (row["transferFormats"] as List<*>).contains("Binary")
                    }
                    if (!supported) { usePolling(); return null }
                    val id = negotiation["connectionToken"] as String
                    permit()
                    run.metrics.socketOpens.incrementAndGet()
                    socket = run.openSocket!!.invoke("$hub?id=${URLEncoder.encode(id, "UTF-8")}", headers, this)
                }
                try { await(ready, run) }
                catch (failure: SourceSignalRFailure) {
                    if (failure.httpStatus in setOf(401, 403, 429)) throw failure
                    // A transport which failed before invocation can safely use long polling.
                    usePolling(); return null
                }
                run.check(); permit()
                val id = (++sequence).toString()
                val result = CompletableFuture<String>()
                synchronized(this) { checkOpen(); pending = Pending(id, result, run.metrics) }
                run.metrics.rpcCalls.incrementAndGet()
                if (!socket!!.send(SourceProtocolCodec.frame(listOf(1, emptyMap<String, Any>(), id, method,
                        listOf(parameters, mapOf("UseGzip" to true)), emptyList<Any>())).toByteString())) {
                    throw TransportFailure(false, SourceSignalRFailure("发送调用"))
                }
                delivered = true
                lastUsed = System.nanoTime()
                return await(result, run)
            } catch (failure: SourceSignalRFailure) {
                throw TransportFailure(delivered, failure)
            } finally {
                synchronized(this) { pending = null }
                lastUsed = System.nanoTime(); unregister(); lock.unlock()
            }
        }

        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (ended) { webSocket.cancel(); return }
            if (!webSocket.send("{\"protocol\":\"messagepack\",\"version\":1}\u001e")) fail(SourceSignalRFailure("发送握手"))
        }

        override fun onMessage(webSocket: WebSocket, text: String) = receive(text.toByteArray())
        override fun onMessage(webSocket: WebSocket, bytes: ByteString) = receive(bytes.toByteArray())

        @Synchronized private fun receive(bytes: ByteArray) {
            if (ended) return
            try {
                var data = bytes
                if (!handshaken) {
                    handshake += data
                    require(handshake.size <= 65536) { "SignalR 握手响应过大" }
                    val end = handshake.indexOf(30)
                    if (end < 0) return
                    val response = gson.fromJson(handshake.copyOfRange(0, end).toString(Charsets.UTF_8), Map::class.java)
                    if (response["error"] != null) SourceSignalR.protocolFailure("握手", response["error"])
                    data = handshake.copyOfRange(end + 1, handshake.size); handshake = byteArrayOf()
                    handshaken = true; ready.complete(Unit)
                    heartbeat = timer.scheduleAtFixedRate({
                        if (System.nanoTime() - lastUsed >= TimeUnit.SECONDS.toNanos(60) && !lock.isLocked) stopIfIdle()
                        else if (!ended && socket?.send(SourceProtocolCodec.frame(listOf(6)).toByteString()) == false) fail(SourceSignalRFailure("连接保活"))
                    }, 15, 15, TimeUnit.SECONDS)
                }
                for (raw in frames.append(data)) {
                    val message = raw as List<*>
                    val target = pending
                    when ((message[0] as Number).toInt()) {
                        7 -> SourceSignalR.protocolFailure("服务端关闭连接", message.getOrNull(1))
                        2 -> if (target != null && message[2] == target.id) complete(target.result, message[3], target.metrics)
                        3 -> if (target != null && message[2] == target.id) {
                            if ((message[3] as Number).toInt() != 3) SourceSignalR.protocolFailure("接口调用", message.getOrNull(4))
                            complete(target.result, message[4], target.metrics)
                        }
                    }
                }
            } catch (failure: Exception) { fail(failure) }
        }

        private fun complete(result: CompletableFuture<String>, value: Any?, metrics: SourceRunMetrics) {
            try {
                val started = System.nanoTime()
                val text = try { SourceSignalR.unwrap(value) }
                    finally { metrics.decodeNanos.addAndGet(System.nanoTime() - started) }
                result.complete(text)
            } catch (failure: Exception) { result.completeExceptionally(failure) }
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = fail(SourceSignalRFailure("连接", response?.code))
        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(1000, ""); fail(SourceSignalRFailure("服务端关闭连接"))
        }
        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = fail(SourceSignalRFailure("连接已结束"))

        @Synchronized private fun fail(failure: Exception) {
            if (!ended) {
                terminal = failure; ended = true; ready.completeExceptionally(failure); pending?.result?.completeExceptionally(failure)
            }
            heartbeat?.cancel(false); socket?.cancel()
        }

        private fun checkOpen() {
            if (!ended) return
            val failure = terminal ?: SourceSignalRFailure("连接已结束")
            if (failure is java.util.concurrent.CancellationException) throw failure
            throw TransportFailure(false, failure)
        }

        private fun usePolling() {
            fallbackUntil = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
            ended = true; socket?.cancel()
            heartbeat = timer.schedule({ remove(this) }, 30, TimeUnit.SECONDS)
        }

        fun stopIfIdle() {
            if (lock.tryLock()) try { stop() } finally { lock.unlock() }
        }
        fun shutdown() { fail(java.util.concurrent.CancellationException()) }
        fun stop() { shutdown(); remove(this) }
    }

    companion object {
        private val gson = Gson()
        private val readOnly = setOf("GetMyInfo", "GetBookInfo", "GetBookList", "GetRank", "GetNovelContent", "GetBookShelf", "GetBookListByIds")
        private val timer = ScheduledThreadPoolExecutor(1) { task -> Thread(task, "SourceHubKeepAlive").apply { isDaemon = true } }.apply { removeOnCancelPolicy = true }
        private fun <T> await(future: CompletableFuture<T>, run: SourceRun): T {
            val started = System.nanoTime()
            try { while (true) {
                run.check()
                try { return future.get(100, TimeUnit.MILLISECONDS).also { run.check() } }
                catch (_: TimeoutException) { }
                catch (failure: ExecutionException) { throw failure.cause!! }
            } } finally { run.metrics.hubNanos.addAndGet(System.nanoTime() - started) }
        }
    }
}
