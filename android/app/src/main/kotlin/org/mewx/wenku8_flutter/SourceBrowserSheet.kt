/* Novel-only host adapter for Legado BottomWebViewDialog.Config (GPL-3.0),
 * 3046111c1718e7b67c2ad468e54edf295ec05820. Existing app pages are unchanged. */
package org.mewx.wenku8_flutter

import android.app.Activity
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.WebView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog

internal class SourceBrowserSheet(private val activity: Activity, content: View, private val paper: Int, done: () -> Unit) {
    private val dialog = BottomSheetDialog(activity, com.google.android.material.R.style.Theme_Material3_DayNight_BottomSheetDialog)
    private var current = linkedMapOf<String, Any?>()
    private var web: WebView? = null
    init {
        dialog.setContentView(content)
        dialog.setOnDismissListener { done() }
    }
    fun show(raw: String?) { dialog.show(); update(raw); }
    fun attach(view: WebView) { web = view; apply() }
    fun update(raw: String?) {
        if (!raw.isNullOrBlank()) {
            require(raw.length <= 64 * 1024) { "书源浏览器配置过大" }
            val parsed = org.mewx.wenku8_flutter.legado.js.SourceGson.gson.fromJson(raw, Map::class.java)
            require(parsed != null) { "书源浏览器配置必须为 JSON 对象" }
            for ((key, value) in parsed) current[key.toString()] = value
        }
        apply()
    }
    fun dismiss() = dialog.dismiss()
    private fun apply() {
        fun number(key: String) = current[key] as? Number
        fun flag(key: String) = current[key] as? Boolean
        val metrics = activity.resources.displayMetrics
        val view = dialog.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet) ?: return
        val behavior = dialog.behavior
        fun height(pixels: String, percentage: String): Int? = number(percentage)?.toFloat()?.takeIf { it > 0 && it <= 1 }
            ?.let { (metrics.heightPixels * it).toInt().coerceAtLeast(1) } ?: number(pixels)?.toInt()?.takeIf { it > 0 }
        val collapsed = height("dialogHeight", "heightPercentage")
        val expanded = height("expandedHeight", "expandedHeightPercentage")?.takeIf { collapsed != null && it > collapsed }
        val layoutHeight = expanded ?: collapsed ?: number("dialogHeight")?.toInt()?.takeIf { it == -1 || it == -2 } ?: -1
        view.layoutParams = view.layoutParams.apply { height = layoutHeight }
        behavior.isHideable = flag("isHideable") ?: true
        behavior.skipCollapsed = flag("skipCollapsed") ?: (collapsed != null && expanded == null)
        behavior.isFitToContents = flag("setFitToContents") ?: true
        behavior.isDraggable = flag("isDraggable") ?: true
        behavior.isDraggableOnNestedScroll = flag("isDraggableOnNestedScroll") ?: (expanded != null || collapsed == null)
        behavior.isGestureInsetBottomIgnored = flag("isGestureInsetBottomIgnored") ?: false
        number("setHalfExpandedRatio")?.toFloat()?.takeIf { it > 0 && it < 1 }?.let { behavior.halfExpandedRatio = it }
        number("setExpandedOffset")?.toInt()?.coerceAtLeast(0)?.let { behavior.expandedOffset = it }
        number("significantVelocityThreshold")?.toInt()?.coerceAtLeast(1)?.let { behavior.significantVelocityThreshold = it }
        number("hideFriction")?.toFloat()?.takeIf { it > 0 && it <= 1 }?.let { behavior.hideFriction = it }
        behavior.peekHeight = number("peekHeight")?.toInt() ?: collapsed ?: BottomSheetBehavior.PEEK_HEIGHT_AUTO
        behavior.maxHeight = number("maxHeight")?.toInt()?.takeIf { it > 0 } ?: expanded ?: collapsed ?: -1
        behavior.maxWidth = number("maxWidth")?.toInt()?.takeIf { it > 0 } ?: number("widthPercentage")?.toFloat()?.takeIf { it > 0 && it <= 1 }
            ?.let { (metrics.widthPixels * it).toInt().coerceAtLeast(1) } ?: -1
        flag("setUpdateImportantForAccessibilityOnSiblings")?.let { behavior.setUpdateImportantForAccessibilityOnSiblings(it) }
        val state = number("state")?.toInt() ?: if (expanded != null) BottomSheetBehavior.STATE_COLLAPSED else BottomSheetBehavior.STATE_EXPANDED
        if (state in 3..6 && (state != 5 || behavior.isHideable)) behavior.state = state
        val radius = (number("expandedCornersRadius")?.toFloat() ?: 28f).coerceIn(0f, 128f) * metrics.density
        view.background = GradientDrawable().apply { setColor(paper); cornerRadii = floatArrayOf(radius,radius,radius,radius,0f,0f,0f,0f) }
        view.clipToOutline = true
        dialog.window?.apply {
            setDimAmount(number("backgroundDimAmount")?.toFloat()?.coerceIn(0f,1f) ?: .28f)
            if (flag("shouldDimBackground") == false) clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            else addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            if (flag("hardwareAccelerated") != false) addFlags(WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED)
        }
        dialog.setCanceledOnTouchOutside(flag("dismissOnTouchOutside") ?: true)
        web?.let { browser ->
            number("webViewInitialScale")?.toInt()?.takeIf { it in 0..1000 }?.let { browser.setInitialScale(it) }
            number("webViewCacheMode")?.toInt()?.takeIf { it in -1..3 }?.let { browser.settings.cacheMode = it }
            browser.isNestedScrollingEnabled = flag("isNestedScrollingEnabled") ?: true
        }
    }
}
