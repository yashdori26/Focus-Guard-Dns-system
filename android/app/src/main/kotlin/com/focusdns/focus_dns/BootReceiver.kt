package com.focusdns.focus_dns

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService

/** Restarts protection after reboot / app update if it was running before. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (LocalDb.get(context).getKv("was_running", "0") != "1") return
        if (VpnService.prepare(context) != null) return // permission needs user action
        try {
            val i = Intent(context, FocusDnsVpnService::class.java).setAction(FocusDnsVpnService.ACTION_START)
            if (android.os.Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
        } catch (_: Exception) {}
    }
}
