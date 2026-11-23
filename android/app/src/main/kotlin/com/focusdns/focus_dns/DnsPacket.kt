package com.focusdns.focus_dns

/** Minimal IPv4/UDP/DNS helpers for the local DNS-only VPN. */
object DnsPacket {
    class Query(
        val ipHeaderLen: Int, val srcIp: ByteArray, val dstIp: ByteArray,
        val srcPort: Int, val dstPort: Int, val dns: ByteArray
    )

    private fun u16(b: ByteArray, i: Int) = ((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)

    /** Returns the UDP/53 query inside an IPv4 packet, or null for anything else. */
    fun parseUdpDns(p: ByteArray, len: Int): Query? {
        if (len < 28) return null
        if ((p[0].toInt() shr 4) != 4) return null
        val ihl = (p[0].toInt() and 0x0F) * 4
        if (ihl < 20 || len < ihl + 8) return null
        if ((p[9].toInt() and 0xFF) != 17) return null
        val srcPort = u16(p, ihl)
        val dstPort = u16(p, ihl + 2)
        if (dstPort != 53) return null
        val udpLen = u16(p, ihl + 4)
        val end = minOf(len, ihl + udpLen)
        if (end <= ihl + 8) return null
        return Query(
            ihl, p.copyOfRange(12, 16), p.copyOfRange(16, 20), srcPort, dstPort,
            p.copyOfRange(ihl + 8, end)
        )
    }

    /** Reads the first question name (lowercase, dot separated) and its type. */
    fun questionName(dns: ByteArray): Pair<String, Int>? {
        if (dns.size < 13) return null
        var i = 12
        val sb = StringBuilder()
        while (i < dns.size) {
            val l = dns[i].toInt() and 0xFF
            if (l == 0) { i++; break }
            if (l and 0xC0 != 0) return null
            if (i + 1 + l > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 1..l) sb.append((dns[i + k].toInt() and 0xFF).toChar())
            i += 1 + l
        }
        if (i + 4 > dns.size) return null
        return Pair(sb.toString().lowercase(), u16(dns, i))
    }

    /** NXDOMAIN reply that echoes the question. */
    fun nxdomain(query: ByteArray): ByteArray {
        val r = query.copyOf()
        r[2] = (0x81).toByte()          // QR=1, RD=1
        r[3] = (0x83).toByte()          // RA=1, RCODE=3
        r[6] = 0; r[7] = 0              // ANCOUNT
        r[8] = 0; r[9] = 0              // NSCOUNT
        r[10] = 0; r[11] = 0            // ARCOUNT
        return r
    }

    fun servfail(query: ByteArray): ByteArray {
        val r = nxdomain(query)
        r[3] = (0x82).toByte()
        return r
    }

    /** Crafts a DNS answer pointing directly to an IPv4 VIP (e.g. for SafeSearch). */
    fun answerA(query: ByteArray, ipBytes: ByteArray): ByteArray {
        val total = query.size + 16
        val r = ByteArray(total)
        System.arraycopy(query, 0, r, 0, query.size)
        r[2] = 0x81.toByte() // QR=1, RD=1
        r[3] = 0x80.toByte() // RA=1, RCODE=0 (NOERROR)
        r[6] = 0; r[7] = 1   // ANCOUNT = 1
        r[8] = 0; r[9] = 0   // NSCOUNT = 0
        r[10] = 0; r[11] = 0 // ARCOUNT = 0

        val o = query.size
        r[o] = 0xC0.toByte(); r[o + 1] = 0x0C.toByte() // Pointer to question name
        r[o + 2] = 0; r[o + 3] = 1                     // Type A
        r[o + 4] = 0; r[o + 5] = 1                     // Class IN
        r[o + 6] = 0; r[o + 7] = 0; r[o + 8] = 0; r[o + 9] = 60 // TTL = 60s
        r[o + 10] = 0; r[o + 11] = 4                    // Data len = 4
        System.arraycopy(ipBytes, 0, r, o + 12, 4)
        return r
    }

    /** Wraps a DNS reply into an IPv4/UDP packet going back to the querying app. */
    fun buildReply(q: Query, dnsReply: ByteArray): ByteArray {
        val total = 20 + 8 + dnsReply.size
        val o = ByteArray(total)
        o[0] = 0x45.toByte()
        o[2] = (total shr 8).toByte(); o[3] = total.toByte()
        o[6] = 0x40.toByte()                 // DF
        o[8] = 64                            // TTL
        o[9] = 17                            // UDP
        System.arraycopy(q.dstIp, 0, o, 12, 4)  // src = DNS server ip
        System.arraycopy(q.srcIp, 0, o, 16, 4)  // dst = app ip
        var sum = 0
        for (i in 0 until 20 step 2) sum += ((o[i].toInt() and 0xFF) shl 8) or (o[i + 1].toInt() and 0xFF)
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        val ck = sum.inv() and 0xFFFF
        o[10] = (ck shr 8).toByte(); o[11] = ck.toByte()
        o[20] = (53 shr 8).toByte(); o[21] = 53
        o[22] = (q.srcPort shr 8).toByte(); o[23] = q.srcPort.toByte()
        val udpLen = 8 + dnsReply.size
        o[24] = (udpLen shr 8).toByte(); o[25] = udpLen.toByte()
        // UDP checksum 0 = not computed (valid for IPv4)
        System.arraycopy(dnsReply, 0, o, 28, dnsReply.size)
        return o
    }
}
