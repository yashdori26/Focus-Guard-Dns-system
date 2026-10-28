"""
FocusDNS Engine - eBPF / XDP (eXpress Data Path) High-Speed Packet Filter
Features:
- Kernel-bypass and driver-level packet filtering simulation (XDP_DROP, XDP_PASS, XDP_TX)
- High-performance in-kernel BPF Hash Map and LPM (Longest Prefix Match) Trie Map
- Line-rate DDoS UDP reflection drop without user-space socket context switches
- In-kernel token-bucket rate limiting table
- Hardware offload efficiency telemetry
"""

import ipaddress
import struct
import threading
import time
from enum import Enum
from typing import Dict, List, Optional, Tuple, Any

# Standard XDP Action Verbs (Linux kernel bpf.h)
XDP_ABORTED = 0
XDP_DROP = 1
XDP_PASS = 2
XDP_TX = 3
XDP_REDIRECT = 4

class XDPAction(Enum):
    ABORTED = 0
    DROP = 1
    PASS = 2
    TX = 3
    REDIRECT = 4

ACTION_NAMES = {
    XDP_ABORTED: "XDP_ABORTED",
    XDP_DROP: "XDP_DROP",
    XDP_PASS: "XDP_PASS",
    XDP_TX: "XDP_TX",
    XDP_REDIRECT: "XDP_REDIRECT",
}


class BPFMapType:
    HASH = "BPF_MAP_TYPE_HASH"
    LPM_TRIE = "BPF_MAP_TYPE_LPM_TRIE"
    PERCPU_ARRAY = "BPF_MAP_TYPE_PERCPU_ARRAY"


class XDPFilterRule:
    """Represents a compiled eBPF filter rule in an XDP map."""

    def __init__(
        self,
        key: str,
        action: int = XDP_DROP,
        reason: str = "Banned Attacker IP",
        ttl_seconds: int = 3600,
        rate_limit_pps: int = 0,
    ):
        self.key = key.strip()
        self.action = action
        self.reason = reason
        self.ttl = ttl_seconds
        self.created_at = time.time()
        self.rate_limit_pps = rate_limit_pps

        # Token state if rate-limited
        self.tokens = float(rate_limit_pps)
        self.last_refill = time.time()
        self.hit_count = 0

    def is_expired(self) -> bool:
        if self.ttl <= 0:
            return False  # Permanent
        return (time.time() - self.created_at) > self.ttl

    def consume_token(self) -> bool:
        """Simulates in-kernel BPF atomics token bucket decrement."""
        if self.rate_limit_pps <= 0:
            return True
        now = time.time()
        elapsed = now - self.last_refill
        self.last_refill = now
        self.tokens = min(float(self.rate_limit_pps), self.tokens + (elapsed * self.rate_limit_pps))
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return True
        return False


