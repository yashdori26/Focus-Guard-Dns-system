package com.focusdns.app.daemon

/**
 * RawPacketFilter
 * ===============
 * Fast-path byte-level IP/UDP/DNS packet parser and synthesizer.
 */
object RawPacketFilter {

    data class PacketValidation(
        val isValid: Boolean,
        val headerLength: Int = 0,
        val payloadLength: Int = 0
    )

    fun validatePacket(buffer: ByteArray, bytesRead: Int): PacketValidation {
        if (bytesRead < 28) return PacketValidation(false) // 20 IP + 8 UDP

        // Version = 4
        val version = (buffer[0].toInt() shr 4) and 0x0F
        if (version != 4) return PacketValidation(false)

        // Protocol = 17 (UDP)
        val protocol = buffer[9].toInt() and 0xFF
        if (protocol != 17) return PacketValidation(false)

        val ipHeaderLen = (buffer[0].toInt() and 0x0F) * 4
        val udpHeaderLen = 8
        val totalHeaderLen = ipHeaderLen + udpHeaderLen

        if (bytesRead <= totalHeaderLen) return PacketValidation(false)

        val payloadLen = bytesRead - totalHeaderLen
        return PacketValidation(true, totalHeaderLen, payloadLen)
    }

    fun extractDomainName(dnsPayload: ByteArray): String {
        if (dnsPayload.size < 12) return ""
        val sb = StringBuilder()
        var offset = 12
        var first = true

        while (offset < dnsPayload.size) {
            val len = dnsPayload[offset++].toInt() and 0xFF
            if (len == 0) break
            if ((len and 0xC0) == 0xC0) {
                // Compression pointer
                break
            }
            if (offset + len > dnsPayload.size) break

            if (!first) sb.append(".")
            first = false

            for (i in 0 until len) {
                sb.append(dnsPayload[offset + i].toInt().toChar())
            }
            offset += len
        }

        return sb.toString().lowercase()
    }

    fun buildSyntheticNxDomain(rawBuffer: ByteArray, bytesRead: Int): ByteArray {
        val out = ByteArray(bytesRead)
        System.arraycopy(rawBuffer, 0, out, 0, bytesRead)

        // Swap IP source and dest
        for (i in 0 until 4) {
            val tmp = out[12 + i]
            out[12 + i] = out[16 + i]
            out[16 + i] = tmp
        }

        val ipHeaderLen = (out[0].toInt() and 0x0F) * 4

        // Swap UDP ports
        val srcPortHigh = out[ipHeaderLen]
        val srcPortLow = out[ipHeaderLen + 1]
        out[ipHeaderLen] = out[ipHeaderLen + 2]
        out[ipHeaderLen + 1] = out[ipHeaderLen + 3]
        out[ipHeaderLen + 2] = srcPortHigh
        out[ipHeaderLen + 3] = srcPortLow

        // Zero out UDP checksum
        out[ipHeaderLen + 6] = 0
        out[ipHeaderLen + 7] = 0

        val dnsOffset = ipHeaderLen + 8
        if (dnsOffset + 4 <= bytesRead) {
            // Set QR=1, RCODE=3 (NXDOMAIN)
            out[dnsOffset + 2] = 0x81.toByte()
            out[dnsOffset + 3] = 0x83.toByte()
            // ANCOUNT = 0
            out[dnsOffset + 6] = 0
            out[dnsOffset + 7] = 0
        }

        return out
    }

    fun buildUdpPacket(rawBuffer: ByteArray, rawLength: Int, dnsPayload: ByteArray, dnsPayloadLen: Int): ByteArray {
        val ipHeaderLen = (rawBuffer[0].toInt() and 0x0F) * 4
        val totalLength = ipHeaderLen + 8 + dnsPayloadLen
        val out = ByteArray(totalLength)

        // Copy IP Header
        System.arraycopy(rawBuffer, 0, out, 0, ipHeaderLen)

        // Set IP Total Length
        out[2] = ((totalLength shr 8) and 0xFF).toByte()
        out[3] = (totalLength and 0xFF).toByte()

        // Swap IP Addresses
        for (i in 0 until 4) {
            out[12 + i] = rawBuffer[16 + i]
            out[16 + i] = rawBuffer[12 + i]
        }

        // Swap UDP Ports
        out[ipHeaderLen] = rawBuffer[ipHeaderLen + 2]
        out[ipHeaderLen + 1] = rawBuffer[ipHeaderLen + 3]
        out[ipHeaderLen + 2] = rawBuffer[ipHeaderLen]
        out[ipHeaderLen + 3] = rawBuffer[ipHeaderLen + 1]

        // UDP Length
        val udpLength = 8 + dnsPayloadLen
        out[ipHeaderLen + 4] = ((udpLength shr 8) and 0xFF).toByte()
        out[ipHeaderLen + 5] = (udpLength and 0xFF).toByte()

        // UDP Checksum = 0
        out[ipHeaderLen + 6] = 0
        out[ipHeaderLen + 7] = 0

        // Copy DNS payload
        System.arraycopy(dnsPayload, 0, out, ipHeaderLen + 8, dnsPayloadLen)

        return out
    }
}
