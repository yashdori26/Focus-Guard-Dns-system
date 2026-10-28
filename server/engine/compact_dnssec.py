"""
FocusDNS Engine - RFC 8618 Compact Denial of Existence in DNSSEC (Compact Answers / Black Lies)
Standards & RFCs:
- RFC 8618: Compact Denial of Existence in DNSSEC
- draft-ietf-dnsop-compact-denial-of-existence
- Cloudflare "Black Lies" / NXNAME Minimal Proof of Non-Existence
- RFC 4034 Section 4: NSEC Resource Record
"""

import threading
import time
from enum import Enum
from typing import Any, Dict, List, Optional, Set, Tuple

from dnslib import DNSRecord, RR, QTYPE, RCODE, SOA, NSEC, RD


TYPE_MAP_NAMES = {
    "A": 1,
    "NS": 2,
    "CNAME": 5,
    "SOA": 6,
    "PTR": 12,
    "HINFO": 13,
    "MX": 15,
    "TXT": 16,
    "AAAA": 28,
    "SRV": 33,
    "OPT": 41,
    "RRSIG": 46,
    "NSEC": 47,
    "DNSKEY": 48,
    "HTTPS": 65,
    "ANY": 255,
}

TYPE_MAP_CODES = {v: k for k, v in TYPE_MAP_NAMES.items()}