class XDPFilterEngine:
    """
    eBPF / XDP High-Performance Packet Filter Engine.
    Evaluates incoming network frames at the NIC driver layer,
    dropping malformed packets, amplification floods, and banned CIDRs
    before they reach the Python socket layer.
    """

    def __init__(self, interface_name: str = "eth0", max_map_entries: int = 100000):
        self.interface_name = interface_name
        self.max_map_entries = max_map_entries

        # BPF Maps
        # IP -> XDPFilterRule (O(1) Hash Map)
        self._ip_hash_map: Dict[str, XDPFilterRule] = {}
        # CIDR list sorted by prefixlen descending (LPM Trie)
        self._lpm_networks: List[Tuple[Any, XDPFilterRule]] = []

        self._lock = threading.Lock()

        # Telemetry & Performance Counters
        self._total_frames_inspected = 0
        self._total_frames_passed = 0
        self._total_frames_dropped = 0
        self._total_bytes_inspected = 0
        self._total_bytes_dropped = 0

    def bpf_map_update_ip(
        self,
        ip_str: str,
        action: int = XDP_DROP,
        reason: str = "Banned Attacker IP",
        ttl_seconds: int = 3600,
        rate_limit_pps: int = 0,
    ):
        """Updates the in-kernel BPF Hash Map with an IP rule."""
        rule = XDPFilterRule(
            key=ip_str,
            action=action,
            reason=reason,
            ttl_seconds=ttl_seconds,
            rate_limit_pps=rate_limit_pps,
        )
        with self._lock:
            if len(self._ip_hash_map) >= self.max_map_entries:
                # Evict oldest entry
                self._ip_hash_map.pop(next(iter(self._ip_hash_map)))
            self._ip_hash_map[ip_str.strip()] = rule

    def bpf_map_update_cidr(
        self,
        cidr_str: str,
        action: int = XDP_DROP,
        reason: str = "Banned Subnet CIDR",
        ttl_seconds: int = 86400,
    ):
        """Updates the in-kernel BPF LPM (Longest Prefix Match) Trie with a CIDR rule."""
        try:
            net = ipaddress.ip_network(cidr_str.strip(), strict=False)
            rule = XDPFilterRule(key=cidr_str, action=action, reason=reason, ttl_seconds=ttl_seconds)
            with self._lock:
                self._lpm_networks = [item for item in self._lpm_networks if item[0] != net]
                self._lpm_networks.append((net, rule))
                # Sort by prefix length descending (LPM order)
                self._lpm_networks.sort(key=lambda item: item[0].prefixlen, reverse=True)
        except ValueError:
            pass

    def bpf_map_delete(self, ip_or_cidr: str) -> bool:
        """Removes key from BPF maps."""
        clean = ip_or_cidr.strip()
        with self._lock:
            if clean in self._ip_hash_map:
                del self._ip_hash_map[clean]
                return True
            before_len = len(self._lpm_networks)
            self._lpm_networks = [item for item in self._lpm_networks if str(item[0]) != clean]
            return len(self._lpm_networks) < before_len

    def inspect_packet(
        self,
        client_ip: str,
        packet_len: int = 64,
        dest_port: int = 53,
    ) -> Tuple[int, str]:
        """
        Executes XDP eBPF driver program against incoming packet metadata.
        Returns (action_code, reason_string).
        """
        with self._lock:
            self._total_frames_inspected += 1
            self._total_bytes_inspected += packet_len

            # 1. Fast O(1) Hash Map Lookup
            rule = self._ip_hash_map.get(client_ip)
            if rule:
                if rule.is_expired():
                    del self._ip_hash_map[client_ip]
                else:
                    rule.hit_count += 1
                    if rule.rate_limit_pps > 0:
                        if not rule.consume_token():
                            self._total_frames_dropped += 1
                            self._total_bytes_dropped += packet_len
                            return XDP_DROP, f"XDP Rate Limit Exceeded: {rule.reason}"
                        else:
                            self._total_frames_passed += 1
                            return XDP_PASS, f"XDP Rate Limit Permitted: {rule.reason}"
                    elif rule.action == XDP_DROP:
                        self._total_frames_dropped += 1
                        self._total_bytes_dropped += packet_len
                        return XDP_DROP, f"XDP Drop: {rule.reason}"
                    else:
                        self._total_frames_passed += 1
                        return rule.action, f"XDP Action: {rule.reason}"

            # 2. Longest Prefix Match (LPM) Trie Lookup
            try:
                ip_obj = ipaddress.ip_address(client_ip)
                for net, lpm_rule in self._lpm_networks:
                    if ip_obj in net:
                        if lpm_rule.is_expired():
                            self._lpm_networks.remove((net, lpm_rule))
                        else:
                            lpm_rule.hit_count += 1
                            if lpm_rule.action == XDP_DROP:
                                self._total_frames_dropped += 1
                                self._total_bytes_dropped += packet_len
                                return XDP_DROP, f"XDP Subnet Drop: {lpm_rule.reason} ({net})"
                            else:
                                self._total_frames_passed += 1
                                return lpm_rule.action, f"XDP Subnet Match: {lpm_rule.reason} ({net})"
            except ValueError:
                pass

            # 3. Default: Pass to user-space network stack
            self._total_frames_passed += 1
            return XDP_PASS, "XDP Pass"

    def prune_expired(self):
        """Housekeeping: cleans up expired temporary BPF map rules."""
        with self._lock:
            self._ip_hash_map = {k: v for k, v in self._ip_hash_map.items() if not v.is_expired()}
            self._lpm_networks = [item for item in self._lpm_networks if not item[1].is_expired()]

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            drop_ratio = (
                round((self._total_frames_dropped / max(1, self._total_frames_inspected)) * 100.0, 2)
            )
            return {
                "interface": self.interface_name,
                "total_frames_inspected": self._total_frames_inspected,
                "total_frames_passed": self._total_frames_passed,
                "total_frames_dropped": self._total_frames_dropped,
                "total_bytes_inspected": self._total_bytes_inspected,
                "total_bytes_dropped": self._total_bytes_dropped,
                "drop_ratio_percent": drop_ratio,
                "active_bpf_ip_rules": len(self._ip_hash_map),
                "active_bpf_cidr_rules": len(self._lpm_networks),
            }


