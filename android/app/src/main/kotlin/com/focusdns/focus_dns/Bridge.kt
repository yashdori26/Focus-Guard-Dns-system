package com.focusdns.focus_dns

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Lets native services push events to Dart (only while the Flutter engine is alive). */
object Bridge {
    @Volatile var vpnChannel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(method: String, args: Map<String, Any?>) {
        val ch = vpnChannel ?: return
        main.post { try { ch.invokeMethod(method, args) } catch (_: Exception) {} }
    }
}
