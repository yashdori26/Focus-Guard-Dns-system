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
     * Computes RFC 793 TCP checksum over pseudo-header and TCP segment.
     */
    fun computeTcpChecksum(srcIp: ByteArray, dstIp: ByteArray, tcpSegment: ByteArray): Short {
        var sum = 0L
        for (i in 0 until 4 step 2) {
            sum += (((srcIp[i].toInt() and 0xFF) shl 8) or (srcIp[i + 1].toInt() and 0xFF))
            sum += (((dstIp[i].toInt() and 0xFF) shl 8) or (dstIp[i + 1].toInt() and 0xFF))
        }
        sum += 6 // Protocol 6 (TCP)
        sum += tcpSegment.size

        for (i in 0 until tcpSegment.size - 1 step 2) {
            sum += (((tcpSegment[i].toInt() and 0xFF) shl 8) or (tcpSegment[i + 1].toInt() and 0xFF))
        }
        if (tcpSegment.size % 2 != 0) {
            sum += ((tcpSegment[tcpSegment.size - 1].toInt() and 0xFF) shl 8)
        }

        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv() and 0xFFFF).toShort()
    }

    /**
     * Synthesizes an authentic TCP RST+ACK packet for ports 53, 443, and 853.
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
        val tcpSegment = ByteArray(20)
        val tcpBuf = ByteBuffer.wrap(tcpSegment)
        tcpBuf.putShort(serverPort.toShort())
        tcpBuf.putShort(clientPort.toShort())
        tcpBuf.putInt(ackNum)          // Sequence Number
        tcpBuf.putInt(0)               // Acknowledgment Number
        tcpBuf.putShort(0x5014.toShort()) // Header length 5 (20 bytes), Flags: RST + ACK (0x14)
        tcpBuf.putShort(0.toShort())      // Window Size
        tcpBuf.putShort(0.toShort())      // Checksum placeholder
        tcpBuf.putShort(0.toShort())      // Urgent pointer

        val tcpChecksum = computeTcpChecksum(serverIp, clientIp, tcpSegment)
        tcpBuf.putShort(16, tcpChecksum)

        buf.put(tcpSegment)
        return buf.array()
    }

    /**
     * Parsed DNS Question header and payload details.
     */
    data class DnsQuestion(
        val domain: String,
        val qtype: Int,
        val qclass: Int,
        val questionEndOffset: Int
    )

    /**
     * RFC 1035 wire-format question parser.
     * Extracts QNAME (domain name) and QTYPE (A=1, AAAA=28, HTTPS=65, etc.).
     */
    fun parseDnsQuestion(queryBytes: ByteArray): DnsQuestion? {
        if (queryBytes.size < 16) return null
        var offset = 12
        val sb = StringBuilder()
        while (offset < queryBytes.size) {
            val len = queryBytes[offset].toInt() and 0xFF
            offset++
            if (len == 0) break
            if (len >= 192) {
                // Unexpected pointer in question
                offset++
                break
            }
            if (offset + len > queryBytes.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (i in 0 until len) {
                sb.append(queryBytes[offset + i].toInt().toChar())
            }
            offset += len
        }
        if (offset + 4 > queryBytes.size) return null
        val qtype = ((queryBytes[offset].toInt() and 0xFF) shl 8) or (queryBytes[offset + 1].toInt() and 0xFF)
        val qclass = ((queryBytes[offset + 2].toInt() and 0xFF) shl 8) or (queryBytes[offset + 3].toInt() and 0xFF)
        return DnsQuestion(sb.toString().lowercase(), qtype, qclass, offset + 4)
    }

    /**
     * Synthesizes an immediate NextDNS/AdGuard-style sinkhole DNS response.
     * Returns 0.0.0.0 for A queries (type 1) and :: for AAAA queries (type 28).
     * For other query types (e.g. HTTPS RR 65), returns NOERROR with 0 answers so clients fall back cleanly.
     */
    fun craftBlockedDnsReply(queryBytes: ByteArray, qtype: Int, questionEndOffset: Int): ByteArray? {
        if (queryBytes.size < questionEndOffset || questionEndOffset < 16) return null

        val isA = (qtype == 1)
        val isAaaa = (qtype == 28)

        if (!isA && !isAaaa) {
            // For HTTPS/SVCB/TXT queries on blocked domains: return NOERROR with 0 answers
            val totalLen = questionEndOffset
            val buf = ByteBuffer.allocate(totalLen)
            buf.put(queryBytes, 0, 2) // ID
            buf.putShort(0x8180.toShort()) // Standard Response, NOERROR, RD+RA
            buf.putShort(1.toShort())      // QDCOUNT = 1
            buf.putShort(0.toShort())      // ANCOUNT = 0
            buf.putShort(0.toShort())      // NSCOUNT = 0
            buf.putShort(0.toShort())      // ARCOUNT = 0
            buf.put(queryBytes, 12, questionEndOffset - 12)
            return buf.array()
        }

        val rdataLen = if (isAaaa) 16 else 4
        val answerRecordLen = 2 + 2 + 2 + 4 + 2 + rdataLen
        val totalLen = questionEndOffset + answerRecordLen

        val buf = ByteBuffer.allocate(totalLen)
        // Header
        buf.put(queryBytes, 0, 2)      // ID
        buf.putShort(0x8180.toShort()) // Flags: QR=1, AA=0, RD=1, RA=1, RCODE=0 (NOERROR)
        buf.putShort(1.toShort())      // QDCOUNT = 1
        buf.putShort(1.toShort())      // ANCOUNT = 1
        buf.putShort(0.toShort())      // NSCOUNT = 0
        buf.putShort(0.toShort())      // ARCOUNT = 0

        // Question section verbatim
        buf.put(queryBytes, 12, questionEndOffset - 12)

        // Answer Section:
        buf.putShort(0xC00C.toShort())  // Name pointer to QNAME at byte 12
        buf.putShort(qtype.toShort())   // Type: A (1) or AAAA (28)
        buf.putShort(1.toShort())       // Class: IN (1)
        buf.putInt(60)                  // TTL: 60 seconds
        buf.putShort(rdataLen.toShort())// RDLENGTH
        buf.put(ByteArray(rdataLen))    // RDATA: 0.0.0.0 (4 zeroes) or :: (16 zeroes)

        return buf.array()
    }

    /**
     * Synthesizes an immediate DNS response delivering an exact VIP (e.g. SafeSearch).
     */
    fun craftIpDnsReply(queryBytes: ByteArray, qtype: Int, questionEndOffset: Int, ipBytes: ByteArray): ByteArray? {
        if (queryBytes.size < questionEndOffset || questionEndOffset < 16) return null

        val isA = (qtype == 1 && ipBytes.size == 4)
        val isAaaa = (qtype == 28 && ipBytes.size == 16)

        if (!isA && !isAaaa) {
            return craftBlockedDnsReply(queryBytes, qtype, questionEndOffset)
        }

        val rdataLen = ipBytes.size
        val answerRecordLen = 2 + 2 + 2 + 4 + 2 + rdataLen
        val totalLen = questionEndOffset + answerRecordLen

        val buf = ByteBuffer.allocate(totalLen)
        // Header
        buf.put(queryBytes, 0, 2)      // ID
        buf.putShort(0x8180.toShort()) // Flags: QR=1, AA=0, RD=1, RA=1, RCODE=0 (NOERROR)
        buf.putShort(1.toShort())      // QDCOUNT = 1
        buf.putShort(1.toShort())      // ANCOUNT = 1
        buf.putShort(0.toShort())      // NSCOUNT = 0
        buf.putShort(0.toShort())      // ARCOUNT = 0

        // Question section verbatim
        buf.put(queryBytes, 12, questionEndOffset - 12)

        // Answer Section:
        buf.putShort(0xC00C.toShort())  // Name pointer to QNAME at byte 12
        buf.putShort(qtype.toShort())   // Type: A (1) or AAAA (28)
        buf.putShort(1.toShort())       // Class: IN (1)
        buf.putInt(300)                 // TTL: 300 seconds
        buf.putShort(rdataLen.toShort())// RDLENGTH
        buf.put(ipBytes)                // RDATA

        return buf.array()
    }
}