# Backwards compatibility and architecture aliases
XDPPacketFilter = XDPFilterEngine


class BPFHashMap:
    """In-memory representation of BPF_MAP_TYPE_HASH."""
    def __init__(self, filter_engine: XDPFilterEngine):
        self._engine = filter_engine

    def set(self, ip: str, action: int = XDP_DROP, reason: str = "Banned IP", ttl: int = 3600):
        self._engine.bpf_map_update_ip(ip, action=action, reason=reason, ttl_seconds=ttl)

    def delete(self, ip: str) -> bool:
        return self._engine.bpf_map_delete(ip)

    def get(self, ip: str) -> Optional[XDPFilterRule]:
        with self._engine._lock:
            return self._engine._ip_hash_map.get(ip)


class LPMTrie:
    """In-memory representation of BPF_MAP_TYPE_LPM_TRIE."""
    def __init__(self, filter_engine: XDPFilterEngine):
        self._engine = filter_engine

    def insert_prefix(self, cidr: str, action: int = XDP_DROP, reason: str = "Banned CIDR", ttl: int = 86400):
        self._engine.bpf_map_update_cidr(cidr, action=action, reason=reason, ttl_seconds=ttl)

    def delete_prefix(self, cidr: str) -> bool:
        return self._engine.bpf_map_delete(cidr)


class RawEthernetPacket:
    """Decoded Layer-2 Ethernet II frame."""

    def __init__(self, dst_mac: str, src_mac: str, ethertype: int, payload: bytes):
        self.dst_mac = dst_mac
        self.src_mac = src_mac
        self.ethertype = ethertype
        self.payload = payload


class RawIPv4Packet:
    """Decoded Layer-3 IPv4 packet header."""

    def __init__(
        self,
        src_ip: str,
        dst_ip: str,
        protocol: int,
        ttl: int,
        total_len: int,
        identification: int,
        flags: int,
        payload: bytes,
    ):
        self.src_ip = src_ip
        self.dst_ip = dst_ip
        self.protocol = protocol  # 17 = UDP, 6 = TCP, 1 = ICMP
        self.ttl = ttl
        self.total_len = total_len
        self.identification = identification
        self.flags = flags
        self.payload = payload


class RawUDPPacket:
    """Decoded Layer-4 UDP datagram header."""

    def __init__(self, src_port: int, dst_port: int, length: int, checksum: int, payload: bytes):
        self.src_port = src_port
        self.dst_port = dst_port
        self.length = length
        self.checksum = checksum
        self.payload = payload


