package org.mewx.wenku8_flutter

import com.google.gson.Gson
import java.net.URLEncoder

internal class SourceSignalRFailure(val stage: String, val httpStatus: Int? = null) : IllegalStateException(
    if (httpStatus == 401) "轻书架登录已过期，请重新登录"
    else "书源轻书架${stage}失败" + (httpStatus?.let { "（HTTP $it）" } ?: ""))

internal object SourceSignalR {
    private val gson = Gson()
    private val authenticationError = Regex("401|unauthori[sz]ed|invalid token|no\\s*token|notoken|无效token|未登录|授权", RegexOption.IGNORE_CASE)

    fun protocolFailure(stage: String, detail: Any?): Nothing {
        throw SourceSignalRFailure(stage, if (detail is String && authenticationError.containsMatchIn(detail)) 401 else null)
    }

    fun invoke(hub: String, token: String, method: String, parameters: Map<String, Any?>?,
               run: SourceRun, socketHeaders: Map<String, String> = emptyMap(), permit: () -> Unit = { run.countRequest() },
               request: (String, String, Map<String, String>, ByteArray?) -> SourceReply): String {
        SourceNetwork.url(hub)
        val headers = if (token.isEmpty()) emptyMap() else mapOf("Authorization" to "Bearer $token")
        if (run.hubs != null && run.openSocket != null) {
            run.hubs.invoke(hub, method, parameters, socketHeaders + headers, run, request, permit)?.let { return it }
        }
        fun call(stage: String, url: String, verb: String, data: ByteArray? = null, type: String = "application/octet-stream"): SourceReply {
            run.check()
            val response = request(url, verb, headers + mapOf("Content-Type" to type), data)
            if (response.status !in 200..299) throw SourceSignalRFailure(stage, response.status)
            return response
        }
        val negotiation = call("连接协商", "$hub/negotiate?negotiateVersion=1", "POST", "{}".toByteArray(), "application/json")
        val connection = gson.fromJson((negotiation.data ?: negotiation.body.toByteArray()).toString(Charsets.UTF_8), Map::class.java)
        val id = connection["connectionToken"] as String
        val url = "$hub?id=${URLEncoder.encode(id, "UTF-8") }"
        val frames = SourceProtocolCodec.Frames()
        var handshake = byteArrayOf()
        var ready = false
        try {
            call("建立连接", url, "GET")
            call("发送握手", url, "POST", "{\"protocol\":\"messagepack\",\"version\":1}\u001e".toByteArray(), "text/plain;charset=UTF-8")
            while (!ready) {
                val response = call("等待握手", url, "GET")
                handshake += response.data ?: response.body.toByteArray()
                require(handshake.size <= 65536) { "SignalR 握手响应过大" }
                val end = handshake.indexOf(30)
                if (end >= 0) {
                    val reply = gson.fromJson(handshake.copyOfRange(0, end).toString(Charsets.UTF_8), Map::class.java)
                    if (reply["error"] != null) protocolFailure("握手", reply["error"])
                    frames.append(handshake.copyOfRange(end + 1, handshake.size))
                    ready = true
                }
            }
            run.metrics.rpcCalls.incrementAndGet()
            call("发送调用", url, "POST", SourceProtocolCodec.frame(listOf(1, emptyMap<String, Any>(), "1", method,
                listOf(parameters, mapOf("UseGzip" to true)), emptyList<Any>())))
            while (true) {
                val response = call("读取结果", url, "GET")
                if (response.status == 204) throw SourceSignalRFailure("连接已结束", 204)
                for (raw in frames.append(response.data ?: response.body.toByteArray())) {
                    val message = raw as List<*>
                    when ((message[0] as Number).toInt()) {
                        7 -> protocolFailure("服务端关闭连接", message.getOrNull(1))
                        2 -> if (message[2] == "1") return unwrap(message[3])
                        3 -> if (message[2] == "1") {
                            if ((message[3] as Number).toInt() != 3) protocolFailure("接口调用", message.getOrNull(4))
                            return unwrap(message[4])
                        }
                    }
                }
            }
        } finally {
            // Release the polling connection without hiding the original request failure.
            runCatching { request(url, "DELETE", headers, null) }
        }
    }

    fun unwrap(raw: Any?): String {
        val response = raw as Map<*, *>
        if (response["Success"] != true) {
            if ((response["Status"] as? Number)?.toInt() in setOf(401, -100)) error("轻书架登录已过期，请重新登录")
            val status = (response["Status"] as? Number)?.toInt()
            throw SourceAccountFailure("书源轻书架业务请求未成功" + (status?.let { "（状态码 $it）" } ?: ""))
        }
        val result = response["Response"]
        return if (result is ByteArray) SourceProtocolCodec.inflate(result, "gzip").toString(Charsets.UTF_8)
            else gson.toJson(result)
    }
}
