"""
FocusDNS Engine - DNS Traffic Replay & PCAP Dissector Subsystem
Standards & File Formats:
- Libpcap 2.4 Wire Capture Specification (Standard .pcap format)
- Ethernet II, IPv4, UDP Layer Dissection
- High-Performance Production Traffic Replay & Stress Testing Harness
"""

import io
import socket
import struct
import threading
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

from dnslib import DNSRecord, DNSQuestion, QTYPE


# Libpcap 2.4 Standard Magic & Constants
PCAP_MAGIC_MICROSECONDS = 0xA1B2C3D4
PCAP_MAGIC_NANOSECONDS = 0xA1B23C4D
PCAP_MAGIC_SWAPPED = 0xD4C3B2A1

LINKTYPE_ETHERNET = 1


class PCAPPacket:
    """Represents a single captured packet frame parsed from a PCAP file."""

    def __init__(
        self,
        timestamp_sec: int,
        timestamp_usec: int,
        orig_len: int,
        data: bytes,
        dns_payload: Optional[bytes] = None,
        src_ip: str = "127.0.0.1",
        dst_ip: str = "127.0.0.1",
        src_port: int = 5354,
        dst_port: int = 5354,
        protocol: str = "UDP",
    ):
        self.timestamp_sec: int = timestamp_sec
        self.timestamp_usec: int = timestamp_usec
        self.orig_len: int = orig_len
        self.data: bytes = data
        self.dns_payload: Optional[bytes] = dns_payload
        self.src_ip: str = src_ip
        self.dst_ip: str = dst_ip
        self.src_port: int = src_port
        self.dst_port: int = dst_port
        self.protocol: str = protocol

    @property
    def timestamp(self) -> float:
        return self.timestamp_sec + (self.timestamp_usec / 1e6)


