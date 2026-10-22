package org.mewx.wenku8_flutter

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.util.ArrayDeque

/** Foreground DNS-SD only. Advertisements contain no book or account data. */
class LanDiscoveryPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var manager: NsdManager
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val type = "_wenkuread._tcp."
    private var epoch = 0
    private var ownId = ""
    private var registration: NsdManager.RegistrationListener? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var multicast: WifiManager.MulticastLock? = null
    private val found = linkedMapOf<String, Map<String, Any>>()
    private val present = mutableSetOf<String>()
    private val callbacks = mutableMapOf<String, NsdManager.ServiceInfoCallback>()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/lan_discovery").also { it.setMethodCallHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> try {
                val id = call.argument<String>("id") ?: ""
                val port = call.argument<Int>("port") ?: 0
                require(id.matches(Regex("[a-f0-9]{32}")) && port in 1024..65535)
                stop()
                ownId = id
                val generation = epoch
                val label = (Build.MANUFACTURER + " " + Build.MODEL).trim().take(60)
                if (Build.VERSION.SDK_INT < 33 || SdkExtensions.getExtensionVersion(33) < 7) {
                    val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    multicast = wifi.createMulticastLock("wenku-nearby-reading").apply { setReferenceCounted(false); acquire() }
                }
                val service = NsdServiceInfo().apply {
                    serviceName = "wenku-${id.take(12)}"; serviceType = type; setPort(port)
                    setAttribute("id", id); setAttribute("name", label); setAttribute("v", "1")
                }
                val registered = object : NsdManager.RegistrationListener {
                    override fun onServiceRegistered(info: NsdServiceInfo) = Unit
                    override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
                    override fun onRegistrationFailed(info: NsdServiceInfo, code: Int) { failure(generation) }
                    override fun onUnregistrationFailed(info: NsdServiceInfo, code: Int) = Unit
                }
                registration = registered
                manager.registerService(service, NsdManager.PROTOCOL_DNS_SD, registered)
                val listener = object : NsdManager.DiscoveryListener {
                    override fun onDiscoveryStarted(type: String) = Unit
                    override fun onDiscoveryStopped(type: String) = Unit
                    override fun onStartDiscoveryFailed(type: String, code: Int) { failure(generation) }
                    override fun onStopDiscoveryFailed(type: String, code: Int) = Unit
                    override fun onServiceFound(service: NsdServiceInfo) { main.post {
                        if (generation == epoch && service.serviceType.trimEnd('.') == type.trimEnd('.') &&
                            service.serviceName.startsWith("wenku-") && found.size + callbacks.size + queue.size < 64) {
                            present.add(service.serviceName)
                            resolve(service, generation)
                        }
                    } }
                    override fun onServiceLost(service: NsdServiceInfo) { main.post {
                        if (generation == epoch) {
                            present.remove(service.serviceName)
                            queue.removeAll { it.serviceName == service.serviceName }
                            if (Build.VERSION.SDK_INT >= 34) callbacks.remove(service.serviceName)?.let {
                                runCatching { manager.unregisterServiceInfoCallback(it) }
                            }
                            found.remove(service.serviceName); publish()
                        }
                    } }
                }
                discovery = listener
                manager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
                result.success(label)
            } catch (_: Exception) {
                stop(); result.error("LAN_DISCOVERY", "自动发现暂不可用，请检查本地网络权限", null)
            }
            "stop" -> { stop(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(service: NsdServiceInfo, generation: Int) {
        if (Build.VERSION.SDK_INT >= 34) {
            if (callbacks.containsKey(service.serviceName)) return
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(code: Int) { main.post { if (generation == epoch) callbacks.remove(service.serviceName) } }
                override fun onServiceUpdated(info: NsdServiceInfo) { main.post { accept(info, generation) } }
                override fun onServiceLost() { main.post { if (generation == epoch) { found.remove(service.serviceName); publish() } } }
                override fun onServiceInfoCallbackUnregistered() = Unit
            }
            callbacks[service.serviceName] = callback
            runCatching { manager.registerServiceInfoCallback(service, context.mainExecutor, callback) }
                .onFailure { callbacks.remove(service.serviceName) }
        } else {
            if (queue.none { it.serviceName == service.serviceName }) queue.add(service)
            resolveNext(generation)
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveNext(generation: Int) {
        if (resolving || queue.isEmpty() || generation != epoch) return
        resolving = true
        val service = queue.removeFirst()
        val listener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) { main.post {
                if (generation == epoch) { resolving = false; resolveNext(generation) }
            } }
            override fun onServiceResolved(info: NsdServiceInfo) { main.post {
                if (generation == epoch) { accept(info, generation); resolving = false; resolveNext(generation) }
            } }
        }
        runCatching { manager.resolveService(service, listener) }.onFailure { resolving = false; resolveNext(generation) }
    }

    @Suppress("DEPRECATION")
    private fun accept(info: NsdServiceInfo, generation: Int) {
        if (generation != epoch || !present.contains(info.serviceName)) return
        val id = info.attributes["id"]?.toString(Charsets.UTF_8) ?: return
        val label = info.attributes["name"]?.toString(Charsets.UTF_8) ?: return
        val version = info.attributes["v"]?.toString(Charsets.UTF_8)
        val address = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses.firstOrNull { it is Inet4Address } else info.host
        if (id == ownId || !id.matches(Regex("[a-f0-9]{32}")) || label.isBlank() || label.length > 64 || version != "1" ||
            address !is Inet4Address || !(address.isSiteLocalAddress || address.isLinkLocalAddress || address.isLoopbackAddress) || info.port !in 1024..65535) return
        val value = mapOf("id" to id, "name" to label, "host" to address.hostAddress!!, "port" to info.port)
        if (found[info.serviceName] != value) { found[info.serviceName] = value; publish() }
    }

    private fun publish() { channel?.invokeMethod("devices", found.values.toList()) }
    private fun failure(generation: Int) { main.post {
        if (generation == epoch) { stop(); channel?.invokeMethod("failure", null) }
    } }
    private fun stop() {
        epoch++
        discovery?.let { runCatching { manager.stopServiceDiscovery(it) } }; discovery = null
        registration?.let { runCatching { manager.unregisterService(it) } }; registration = null
        if (Build.VERSION.SDK_INT >= 34) callbacks.values.forEach { runCatching { manager.unregisterServiceInfoCallback(it) } }
        callbacks.clear(); queue.clear(); resolving = false; found.clear(); present.clear()
        multicast?.let { if (it.isHeld) it.release() }; multicast = null
        publish()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop(); channel?.setMethodCallHandler(null); channel = null
    }
}
