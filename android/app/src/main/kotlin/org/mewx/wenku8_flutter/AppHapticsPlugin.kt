package org.mewx.wenku8_flutter

import android.app.Activity
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.HapticFeedbackConstants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal object AppHapticPolicy {
    data class Pulse(val scale: Float, val delayMs: Int = 0)

    fun strength(value: String?): String? = when (value) {
        null, "standard" -> "standard"
        "light", "strong" -> value
        else -> null
    }

    /** Scale the transient, never lengthen a buzz or add repeats for strength. */
    fun pulses(cue: String, strength: String): List<Pulse> {
        val scale = if (strength == "light") .5f else 1f
        return when (cue) {
            "success" -> listOf(Pulse(scale * .65f), Pulse(scale, 55))
            "error" -> listOf(Pulse(scale), Pulse(scale * .8f, 65))
            else -> listOf(Pulse(scale))
        }
    }

    fun feedback(cue: String, sdk: Int): Int? = when (cue) {
        // Match Flutter selectionClick used by the 0.4.6 shelf. Recent segment
        // and handle presets vary substantially across OEMs; ordinary discrete
        // interactions share this brief click rather than a soft impact tail.
        "shelfStep", "detent", "selection", "pageTurn", "action" -> HapticFeedbackConstants.CLOCK_TICK
        "longPress" -> HapticFeedbackConstants.LONG_PRESS
        "boundary" -> HapticFeedbackConstants.CONTEXT_CLICK
        "success" -> if (sdk >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        "warning" -> if (sdk >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        "error" -> if (sdk >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.VIRTUAL_KEY
        else -> null
    }
}

/** Standard retains OEM presets; adjustable transients respect system touch settings. */
class AppHapticsPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var vibrator: Vibrator? = null
    private var supportedPrimitives: Set<Int>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8_flutter/haptics").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "play") { result.notImplemented(); return }
        val options = call.arguments as? Map<*, *>
        val cue = (options?.get("cue") ?: call.arguments) as? String ?: ""
        val strength = AppHapticPolicy.strength(options?.get("strength") as? String)
        if (strength == null) { result.error("BAD_STRENGTH", "Unknown haptic strength", null); return }
        val feedback = AppHapticPolicy.feedback(cue, Build.VERSION.SDK_INT)
        if (feedback == null) { result.error("BAD_CUE", "Unknown haptic cue", null); return }
        val owner = activity
        val view = owner?.window?.decorView
        if (owner == null || owner.isFinishing || view == null || !view.hasWindowFocus() ||
            !view.isHapticFeedbackEnabled) {
            result.success(false); return
        }
        if (strength == "standard" || Build.VERSION.SDK_INT < 31) {
            result.success(view.performHapticFeedback(feedback)); return
        }
        try {
            val motor = vibrator ?: owner.getSystemService(VibratorManager::class.java)
                ?.defaultVibrator?.also { vibrator = it }
            val supported = supportedPrimitives ?: setOf(
                VibrationEffect.Composition.PRIMITIVE_TICK,
                VibrationEffect.Composition.PRIMITIVE_CLICK,
            ).filter { motor?.areAllPrimitivesSupported(it) == true }
                .toSet().also { supportedPrimitives = it }
            val tick = VibrationEffect.Composition.PRIMITIVE_TICK
            val click = VibrationEffect.Composition.PRIMITIVE_CLICK
            val primitive = when {
                cue in setOf("shelfStep", "selection", "detent") && tick in supported -> tick
                click in supported -> click
                else -> null
            }
            if (motor == null || primitive == null) {
                // Choose the fallback before playback; false must never cause a second pulse.
                result.success(view.performHapticFeedback(feedback)); return
            }
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < 33 && Settings.System.getInt(
                    owner.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0) {
                result.success(false); return
            }
            val composition = VibrationEffect.startComposition()
            for (pulse in AppHapticPolicy.pulses(cue, strength)) {
                composition.addPrimitive(primitive, pulse.scale, pulse.delayMs)
            }
            val effect = composition.compose()
            if (Build.VERSION.SDK_INT >= 33) {
                motor.vibrate(effect, VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_TOUCH).build())
            } else {
                @Suppress("DEPRECATION")
                motor.vibrate(effect, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            }
            result.success(true)
        } catch (_: RuntimeException) {
            // Optional feedback must not interrupt the accepted action or double-play.
            result.success(false)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { detachActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { detachActivity() }
    private fun detachActivity() {
        activity = null
        vibrator = null
        supportedPrimitives = null
    }
}
