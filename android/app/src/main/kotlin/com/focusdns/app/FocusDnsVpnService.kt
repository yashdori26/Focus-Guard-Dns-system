package com.focusdns.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionHandler
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class FocusDnsVpnService : VpnService() {

    companion object {
        const val TAG = "FocusDnsVpn"
        const val CHANNEL_ID = "focus_dns_vpn_channel"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.focusdns.app.START_VPN"
        const val ACTION_STOP = "com.focusdns.app.STOP_VPN"

        const val EXTRA_SERVER_URL = "server_url"
        const val EXTRA_PROFILE_ID = "profile_id"
        const val EXTRA_API_TOKEN = "api_token"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isStarting: Boolean = false
            private set

        @Volatile
        var isBackendReachable: Boolean = true
            private set

        var onStateChangeListener: ((Boolean, Boolean) -> Unit)? = null
    }

    private class DnsQueryTask(
        val queryBytes: ByteArray,
        val clientIp: ByteArray,
        val clientPort: Int,
        val dnsServerIp: ByteArray,
        val isIpv6: Boolean,
        val outputStream: FileOutputStream,
        private val runnable: Runnable
    ) : Runnable {
        override fun run() = runnable.run()
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var readThread: Thread? = null
    private val isRunningFlag = AtomicBoolean(false)
    private val ipIdCounter = AtomicInteger(1000)

    private lateinit var threadPool: ThreadPoolExecutor
    private val outputLock = Any()

    private var serverUrl: String = "http://127.0.0.1:8080/dns-query"
    private var profileId: String = "a1b2c3"
    private var apiToken: String = ""

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // Fast-fail rejection handler: Return SERVFAIL (RCODE 2) on queue saturation using PacketUtils
        val rejectionHandler = RejectedExecutionHandler { r, _ ->
            if (r is DnsQueryTask) {
                Log.w(TAG, "DNS query worker pool full! Returning fast-fail SERVFAIL (RCODE 2)")
                val servfailBytes = PacketUtils.craftServfailReply(r.queryBytes)
                if (servfailBytes != null) {
                    val replyPacket = if (!r.isIpv6) {
                        PacketUtils.craftUdpReplyPacketIpv4(
                            clientIp = r.clientIp,
                            clientPort = r.clientPort,
                            dnsServerIp = r.dnsServerIp,
                            dnsReply = servfailBytes,
                            ipId = (ipIdCounter.incrementAndGet() and 0xFFFF).toShort()
                        )
                    } else {
                        PacketUtils.craftUdpReplyPacketIpv6(
                            clientIp = r.clientIp,
                            clientPort = r.clientPort,
                            dnsServerIp = r.dnsServerIp,
                            dnsReply = servfailBytes
                        )
                    }
                    synchronized(outputLock) {
                        try {
                            r.outputStream.write(replyPacket)
                            r.outputStream.flush()
                        } catch (e: Exception) {
                            Log.d(TAG, "Failed writing rejected SERVFAIL: ${e.message}")
                        }
                    }
                }
            }
        }

        // Bounded thread pool for concurrent DNS resolution (64 queue slots to strictly bound latency)
        threadPool = ThreadPoolExecutor(
            4, 16, 60L, TimeUnit.SECONDS,
            LinkedBlockingQueue(64),
            rejectionHandler
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // System restarted service after memory reclaim
            val wasRunning = RulesStore.getWasRunning(this)
            if (wasRunning) {
                serverUrl = RulesStore.getServerUrl(this)
                profileId = RulesStore.getProfileId(this)
                apiToken = RulesStore.getApiToken(this)
                startVpn()
                return START_STICKY
            }
            return START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_START -> {
                serverUrl = intent.getStringExtra(EXTRA_SERVER_URL) ?: "http://127.0.0.1:8080/dns-query"
                profileId = intent.getStringExtra(EXTRA_PROFILE_ID) ?: "a1b2c3"
                apiToken = intent.getStringExtra(EXTRA_API_TOKEN) ?: ""

                RulesStore.setServerUrl(this, serverUrl)
                RulesStore.setProfileId(this, profileId)
                RulesStore.setApiToken(this, apiToken)
                RulesStore.setWasRunning(this, true)
                RulesStore.setVpnLost(this, false)

                startVpn()
            }
            ACTION_STOP -> {
                RulesStore.setWasRunning(this, false)
                stopVpn()
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunningFlag.get() || isStarting) return
        isStarting = true

        try {
            val notification = buildForegroundNotification(isHealthy = true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            val builder = Builder()
            builder.setSession("FocusDNS")
            builder.setMtu(1500)

            // IPv4: Virtual interface and virtual DNS IP
            builder.addAddress("10.254.1.1", 32)
            builder.addDnsServer("10.254.1.2")
            // CRITICAL: Route ONLY 10.254.1.2/32 so normal web/app traffic bypasses the VPN completely!
            builder.addRoute("10.254.1.2", 32)

            // IPv6: Virtual interface and DNS to capture and prevent IPv6 DNS leak/bypass
            try {
                builder.addAddress("fd00::1", 128)
                builder.addDnsServer("fd00::2")
                builder.addRoute("fd00::2", 128)
            } catch (e: Exception) {
                Log.d(TAG, "IPv6 address assignment omitted: ${e.message}")
            }

            builder.setBlocking(true)

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                isStarting = false
                stopSelf()
                return
            }

            isRunningFlag.set(true)
            isRunning = true
            isStarting = false
            isBackendReachable = true
            notifyStateChange()

            readThread = Thread(TunReadRunnable(vpnInterface!!), "FocusDnsTunReader").apply {
                start()
            }
            RulesStore.setVpnLost(this, false)
            Log.i(TAG, "FocusDNS Local DNS VPN active (Concurrency enabled, fail-closed protection).")
        } catch (e: Exception) {
            isStarting = false
            Log.e(TAG, "Error starting VPN: ${e.message}", e)
            stopVpn()
        }
    }

    private fun stopVpn() {
        isStarting = false
        isRunningFlag.set(false)
        isRunning = false

        try {
            readThread?.interrupt()
            readThread = null
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface: ${e.message}")
        }

        stopForeground(true)
        stopSelf()
        notifyStateChange()
        Log.i(TAG, "FocusDNS Local DNS VPN stopped.")
    }

    override fun onRevoke() {
        Log.w(TAG, "FocusDNS VPN revoked by Android system settings.")
        RulesStore.setVpnLost(this, true)
        RulesStore.setWasRunning(this, false)
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn()
        threadPool.shutdownNow()
        super.onDestroy()
    }

    private fun notifyStateChange() {
        onStateChangeListener?.invoke(isRunning, isBackendReachable)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FocusDNS VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows notification when FocusDNS DNS-only interception is active."
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(isHealthy: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val title = when {
            isHealthy -> "FocusDNS Active"
            else -> "⚠️ FocusDNS Backend Unreachable"
        }
        val text = when {
            isHealthy -> "DNS lookups filtered via FocusDNS (Profile: $profileId)"
            else -> "Backend disconnected — Protected / Fail-closed mode active"
        }

        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(isHealthy: Boolean) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildForegroundNotification(isHealthy))
    }

    // --- Non-Blocking TUN Read Loop ---
    private inner class TunReadRunnable(private val pfd: ParcelFileDescriptor) : Runnable {
        override fun run() {
            val inputStream = FileInputStream(pfd.fileDescriptor)
            val outputStream = FileOutputStream(pfd.fileDescriptor)
            val readBuf = ByteArray(32767)

            while (isRunningFlag.get() && !Thread.currentThread().isInterrupted) {
                try {
                    val length = inputStream.read(readBuf)
                    if (length < 28) continue // Minimum IPv4 + UDP length

                    // Copy exact packet slice for concurrent worker
                    val packetCopy = readBuf.copyOf(length)

                    val firstByte = packetCopy[0].toInt() and 0xFF
                    val version = firstByte shr 4

                    if (version == 4) {
                        handleIpv4Packet(packetCopy, length, outputStream)
                    } else if (version == 6) {
                        handleIpv6Packet(packetCopy, length, outputStream)
                    }
                } catch (e: Exception) {
                    if (!isRunningFlag.get()) break
                    Log.d(TAG, "TUN read error: ${e.message}")
                }
            }
        }
    }

    private fun handleIpv4Packet(packet: ByteArray, length: Int, outputStream: FileOutputStream) {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < 20 || ihl > length) return

        val protocol = packet[9].toInt() and 0xFF

        // Handle UDP (17) on Port 53
        if (protocol == 17 && length >= ihl + 8) {
            val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
            val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
            val udpLen = ((packet[ihl + 4].toInt() and 0xFF) shl 8) or (packet[ihl + 5].toInt() and 0xFF)

            if (dstPort == 53 && udpLen >= 8 && ihl + udpLen <= length) {
                val dnsOffset = ihl + 8
                val dnsLength = udpLen - 8
                val dnsPayload = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
                val clientIp = packet.copyOfRange(12, 16)
                val dnsServerIp = packet.copyOfRange(16, 20)

                // Dispatch to thread pool so read loop never blocks (DnsQueryTask enables SERVFAIL on saturation)
                threadPool.execute(
                    DnsQueryTask(
                        queryBytes = dnsPayload,
                        clientIp = clientIp,
                        clientPort = srcPort,
                        dnsServerIp = dnsServerIp,
                        isIpv6 = false,
                        outputStream = outputStream,
                        runnable = Runnable {
                            processDnsQuery(
                                queryBytes = dnsPayload,
                                clientIp = clientIp,
                                clientPort = srcPort,
                                dnsServerIp = dnsServerIp,
                                isIpv6 = false,
                                outputStream = outputStream
                            )
                        }
                    )
                )
            }
        }
        // Handle TCP (6) on Port 53: Reset connection to fast-fail so client uses UDP
        else if (protocol == 6 && length >= ihl + 20) {
            val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
            if (dstPort == 53) {
                val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                val clientIp = packet.copyOfRange(12, 16)
                val serverIp = packet.copyOfRange(16, 20)
                val seqNum = ByteBuffer.wrap(packet, ihl + 4, 4).int

                threadPool.execute {
                    sendTcpRstIpv4(clientIp, srcPort, serverIp, 53, seqNum, outputStream)
                }
            }
        }
    }

    private fun handleIpv6Packet(packet: ByteArray, length: Int, outputStream: FileOutputStream) {
        if (length < 48) return // 40 bytes IPv6 + 8 bytes UDP
        val nextHeader = packet[6].toInt() and 0xFF

        if (nextHeader == 17) { // UDP
            val srcPort = ((packet[40].toInt() and 0xFF) shl 8) or (packet[41].toInt() and 0xFF)
            val dstPort = ((packet[42].toInt() and 0xFF) shl 8) or (packet[43].toInt() and 0xFF)
            val udpLen = ((packet[44].toInt() and 0xFF) shl 8) or (packet[45].toInt() and 0xFF)

            if (dstPort == 53 && udpLen >= 8 && 40 + udpLen <= length) {
                val dnsPayload = packet.copyOfRange(48, 48 + udpLen - 8)
                val clientIp = packet.copyOfRange(8, 24)
                val dnsServerIp = packet.copyOfRange(24, 40)

                threadPool.execute(
                    DnsQueryTask(
                        queryBytes = dnsPayload,
                        clientIp = clientIp,
                        clientPort = srcPort,
                        dnsServerIp = dnsServerIp,
                        isIpv6 = true,
                        outputStream = outputStream,
                        runnable = Runnable {
                            processDnsQuery(
                                queryBytes = dnsPayload,
                                clientIp = clientIp,
                                clientPort = srcPort,
                                dnsServerIp = dnsServerIp,
                                isIpv6 = true,
                                outputStream = outputStream
                            )
                        }
                    )
                )
            }
        }
    }

    private fun processDnsQuery(
        queryBytes: ByteArray,
        clientIp: ByteArray,
        clientPort: Int,
        dnsServerIp: ByteArray,
        isIpv6: Boolean,
        outputStream: FileOutputStream
    ) {
        if (!isRunningFlag.get()) return

        val dnsResponse = resolveDnsWire(queryBytes)
        if (dnsResponse != null && isRunningFlag.get()) {
            val replyPacket = if (!isIpv6) {
                PacketUtils.craftUdpReplyPacketIpv4(
                    clientIp = clientIp,
                    clientPort = clientPort,
                    dnsServerIp = dnsServerIp,
                    dnsReply = dnsResponse,
                    ipId = (ipIdCounter.incrementAndGet() and 0xFFFF).toShort()
                )
            } else {
                PacketUtils.craftUdpReplyPacketIpv6(
                    clientIp = clientIp,
                    clientPort = clientPort,
                    dnsServerIp = dnsServerIp,
                    dnsReply = dnsResponse
                )
            }

            synchronized(outputLock) {
                try {
                    outputStream.write(replyPacket)
                    outputStream.flush()
                } catch (e: Exception) {
                    Log.d(TAG, "Write packet failed: ${e.message}")
                }
            }
        }
    }

    /**
     * Resolves DNS query via FocusDNS DoH endpoint.
     * Enforces FAIL-CLOSED behavior: if backend is unreachable, generates SERVFAIL (RCODE 2)
     * so queries fail immediately rather than silently leaking unfiltered.
     */
    private fun resolveDnsWire(queryBytes: ByteArray): ByteArray? {
        val targetUrl = if (serverUrl.contains("?")) {
            "$serverUrl&profile_id=$profileId"
        } else {
            "$serverUrl?profile_id=$profileId"
        }

        try {
            val url = URL(targetUrl)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 1500
                readTimeout = 2000
                setRequestProperty("Content-Type", "application/dns-message")
                setRequestProperty("Accept", "application/dns-message")
                if (apiToken.isNotEmpty()) {
                    setRequestProperty("X-Api-Key", apiToken)
                    setRequestProperty("Authorization", "Bearer $apiToken")
                }
            }

            conn.outputStream.use { os ->
                os.write(queryBytes)
                os.flush()
            }

            if (conn.responseCode == 200) {
                val reply = conn.inputStream.use { it.readBytes() }
                if (!isBackendReachable) {
                    isBackendReachable = true
                    updateNotification(isHealthy = true)
                    notifyStateChange()
                }
                return reply
            } else {
                Log.w(TAG, "DoH returned non-200 code: ${conn.responseCode}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "FocusDNS backend unreachable: ${e.message}")
            if (isBackendReachable) {
                isBackendReachable = false
                updateNotification(isHealthy = false)
                notifyStateChange()
            }
        }

        // FAIL-CLOSED DEFENSE: Generate SERVFAIL (RCODE 2) so blocked apps cannot leak
        return PacketUtils.craftServfailReply(queryBytes)
    }

    private fun sendTcpRstIpv4(
        clientIp: ByteArray,
        clientPort: Int,
        serverIp: ByteArray,
        serverPort: Int,
        ackNum: Int,
        outputStream: FileOutputStream
    ) {
        val rstPacket = PacketUtils.craftTcpRstIpv4(
            clientIp = clientIp,
            clientPort = clientPort,
            serverIp = serverIp,
            serverPort = serverPort,
            ackNum = ackNum,
            ipId = (ipIdCounter.incrementAndGet() and 0xFFFF).toShort()
        )

        synchronized(outputLock) {
            try {
                outputStream.write(rstPacket)
                outputStream.flush()
            } catch (e: Exception) {
                Log.d(TAG, "Write TCP RST failed: ${e.message}")
            }
        }
    }
}