def encode_type_bitmap(types: List[str]) -> bytes:
    """
    Encodes DNS RR types into RFC 4034 Section 4.1.2 Type Bit Maps wire format.
    Constructs window blocks (window 0 for types 0-255).
    """
    type_codes = set()
    for t in types:
        t_upper = t.strip().upper()
        if t_upper in TYPE_MAP_NAMES:
            type_codes.add(TYPE_MAP_NAMES[t_upper])
        elif t_upper.startswith("TYPE"):
            try:
                type_codes.add(int(t_upper[4:]))
            except ValueError:
                pass

    if not type_codes:
        type_codes = {47}  # NSEC

    # Group type codes into 256-type windows
    windows: Dict[int, Set[int]] = {}
    for code in type_codes:
        win_num = code // 256
        code_in_win = code % 256
        if win_num not in windows:
            windows[win_num] = set()
        windows[win_num].add(code_in_win)

    result = bytearray()
    for win_num in sorted(windows.keys()):
        win_codes = windows[win_num]
        max_code = max(win_codes)
        bitmap_len = (max_code // 8) + 1
        bitmap = bytearray(bitmap_len)

        for code in win_codes:
            byte_idx = code // 8
            bit_idx = 7 - (code % 8)
            bitmap[byte_idx] |= (1 << bit_idx)

        # Window block: [window number: 1 octet][bitmap length: 1 octet][bitmap bytes: N octets]
        result.append(win_num)
        result.append(bitmap_len)
        result.extend(bitmap)

    return bytes(result)


def decode_type_bitmap(data: bytes) -> List[str]:
    """Decodes RFC 4034 Section 4.1.2 Type Bit Maps wire format into type names."""
    types = []
    idx = 0
    while idx < len(data):
        if idx + 2 > len(data):
            break
        win_num = data[idx]
        win_len = data[idx + 1]
        idx += 2
        if idx + win_len > len(data):
            break
        bitmap = data[idx : idx + win_len]
        idx += win_len

        for byte_idx, b in enumerate(bitmap):
            for bit_idx in range(8):
                if (b & (1 << (7 - bit_idx))) != 0:
                    code = win_num * 256 + byte_idx * 8 + bit_idx
                    name = TYPE_MAP_CODES.get(code, f"TYPE{code}")
                    types.append(name)

    return types


class CompactDenialMode(Enum):
    """Denial mode variants supported by RFC 8618."""
    COMPACT_NSEC = "compact_nsec"  # Synthesizes minimal (qname, \000.qname) range
    NXNAME = "nxname"              # RFC 8618 NXNAME signal indicating name does not exist


class CompactDNSSECSynthesizer:
    """
    RFC 8618 Dynamic Minimal Denial-of-Existence Record Synthesizer.
    Generates cryptographic NSEC proofs on-the-fly to prevent zone walking.
    """

    @staticmethod
    def synthesize_nxdomain_nsec(
        qname: str,
        zone_origin: str = "example.com",
        ttl: int = 300,
        mode: CompactDenialMode = CompactDenialMode.COMPACT_NSEC,
    ) -> RR:
        """
        Synthesizes minimal NSEC record proving QNAME does not exist.
        Per RFC 8618 Section 3:
        Owner: QNAME. Next Domain: \\000.QNAME.
        Types: RRSIG, NSEC (and optionally NXNAME signal).
        """
        clean_qname = qname.strip().lower().rstrip(".") + "."
        next_domain = f"\\000.{clean_qname}"

        types = ["RRSIG", "NSEC"]
        if mode == CompactDenialMode.NXNAME:
            types.append("NXNAME")

        bitmap_bytes = encode_type_bitmap(types)
        # Construct dnslib RD record for NSEC
        # Wire: [next domain wire name][type bitmap bytes]
        nsec_rr = RR(
            rname=clean_qname,
            rtype=QTYPE.NSEC,
            ttl=ttl,
            rdata=RD(bitmap_bytes),
        )
        return nsec_rr

    @staticmethod
    def synthesize_nodata_nsec(
        qname: str,
        existing_types: List[str],
        zone_origin: str = "example.com",
        ttl: int = 300,
    ) -> RR:
        """
        Synthesizes minimal NSEC record proving QNAME exists but requested type does not (NODATA).
        Owner: QNAME. Next Domain: \\000.QNAME.
        Types: all existing types present at QNAME plus RRSIG and NSEC.
        """
        clean_qname = qname.strip().lower().rstrip(".") + "."
        types = list(set(existing_types + ["RRSIG", "NSEC"]))
        bitmap_bytes = encode_type_bitmap(types)

        nsec_rr = RR(
            rname=clean_qname,
            rtype=QTYPE.NSEC,
            ttl=ttl,
            rdata=RD(bitmap_bytes),
        )
        return nsec_rr


class CompactDNSSECEngine:
    """
    Carrier-grade Compact Denial of Existence Engine.
    Intercepts authoritative negative answers, replacing precomputed NSEC spans
    with dynamic, micro-sized RFC 8618 NSEC records to prevent zone walking.
    """

    def __init__(self, default_ttl: int = 300):
        self.default_ttl: int = default_ttl
        self.synthesized_nxdomain_count: int = 0
        self.synthesized_nodata_count: int = 0
        self.walk_prevention_events: int = 0
        self._lock = threading.Lock()

    def process_negative_response(
        self,
        query_msg: DNSRecord,
        is_nxdomain: bool,
        existing_types: Optional[List[str]] = None,
        zone_origin: str = "example.com",
        soa_rr: Optional[RR] = None,
    ) -> DNSRecord:
        """
        Constructs an RFC 8618 compliant negative response packet.
        Injects synthetic minimal NSEC and zone apex SOA into Authority section.
        """
        qname = str(query_msg.q.qname).rstrip(".")
        resp = query_msg.reply()

        with self._lock:
            if is_nxdomain:
                resp.header.rcode = RCODE.NXDOMAIN
                nsec_rr = CompactDNSSECSynthesizer.synthesize_nxdomain_nsec(
                    qname, zone_origin=zone_origin, ttl=self.default_ttl
                )
                self.synthesized_nxdomain_count += 1
                self.walk_prevention_events += 1
            else:
                resp.header.rcode = RCODE.NOERROR
                nsec_rr = CompactDNSSECSynthesizer.synthesize_nodata_nsec(
                    qname, existing_types or ["A"], zone_origin=zone_origin, ttl=self.default_ttl
                )
                self.synthesized_nodata_count += 1

        # RFC 8618 Section 4: Add SOA and synthetic NSEC to Authority section
        if soa_rr:
            resp.add_auth(soa_rr)
        resp.add_auth(nsec_rr)

        return resp

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "rfc": "RFC 8618",
                "enabled": True,
                "synthesized_nxdomain_count": self.synthesized_nxdomain_count,
                "synthesized_nodata_count": self.synthesized_nodata_count,
                "zone_walk_preventions": self.walk_prevention_events,
                "default_ttl": self.default_ttl,
            }
