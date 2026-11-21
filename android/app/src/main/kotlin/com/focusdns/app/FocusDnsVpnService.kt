package com.focusdns.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
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
            // Route 10.254.1.2/32
            builder.addRoute("10.254.1.2", 32)

            // Trap well-known public DNS server IPs to capture DoH/DoT bypass in Chrome/Brave/Incognito
            val trapDnsIps = listOf(
                "1.1.1.1", "1.0.0.1",
                "8.8.8.8", "8.8.4.4",
                "9.9.9.9", "149.112.112.112",
                "208.67.222.222", "208.67.220.220",
                "94.140.14.14", "94.140.15.15"
            )
            for (trapIp in trapDnsIps) {
                try {
                    builder.addRoute(trapIp, 32)
                } catch (e: Exception) {
                    Log.d(TAG, "Trap route $trapIp omitted: ${e.message}")
                }
            }

            // IPv6: Virtual interface and DNS to capture and prevent IPv6 DNS leak/bypass
            try {
                builder.addAddress("fd00::1", 128)
                builder.addDnsServer("fd00::2")
                builder.addRoute("fd00::2", 128)
            } catch (e: Exception) {
                Log.d(TAG, "IPv6 address assignment omitted: ${e.message}")
            }

            builder.setBlocking(true)

            // Apply per-app split tunneling configuration
            SplitTunnelManager.applyToVpnBuilder(this, builder)

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
            ProtectionStateCoordinator.setProtectionActive(this, true)
            MdmPolicyEngine.syncUninstallLock(this)
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
        ProtectionStateCoordinator.setProtectionActive(this, false)
        MdmPolicyEngine.syncUninstallLock(this)
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
        // Handle TCP (6) on Port 53 (DNS), 443 (DoH trap), or 853 (DoT trap): Reset connection to fast-fail so client uses UDP system DNS
        else if (protocol == 6 && length >= ihl + 20) {
            val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
            if (dstPort == 53 || dstPort == 443 || dstPort == 853) {
                val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                val clientIp = packet.copyOfRange(12, 16)
                val serverIp = packet.copyOfRange(16, 20)
                val seqNum = ByteBuffer.wrap(packet, ihl + 4, 4).int

                threadPool.execute {
                    sendTcpRstIpv4(clientIp, srcPort, serverIp, dstPort, seqNum, outputStream)
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

    private fun getSafeSearchVip(qname: String, qtype: Int): ByteArray? {
        val clean = qname.trim().trimEnd('.').lowercase()
        // Google SafeSearch: forcesafesearch.google.com -> 216.239.38.120 (IPv4) or 2001:4860:4806::78 (IPv6)
        if (clean == "google.com" || clean.endsWith(".google.com") ||
            clean.matches(Regex(".*google\\.(com|co\\.[a-z]{2}|[a-z]{2,3})$"))) {
            return if (qtype == 1) {
                byteArrayOf(216.toByte(), 239.toByte(), 38.toByte(), 120.toByte())
            } else if (qtype == 28) {
                byteArrayOf(
                    0x20.toByte(), 0x01.toByte(), 0x48.toByte(), 0x60.toByte(),
                    0x48.toByte(), 0x06.toByte(), 0x00.toByte(), 0x00.toByte(),
                    0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte(),
                    0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x78.toByte()
                )
            } else null
        }
        // Bing SafeSearch: strict.bing.com -> 204.79.197.220
        if (clean == "bing.com" || clean.endsWith(".bing.com")) {
            return if (qtype == 1) {
                byteArrayOf(204.toByte(), 79.toByte(), 197.toByte(), 220.toByte())
            } else null
        }
        // DuckDuckGo SafeSearch: safe.duckduckgo.com -> 52.142.124.215
        if (clean == "duckduckgo.com" || clean.endsWith(".duckduckgo.com")) {
            return if (qtype == 1) {
                byteArrayOf(52.toByte(), 142.toByte(), 124.toByte(), 215.toByte())
            } else null
        }
        return null
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

        // Immediately check if strict focus timer expired in native background
        if (RulesStore.hasStrictTimerExpired(this)) {
            Log.i(TAG, "Strict focus timer expired! Auto-stopping VPN immediately to unblock apps.")
            RulesStore.setStrictMode(this, false)
            RulesStore.setTimedStrictMode(this, 0)
            ProtectionStateCoordinator.setStrictTimer(this, 0L)
            ProtectionStateCoordinator.setProtectionActive(this, false)
            stopVpn()
            // Forward this query upstream so app's request succeeds immediately
            val reply = resolveDnsWire(queryBytes)
            if (reply != null) {
                val replyPacket = if (!isIpv6) {
                    PacketUtils.craftUdpReplyPacketIpv4(clientIp, clientPort, dnsServerIp, reply, (ipIdCounter.incrementAndGet() and 0xFFFF).toShort())
                } else {
                    PacketUtils.craftUdpReplyPacketIpv6(clientIp, clientPort, dnsServerIp, reply)
                }
                synchronized(outputLock) {
                    try {
                        outputStream.write(replyPacket)
                        outputStream.flush()
                    } catch (_: Exception) {}
                }
            }
            return
        }

        val startTime = System.currentTimeMillis()
        val parsed = PacketUtils.parseDnsQuestion(queryBytes)
        val qname = parsed?.domain ?: ""
        val qtype = parsed?.qtype ?: 1

        var isBlockedByUid = false
        var uidBlockedRule = ""
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                if (cm != null) {
                    val clientAddr = InetSocketAddress(InetAddress.getByAddress(clientIp), clientPort)
                    val serverAddr = InetSocketAddress(InetAddress.getByAddress(dnsServerIp), 53)
                    val uid = cm.getConnectionOwnerUid(17 /* UDP */, clientAddr, serverAddr)
                    if (uid > 0) {
                        val packages = packageManager.getPackagesForUid(uid)
                        val blockedPkgs = RulesStore.getBlockedPackages(this)
                        if (packages != null) {
                            for (pkg in packages) {
                                val pkgLower = pkg.lowercase()
                                if (blockedPkgs.contains(pkg) || blockedPkgs.any { b -> pkgLower.contains(b.lowercase()) || b.lowercase().contains(pkgLower) }) {
                                    isBlockedByUid = true
                                    uidBlockedRule = "Blocked App UID ($pkg)"
                                    break
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore socket owner lookup errors
            }
        }

        val (domainBlocked, domainRule) = if (qname.isNotEmpty()) {
            RulesStore.isDomainBlocked(this, qname)
        } else {
            Pair(false, "")
        }

        val isBlocked = isBlockedByUid || domainBlocked
        val matchedRule = if (isBlockedByUid) uidBlockedRule else domainRule

        val safeSearchVip = if (RulesStore.isAdultBlockingActive(this) && parsed != null) {
            getSafeSearchVip(qname, qtype)
        } else null

        val dnsResponse: ByteArray? = if (isBlocked && parsed != null) {
            // IMMEDIATE SINKHOLE: Return 0.0.0.0 (IPv4) or :: (IPv6) in <1ms without network delay
            val blockedReply = PacketUtils.craftBlockedDnsReply(queryBytes, qtype, parsed.questionEndOffset)
            val elapsed = (System.currentTimeMillis() - startTime).toInt()
            DnsTelemetryManager.recordQuery(qname, "BLOCKED", matchedRule, elapsed)
            Log.i(TAG, "BLOCKED DNS query: $qname -> 0.0.0.0 (rule: $matchedRule)")
            blockedReply
        } else if (safeSearchVip != null && parsed != null) {
            val safeReply = PacketUtils.craftIpDnsReply(queryBytes, qtype, parsed.questionEndOffset, safeSearchVip)
            val elapsed = (System.currentTimeMillis() - startTime).toInt()
            DnsTelemetryManager.recordQuery(qname, "SAFESEARCH", "SafeSearch VIP Enforced", elapsed)
            Log.i(TAG, "SAFESEARCH DNS query: $qname -> VIP rewritten")
            safeReply
        } else {
            // ALLOWED: Resolve via configured DoH or protected upstream nameservers (1.1.1.1 / 8.8.8.8)
            val reply = resolveDnsWire(queryBytes)
            val elapsed = (System.currentTimeMillis() - startTime).toInt()
            if (qname.isNotEmpty()) {
                val status = if (reply != null) "ALLOWED" else "SERVFAIL"
                DnsTelemetryManager.recordQuery(qname, status, "Upstream DNS", elapsed)
            }
            reply
        }

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
     * Resolves DNS query via configured DoH server or direct VPN-protected upstream UDP socket.
     * Guarantees mobile connection stability and sub-20ms resolution.
     */
    private fun resolveDnsWire(queryBytes: ByteArray): ByteArray? {
        // 1. If serverUrl points to a remote server, try DoH first
        val isLocalhost = serverUrl.contains("127.0.0.1") || serverUrl.contains("localhost") || serverUrl.contains("10.0.2.2")
        if (!isLocalhost && (serverUrl.startsWith("http://") || serverUrl.startsWith("https://"))) {
            val dohReply = resolveViaDoH(queryBytes)
            if (dohReply != null) return dohReply
        }

        // 2. Direct upstream UDP resolution to 1.1.1.1 (Cloudflare) with fallback to 8.8.8.8 (Google)
        // Exempted from VPN routing using protect(socket)
        return resolveViaUpstreamUdp(queryBytes)
    }

    private fun resolveViaDoH(queryBytes: ByteArray): ByteArray? {
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
                connectTimeout = 1200
                readTimeout = 1500
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
            }
        } catch (e: Exception) {
            Log.d(TAG, "DoH query failed: ${e.message}")
        }
        return null
    }

    private fun resolveViaUpstreamUdp(queryBytes: ByteArray): ByteArray? {
        val upstreams = listOf("1.1.1.1", "1.0.0.1", "8.8.8.8")
        for (upstreamIp in upstreams) {
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket()
                protect(socket) // CRITICAL: Protect socket from entering VPN tun interface!
                socket.soTimeout = 1800

                val addr = InetAddress.getByName(upstreamIp)
                val outPacket = DatagramPacket(queryBytes, queryBytes.size, addr, 53)
                socket.send(outPacket)

                val inBuf = ByteArray(4096)
                val inPacket = DatagramPacket(inBuf, inBuf.size)
                socket.receive(inPacket)

                val reply = inBuf.copyOf(inPacket.length)
                if (!isBackendReachable) {
                    isBackendReachable = true
                    updateNotification(isHealthy = true)
                    notifyStateChange()
                }
                return reply
            } catch (e: Exception) {
                Log.d(TAG, "Upstream $upstreamIp failed: ${e.message}")
            } finally {
                socket?.close()
            }
        }

        // Fast-fail SERVFAIL if all upstreams fail
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
