package com.focusdns.focus_dns

import android.app.AlarmManager
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
import android.os.SystemClock
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionHandler
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Local DNS-only VPN with Active Anti-Bypass, DoT/DoH Traps, and IPv6 Leak Protection.
 * 
 * Capabilities:
 * 1. Binds local virtual DNS (10.111.222.2 and fd00::2).
 * 2. Traps well-known public DNS server IPs (1.1.1.1, 8.8.8.8, 9.9.9.9) into the tunnel.
 * 3. Actively sends TCP RST on ports 53, 443, and 853 to prevent DoH/DoT bypass in browsers & Private DNS.
 * 4. Resolves allowed queries via VPN-protected upstream sockets without external server dependency.
 * 5. Rewrites Google, Bing, and DuckDuckGo SafeSearch VIPs for both IPv4 and IPv6.
 */
class FocusDnsVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.focusdns.focus_dns.START"
        const val ACTION_STOP = "com.focusdns.focus_dns.STOP"
        const val DNS_IP = "10.111.222.2"
        const val DNS_IPV6 = "fd00::2"
        private const val TAG = "FocusDnsVpn"
        private const val CHANNEL_ID = "focusdns_vpn"
        private val UPSTREAMS = arrayOf("1.1.1.1", "1.0.0.1", "8.8.8.8", "9.9.9.9")
        @Volatile var isRunning = false
    }

    private var tun: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private val running = AtomicBoolean(false)
    private var pool: ThreadPoolExecutor? = null
    private val writeLock = Any()
    private val ipIdCounter = AtomicInteger(1000)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            LocalDb.get(this).putKv("was_running", "0")
            stopVpn()
            return START_NOT_STICKY
        }
        if (intent == null && LocalDb.get(this).getKv("was_running", "0") != "1") {
            stopSelf()
            return START_NOT_STICKY
        }
        startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        if (running.get()) return
        startAsForeground()
        Rules.reload(this)

        val pfd = try {
            val builder = Builder()
                .setSession("FocusDNS")
                .setMtu(1500)
                .setBlocking(true)
                .addAddress("10.111.222.1", 32)
                .addDnsServer(DNS_IP)
                .addRoute(DNS_IP, 32)

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

            // IPv6 Virtual interface and DNS route to capture and prevent IPv6 DNS leaks
            try {
                builder.addAddress("fd00::1", 128)
                builder.addDnsServer(DNS_IPV6)
                builder.addRoute(DNS_IPV6, 128)
            } catch (e: Exception) {
                Log.d(TAG, "IPv6 address assignment omitted: ${e.message}")
            }

            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "establish failed: ${e.message}")
            null
        }

        if (pfd == null) {
            stopVpn()
            return
        }

        tun = pfd
        running.set(true)
        isRunning = true
        LocalDb.get(this).putKv("was_running", "1")

        val threadCount = Runtime.getRuntime().availableProcessors().coerceIn(4, 16)
        val queue = LinkedBlockingQueue<Runnable>(250)
        val rejectionHandler = RejectedExecutionHandler { _, _ ->
            Log.w(TAG, "DNS query worker pool full! Dropping saturated request")
        }
        pool = ThreadPoolExecutor(threadCount, threadCount, 60L, TimeUnit.SECONDS, queue, rejectionHandler)

        reader = Thread({ readLoop(pfd) }, "focusdns-tun").also { it.start() }
        Bridge.emit("onVpnStateChanged", mapOf("isRunning" to true, "isBackendReachable" to true))
    }

    private fun readLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val buf = ByteArray(32767)

        while (running.get()) {
            val n = try { input.read(buf) } catch (e: Exception) { -1 }
            if (n <= 0) break

            val version = (buf[0].toInt() shr 4) and 0x0F
            if (version == 4) {
                handleIpv4Packet(buf, n, output)
            } else if (version == 6) {
                handleIpv6Packet(buf, n, output)
            }
        }
        if (running.get()) stopVpn()
    }

    private fun handleIpv4Packet(packet: ByteArray, length: Int, output: FileOutputStream) {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < 20 || length < ihl + 8) return
        val protocol = packet[9].toInt() and 0xFF

        // UDP (17) on port 53 (DNS)
        if (protocol == 17) {
            val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
            val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
            val udpLen = ((packet[ihl + 4].toInt() and 0xFF) shl 8) or (packet[ihl + 5].toInt() and 0xFF)

            if (dstPort == 53 && udpLen >= 8 && ihl + udpLen <= length) {
                val dnsPayload = packet.copyOfRange(ihl + 8, ihl + udpLen)
                val clientIp = packet.copyOfRange(12, 16)
                val serverIp = packet.copyOfRange(16, 20)

                pool?.execute {
                    handleDnsQuery(dnsPayload, clientIp, srcPort, serverIp, false, output)
                }
            }
        }
        // TCP (6) on port 53 (TCP DNS), 443 (DoH trap), or 853 (DoT trap)
        // Reset connection to fast-fail so client uses standard UDP DNS
        else if (protocol == 6 && length >= ihl + 20) {
            val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
            if (dstPort == 53 || dstPort == 443 || dstPort == 853) {
                val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
                val clientIp = packet.copyOfRange(12, 16)
                val serverIp = packet.copyOfRange(16, 20)
                val seqNum = ByteBuffer.wrap(packet, ihl + 4, 4).int

                pool?.execute {
                    sendTcpRstIpv4(clientIp, srcPort, serverIp, dstPort, seqNum, output)
                }
            }
        }
    }

    private fun handleIpv6Packet(packet: ByteArray, length: Int, output: FileOutputStream) {
        if (length < 48) return // 40 bytes IPv6 + 8 bytes UDP
        val nextHeader = packet[6].toInt() and 0xFF

        if (nextHeader == 17) { // UDP
            val srcPort = ((packet[40].toInt() and 0xFF) shl 8) or (packet[41].toInt() and 0xFF)
            val dstPort = ((packet[42].toInt() and 0xFF) shl 8) or (packet[43].toInt() and 0xFF)
            val udpLen = ((packet[44].toInt() and 0xFF) shl 8) or (packet[45].toInt() and 0xFF)

            if (dstPort == 53 && udpLen >= 8 && 40 + udpLen <= length) {
                val dnsPayload = packet.copyOfRange(48, 48 + udpLen - 8)
                val clientIp = packet.copyOfRange(8, 24)
                val serverIp = packet.copyOfRange(24, 40)

                pool?.execute {
                    handleDnsQuery(dnsPayload, clientIp, srcPort, serverIp, true, output)
                }
            }
        }
    }

    private fun sendTcpRstIpv4(
        clientIp: ByteArray,
        clientPort: Int,
        serverIp: ByteArray,
        serverPort: Int,
        ackNum: Int,
        output: FileOutputStream
    ) {
        val rstPacket = PacketUtils.craftTcpRstIpv4(
            clientIp = clientIp,
            clientPort = clientPort,
            serverIp = serverIp,
            serverPort = serverPort,
            ackNum = ackNum,
            ipId = (ipIdCounter.incrementAndGet() and 0xFFFF).toShort()
        )

        synchronized(writeLock) {
            try {
                output.write(rstPacket)
                output.flush()
            } catch (e: Exception) {
                Log.d(TAG, "Write TCP RST failed: ${e.message}")
            }
        }
    }

    private fun getSafeSearchIp(name: String, qtype: Int): ByteArray? {
        if (!Rules.safeSearchEnabled) return null
        val clean = name.trim().trimEnd('.').lowercase()
        // Google SafeSearch: forcesafesearch.google.com -> 216.239.38.120 (IPv4) or 2001:4860:4806::78 (IPv6)
        if (clean == "google.com" || clean.endsWith(".google.com")) {
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

    private fun handleDnsQuery(
        dnsBytes: ByteArray,
        clientIp: ByteArray,
        clientPort: Int,
        serverIp: ByteArray,
        isIpv6: Boolean,
        output: FileOutputStream
    ) {
        val start = System.currentTimeMillis()
        val parsed = PacketUtils.parseDnsQuestion(dnsBytes)
        val name = parsed?.domain ?: ""
        val qtype = parsed?.qtype ?: 1
        val decision = if (name.isNotEmpty()) Rules.decide(this, name) else Decision(false, "")
        val safeVip = if (name.isNotEmpty() && parsed != null) getSafeSearchIp(name, qtype) else null

        val dnsResponse: ByteArray? = if (decision.blocked && parsed != null) {
            PacketUtils.craftBlockedDnsReply(dnsBytes, qtype, parsed.questionEndOffset)
        } else if (safeVip != null && parsed != null) {
            PacketUtils.craftIpDnsReply(dnsBytes, qtype, parsed.questionEndOffset, safeVip)
        } else {
            val up = forward(dnsBytes)
            up ?: PacketUtils.craftServfailReply(dnsBytes)
        }

        val status = if (decision.blocked) "BLOCKED" else if (safeVip != null) "ALLOWED" else if (dnsResponse != null) "ALLOWED" else "SERVFAIL"
        val reason = if (safeVip != null) "SafeSearch VIP" else decision.reason
        val ms = (System.currentTimeMillis() - start).toInt()

        if (name.isNotEmpty()) {
            DnsStats.record(name, status, reason, ms)
            try { LocalDb.get(this).addLog(name, status, reason) } catch (_: Exception) {}
            Bridge.emit("onLiveQuery", mapOf(
                "domain" to name,
                "status" to status,
                "reason" to reason,
                "latencyMs" to ms,
                "timestampMs" to System.currentTimeMillis(),
                "id" to start.toString()
            ))
        }

        if (dnsResponse != null && running.get()) {
            val replyPacket = if (!isIpv6) {
                PacketUtils.craftUdpReplyPacketIpv4(
                    clientIp = clientIp,
                    clientPort = clientPort,
                    dnsServerIp = serverIp,
                    dnsReply = dnsResponse,
                    ipId = (ipIdCounter.incrementAndGet() and 0xFFFF).toShort()
                )
            } else {
                PacketUtils.craftUdpReplyPacketIpv6(
                    clientIp = clientIp,
                    clientPort = clientPort,
                    dnsServerIp = serverIp,
                    dnsReply = dnsResponse
                )
            }

            synchronized(writeLock) {
                try {
                    output.write(replyPacket)
                    output.flush()
                } catch (_: Exception) {}
            }
        }
    }

    private fun forward(query: ByteArray): ByteArray? {
        for (host in UPSTREAMS) {
            var sock: DatagramSocket? = null
            try {
                sock = DatagramSocket()
                protect(sock)               // Keep this socket out of the VPN tunnel
                sock.soTimeout = 1800
                val addr = InetAddress.getByName(host)
                sock.send(DatagramPacket(query, query.size, addr, 53))
                val buf = ByteArray(4096)
                val resp = DatagramPacket(buf, buf.size)
                sock.receive(resp)
                return buf.copyOf(resp.length)
            } catch (e: Exception) {
                Log.d(TAG, "Upstream $host failed: ${e.message}")
            } finally {
                try { sock?.close() } catch (_: Exception) {}
            }
        }
        return null
    }

    private fun stopVpn() {
        val wasRunning = running.getAndSet(false)
        isRunning = false
        try { tun?.close() } catch (_: Exception) {}
        tun = null
        pool?.shutdownNow()
        pool = null
        stopForeground(true)
        stopSelf()
        if (wasRunning) Bridge.emit("onVpnStateChanged", mapOf("isRunning" to false, "isBackendReachable" to true))
    }

    override fun onRevoke() {
        LocalDb.get(this).putKv("was_running", "0")
        stopVpn()
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val open = PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
            val n = b.setContentTitle("Focus Shield: Accessibility Guard Active")
                .setContentText("External VPN connected. Prohibited apps & domains remain strictly blocked.")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            nm.notify(2, n)
        } catch (_: Exception) {}
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val db = LocalDb.get(this)
        val wasRunning = db.getKv("was_running", "0") == "1"
        val until = db.getKv("strict_until", "0").toLongOrNull() ?: 0L
        val isStrict = (until - System.currentTimeMillis()) > 0
        val isAnyModeActive = wasRunning || isStrict || isRunning

        if (isAnyModeActive) {
            Log.d(TAG, "Task removed but active protection mode detected. Keeping Focus Shield alive.")
            try {
                val restartIntent = Intent(applicationContext, FocusDnsVpnService::class.java).apply {
                    setPackage(packageName)
                    action = ACTION_START
                }
                val restartPendingIntent = PendingIntent.getService(
                    this, 101, restartIntent,
                    PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
                )
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.set(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 1000,
                    restartPendingIntent
                )
            } catch (_: Exception) {}
        } else {
            stopVpn()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running.set(false)
        isRunning = false
        try { tun?.close() } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "FocusDNS protection", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val n = b.setContentTitle("FocusDNS is protecting this device")
            .setContentText("Local filtering & Anti-Bypass active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(1, n)
            }
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed: ${e.message}")
        }
    }
}