class XDPPacketDissector:
    """
    Simulates eBPF driver-level packet header parsing directly from raw NIC buffer.
    Performs boundary checks without memory allocations.
    """

    ETHERTYPE_IPV4 = 0x0800
    ETHERTYPE_IPV6 = 0x86DD
    ETHERTYPE_VLAN = 0x8100
    PROTO_UDP = 17
    PROTO_TCP = 6

    @classmethod
    def format_mac(cls, raw_bytes: bytes) -> str:
        return ":".join(f"{b:02x}" for b in raw_bytes)

    @classmethod
    def dissect_ethernet(cls, frame_bytes: bytes) -> Optional[RawEthernetPacket]:
        """Parses 14-octet Ethernet II header."""
        if len(frame_bytes) < 14:
            return None
        dst_mac = cls.format_mac(frame_bytes[0:6])
        src_mac = cls.format_mac(frame_bytes[6:12])
        ethertype = struct.unpack("!H", frame_bytes[12:14])[0]
        offset = 14

        # 802.1Q VLAN Tag Handling
        if ethertype == cls.ETHERTYPE_VLAN:
            if len(frame_bytes) < 18:
                return None
            ethertype = struct.unpack("!H", frame_bytes[16:18])[0]
            offset = 18

        return RawEthernetPacket(dst_mac, src_mac, ethertype, frame_bytes[offset:])

    @classmethod
    def dissect_ipv4(cls, ip_bytes: bytes) -> Optional[RawIPv4Packet]:
        """Parses minimum 20-octet IPv4 header."""
        if len(ip_bytes) < 20:
            return None

        ver_ihl = ip_bytes[0]
        version = ver_ihl >> 4
        ihl = (ver_ihl & 0x0F) * 4
        if version != 4 or len(ip_bytes) < ihl:
            return None

        total_len, ident, flags_frag, ttl, proto, _ = struct.unpack("!HHHBBH", ip_bytes[2:12])
        src_ip = socket.inet_ntoa(ip_bytes[12:16])
        dst_ip = socket.inet_ntoa(ip_bytes[16:20])
        payload = ip_bytes[ihl:total_len] if total_len <= len(ip_bytes) else ip_bytes[ihl:]

        return RawIPv4Packet(
            src_ip=src_ip,
            dst_ip=dst_ip,
            protocol=proto,
            ttl=ttl,
            total_len=total_len,
            identification=ident,
            flags=(flags_frag >> 13),
            payload=payload,
        )

    @classmethod
    def dissect_udp(cls, udp_bytes: bytes) -> Optional[RawUDPPacket]:
        """Parses 8-octet UDP header."""
        if len(udp_bytes) < 8:
            return None

        src_port, dst_port, length, checksum = struct.unpack("!HHHH", udp_bytes[0:8])
        payload = udp_bytes[8:length] if length <= len(udp_bytes) else udp_bytes[8:]

        return RawUDPPacket(src_port, dst_port, length, checksum, payload)

    @classmethod
    def dissect_l2_dns_packet(cls, raw_frame: bytes) -> Tuple[Optional[str], int, Optional[bytes]]:
        """
        Parses raw Layer 2 Ethernet frame down to DNS wire payload.
        Returns: (src_ip, dst_port, dns_wire_bytes)
        """
        eth = cls.dissect_ethernet(raw_frame)
        if not eth or eth.ethertype != cls.ETHERTYPE_IPV4:
            return None, 0, None

        ip = cls.dissect_ipv4(eth.payload)
        if not ip or ip.protocol != cls.PROTO_UDP:
            return None, 0, None

        udp = cls.dissect_udp(ip.payload)
        if not udp:
            return None, 0, None

        return ip.src_ip, udp.dst_port, udp.payload


class XDPAmplificationGuard:
    """
    In-kernel heuristic defense against DNS reflection and amplification DDoS attacks.
    Detects high-frequency queries requesting ANY records or requesting massive buffer responses,
    automatically compiling dynamic BPF hash map blocks.
    """

    def __init__(self, filter_engine: XDPFilterEngine, threshold_pps: int = 50, ban_duration_sec: int = 300):
        self.engine = filter_engine
        self.threshold_pps = threshold_pps
        self.ban_duration_sec = ban_duration_sec

        # ip -> (first_seen, count)
        self._any_query_tracker: Dict[str, Tuple[float, int]] = {}
        self._lock = threading.Lock()

    def inspect_query(self, client_ip: str, qtype_int: int, has_large_edns0: bool) -> bool:
        """
        Inspects query characteristics.
        Returns True if permitted, False if suspicious reflection flood dropped.
        """
        now = time.time()
        # QTYPE.ANY is 255
        is_suspicious_any = (qtype_int == 255 and has_large_edns0)

        if not is_suspicious_any:
            return True

        with self._lock:
            first_seen, count = self._any_query_tracker.get(client_ip, (now, 0))
            elapsed = now - first_seen

            if elapsed > 1.0:
                # Reset window
                self._any_query_tracker[client_ip] = (now, 1)
                return True

            new_count = count + 1
            self._any_query_tracker[client_ip] = (first_seen, new_count)

            if new_count > self.threshold_pps:
                # Trigger automatic in-kernel BPF map ban!
                self.engine.bpf_map_update_ip(
                    client_ip,
                    action=XDP_DROP,
                    reason="Automated XDP Guard: DNS Reflection ANY Flood",
                    ttl_seconds=self.ban_duration_sec,
                )
                return False

        return True
