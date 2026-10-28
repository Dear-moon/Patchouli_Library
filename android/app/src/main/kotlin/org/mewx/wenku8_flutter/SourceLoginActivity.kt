package org.mewx.wenku8_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Build
import android.view.Gravity
import android.view.WindowManager
import android.webkit.WebView
import android.widget.LinearLayout
import android.widget.TextView

/** A web login owns the same serialized renderer slot/profile as source JS.
 * No DOM/password bridge is exposed; only that profile's cookies return. */
internal object SourceLoginSessions {
    class Session(val key: String, val request: SourceWebRequest, val cookie: String,
        val complete: (Map<String, Any?>?, String?) -> Unit) {
        var activity: SourceLoginActivity? = null
    }
    private val sessions = mutableMapOf<String, Session>()
    fun get(id: String) = sessions[id]
    fun finish(id: String, value: Map<String, Any?>?, error: String?) {
        val session = sessions.remove(id) ?: return
        session.activity?.finish()
        session.complete(value, error)
    }
    fun open(context: Context, id: String, key: String, request: SourceWebRequest, cookie: String,
        complete: (Map<String, Any?>?, String?) -> Unit): () -> Unit {
        sessions[id] = Session(key, request, cookie, complete)
        try {
            context.startActivity(Intent(context, SourceLoginActivity::class.java)
                .putExtra("session", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (failure: Exception) { sessions.remove(id); throw failure }
        return { sessions[id]?.activity?.cancelLogin() ?: finish(id, null, "书源网页登录已取消") }
    }
}

class SourceLoginActivity : Activity() {
    private var renderer: SourceWebRenderer? = null
    private var web: WebView? = null
    private var id = ""
    private var sheet: SourceBrowserSheet? = null
    private var backCallback: android.window.OnBackInvokedCallback? = null
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    override fun onCreate(savedInstanceState: Bundle?) {
        id = intent.getStringExtra("session").orEmpty()
        if (SourceLoginSessions.get(id)?.request?.browserSheet == true) setTheme(R.style.SourceBrowserHostTheme)
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        id = intent.getStringExtra("session").orEmpty()
        val session = SourceLoginSessions.get(id) ?: run { finish(); return }
        session.activity = this
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val paper = if (dark) Color.rgb(35, 37, 40) else Color.rgb(247, 246, 242)
        val ink = if (dark) Color.rgb(233, 233, 229) else Color.rgb(49, 52, 55)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(paper) }
        root.setOnApplyWindowInsetsListener { view, insets ->
            @Suppress("DEPRECATION")
            view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            insets
        }
        val toolbar = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(8))
        }
        fun control(label: String, action: () -> Unit) = TextView(this).apply {
            text = label; contentDescription = label; textSize = 14f; setTextColor(ink)
            gravity = Gravity.CENTER; setPadding(dp(14), dp(12), dp(14), dp(12))
            background = GradientDrawable().apply { cornerRadius = dp(22).toFloat(); setColor(if (dark) 0xff34373b.toInt() else Color.WHITE) }
            setOnClickListener { action() }
        }
        toolbar.addView(control("返回") { back() })
        toolbar.addView(TextView(this).apply {
            text = session.request.title?.takeIf { it.isNotBlank() } ?: "书源登录"; textSize = 17f; setTextColor(ink); gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(0, dp(48), 1f))
        toolbar.addView(control("保存并返回") { renderer?.done() })
        root.addView(toolbar)
        if (session.request.browserSheet) {
            sheet = SourceBrowserSheet(this, root, paper) { renderer?.done() }
        } else setContentView(root)
        renderer = SourceWebRenderer(this, session.key, session.request, session.cookie,
            complete = { value, error -> SourceLoginSessions.finish(id, value, error) },
            attach = { view -> web = view; root.addView(view, LinearLayout.LayoutParams(-1, 0, 1f)); sheet?.attach(view) },
            configure = { raw -> sheet?.update(raw) }).also { it.start() }
        sheet?.show(session.request.browserConfig)
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback = android.window.OnBackInvokedCallback { back() }.also {
                onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, it)
            }
        }
    }
    // This is an authentication flow, not a general browser: returning to the
    // app also transfers its session, even after several login redirects.
    private fun back() { renderer?.done() }
    internal fun cancelLogin() { renderer?.cancel() ?: SourceLoginSessions.finish(id, null, "书源网页登录已取消") }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() = back()
    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= 33) backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        backCallback = null
        cancelLogin(); renderer = null; web = null
        sheet?.dismiss(); sheet = null
        super.onDestroy()
    }
}
