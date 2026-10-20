package org.mewx.wenku8_flutter

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Source builds attach local platform capabilities only. */
internal fun attachWenkuEnginePlugins(engine: FlutterEngine) {
    if (!engine.plugins.has(WenkuHostPlugin::class.java)) engine.plugins.add(WenkuHostPlugin())
    if (!engine.plugins.has(SystemSpeechPlugin::class.java)) engine.plugins.add(SystemSpeechPlugin())
    if (!engine.plugins.has(AppUpdatePlugin::class.java)) engine.plugins.add(AppUpdatePlugin())
    if (!engine.plugins.has(CustomSpeechConfigPlugin::class.java)) engine.plugins.add(CustomSpeechConfigPlugin())
    if (!engine.plugins.has(CloudSourceConfigPlugin::class.java)) engine.plugins.add(CloudSourceConfigPlugin())
    if (!engine.plugins.has(ReaderControlsPlugin::class.java)) engine.plugins.add(ReaderControlsPlugin())
    if (!engine.plugins.has(NetworkStatusPlugin::class.java)) engine.plugins.add(NetworkStatusPlugin())
    if (!engine.plugins.has(FrameRatePlugin::class.java)) engine.plugins.add(FrameRatePlugin())
}

class WenkuHostPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    private var toolsChannel: MethodChannel? = null
    private var tools: LocalTools? = null
    private var documents: BookDocuments? = null
    private var documentsChannel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        toolsChannel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/local_tools").also {
            it.setMethodCallHandler { call, result ->
                val attached = tools
                if (attached != null) attached.onMethodCall(call, result)
                else result.error("NO_ACTIVITY", "This action needs the app page", null)
            }
        }
        documentsChannel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/book_documents").also {
            it.setMethodCallHandler { call, result ->
                val attached = documents
                if (attached != null) attached.onMethodCall(call, result)
                else result.error("NO_ACTIVITY", "请在文库页面执行文件操作", null)
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        toolsChannel?.setMethodCallHandler(null)
        documentsChannel?.setMethodCallHandler(null)
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        tools = LocalTools(binding.activity)
        documents = BookDocuments(binding.activity)
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }
    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        tools?.close(); tools = null
        documents?.close(); documents = null
    }
    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        (tools?.onActivityResult(requestCode, resultCode, data) ?: false) ||
            (documents?.onActivityResult(requestCode, resultCode, data) ?: false)
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean =
        documents?.onRequestPermissionsResult(requestCode) ?: false
}
