package com.focusdns.app

import java.nio.ByteBuffer

/**
 * Pure Kotlin packet crafting and checksum utilities.
 * Free of Android framework dependencies so it can be tested directly with JUnit.
 */
object PacketUtils {

    /**
     * Computes RFC 791 / RFC 1071 16-bit one's complement checksum over [data] from [offset] for [length] bytes.
     */
    fun computeIpChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        while (i < offset + length) {
            val word = ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            sum += word
            if (sum > 0xFFFF) {
                sum = (sum and 0xFFFF) + (sum shr 16)
            }
            i += 2
        }
        return sum.inv() and 0xFFFF
    }

    /**
     * Synthesizes a fast-fail SERVFAIL response for the given DNS request.
     * Sets QR=1 (response) and RCODE=2 (SERVFAIL), preserving transaction ID and question.
     */
    fun craftServfailReply(queryBytes: ByteArray): ByteArray? {
        if (queryBytes.size < 12) return null
        val resp = queryBytes.copyOf()
        // Set QR bit to 1 (response), clear AA/TC (bits 2 and 1), and set RCODE to 2 (SERVFAIL)
        resp[2] = ((resp[2].toInt() or 0x80) and 0x06.inv()).toByte()
        resp[3] = ((resp[3].toInt() and 0xF0) or 0x02).toByte()
        return resp
    }

    /**
     * Crafts a complete IPv4 UDP packet containing the DNS response.
     */
    fun craftUdpReplyPacketIpv4(
        clientIp: ByteArray,
        clientPort: Int,
        dnsServerIp: ByteArray,
        dnsReply: ByteArray,
        ipId: Short = 1000
    ): ByteArray {
        val totalLength = 20 + 8 + dnsReply.size
        val buf = ByteBuffer.allocate(totalLength)

        // --- IPv4 Header (20 bytes) ---
        buf.put(0x45.toByte())               // Version 4, IHL 5 (20 bytes)
        buf.put(0x00.toByte())               // DSCP/ECN
        buf.putShort(totalLength.toShort())  // Total Length
        buf.putShort(ipId)                   // Dynamic Identification
        buf.putShort(0x4000.toShort())       // Flags (Don't Fragment)
        buf.put(64.toByte())                 // TTL
        buf.put(17.toByte())                 // Protocol 17 = UDP
        buf.putShort(0.toShort())            // Checksum placeholder
        buf.put(dnsServerIp)                 // Source IP (virtual DNS)
        buf.put(clientIp)                    // Destination IP (client)

        val ipChecksum = computeIpChecksum(buf.array(), 0, 20)
        buf.putShort(10, ipChecksum.toShort())

        // --- UDP Header (8 bytes) ---
        buf.putShort(53.toShort())           // Source Port (DNS)
        buf.putShort(clientPort.toShort())   // Destination Port (client)
        buf.putShort((8 + dnsReply.size).toShort()) // UDP Length
        buf.putShort(0.toShort())            // Checksum (optional in IPv4 UDP)

        // --- DNS Payload ---
        buf.put(dnsReply)

        return buf.array()
    }

    /**
     * Crafts a complete IPv6 UDP packet containing the DNS response.
     */
    fun craftUdpReplyPacketIpv6(
        clientIp: ByteArray,
        clientPort: Int,
        dnsServerIp: ByteArray,
        dnsReply: ByteArray
    ): ByteArray {
        val udpLength = 8 + dnsReply.size
        val totalLength = 40 + udpLength
        val buf = ByteBuffer.allocate(totalLength)

        // --- IPv6 Header (40 bytes) ---
        buf.put(0x60.toByte())               // Version 6
        buf.put(0x00.toByte())               // Traffic class
        buf.putShort(0.toShort())            // Flow label
        buf.putShort(udpLength.toShort())    // Payload length
        buf.put(17.toByte())                 // Next header = UDP (17)
        buf.put(64.toByte())                 // Hop limit
        buf.put(dnsServerIp)                 // Source IPv6 (16 bytes)
        buf.put(clientIp)                    // Destination IPv6 (16 bytes)

        // --- UDP Header (8 bytes) ---
        buf.putShort(53.toShort())           // Source Port (DNS)
        buf.putShort(clientPort.toShort())   // Destination Port
        buf.putShort(udpLength.toShort())    // Length
        buf.putShort(0.toShort())            // Checksum placeholder

        // --- DNS Payload ---
        buf.put(dnsReply)

        return buf.array()
    }

    /**
     * Synthesizes a TCP RST+ACK packet for port 53.
     */
    fun craftTcpRstIpv4(
        clientIp: ByteArray,
        clientPort: Int,
        serverIp: ByteArray,
        serverPort: Int,
        ackNum: Int,
        ipId: Short = 2000
    ): ByteArray {
        val totalLength = 20 + 20
        val buf = ByteBuffer.allocate(totalLength)

        // IPv4 Header (20 bytes)
        buf.put(0x45.toByte())
        buf.put(0x00.toByte())
        buf.putShort(totalLength.toShort())
        buf.putShort(ipId)
        buf.putShort(0x4000.toShort())
        buf.put(64.toByte())
        buf.put(6.toByte()) // Protocol 6 = TCP
        buf.putShort(0.toShort())
        buf.put(serverIp)
        buf.put(clientIp)

        val ipChecksum = computeIpChecksum(buf.array(), 0, 20)
        buf.putShort(10, ipChecksum.toShort())

        // TCP Header (20 bytes)
        buf.putShort(serverPort.toShort())
        buf.putShort(clientPort.toShort())
        buf.putInt(ackNum)     // Sequence Number
        buf.putInt(0)          // Acknowledgment Number
        buf.putShort(0x5014.toShort()) // Header length 5 (20 bytes), Flags: RST + ACK (0x14)
        buf.putShort(0.toShort())      // Window Size
        buf.putShort(0.toShort())      // Checksum
        buf.putShort(0.toShort())      // Urgent Pointer

        return buf.array()
    }
}
