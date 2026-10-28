"""
FocusDNS Engine - RFC 8900 & RFC 6891 PMTU & Truncation Subsystem
Standards & RFCs:
- RFC 8900: IP Fragmentation Considered Fragile
- RFC 6891: Extension Mechanisms for DNS (EDNS(0)) - Buffer Size Negotiation
- RFC 7766: DNS Transport over TCP - Implementation Requirements
- DNS Flag Day 2020: 1232-byte UDP Buffer Size Standard
"""

import socket
import threading
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from dnslib import DNSRecord, EDNSOption, QTYPE, RR


# Standards-recommended MTU and buffer limits
DEFAULT_FLAG_DAY_BUFFER_SIZE = 1232  # DNS Flag Day standard (1280 IPv6 MTU - 48B header)
LEGACY_UDP_MAX_SIZE = 512            # RFC 1035 legacy limit
MAX_EDNS_BUFFER_SIZE = 4096          # RFC 6891 maximum practical buffer
IPV4_MIN_MTU = 576                   # RFC 791 minimum MTU
IPV6_MIN_MTU = 1280                  # RFC 8200 minimum MTU


class PMTUConfig:
    """Configuration for Path MTU buffer clamping and truncation policy."""

    def __init__(
        self,
        max_udp_payload: int = DEFAULT_FLAG_DAY_BUFFER_SIZE,
        enforce_flag_day_limit: bool = True,
        strip_on_truncation: bool = True,
        max_tcp_clients: int = 1000,
        tcp_idle_timeout_sec: float = 10.0,
    ):
        self.max_udp_payload: int = max_udp_payload
        self.enforce_flag_day_limit: bool = enforce_flag_day_limit
        self.strip_on_truncation: bool = strip_on_truncation
        self.max_tcp_clients: int = max_tcp_clients
        self.tcp_idle_timeout_sec: float = tcp_idle_timeout_sec


class PMTUManager:
    """
    Evaluates DNS wire message sizes against Path MTU and client EDNS advertised limits.
    Prevents IP packet fragmentation by enforcing RFC 8900 compliant truncation (TC=1)
    and steering oversized responses to TCP.
    """

    def __init__(self, config: Optional[PMTUConfig] = None):
        self.config: PMTUConfig = config or PMTUConfig()
        self.truncation_count: int = 0
        self.udp_evaluated: int = 0
        self.tcp_evaluated: int = 0
        self.oversized_dropped: int = 0
        self._lock = threading.Lock()

    def determine_effective_payload_limit(
        self, query_msg: Optional[DNSRecord], is_ipv6: bool = False
    ) -> int:
        """
        Calculates the maximum permissible UDP payload size for a given transaction.
        Checks client's EDNS OPT record buffer size and clamps to local PMTU limit.
        """
        advertised = LEGACY_UDP_MAX_SIZE

        # Check for EDNS(0) OPT pseudo-record
        if query_msg and hasattr(query_msg, "ar"):
            for rr in query_msg.ar:
                if rr.rtype == QTYPE.OPT:
                    # In dnslib, rr.rclass holds the requestor's EDNS UDP payload size
                    if rr.rclass > 0:
                        advertised = rr.rclass
                    break

        # Apply DNS Flag Day and local PMTU clamping
        effective = advertised
        if self.config.enforce_flag_day_limit:
            effective = min(effective, self.config.max_udp_payload)

        # Sanity bounds check
        if is_ipv6:
            effective = min(effective, IPV6_MIN_MTU - 48)  # IPv6 header (40) + UDP (8)
        return max(LEGACY_UDP_MAX_SIZE, min(effective, MAX_EDNS_BUFFER_SIZE))

    def evaluate_response(
        self,
        query_msg: Optional[DNSRecord],
        response_msg: DNSRecord,
        is_tcp: bool = False,
        is_ipv6: bool = False,
    ) -> Tuple[DNSRecord, bool]:
        """
        Evaluates packed wire response against PMTU constraints.
        Returns: (processed_response_record, was_truncated: bool)
        """
        if is_tcp:
            with self._lock:
                self.tcp_evaluated += 1
            return response_msg, False

        with self._lock:
            self.udp_evaluated += 1

        limit = self.determine_effective_payload_limit(query_msg, is_ipv6=is_ipv6)

        try:
            wire_bytes = response_msg.pack()
        except Exception:
            return response_msg, False

        if len(wire_bytes) <= limit:
            return response_msg, False

        # Message exceeds limit: RFC 8900 Truncation Trigger
        with self._lock:
            self.truncation_count += 1

        # Build truncated response
        truncated_msg = DNSRecord()
        truncated_msg.header = response_msg.header
        truncated_msg.header.tc = 1  # Truncated flag set

        # Preserve question section
        truncated_msg.questions = response_msg.questions

        if not self.config.strip_on_truncation:
            # Retain records that fit within limit
            current_size = len(truncated_msg.pack())
            for rr in response_msg.rr:
                truncated_msg.add_answer(rr)
                if len(truncated_msg.pack()) > limit:
                    # Exceeded; roll back last record and break
                    truncated_msg.rr.pop()
                    break
        # else: RFC 2181 §9 recommended practice: omit answers so client instantly falls back to TCP

        return truncated_msg, True

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            rate = (self.truncation_count / self.udp_evaluated * 100.0) if self.udp_evaluated > 0 else 0.0
            return {
                "max_udp_payload_configured": self.config.max_udp_payload,
                "enforce_flag_day_limit": self.config.enforce_flag_day_limit,
                "udp_packets_evaluated": self.udp_evaluated,
                "tcp_packets_evaluated": self.tcp_evaluated,
                "truncation_events": self.truncation_count,
                "truncation_rate_percent": round(rate, 2),
            }


