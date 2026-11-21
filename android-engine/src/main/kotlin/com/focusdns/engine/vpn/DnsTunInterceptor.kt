package com.focusdns.engine.vpn

import android.util.Log
import com.focusdns.engine.rules.RulesEngine
import com.focusdns.engine.session.EvaluationTarget
import com.focusdns.engine.session.SessionStateMachineEngine
import java.io.OutputStream
import java.nio.ByteBuffer

/**
 * Parses raw IP/UDP/TCP DNS packets received on tun0 and performs zero-overhead
 * on-device interception with Double Verification and Anti-Bypass Armor.
 *
 * Anti-Bypass Capabilities:
 * 1. UDP 53 & TCP 53 full interception and NXDOMAIN synthesis.
 * 2. IPv6 (fd00::1) query support with RFC 2460 pseudo-header checksums.
 * 3. DNS-over-TLS (Port 853) probe blocking (prevents Android Private DNS circumvention).
 * 4. Double Verification: verifies both exact blocklists (Tier 1) and lexical category tokens (Tier 2).
 */
object DnsTunInterceptor {
    private const val TAG = "DnsTunInterceptor"
    private const val IPV4_HEADER_MIN_LEN = 20
    private const val IPV6_HEADER_LEN = 40
    private const val UDP_HEADER_LEN = 8
    private const val DNS_PORT = 53
    private const val DOT_PORT = 853

    private const val PROTO_TCP = 6
    private const val PROTO_UDP = 17

    var stateMachineEngine: SessionStateMachineEngine? = null
    var rulesEngine: RulesEngine? = null

    fun handleIncomingPacket(buffer: ByteArray, length: Int, outputStream: OutputStream) {
        if (length < IPV4_HEADER_MIN_LEN) return

        val version = (buffer[0].toInt() shr 4) and 0x0F

        when (version) {
            4 -> handleIpv4Packet(buffer, length, outputStream)
            6 -> handleIpv6Packet(buffer, length, outputStream)
            else -> return
        }
    }

