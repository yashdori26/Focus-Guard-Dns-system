"""
FocusDNS Engine - DNS64 & NAT64 IPv6-only Transition Subsystem
Standards & RFCs:
- RFC 6052: IPv6 Addressing of IPv4/IPv6 Translators
- RFC 6147: DNS64: DNS Extensions for Network Address Translation from IPv6 Clients to IPv4 Servers
- RFC 2317: Reverse DNS Mapping for IPv4 in IPv6 (ip6.arpa translation)
"""

import ipaddress
import re
import struct
import threading
from typing import Dict, List, Optional, Tuple, Any

from dnslib import (
    DNSRecord,
    DNSHeader,
    RR,
    QTYPE,
    RCODE,
    A,
    AAAA,
    PTR,
    SOA,
)

# RFC 6052 Well-Known Prefix (WKP)
DEFAULT_DNS64_PREFIX = "64:ff9b::/96"


def embed_ipv4_in_ipv6(ipv4_str: str, prefix_str: str = DEFAULT_DNS64_PREFIX) -> str:
    """
    Embeds 32-bit IPv4 address into IPv6 prefix according to RFC 6052.
    Supports standard prefix lengths: /32, /40, /48, /56, /64, /96.
    Notice: For prefixes shorter than /96, RFC 6052 §2.2 mandates octet 8 (bits 64-71)
    is reserved as zeros (the 'u' byte).
    """
    ip4 = ipaddress.IPv4Address(ipv4_str.strip())
    net6 = ipaddress.IPv6Network(prefix_str.strip(), strict=False)

    prefix_len = net6.prefixlen
    prefix_bytes = bytearray(net6.network_address.packed)
    v4_bytes = ip4.packed

    if prefix_len == 96:
        # IPv4 occupies bytes 12..15
        prefix_bytes[12:16] = v4_bytes
    elif prefix_len == 64:
        # Octet 8 is 0x00 reserved byte, IPv4 occupies bytes 9..12
        prefix_bytes[8] = 0x00
        prefix_bytes[9:13] = v4_bytes
    elif prefix_len == 56:
        # Octet 7 is byte 0 of IPv4, Octet 8 is 0x00, Octets 9..11 are bytes 1..3
        prefix_bytes[7] = v4_bytes[0]
        prefix_bytes[8] = 0x00
        prefix_bytes[9:12] = v4_bytes[1:4]
    elif prefix_len == 48:
        # Octets 6..7 are bytes 0..1 of IPv4, Octet 8 is 0x00, Octets 9..10 are bytes 2..3
        prefix_bytes[6:8] = v4_bytes[0:2]
        prefix_bytes[8] = 0x00
        prefix_bytes[9:11] = v4_bytes[2:4]
    elif prefix_len == 40:
        # Octets 5..7 are bytes 0..2, Octet 8 is 0x00, Octet 9 is byte 3
        prefix_bytes[5:8] = v4_bytes[0:3]
        prefix_bytes[8] = 0x00
        prefix_bytes[9] = v4_bytes[3]
    elif prefix_len == 32:
        # Octets 4..7 are bytes 0..3 of IPv4, Octet 8 is 0x00
        prefix_bytes[4:8] = v4_bytes
        prefix_bytes[8] = 0x00
    else:
        # Fallback to standard 96-bit suffix
        prefix_bytes[12:16] = v4_bytes

    return str(ipaddress.IPv6Address(bytes(prefix_bytes)))


def extract_ipv4_from_ipv6(ipv6_str: str, prefix_str: str = DEFAULT_DNS64_PREFIX) -> Optional[str]:
    """
    Extracts embedded IPv4 address from synthesized IPv6 address using RFC 6052 rules.
    """
    try:
        ip6 = ipaddress.IPv6Address(ipv6_str.strip())
        net6 = ipaddress.IPv6Network(prefix_str.strip(), strict=False)
        if ip6 not in net6:
            return None

        raw = ip6.packed
        prefix_len = net6.prefixlen

        if prefix_len == 96:
            v4_bytes = raw[12:16]
        elif prefix_len == 64:
            v4_bytes = raw[9:13]
        elif prefix_len == 56:
            v4_bytes = bytes([raw[7]]) + raw[9:12]
        elif prefix_len == 48:
            v4_bytes = raw[6:8] + raw[9:11]
        elif prefix_len == 40:
            v4_bytes = raw[5:8] + bytes([raw[9]])
        elif prefix_len == 32:
            v4_bytes = raw[4:8]
        else:
            v4_bytes = raw[12:16]

        return str(ipaddress.IPv4Address(v4_bytes))
    except Exception:
        return None


def reverse_ip6_arpa_to_ipv6(arpa_name: str) -> Optional[str]:
    """
    Converts nibble-reversed 'b.a.9.8...ip6.arpa' string back into IPv6 address.
    """
    clean = arpa_name.strip().lower().rstrip(".")
    if not clean.endswith(".ip6.arpa"):
        return None

    nibble_str = clean[:-len(".ip6.arpa")].replace(".", "")
    if len(nibble_str) != 32:
        return None

    # Reverse nibbles back to standard big-endian order
    forward_hex = nibble_str[::-1]
    # Group into 4-character hex words
    words = [forward_hex[i:i+4] for i in range(0, 32, 4)]
    return ":".join(words)