class TCPFallbackClient:
    """Tracks state and rate metrics for a single TCP fallback connection."""

    def __init__(self, client_ip: str):
        self.client_ip: str = client_ip
        self.connected_at: float = time.time()
        self.last_active: float = self.connected_at
        self.queries_served: int = 0

    def touch(self):
        self.last_active = time.time()
        self.queries_served += 1


class TCPFallbackManager:
    """
    Manages client TCP fallback connections following a TC=1 truncation event.
    Defends against TCP connection exhaustion and slow-loris attacks per RFC 7766 §9.
    """

    def __init__(self, max_concurrent: int = 1000, idle_timeout: float = 10.0):
        self.max_concurrent: int = max_concurrent
        self.idle_timeout: float = idle_timeout
        self._active_clients: Dict[str, TCPFallbackClient] = {}
        self._lock = threading.Lock()
        self.total_tcp_connections: int = 0
        self.rejected_connections: int = 0

    def register_client(self, client_ip: str) -> bool:
        """Registers a new TCP client; rejects if connection capacity exceeded."""
        now = time.time()
        with self._lock:
            self._purge_stale(now)

            if len(self._active_clients) >= self.max_concurrent:
                self.rejected_connections += 1
                return False

            self._active_clients[client_ip] = TCPFallbackClient(client_ip)
            self.total_tcp_connections += 1
            return True

    def record_query(self, client_ip: str):
        with self._lock:
            if client_ip in self._active_clients:
                self._active_clients[client_ip].touch()

    def release_client(self, client_ip: str):
        with self._lock:
            self._active_clients.pop(client_ip, None)

    def _purge_stale(self, now: float):
        """Purges connections exceeding the RFC 7766 idle timeout."""
        stale_ips = [
            ip for ip, client in self._active_clients.items()
            if (now - client.last_active) > self.idle_timeout
        ]
        for ip in stale_ips:
            del self._active_clients[ip]

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "active_tcp_connections": len(self._active_clients),
                "total_tcp_connections": self.total_tcp_connections,
                "rejected_connections": self.rejected_connections,
                "idle_timeout_seconds": self.idle_timeout,
            }
