package com.example.focus_dns

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusDnsVpnPacketTest {

    @Test
    fun testIpChecksumComputation() {
        // Standard IPv4 20-byte header sample
        val header = byteArrayOf(
            0x45.toByte(), 0x00.toByte(), 0x00.toByte(), 0x3c.toByte(),
            0x1c.toByte(), 0x46.toByte(), 0x40.toByte(), 0x00.toByte(),
            0x40.toByte(), 0x11.toByte(), 0x00.toByte(), 0x00.toByte(), // checksum at bytes 10-11
            0x0a.toByte(), 0xfe.toByte(), 0x01.toByte(), 0x02.toByte(), // 10.254.1.2
            0x0a.toByte(), 0xfe.toByte(), 0x01.toByte(), 0x01.toByte()  // 10.254.1.1
        )

        val checksum = PacketUtils.computeIpChecksum(header, 0, 20)
        assertTrue("Checksum must be non-zero 16-bit integer", checksum in 1..0xFFFF)

        header[10] = (checksum shr 8).toByte()
        header[11] = (checksum and 0xFF).toByte()

        // Recomputing checksum over the header with valid checksum field must yield 0xFFFF in 1's complement sum
        var verifySum = 0
        var i = 0
        while (i < 20) {
            val word = ((header[i].toInt() and 0xFF) shl 8) or (header[i + 1].toInt() and 0xFF)
            verifySum += word
            if (verifySum > 0xFFFF) {
                verifySum = (verifySum and 0xFFFF) + (verifySum shr 16)
            }
            i += 2
        }
        assertEquals("Verifying IPv4 header with valid checksum must equal 0xFFFF", 0xFFFF, verifySum)
    }

    @Test
    fun testServfailPacketGeneration() {
        val query = byteArrayOf(
            0x12.toByte(), 0x34.toByte(), 0x01.toByte(), 0x00.toByte(),
            0x00.toByte(), 0x01.toByte(), 0x00.toByte(), 0x00.toByte(),
            0x00.toByte(), 0x00.toByte(), 0x00.toByte(), 0x00.toByte()
        )

        val resp = PacketUtils.craftServfailReply(query)
        assertNotNull(resp)
        assertEquals("Transaction ID high byte must be preserved", 0x12.toByte(), resp!![0])
        assertEquals("Transaction ID low byte must be preserved", 0x34.toByte(), resp[1])
        assertTrue("QR bit must be 1 (Response)", (resp[2].toInt() and 0x80) != 0)
        assertEquals("RCODE must be 2 (SERVFAIL)", 2, resp[3].toInt() and 0x0F)
    }

    @Test
    fun testUdpReplyPacketIpv4Framing() {
        val clientIp = byteArrayOf(10.toByte(), 254.toByte(), 1.toByte(), 1.toByte()) // 10.254.1.1
        val dnsServerIp = byteArrayOf(10.toByte(), 254.toByte(), 1.toByte(), 2.toByte()) // 10.254.1.2
        val clientPort = 54321
        val fakeDnsPayload = byteArrayOf(0xAB.toByte(), 0xCD.toByte(), 0x81.toByte(), 0x80.toByte())

        // Directly exercises production PacketUtils code
        val packet = PacketUtils.craftUdpReplyPacketIpv4(clientIp, clientPort, dnsServerIp, fakeDnsPayload, ipId = 1234)
        assertEquals("Total length must match 20 IP + 8 UDP + 4 payload", 32, packet.size)

        // Verify IPv4 Header
        assertEquals("IPv4 Version/IHL byte must be 0x45", 0x45.toByte(), packet[0])
        assertEquals("Protocol must be UDP (17)", 17.toByte(), packet[9])
        assertEquals("Source IP must be 10.254.1.2", 10.toByte(), packet[12])
        assertEquals("Source IP must be 10.254.1.2", 2.toByte(), packet[15])
        assertEquals("Destination IP must be 10.254.1.1", 10.toByte(), packet[16])
        assertEquals("Destination IP must be 10.254.1.1", 1.toByte(), packet[19])

        // Verify IPv4 Checksum validity
        var verifySum = 0
        var i = 0
        while (i < 20) {
            val word = ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            verifySum += word
            if (verifySum > 0xFFFF) {
                verifySum = (verifySum and 0xFFFF) + (verifySum shr 16)
            }
            i += 2
        }
        assertEquals("IPv4 Header checksum must verify cleanly to 0xFFFF", 0xFFFF, verifySum)

        // Verify UDP Header
        val srcPort = ((packet[20].toInt() and 0xFF) shl 8) or (packet[21].toInt() and 0xFF)
        val dstPort = ((packet[22].toInt() and 0xFF) shl 8) or (packet[23].toInt() and 0xFF)
        val udpLen = ((packet[24].toInt() and 0xFF) shl 8) or (packet[25].toInt() and 0xFF)

        assertEquals("Source port must be 53 (DNS)", 53, srcPort)
        assertEquals("Destination port must match client port", clientPort, dstPort)
        assertEquals("UDP length must be 8 + payload size", 12, udpLen)

        // Verify Payload preserved
        assertEquals(0xAB.toByte(), packet[28])
        assertEquals(0xCD.toByte(), packet[29])
    }

    @Test
    fun testUdpReplyPacketIpv6Framing() {
        val clientIp = ByteArray(16) { 0x01 }
        val dnsServerIp = ByteArray(16) { 0x02 }
        val clientPort = 53535
        val fakePayload = byteArrayOf(0x01, 0x02, 0x03, 0x04)

        val packet = PacketUtils.craftUdpReplyPacketIpv6(clientIp, clientPort, dnsServerIp, fakePayload)
        assertEquals("IPv6 packet must be 40 IP + 8 UDP + 4 payload = 52 bytes", 52, packet.size)

        // Version 6
        assertEquals(0x60.toByte(), packet[0])
        // Next header = 17 (UDP)
        assertEquals(17.toByte(), packet[6])
    }

    @Test
    fun testTcpRstPacketGeneration() {
        val clientIp = byteArrayOf(10.toByte(), 254.toByte(), 1.toByte(), 1.toByte())
        val serverIp = byteArrayOf(10.toByte(), 254.toByte(), 1.toByte(), 2.toByte())
        val clientPort = 49152
        val ackNum = 987654321

        // Directly exercises production PacketUtils code
        val rstPacket = PacketUtils.craftTcpRstIpv4(clientIp, clientPort, serverIp, 53, ackNum)
        assertEquals("TCP RST total packet size must be 40 bytes", 40, rstPacket.size)

        // Protocol is TCP (6)
        assertEquals("Protocol must be 6 (TCP)", 6.toByte(), rstPacket[9])

        // TCP Flags: offset 20 + 12 = 32. 0x5014 -> low byte is flags = 0x14 (RST + ACK)
        val flags = rstPacket[33].toInt() and 0xFF
        assertEquals("TCP Flags must have RST and ACK set (0x14)", 0x14, flags)
    }
}