class PCAPDissector:
    """
    Parses and dissects standard PCAP files into Ethernet, IPv4, UDP, and DNS payloads.
    Provides pure Python wire parsing without native libpcap C bindings.
    """

    @classmethod
    def parse_stream(cls, stream: io.BytesIO) -> List[PCAPPacket]:
        """Parses all packets from an open PCAP byte stream."""
        # Read 24-byte PCAP file header
        global_header = stream.read(24)
        if len(global_header) < 24:
            raise ValueError("Invalid PCAP file: header too short")

        magic = struct.unpack("!I", global_header[:4])[0]
        is_little_endian = (magic in (0xD4C3B2A1, 0x4D3CB2A1))
        endian_fmt = "<" if is_little_endian else ">"

        magic, v_maj, v_min, tz, sigfigs, snaplen, linktype = struct.unpack(
            f"{endian_fmt}IHHiIII", global_header
        )

        packets: List[PCAPPacket] = []

        while True:
            # Read 16-byte packet record header: [ts_sec: 4][ts_usec: 4][incl_len: 4][orig_len: 4]
            pkt_hdr = stream.read(16)
            if len(pkt_hdr) < 16:
                break

            ts_sec, ts_usec, incl_len, orig_len = struct.unpack(f"{endian_fmt}IIII", pkt_hdr)
            pkt_data = stream.read(incl_len)
            if len(pkt_data) < incl_len:
                break

            # Dissect packet layers
            parsed = cls._dissect_packet(ts_sec, ts_usec, orig_len, pkt_data, linktype)
            if parsed:
                packets.append(parsed)

        return packets

    @classmethod
    def _dissect_packet(
        cls, ts_sec: int, ts_usec: int, orig_len: int, data: bytes, linktype: int
    ) -> Optional[PCAPPacket]:
        """Dissects L2 Ethernet, L3 IPv4, and L4 UDP to extract DNS payload."""
        offset = 0

        # Layer 2: Ethernet II (14 octets)
        if linktype == LINKTYPE_ETHERNET:
            if len(data) < 14:
                return None
            ethertype = struct.unpack("!H", data[12:14])[0]
            offset = 14
            # Handle 802.1Q VLAN Tagging (0x8100)
            if ethertype == 0x8100:
                if len(data) < 18:
                    return None
                ethertype = struct.unpack("!H", data[16:18])[0]
                offset = 18

            if ethertype != 0x0800:  # Not IPv4
                return None

        # Layer 3: IPv4 Header (minimum 20 octets)
        if len(data) - offset < 20:
            return None

        v_ihl = data[offset]
        ihl = (v_ihl & 0x0F) * 4
        if ihl < 20 or len(data) - offset < ihl:
            return None

        proto = data[offset + 9]
        src_ip = socket.inet_ntoa(data[offset + 12 : offset + 16])
        dst_ip = socket.inet_ntoa(data[offset + 16 : offset + 20])
        offset += ihl

        # Layer 4: UDP (8 octets)
        dns_payload = None
        src_port = 0
        dst_port = 0
        protocol_str = "OTHER"

        if proto == 17:  # UDP
            protocol_str = "UDP"
            if len(data) - offset >= 8:
                src_port, dst_port, udp_len = struct.unpack("!HHH", data[offset : offset + 6])
                offset += 8
                dns_payload = data[offset : offset + (udp_len - 8)]
        elif proto == 6:  # TCP
            protocol_str = "TCP"
            if len(data) - offset >= 20:
                src_port, dst_port = struct.unpack("!HH", data[offset : offset + 4])
                tcp_data_offset = ((data[offset + 12] >> 4) & 0x0F) * 4
                offset += tcp_data_offset
                if len(data) - offset >= 2:
                    # TCP DNS 2-octet length prefix
                    msg_len = struct.unpack("!H", data[offset : offset + 2])[0]
                    offset += 2
                    dns_payload = data[offset : offset + msg_len]

        return PCAPPacket(
            timestamp_sec=ts_sec,
            timestamp_usec=ts_usec,
            orig_len=orig_len,
            data=data,
            dns_payload=dns_payload,
            src_ip=src_ip,
            dst_ip=dst_ip,
            src_port=src_port,
            dst_port=dst_port,
            protocol=protocol_str,
        )

    @classmethod
    def generate_synthetic_pcap(
        cls,
        domains: List[str],
        qtype: str = "A",
        src_ip: str = "192.0.2.10",
        dst_ip: str = "127.0.0.1",
        dst_port: int = 5354,
    ) -> bytes:
        """Generates a valid, standards-compliant binary PCAP file for testing."""
        buf = io.BytesIO()

        # Write 24-octet PCAP global header
        buf.write(
            struct.pack(
                "!IHHiIII",
                PCAP_MAGIC_MICROSECONDS,
                2,  # v_major
                4,  # v_minor
                0,  # tz
                0,  # sigfigs
                65535,  # snaplen
                LINKTYPE_ETHERNET,  # linktype
            )
        )

        base_time = int(time.time())

        for idx, domain in enumerate(domains):
            q_code = getattr(QTYPE, qtype, 1) if isinstance(qtype, str) else int(qtype)
            req = DNSRecord(q=DNSQuestion(domain, q_code))
            dns_bytes = req.pack()

            # Build L4 UDP (8 bytes)
            udp_hdr = struct.pack("!HHHH", 49152 + idx, dst_port, 8 + len(dns_bytes), 0)

            # Build L3 IPv4 (20 bytes)
            total_ip_len = 20 + 8 + len(dns_bytes)
            ip_hdr = struct.pack(
                "!BBHHHBBH4s4s",
                0x45,  # v=4, ihl=5
                0,     # tos
                total_ip_len,
                idx,   # id
                0x4000,  # DF flag
                64,    # ttl
                17,    # UDP
                0,     # checksum
                socket.inet_aton(src_ip),
                socket.inet_aton(dst_ip),
            )

            # Build L2 Ethernet (14 bytes)
            eth_hdr = b"\x00\x00\x5e\x00\x53\x01\x00\x00\x5e\x00\x53\x02\x08\x00"

            full_frame = eth_hdr + ip_hdr + udp_hdr + dns_bytes
            frame_len = len(full_frame)

            # Write 16-byte record header + frame
            ts_usec = (idx * 5000) % 1000000
            buf.write(struct.pack("!IIII", base_time + (idx // 200), ts_usec, frame_len, frame_len))
            buf.write(full_frame)

        return buf.getvalue()


class TrafficReplayEngine:
    """
    Carrier traffic replay and load simulation harness.
    Replays recorded PCAP packet sequences against an in-memory or networked DNS endpoint.
    Computes real-time throughput, packet loss, and latency percentiles.
    """

    def __init__(
        self,
        target_handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        speed_multiplier: float = 1.0,
    ):
        self.target_handler = target_handler
        self.speed_multiplier: float = speed_multiplier
        self.total_replayed: int = 0
        self.successful_responses: int = 0
        self.failed_responses: int = 0
        self.latencies_ms: List[float] = []
        self._lock = threading.Lock()

    def replay_packets(self, packets: List[PCAPPacket]) -> Dict[str, Any]:
        """Replays a sequence of PCAPPacket instances sequentially or accelerated."""
        start_time = time.time()

        for pkt in packets:
            if not pkt.dns_payload:
                continue

            with self._lock:
                self.total_replayed += 1

            t0 = time.perf_counter()
            success = False

            if self.target_handler:
                try:
                    reply_bytes, meta = self.target_handler(pkt.dns_payload, pkt.src_ip)
                    if reply_bytes and len(reply_bytes) > 0:
                        success = True
                except Exception:
                    success = False

            elapsed_ms = (time.perf_counter() - t0) * 1000.0

            with self._lock:
                if success:
                    self.successful_responses += 1
                    self.latencies_ms.append(elapsed_ms)
                else:
                    self.failed_responses += 1

        total_elapsed = time.time() - start_time
        qps = (self.total_replayed / total_elapsed) if total_elapsed > 0 else 0.0

        return self._compute_summary(total_elapsed, qps)

    def _compute_summary(self, elapsed_sec: float, qps: float) -> Dict[str, Any]:
        with self._lock:
            lats = sorted(self.latencies_ms) if self.latencies_ms else [0.0]
            count = len(lats)
            p50 = lats[int(count * 0.50)]
            p90 = lats[int(count * 0.90)]
            p99 = lats[min(int(count * 0.99), count - 1)]
            loss = (self.failed_responses / self.total_replayed * 100.0) if self.total_replayed > 0 else 0.0

            return {
                "total_packets_replayed": self.total_replayed,
                "successful_responses": self.successful_responses,
                "failed_responses": self.failed_responses,
                "packet_loss_percent": round(loss, 2),
                "duration_seconds": round(elapsed_sec, 3),
                "sustained_qps": round(qps, 1),
                "latency_p50_ms": round(p50, 3),
                "latency_p90_ms": round(p90, 3),
                "latency_p99_ms": round(p99, 3),
            }