    private fun handleIpv4Packet(buffer: ByteArray, length: Int, outputStream: OutputStream) {
        val ipHeaderLen = (buffer[0].toInt() and 0x0F) * 4
        if (length < ipHeaderLen + UDP_HEADER_LEN) return

        val protocol = buffer[9].toInt() and 0xFF
        val dstPort = ((buffer[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or
                      (buffer[ipHeaderLen + 3].toInt() and 0xFF)

        // 1. Anti-Bypass: Intercept & block DoT Port 853 (Private DNS leak prevention)
        if (dstPort == DOT_PORT) {
            if (protocol == PROTO_TCP) {
                val rst = synthesizeIpv4TcpRst(buffer, ipHeaderLen)
                synchronized(outputStream) {
                    try {
                        outputStream.write(rst)
                        outputStream.flush()
                    } catch (e: Exception) {
                        Log.w(TAG, "Error writing TCP RST for DoT: ${e.message}")
                    }
                }
            }
            Log.d(TAG, "Blocked IPv4 DoT Port 853 probe to prevent Private DNS bypass")
            return
        }

        // 2. Intercept standard DNS (Port 53)
        if (dstPort != DNS_PORT) return

        if (protocol == PROTO_UDP) {
            handleIpv4UdpDns(buffer, length, ipHeaderLen, outputStream)
        } else if (protocol == PROTO_TCP) {
            handleIpv4TcpDns(buffer, length, ipHeaderLen, outputStream)
        }
    }

    private fun handleIpv4UdpDns(
        buffer: ByteArray,
        length: Int,
        ipHeaderLen: Int,
        outputStream: OutputStream
    ) {
        val dnsOffset = ipHeaderLen + UDP_HEADER_LEN
        val dnsLength = length - dnsOffset
        if (dnsLength < 12) return

        try {
            val qName = extractQName(buffer, dnsOffset)
            if (qName.isNullOrEmpty()) return

            val (isBlocked, reason) = evaluateDoubleVerification(qName)

            if (isBlocked) {
                val reply = synthesizeNxDomainReply(buffer, length, ipHeaderLen, dnsOffset, dnsLength)
                synchronized(outputStream) {
                    outputStream.write(reply)
                    outputStream.flush()
                }
                Log.d(TAG, "Sinkholed UDP query for: $qName ($reason)")
            } else {
                rulesEngine?.resolveUpstreamDoH(qName, buffer, dnsOffset, dnsLength) { resolvedDnsPayload ->
                    if (resolvedDnsPayload != null) {
                        val reply = synthesizeForwardReply(buffer, length, ipHeaderLen, resolvedDnsPayload)
                        try {
                            synchronized(outputStream) {
                                outputStream.write(reply)
                                outputStream.flush()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Error writing resolved DNS reply to tun: ${e.message}")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing IPv4 UDP DNS packet: ${e.message}")
        }
    }

    private fun handleIpv4TcpDns(
        buffer: ByteArray,
        length: Int,
        ipHeaderLen: Int,
        outputStream: OutputStream
    ) {
        val tcpHeaderLen = ((buffer[ipHeaderLen + 12].toInt() shr 4) and 0x0F) * 4
        val tcpOffset = ipHeaderLen + tcpHeaderLen
        if (length < tcpOffset + 2 + 12) {
            // TCP handshake packet (SYN) on port 53 - acknowledge or reply RST
            val rst = synthesizeIpv4TcpRst(buffer, ipHeaderLen)
            synchronized(outputStream) {
                outputStream.write(rst)
                outputStream.flush()
            }
            return
        }

        val dnsOffset = tcpOffset + 2
        val dnsLength = length - dnsOffset
        val qName = extractQName(buffer, dnsOffset) ?: return

        val (isBlocked, reason) = evaluateDoubleVerification(qName)
        if (isBlocked) {
            val rst = synthesizeIpv4TcpRst(buffer, ipHeaderLen)
            synchronized(outputStream) {
                outputStream.write(rst)
                outputStream.flush()
            }
            Log.d(TAG, "Sinkholed TCP DNS query for: $qName ($reason)")
        } else {
            // For allowed TCP queries, fall back or forward via DoH
            rulesEngine?.resolveUpstreamDoH(qName, buffer, dnsOffset, dnsLength) { resolved ->
                if (resolved != null) {
                    val reply = synthesizeIpv4TcpReply(buffer, ipHeaderLen, tcpHeaderLen, resolved)
                    try {
                        synchronized(outputStream) {
                            outputStream.write(reply)
                            outputStream.flush()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Error writing TCP resolved DNS reply: ${e.message}")
                    }
                }
            }
        }
    }

    private fun handleIpv6Packet(buffer: ByteArray, length: Int, outputStream: OutputStream) {
        if (length < IPV6_HEADER_LEN + UDP_HEADER_LEN) return

        val nextHeader = buffer[6].toInt() and 0xFF
        val dstPort = ((buffer[IPV6_HEADER_LEN + 2].toInt() and 0xFF) shl 8) or
                      (buffer[IPV6_HEADER_LEN + 3].toInt() and 0xFF)

        // 1. Anti-Bypass: Block IPv6 DoT Port 853
        if (dstPort == DOT_PORT) {
            Log.d(TAG, "Blocked IPv6 DoT Port 853 probe to prevent Private DNS bypass")
            return
        }

        // 2. IPv6 DNS on Port 53
        if (dstPort != DNS_PORT || nextHeader != PROTO_UDP) return

        val dnsOffset = IPV6_HEADER_LEN + UDP_HEADER_LEN
        val dnsLength = length - dnsOffset
        if (dnsLength < 12) return

        val qName = extractQName(buffer, dnsOffset) ?: return
        val (isBlocked, reason) = evaluateDoubleVerification(qName)

        if (isBlocked) {
            val reply = synthesizeIpv6NxDomainReply(buffer, length, dnsOffset)
            synchronized(outputStream) {
                outputStream.write(reply)
                outputStream.flush()
            }
            Log.d(TAG, "Sinkholed IPv6 query for: $qName ($reason)")
        } else {
            rulesEngine?.resolveUpstreamDoH(qName, buffer, dnsOffset, dnsLength) { resolved ->
                if (resolved != null) {
                    val reply = synthesizeIpv6ForwardReply(buffer, length, resolved)
                    try {
                        synchronized(outputStream) {
                            outputStream.write(reply)
                            outputStream.flush()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Error writing resolved IPv6 DNS reply: ${e.message}")
                    }
                }
            }
        }
    }

    /**
     * Executes Double Verification against the domain:
     * Check 1: StateMachine and explicit blocklists (Tier 1)
     * Check 2: Lexical category and TLD vocabulary verification (Tier 2)
     */
    fun evaluateDoubleVerification(qName: String): Pair<Boolean, String> {
        val target = EvaluationTarget(domain = qName)
        val decision = stateMachineEngine?.isBlocked(target)
        if (decision?.isBlocked == true) {
            return Pair(true, decision.reason)
        }

        val rulesVerdict = rulesEngine?.doubleVerifyDomain(qName)
        if (rulesVerdict?.isBlocked == true) {
            return Pair(true, rulesVerdict.reason)
        }

        return Pair(false, "Clean")
    }

    private fun extractQName(buffer: ByteArray, dnsOffset: Int): String? {
        var pos = dnsOffset + 12
        val sb = StringBuilder()

        while (pos < buffer.size) {
            val len = buffer[pos].toInt() and 0xFF
            if (len == 0) break
            if ((len and 0xC0) != 0) return null

            pos++
            if (pos + len > buffer.size) return null

            if (sb.isNotEmpty()) sb.append(".")
            for (i in 0 until len) {
                sb.append(buffer[pos + i].toInt().toChar())
            }
            pos += len
        }

        return sb.toString().lowercase()
    }

    private fun synthesizeNxDomainReply(
        src: ByteArray,
        srcLen: Int,
        ipHeaderLen: Int,
        dnsOffset: Int,
        dnsLen: Int
    ): ByteArray {
        val reply = src.copyOf(srcLen)

        // Swap IPv4 Addrs
        for (i in 0 until 4) {
            val tmp = reply[12 + i]
            reply[12 + i] = reply[16 + i]
            reply[16 + i] = tmp
        }

        // Swap UDP Ports
        val srcPort = ((reply[ipHeaderLen].toInt() and 0xFF) shl 8) or (reply[ipHeaderLen + 1].toInt() and 0xFF)
        val dstPort = ((reply[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or (reply[ipHeaderLen + 3].toInt() and 0xFF)
        reply[ipHeaderLen] = (dstPort shr 8).toByte()
        reply[ipHeaderLen + 1] = dstPort.toByte()
        reply[ipHeaderLen + 2] = (srcPort shr 8).toByte()
        reply[ipHeaderLen + 3] = srcPort.toByte()

        // Set DNS flags: QR=1 (response), AA=1, RA=1, RCODE=3 (NXDOMAIN)
        reply[dnsOffset + 2] = 0x81.toByte()
        reply[dnsOffset + 3] = 0x83.toByte()

        // Zero UDP checksum
        reply[ipHeaderLen + 6] = 0
        reply[ipHeaderLen + 7] = 0

        // Recalculate IP header checksum
        reply[10] = 0
        reply[11] = 0
        val ipChecksum = computeIpChecksum(reply, ipHeaderLen)
        reply[10] = (ipChecksum shr 8).toByte()
        reply[11] = ipChecksum.toByte()

        return reply
    }

    private fun synthesizeForwardReply(
        src: ByteArray,
        srcLen: Int,
        ipHeaderLen: Int,
        dnsReplyPayload: ByteArray
    ): ByteArray {
        val totalLen = ipHeaderLen + UDP_HEADER_LEN + dnsReplyPayload.size
        val reply = ByteArray(totalLen)

        System.arraycopy(src, 0, reply, 0, ipHeaderLen)

        for (i in 0 until 4) {
            val tmp = reply[12 + i]
            reply[12 + i] = reply[16 + i]
            reply[16 + i] = tmp
        }

        reply[2] = (totalLen shr 8).toByte()
        reply[3] = totalLen.toByte()

        val srcPort = ((src[ipHeaderLen].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 1].toInt() and 0xFF)
        val dstPort = ((src[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 3].toInt() and 0xFF)
        reply[ipHeaderLen] = (dstPort shr 8).toByte()
        reply[ipHeaderLen + 1] = dstPort.toByte()
        reply[ipHeaderLen + 2] = (srcPort shr 8).toByte()
        reply[ipHeaderLen + 3] = srcPort.toByte()

        val udpLen = UDP_HEADER_LEN + dnsReplyPayload.size
        reply[ipHeaderLen + 4] = (udpLen shr 8).toByte()
        reply[ipHeaderLen + 5] = udpLen.toByte()
        reply[ipHeaderLen + 6] = 0
        reply[ipHeaderLen + 7] = 0

        System.arraycopy(dnsReplyPayload, 0, reply, ipHeaderLen + UDP_HEADER_LEN, dnsReplyPayload.size)

        reply[10] = 0
        reply[11] = 0
        val ipChecksum = computeIpChecksum(reply, ipHeaderLen)
        reply[10] = (ipChecksum shr 8).toByte()
        reply[11] = ipChecksum.toByte()

        return reply
    }

    private fun synthesizeIpv4TcpRst(src: ByteArray, ipHeaderLen: Int): ByteArray {
        val tcpLen = 20
        val totalLen = ipHeaderLen + tcpLen
        val reply = ByteArray(totalLen)

        // Copy IP header
        System.arraycopy(src, 0, reply, 0, ipHeaderLen)

        // Swap IP addresses
        for (i in 0 until 4) {
            val tmp = reply[12 + i]
            reply[12 + i] = reply[16 + i]
            reply[16 + i] = tmp
        }

        reply[2] = (totalLen shr 8).toByte()
        reply[3] = totalLen.toByte()
        reply[8] = 64.toByte() // TTL

        // TCP header
        val srcPort = ((src[ipHeaderLen].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 1].toInt() and 0xFF)
        val dstPort = ((src[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 3].toInt() and 0xFF)
        reply[ipHeaderLen] = (dstPort shr 8).toByte()
        reply[ipHeaderLen + 1] = dstPort.toByte()
        reply[ipHeaderLen + 2] = (srcPort shr 8).toByte()
        reply[ipHeaderLen + 3] = srcPort.toByte()

        // Sequence number: acknowledgment number of incoming packet or 0
        reply[ipHeaderLen + 4] = 0
        reply[ipHeaderLen + 5] = 0
        reply[ipHeaderLen + 6] = 0
        reply[ipHeaderLen + 7] = 1

        // Flags: RST + ACK (0x14)
        reply[ipHeaderLen + 12] = (5 shl 4).toByte() // Data offset = 5 (20 bytes)
        reply[ipHeaderLen + 13] = 0x14.toByte()      // RST + ACK

        // Window size = 0
        reply[ipHeaderLen + 14] = 0
        reply[ipHeaderLen + 15] = 0

        // IP Checksum
        reply[10] = 0
        reply[11] = 0
        val ipChecksum = computeIpChecksum(reply, ipHeaderLen)
        reply[10] = (ipChecksum shr 8).toByte()
        reply[11] = ipChecksum.toByte()

        return reply
    }

    private fun synthesizeIpv4TcpReply(
        src: ByteArray,
        ipHeaderLen: Int,
        tcpHeaderLen: Int,
        dnsReplyPayload: ByteArray
    ): ByteArray {
        val tcpOffset = ipHeaderLen + tcpHeaderLen
        val tcpDataLen = 2 + dnsReplyPayload.size
        val totalLen = ipHeaderLen + tcpHeaderLen + tcpDataLen
        val reply = ByteArray(totalLen)

        System.arraycopy(src, 0, reply, 0, ipHeaderLen + tcpHeaderLen)

        // Swap IP
        for (i in 0 until 4) {
            val tmp = reply[12 + i]
            reply[12 + i] = reply[16 + i]
            reply[16 + i] = tmp
        }

        reply[2] = (totalLen shr 8).toByte()
        reply[3] = totalLen.toByte()

        // Swap TCP ports
        val srcPort = ((src[ipHeaderLen].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 1].toInt() and 0xFF)
        val dstPort = ((src[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or (src[ipHeaderLen + 3].toInt() and 0xFF)
        reply[ipHeaderLen] = (dstPort shr 8).toByte()
        reply[ipHeaderLen + 1] = dstPort.toByte()
        reply[ipHeaderLen + 2] = (srcPort shr 8).toByte()
        reply[ipHeaderLen + 3] = srcPort.toByte()

        // Flags: PSH + ACK (0x18)
        reply[ipHeaderLen + 13] = 0x18.toByte()

        // Write 2-byte DNS length prefix
        reply[tcpOffset] = (dnsReplyPayload.size shr 8).toByte()
        reply[tcpOffset + 1] = dnsReplyPayload.size.toByte()

        // Copy DNS payload
        System.arraycopy(dnsReplyPayload, 0, reply, tcpOffset + 2, dnsReplyPayload.size)

        // IP checksum
        reply[10] = 0
        reply[11] = 0
        val ipChecksum = computeIpChecksum(reply, ipHeaderLen)
        reply[10] = (ipChecksum shr 8).toByte()
        reply[11] = ipChecksum.toByte()

        return reply
    }

    private fun synthesizeIpv6NxDomainReply(src: ByteArray, srcLen: Int, dnsOffset: Int): ByteArray {
        val reply = src.copyOf(srcLen)

        // Swap 16-byte IPv6 Source and Destination addresses
        for (i in 0 until 16) {
            val tmp = reply[8 + i]
            reply[8 + i] = reply[24 + i]
            reply[24 + i] = tmp
        }

        // Swap UDP ports
        val srcPort = ((reply[40].toInt() and 0xFF) shl 8) or (reply[41].toInt() and 0xFF)
        val dstPort = ((reply[42].toInt() and 0xFF) shl 8) or (reply[43].toInt() and 0xFF)
        reply[40] = (dstPort shr 8).toByte()
        reply[41] = dstPort.toByte()
        reply[42] = (srcPort shr 8).toByte()
        reply[43] = srcPort.toByte()

        // DNS flags: QR=1, AA=1, RA=1, RCODE=3 (NXDOMAIN)
        reply[dnsOffset + 2] = 0x81.toByte()
        reply[dnsOffset + 3] = 0x83.toByte()

        // Compute RFC 2460 IPv6 UDP checksum
        reply[46] = 0
        reply[47] = 0
        val csum = computeIpv6UdpChecksum(reply, 40, srcLen - 40)
        reply[46] = (csum shr 8).toByte()
        reply[47] = csum.toByte()

        return reply
    }

    private fun synthesizeIpv6ForwardReply(src: ByteArray, srcLen: Int, dnsReplyPayload: ByteArray): ByteArray {
        val totalUdpLen = UDP_HEADER_LEN + dnsReplyPayload.size
        val totalLen = IPV6_HEADER_LEN + totalUdpLen
        val reply = ByteArray(totalLen)

        System.arraycopy(src, 0, reply, 0, IPV6_HEADER_LEN)

        for (i in 0 until 16) {
            val tmp = reply[8 + i]
            reply[8 + i] = reply[24 + i]
            reply[24 + i] = tmp
        }

        // IPv6 Payload Length (does not include the 40-byte IPv6 header)
        reply[4] = (totalUdpLen shr 8).toByte()
        reply[5] = totalUdpLen.toByte()

        // UDP ports
        val srcPort = ((src[40].toInt() and 0xFF) shl 8) or (src[41].toInt() and 0xFF)
        val dstPort = ((src[42].toInt() and 0xFF) shl 8) or (src[43].toInt() and 0xFF)
        reply[40] = (dstPort shr 8).toByte()
        reply[41] = dstPort.toByte()
        reply[42] = (srcPort shr 8).toByte()
        reply[43] = srcPort.toByte()

        reply[44] = (totalUdpLen shr 8).toByte()
        reply[45] = totalUdpLen.toByte()
        reply[46] = 0
        reply[47] = 0

        System.arraycopy(dnsReplyPayload, 0, reply, IPV6_HEADER_LEN + UDP_HEADER_LEN, dnsReplyPayload.size)

        val csum = computeIpv6UdpChecksum(reply, 40, totalUdpLen)
        reply[46] = (csum shr 8).toByte()
        reply[47] = csum.toByte()

        return reply
    }

    private fun computeIpChecksum(buf: ByteArray, length: Int): Int {
        var sum = 0
        var i = 0
        while (i < length) {
            val word = ((buf[i].toInt() and 0xFF) shl 8) or (buf[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return sum.inv() and 0xFFFF
    }

    private fun computeIpv6UdpChecksum(packet: ByteArray, udpOffset: Int, udpLen: Int): Int {
        var sum = 0

        // 1. IPv6 Source (16 bytes) and Destination (16 bytes)
        var i = 8
        while (i < 40) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            i += 2
        }

        // 2. Upper-Layer Packet Length (UDP length 4 bytes: 0x0000 + udpLen)
        sum += udpLen

        // 3. Next Header (0x0011 for UDP)
        sum += PROTO_UDP

        // 4. UDP Header and Payload
        i = udpOffset
        val end = udpOffset + udpLen
        while (i < end - 1) {
            sum += ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) {
            sum += (packet[i].toInt() and 0xFF) shl 8
        }

        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        val res = sum.inv() and 0xFFFF
        return if (res == 0) 0xFFFF else res
    }
}