def reverse_ipv6_to_ipv4_ptr(arpa_name: str, prefix_str: str = DEFAULT_DNS64_PREFIX) -> Optional[str]:
    """Translates an ip6.arpa domain into corresponding in-addr.arpa domain if matching prefix."""
    clean = arpa_name.strip().lower().rstrip(".")
    if not clean.endswith(".ip6.arpa"):
        return None
    v6_str = reverse_ip6_arpa_to_ipv6(clean)
    if not v6_str:
        return None
    v4_str = extract_ipv4_from_ipv6(v6_str, prefix_str)
    if not v4_str:
        return None
    v4_octets = v4_str.split(".")[::-1]
    return ".".join(v4_octets) + ".in-addr.arpa."


class DNS64Engine:
    """
    RFC 6147 DNS64 Translator.
    Enables IPv6-only clients (e.g. cellular LTE/5G networks, IPv6 datacenters)
    to connect to legacy IPv4-only services seamlessly.
    """

    def __init__(
        self,
        prefix: str = DEFAULT_DNS64_PREFIX,
        enabled: bool = True,
        synth_ttl: int = 300,
        exclude_subnets: Optional[List[str]] = None,
    ):
        self.prefix = prefix
        self.enabled = enabled
        self.synth_ttl = synth_ttl
        self.exclude_networks: List[Any] = []

        # Standard excluded IPv4 blocks (RFC 6147 §5.1.4: 127.0.0.0/8, 0.0.0.0/8, etc.)
        default_excludes = ["0.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "255.255.255.255/32"]
        for s in (exclude_subnets or default_excludes):
            try:
                self.exclude_networks.append(ipaddress.ip_network(s.strip(), strict=False))
            except ValueError:
                pass

        self._lock = threading.Lock()

        # Telemetry
        self._total_evaluated = 0
        self._synthetic_aaaa_generated = 0
        self._reverse_ptr_synthesized = 0

    def is_ipv4_excluded(self, ipv4_str: str) -> bool:
        """Checks if IPv4 falls into private/reserved ranges excluded from DNS64 synthesis."""
        try:
            ip = ipaddress.IPv4Address(ipv4_str.strip())
            return any(ip in net for net in self.exclude_networks)
        except ValueError:
            return True

    def synthesize_aaaa_records(
        self,
        qname: str,
        ipv4_addresses: List[str],
        original_ttl: int = 300,
    ) -> List[RR]:
        """
        Creates synthetic RFC 6147 AAAA Resource Records from resolved IPv4 addresses.
        """
        results: List[RR] = []
        ttl = max(5, min(original_ttl, self.synth_ttl))

        for v4 in ipv4_addresses:
            if self.is_ipv4_excluded(v4):
                continue
            v6_str = embed_ipv4_in_ipv6(v4, self.prefix)
            rr = RR(
                rname=f"{qname.rstrip('.')}." ,
                rtype=QTYPE.AAAA,
                ttl=ttl,
                rdata=AAAA(v6_str),
            )
            results.append(rr)

        with self._lock:
            self._synthetic_aaaa_generated += len(results)

        return results

    def should_synthesize(
        self,
        qtype_int: int,
        native_aaaa_records: List[Any],
    ) -> bool:
        """
        Evaluates whether DNS64 synthesis must be activated.
        Synthesis occurs only if query was AAAA and NO native AAAA answers were returned.
        """
        if not self.enabled:
            return False
        if qtype_int != QTYPE.AAAA:
            return False
        # If native AAAA exists, RFC 6147 requires returning native IPv6 without synthesis
        return len(native_aaaa_records) == 0

    def handle_reverse_ip6_arpa(
        self,
        qname: str,
        ptr_resolver_func,
    ) -> Optional[Tuple[bytes, Dict[str, Any]]]:
        """
        Intercepts RFC 2317 reverse lookups under 'ip6.arpa'.
        If address matches DNS64 prefix, translates to IPv4 in-addr.arpa and returns PTR answer.
        """
        clean = qname.strip().lower().rstrip(".")
        if not clean.endswith(".ip6.arpa"):
            return None

        v6_str = reverse_ip6_arpa_to_ipv6(clean)
        if not v6_str:
            return None

        v4_str = extract_ipv4_from_ipv6(v6_str, self.prefix)
        if not v4_str:
            return None

        # Build reverse in-addr.arpa query
        v4_octets = v4_str.split(".")[::-1]
        v4_arpa = ".".join(v4_octets) + ".in-addr.arpa."

        # Fetch underlying PTR
        try:
            target_hostname = ptr_resolver_func(v4_arpa)
            if not target_hostname:
                return None

            rec = DNSRecord.question(clean, "PTR")
            reply = rec.reply()
            reply.header.rcode = RCODE.NOERROR
            reply.header.ra = 1
            reply.add_answer(RR(f"{clean}." , QTYPE.PTR, ttl=self.synth_ttl, rdata=PTR(f"{target_hostname.rstrip('.')}." )))

            with self._lock:
                self._reverse_ptr_synthesized += 1

            return reply.pack(), {
                "status": "allowed",
                "reason": f"DNS64: Reverse PTR Synthesized from IPv4 ({v4_str})",
                "rcode": "NOERROR",
                "protocol": "DNS64",
            }
        except Exception:
            return None

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "prefix": self.prefix,
                "enabled": self.enabled,
                "total_evaluated": self._total_evaluated,
                "synthetic_aaaa_generated": self._synthetic_aaaa_generated,
                "reverse_ptr_synthesized": self._reverse_ptr_synthesized,
            }
