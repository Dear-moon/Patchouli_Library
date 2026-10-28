package org.mewx.wenku8_flutter

import android.media.audiofx.AudioEffect
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Optional per-player gain. The platform enhancer compresses over-range samples. */
class ListeningEnhancementPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var effect: LoudnessEnhancer? = null
    private var sessionId: Int? = null
    private var revision = 0
    private var requested = false
    private var supported = false
    private var failure: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/listening_enhancement")
        channel.setMethodCallHandler(this)
        supported = try {
            Build.VERSION.SDK_INT >= 19 && AudioEffect.queryEffects()?.any {
                it.type == AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER
            } == true
        } catch (_: Exception) { false }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        release()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(state())
            "release" -> { requested = false; failure = null; release(); result.success(null) }
            "configure" -> {
                revision = call.argument<Number>("revision")?.toInt() ?: 0
                requested = call.argument<Boolean>("enabled") == true
                failure = null
                val target = call.argument<Number>("gainDb")?.toDouble()
                val nextSession = call.argument<Number>("sessionId")?.toInt()?.takeIf { it > 0 }
                if (!requested || !supported || nextSession == null) {
                    release()
                } else if (target !in listOf(2.0, 4.0, 6.0)) {
                    release()
                    failure = "声音增强档位无效"
                } else {
                    try {
                        if (sessionId != nextSession) {
                            release()
                            val attached = LoudnessEnhancer(nextSession)
                            effect = attached
                            sessionId = nextSession
                            attached.setControlStatusListener { current, _ -> changed(current) }
                            attached.setEnableStatusListener { current, _ -> changed(current) }
                        }
                        val attached = checkNotNull(effect)
                        check(attached.hasControl()) { "声音增强控制权暂不可用" }
                        attached.setTargetGain((checkNotNull(target) * 100).toInt())
                        check(attached.setEnabled(true) == AudioEffect.SUCCESS) { "声音增强未能启用" }
                    } catch (_: Exception) {
                        release()
                        failure = "声音增强暂不可用，普通播放不受影响"
                    }
                }
                result.success(state())
            }
            else -> result.notImplemented()
        }
    }

    private fun changed(current: AudioEffect) {
        if (effect === current) channel.invokeMethod("changed", state())
    }

    /** Read the actual effect, never infer an enabled state from a successful call. */
    private fun state(): Map<String, Any?> {
        var enabled = false
        var control = false
        var gain = 0.0
        try {
            effect?.let {
                enabled = it.enabled
                control = it.hasControl()
                gain = it.targetGain.toDouble() / 100.0
            }
        } catch (_: Exception) {
            release()
            enabled = false
            control = false
            gain = 0.0
            failure = "声音增强已失效，普通播放不受影响"
        }
        val phase = when {
            !supported -> "unavailable"
            failure != null -> "failed"
            !requested -> "off"
            effect == null -> "waitingSession"
            enabled && control -> "active"
            else -> "failed"
        }
        val reason = when {
            !supported -> "当前设备不支持声音增强"
            failure != null -> failure
            effect != null && !control -> "声音增强控制权暂不可用，普通播放不受影响"
            requested && effect != null && !enabled -> "声音增强未启用，普通播放不受影响"
            else -> null
        }
        return mapOf("supported" to supported, "phase" to phase, "enabled" to enabled,
            "hasControl" to control, "gainDb" to gain, "sessionId" to sessionId,
            "reason" to reason, "revision" to revision)
    }

    private fun release() {
        val previous = effect
        effect = null
        sessionId = null
        try { previous?.release() } catch (_: Exception) { /* Playback owns its own session. */ }
    }
}
