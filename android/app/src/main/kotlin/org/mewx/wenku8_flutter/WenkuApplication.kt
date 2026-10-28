package org.mewx.wenku8_flutter

import android.app.ActivityManager
import android.app.Application
import android.os.Build
import android.os.Process
import android.webkit.WebView
import com.ryanheise.audioservice.AudioServicePlugin

/** Attach app bridges even when Android creates the shared engine for a media service first. */
class WenkuApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val processName = if (Build.VERSION.SDK_INT >= 28) Application.getProcessName() else {
            val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            manager.runningAppProcesses.single { it.pid == Process.myPid() }.processName
        }
        if (processName != applicationInfo.processName) {
            if (Build.VERSION.SDK_INT >= 28) WebView.setDataDirectorySuffix("book_sources")
            return
        }
        // Older versions left interactive source logins as separate recent tasks.
        val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        manager.appTasks.filter {
            it.taskInfo.baseIntent.component?.className == SourceLoginActivity::class.java.name
        }.forEach { it.finishAndRemoveTask() }
        attachAppEnginePlugins(AudioServicePlugin.getFlutterEngine(this))
    }
}
