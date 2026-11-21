package com.focusdns.engine.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.focusdns.engine.session.SessionStateMachineEngine
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground DNS-only VpnService for Android.
 * Intercepts strictly port 53 UDP/TCP DNS queries on 10.254.1.2,
 * routing them to the local/remote DoH resolver without proxying bulk app traffic.
 */
class VpnEngine : VpnService() {

    companion object {
        const val TAG = "FocusVpnEngine"
        const val CHANNEL_ID = "focus_dns_engine_vpn"
        const val NOTIFICATION_ID = 24601

        const val DNS_V4_IP = "10.254.1.2"
        const val DNS_V6_IP = "fd00::1"
        const val MTU = 1500

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isDegraded: Boolean = false
            private set

        var onStateChangeListener: ((running: Boolean, degraded: Boolean) -> Unit)? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val isStopping = AtomicBoolean(false)
    private var workerThread: Thread? = null

    private var connectivityManager: ConnectivityManager? = null
    private var vpnConflictCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        startVpnTunnel()
        registerVpnConflictDetector()
        return START_STICKY
    }

    private fun startVpnTunnel() {
        if (isRunning) return
        isStopping.set(false)

        try {
            val builder = Builder().apply {
                setSession("FocusDNS Security Shield")
                setMtu(MTU)
                addAddress(DNS_V4_IP, 32)
                addDnsServer(DNS_V4_IP)
                addRoute(DNS_V4_IP, 32) // Strict DNS-only route: only intercept DNS IP!

                try {
                    addAddress(DNS_V6_IP, 128)
                    addDnsServer(DNS_V6_IP)
                    addRoute(DNS_V6_IP, 128)
                } catch (e: Exception) {
                    Log.w(TAG, "IPv6 tun configuration bypassed: ${e.message}")
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setMetered(false)
                }
                setBlocking(true)
            }

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface. Permission missing or revoked.")
                stopSelf()
                return
            }

            // Provide VPN socket protector to avoid infinite loop
            DnsTunInterceptor.rulesEngine?.vpnService = this

            isRunning = true
            isDegraded = false
            onStateChangeListener?.invoke(true, false)
            Log.i(TAG, "FocusDNS Tun0 established successfully on $DNS_V4_IP.")

            workerThread = Thread({ processTunPackets() }, "FocusVpnPacketPump").apply {
                priority = Thread.MAX_PRIORITY
                start()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN tunnel: ${e.message}", e)
            stopSelf()
        }
    }

    private fun processTunPackets() {
        val pfd = vpnInterface ?: return
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
        val buffer = ByteArray(MTU)

        while (!isStopping.get()) {
            try {
                val length = inputStream.read(buffer)
                if (length > 0) {
                    // Non-blocking DNS packet handling
                    DnsTunInterceptor.handleIncomingPacket(buffer, length, outputStream)
                }
            } catch (e: Exception) {
                if (!isStopping.get()) {
                    Log.w(TAG, "Packet pump read interrupted: ${e.message}")
                }
                break
            }
        }
    }

    private fun registerVpnConflictDetector() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val cm = connectivityManager ?: return

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()

            vpnConflictCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    val caps = cm.getNetworkCapabilities(network) ?: return
                    // If another VPN acquired network capabilities and our interface is detached
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && isRunning) {
                        Log.w(TAG, "Conflicting third-party VPN detected. Entering Graceful Degradation mode.")
                        isDegraded = true
                        onStateChangeListener?.invoke(true, true)
                    }
                }

                override fun onLost(network: Network) {
                    super.onLost(network)
                    if (isRunning && isDegraded) {
                        Log.i(TAG, "Competing VPN released. Restoring full DNS tunnel capability.")
                        isDegraded = false
                        onStateChangeListener?.invoke(true, false)
                    }
                }
            }

            cm.registerNetworkCallback(request, vpnConflictCallback!!)
        } catch (e: Exception) {
            Log.w(TAG, "Could not register VPN conflict callback: ${e.message}")
        }
    }

    private fun stopVpn() {
        isStopping.set(true)
        isRunning = false
        isDegraded = false

        try {
            vpnConflictCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (e: Exception) {}

        try {
            workerThread?.interrupt()
            workerThread = null
        } catch (e: Exception) {}

        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {}

        onStateChangeListener?.invoke(false, false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i(TAG, "FocusDNS VPN service stopped cleanly.")
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FocusDNS Security Shield",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors system DNS and enforces deep focus lockouts."
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FocusDNS Shield Active")
            .setContentText("Local-first DNS filter & anti-doomscroll lock engaged.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
