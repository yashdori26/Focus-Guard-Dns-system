"""
FocusDNS Engine - RFC 8482 Stop-ANY Amplification Defense Subsystem
Standards & RFCs:
- RFC 8482: Providing Minimal-Sized Responses to DNS Queries with QTYPE=ANY
- RFC 1035: Domain Names - Implementation and Specification (QTYPE 255 / ANY)
- Cloudflare & IETF "Stop using ANY" Best Current Practice
"""

import ipaddress
import struct
import threading
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from dnslib import DNSRecord, RR, QTYPE, RCODE, SOA, RD, RDMAP


class HINFO(RD):
    """
    RFC 1035 Section 3.3.2 Host Information (HINFO) Resource Record.
    Binary wire format: <len><cpu_bytes><len><os_bytes>
    """

    def __init__(self, cpu: Union[str, bytes] = "RFC8482", os_text: Union[str, bytes] = ""):
        self.cpu_bytes: bytes = cpu.encode("utf-8") if isinstance(cpu, str) else cpu
        self.os_bytes: bytes = os_text.encode("utf-8") if isinstance(os_text, str) else os_text
        self.cpu: str = self.cpu_bytes.decode(errors="replace")
        self.os: str = self.os_bytes.decode(errors="replace")
        payload = struct.pack(
            f"!B{len(self.cpu_bytes)}sB{len(self.os_bytes)}s",
            len(self.cpu_bytes),
            self.cpu_bytes,
            len(self.os_bytes),
            self.os_bytes,
        )
        super().__init__(payload)

    @classmethod
    def parse(cls, buffer, length=0):
        cpu_len = buffer.unpack("!B")[0]
        cpu = buffer.get(cpu_len)
        os_len = buffer.unpack("!B")[0]
        os_text = buffer.get(os_len)
        return cls(cpu, os_text)

    def toZone(self):
        return f'"{self.cpu.decode(errors="replace")}" "{self.os.decode(errors="replace")}"'

    def __repr__(self):
        return f"<HINFO: cpu='{self.cpu.decode(errors='replace')}' os='{self.os.decode(errors='replace')}'>"


# Register HINFO in dnslib RDMAP for standard packaging
RDMAP["HINFO"] = HINFO
RDMAP[13] = HINFO


class ANYResponseMode(Enum):
    """Supported RFC 8482 compliance response modes."""
    HINFO_STANDARD = "hinfo_standard"  # RFC 8482 Section 4.1 HINFO "RFC8482" ""
    SINGLE_RRSET = "single_rrset"      # RFC 8482 Section 4.2 Single arbitrary RRset
    REFUSE = "refuse"                  # Returns RCODE REFUSED


class RFC8482Policy:
    """Configurable security policy for handling QTYPE=ANY queries."""

    def __init__(
        self,
        mode: ANYResponseMode = ANYResponseMode.HINFO_STANDARD,
        hinfo_cpu: str = "RFC8482",
        hinfo_os: str = "",
        ttl: int = 3600,
        whitelisted_cidrs: Optional[List[str]] = None,
    ):
        self.mode: ANYResponseMode = mode
        self.hinfo_cpu: str = hinfo_cpu
        self.hinfo_os: str = hinfo_os
        self.ttl: int = ttl
        self.whitelisted_networks: List[Any] = []
        if whitelisted_cidrs:
            for cidr in whitelisted_cidrs:
                try:
                    self.whitelisted_networks.append(ipaddress.ip_network(cidr, strict=False))
                except ValueError:
                    pass

    def is_client_whitelisted(self, client_ip: str) -> bool:
        """Checks if client IP is permitted to receive full legacy ANY dumps."""
        if not self.whitelisted_networks:
            return False
        try:
            ip_obj = ipaddress.ip_address(client_ip)
            return any(ip_obj in net for net in self.whitelisted_networks)
        except ValueError:
            return False


class RFC8482Engine:
    """
    RFC 8482 Minimal ANY Query Response Interceptor.
    Completely neutralizes DNS reflection/amplification attacks targeting port 53
    by replacing multi-kilobyte ANY query dumps with micro-sized HINFO or single-record replies.
    """

    def __init__(self, policy: Optional[RFC8482Policy] = None):
        self.policy: RFC8482Policy = policy or RFC8482Policy()
        self.intercepted_count: int = 0
        self.hinfo_synthesized_count: int = 0
        self.refused_count: int = 0
        self.whitelisted_passthrough_count: int = 0
        self._lock = threading.Lock()

    @staticmethod
    def is_any_query(query_msg: DNSRecord) -> bool:
        """Determines if the inbound DNS message queries for QTYPE 255 (ANY)."""
        if not query_msg or not query_msg.questions:
            return False
        return query_msg.q.qtype == QTYPE.ANY

    def process_query(
        self,
        query_msg: DNSRecord,
        client_ip: str = "127.0.0.1",
        zone_soa: Optional[SOA] = None,
    ) -> Optional[DNSRecord]:
        """
        Intercepts ANY query.
        Returns synthesized minimal DNSRecord if intercepted, or None if whitelisted passthrough.
        """
        if not self.is_any_query(query_msg):
            return None

        with self._lock:
            self.intercepted_count += 1

            if self.policy.is_client_whitelisted(client_ip):
                self.whitelisted_passthrough_count += 1
                return None  # Let query proceed to normal full-zone resolution

            qname = str(query_msg.q.qname)
            resp = query_msg.reply()

            if self.policy.mode == ANYResponseMode.HINFO_STANDARD:
                # RFC 8482 §4.1: Synthesize HINFO "RFC8482" ""
                hinfo_rr = RR(
                    rname=qname,
                    rtype=QTYPE.HINFO,
                    ttl=self.policy.ttl,
                    rdata=HINFO(self.policy.hinfo_cpu, self.policy.hinfo_os),
                )
                resp.add_answer(hinfo_rr)
                resp.header.rcode = RCODE.NOERROR
                self.hinfo_synthesized_count += 1
                return resp

            elif self.policy.mode == ANYResponseMode.REFUSE:
                resp.header.rcode = RCODE.REFUSED
                self.refused_count += 1
                return resp

            elif self.policy.mode == ANYResponseMode.SINGLE_RRSET:
                # RFC 8482 §4.2: Return single arbitrary RRset (SOA or TXT notice)
                if zone_soa:
                    resp.add_answer(RR(qname, QTYPE.SOA, ttl=self.policy.ttl, rdata=zone_soa))
                else:
                    resp.add_answer(RR(qname, QTYPE.HINFO, ttl=self.policy.ttl, rdata=HINFO("RFC8482", "")))
                resp.header.rcode = RCODE.NOERROR
                return resp

        return None

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "rfc": "RFC 8482",
                "mode": self.policy.mode.value,
                "total_any_queries_intercepted": self.intercepted_count,
                "hinfo_synthesized": self.hinfo_synthesized_count,
                "refused": self.refused_count,
                "whitelisted_passthrough": self.whitelisted_passthrough_count,
            }
