"""
FocusDNS Engine - Unified High-Performance DNS Processing Pipeline
Coordinates:
- Compact Radix Trie domain rule matching (sub-microsecond)
- RFC 8767 Stale-While-Revalidate DNS caching (0ms hit & background revalidation)
- RFC 4033/4034/4035 DNSSEC cryptographic chain-of-trust validation
- Multi-protocol transport tagging (UDP, TCP, DoH, DoT, DoQ)
- Dynamic policy enforcement (Deep Focus, Threat Feeds, SafeSearch VIP)
"""

import socket
import struct
import sys
import threading
import time
from typing import Dict, Any, Tuple, Optional, Callable, List

from dnslib import DNSRecord, DNSHeader, RR, QTYPE, RCODE, A, AAAA, SOA

from .radix_trie import (
    RadixTrieMatcher,
    FLAG_ALLOWED,
    FLAG_BLOCKED,
    FLAG_THREAT_MALWARE,
    FLAG_THREAT_MINER,
    FLAG_THREAT_FEED,
    FLAG_DEEP_FOCUS,
    FLAG_SAFESEARCH,
)
from .stale_cache import StaleCacheEngine, CacheState, CacheEntry
from .dnssec import DNSSECValidator, DNSSECSignatureState
from .. import db

# SafeSearch VIP IP Constants
GOOGLE_SAFESEARCH_IPV4 = "216.239.38.120"
GOOGLE_SAFESEARCH_IPV6 = "2001:4860:4806::78"
YOUTUBE_RESTRICTED_IPV4 = "216.239.38.119"
YOUTUBE_RESTRICTED_IPV6 = "2001:4860:4806::77"
BING_STRICT_IPV4 = "204.79.197.220"
BING_STRICT_IPV6 = "2620:1ec:c11::200"
DUCKDUCKGO_SAFE_IPV4 = "52.142.124.215"
DUCKDUCKGO_SAFE_IPV6 = "2603:1030:20a:3::1"

FIREFOX_CANARY_DOMAIN = "use-application-dns.net"


class DNSPipeline:
    """
    Unified high-throughput DNS pipeline.
    Combines the Radix Trie matcher, Stale-While-Revalidate cache, and DNSSEC engine.
    """

    def __init__(
        self,
        upstream_primary: str = "1.1.1.1",
        upstream_secondary: str = "8.8.8.8",
        upstream_port: int = 53,
        upstream_timeout: float = 2.0,
        enable_dnssec: bool = True,
        cache_max_entries: int = 100000,
    ):
        self.upstream_primary = upstream_primary
        self.upstream_secondary = upstream_secondary
        self.upstream_port = upstream_port
        self.upstream_timeout = upstream_timeout
        self.enable_dnssec = enable_dnssec

        # High-performance engines
        self.trie = RadixTrieMatcher()
        self.cache = StaleCacheEngine(
            max_entries=cache_max_entries,
            revalidation_fetcher=self._revalidate_fetcher,
        )
        self.dnssec = DNSSECValidator()

        # Telemetry & Operational Metrics
        self._total_queries = 0
        self._total_blocked = 0
        self._dnssec_verified = 0
        self._dnssec_bogus = 0
        self._lock = threading.Lock()

    def set_upstreams(self, primary: str, secondary: str):
        self.upstream_primary = primary.strip() if primary else "1.1.1.1"
        self.upstream_secondary = secondary.strip() if secondary else "8.8.8.8"

    def _revalidate_fetcher(self, qname: str, qtype: int) -> Optional[bytes]:
        """Background callback invoked by StaleCacheEngine when refreshing stale entries."""
        try:
            req = DNSRecord.question(qname, QTYPE.get(qtype, "A"))
            reply_bytes, _ = self.forward_upstream(req.pack())
            return reply_bytes
        except Exception:
            return None

    def forward_upstream(self, query_bytes: bytes) -> Tuple[Optional[bytes], str]:
        """
        Forwards DNS query packet to primary upstream with fallback to secondary upstream.
        Falls back to TCP if truncated (TC=1).
        """
        reply = None
        # 1. Primary UDP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(self.upstream_timeout)
        try:
            s.sendto(query_bytes, (self.upstream_primary, self.upstream_port))
            reply, _ = s.recvfrom(4096)
        except Exception:
            pass
        finally:
            s.close()

        # 2. Secondary UDP
        if not reply and self.upstream_secondary:
            s_fb = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s_fb.settimeout(self.upstream_timeout)
            try:
                s_fb.sendto(query_bytes, (self.upstream_secondary, self.upstream_port))
                reply, _ = s_fb.recvfrom(4096)
            except Exception:
                return None, "SERVFAIL"
            finally:
                s_fb.close()

        if reply:
            # Check TC (Truncation) bit (RFC 1035 section 4.1.1)
            if len(reply) >= 4 and (reply[2] & 0x02):
                tcp_reply = self._forward_tcp(query_bytes, self.upstream_primary)
                if not tcp_reply and self.upstream_secondary:
                    tcp_reply = self._forward_tcp(query_bytes, self.upstream_secondary)
                if tcp_reply:
                    return tcp_reply, "NOERROR"
            return reply, "NOERROR"

        return None, "SERVFAIL"

    def _forward_tcp(self, query_bytes: bytes, host: str) -> Optional[bytes]:
        """RFC 1035 §4.2.2 TCP relay fallback."""
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(self.upstream_timeout)
        try:
            s.connect((host, self.upstream_port))
            s.sendall(struct.pack("!H", len(query_bytes)) + query_bytes)
            raw_len = s.recv(2)
            if len(raw_len) < 2:
                return None
            msg_len = struct.unpack("!H", raw_len)[0]
            buf = bytearray()
            while len(buf) < msg_len:
                chunk = s.recv(msg_len - len(buf))
                if not chunk:
                    break
                buf.extend(chunk)
            return bytes(buf)
        except Exception:
            return None
        finally:
            try:
                s.close()
            except Exception:
                pass

    def build_blocked_response(
        self,
        req: DNSRecord,
        qname: str,
        reason: str,
        profile_id: str,
        client_ip: str,
        protocol: str = "UDP",
    ) -> Tuple[bytes, Dict[str, Any]]:
        """Constructs RFC 2308 compliant NXDOMAIN negative response."""
        with self._lock:
            self._total_blocked += 1

        reply = req.reply()
        reply.header.rcode = RCODE.NXDOMAIN
        reply.header.ra = 1
        # RFC 2308: 30s SOA record for fast negative cache expiration
        reply.add_auth(RR(
            f"{qname}.",
            QTYPE.SOA,
            ttl=30,
            rdata=SOA("ns1.focusdns.local.", "admin.focusdns.local.", (1, 30, 30, 30, 30))
        ))
        telemetry = {
            "profile_id": profile_id,
            "domain": qname,
            "subdomain": "",
            "qtype": QTYPE.get(req.q.qtype, "A"),
            "status": "blocked",
            "reason": reason,
            "ip": "0.0.0.0" if req.q.qtype == QTYPE.A else "::",
            "rcode": "NXDOMAIN",
            "client_ip": client_ip,
            "protocol": protocol,
        }
        db.log_query_async(profile_id, qname, "", "blocked", reason, client_ip)
        return reply.pack(), telemetry

    def build_safesearch_response(
        self,
        req: DNSRecord,
        qname: str,
        reason: str,
        target_ipv4: str,
        target_ipv6: str,
        profile_id: str,
        client_ip: str,
        protocol: str = "UDP",
    ) -> Tuple[bytes, Dict[str, Any]]:
        """Constructs synthetic NOERROR SafeSearch VIP redirection response."""
        reply = req.reply()
        reply.header.rcode = RCODE.NOERROR
        reply.header.ra = 1

        resolved_ip = target_ipv4
        if req.q.qtype == QTYPE.A:
            reply.add_answer(RR(f"{qname}.", QTYPE.A, ttl=300, rdata=A(target_ipv4)))
        elif req.q.qtype == QTYPE.AAAA:
            reply.add_answer(RR(f"{qname}.", QTYPE.AAAA, ttl=300, rdata=AAAA(target_ipv6)))
            resolved_ip = target_ipv6
        else:
            # Fallback upstream for non-A/AAAA (e.g. TXT, HTTPS)
            upstream_bytes, _ = self.forward_upstream(req.pack())
            if upstream_bytes:
                return upstream_bytes, {
                    "profile_id": profile_id,
                    "domain": qname,
                    "subdomain": "",
                    "qtype": QTYPE.get(req.q.qtype, "A"),
                    "status": "allowed",
                    "reason": reason,
                    "ip": "",
                    "rcode": "NOERROR",
                    "client_ip": client_ip,
                    "protocol": protocol,
                }

        telemetry = {
            "profile_id": profile_id,
            "domain": qname,
            "subdomain": "",
            "qtype": QTYPE.get(req.q.qtype, "A"),
            "status": "allowed",
            "reason": reason,
            "ip": resolved_ip,
            "rcode": "NOERROR",
            "client_ip": client_ip,
            "protocol": protocol,
        }
        db.log_query_async(profile_id, qname, "", "allowed", reason, client_ip)
        return reply.pack(), telemetry

    def process_wire_query(
        self,
        query_bytes: bytes,
        profile_id: str = "a1b2c3",
        client_ip: str = "127.0.0.1",
        protocol: str = "UDP",
    ) -> Tuple[bytes, Dict[str, Any]]:
        """
        Executes the full pipeline against an incoming wire DNS packet:
        1. Parsing & validation
        2. Radix Trie match (blocklist, allowlist, threat, SafeSearch)
        3. Stale-While-Revalidate Cache check
        4. Upstream resolution
        5. DNSSEC cryptographic chain validation
        6. Telemetry and query logging
        """
        with self._lock:
            self._total_queries += 1

        try:
            req = DNSRecord.parse(query_bytes)
        except Exception:
            reply = DNSRecord(DNSHeader(id=0, qr=1, rcode=RCODE.FORMERR))
            return reply.pack(), {"status": "error", "rcode": "FORMERR", "protocol": protocol}

        if not req.q or req.header.qr != 0:
            reply = req.reply()
            reply.header.rcode = RCODE.FORMERR
            return reply.pack(), {"status": "error", "rcode": "FORMERR", "protocol": protocol}

        qname = str(req.q.qname).rstrip(".").lower()
        qtype_int = req.q.qtype
        qtype_str = QTYPE.get(qtype_int, "A")

        # 0. Global Safe Bypass Check
        is_bypass = (db.get_system_config("emergency_bypass", "0") == "1")
        if is_bypass:
            return self._execute_upstream_allowed(req, query_bytes, qname, qtype_int, qtype_str, profile_id, client_ip, protocol, "Emergency Bypass Active")

        # 0b. Firefox Canary Domain Check (Mozilla DoH opt-out standard)
        if qname == FIREFOX_CANARY_DOMAIN:
            return self.build_blocked_response(req, qname, "Bypass Prevention: Firefox Canary Domain", profile_id, client_ip, protocol)

        # 1. Trie Matcher Fast-Path
        match_flags, match_rule, match_metadata = self.trie.match(qname)

        # Allowlist has absolute priority
        if match_flags & FLAG_ALLOWED:
            return self._execute_upstream_allowed(req, query_bytes, qname, qtype_int, qtype_str, profile_id, client_ip, protocol, f"Allowlist: {match_rule or qname}")

        # Blocked domains
        if match_flags & FLAG_BLOCKED:
            return self.build_blocked_response(req, qname, f"Denylist: {match_rule or qname}", profile_id, client_ip, protocol)

        # Threat signatures
        if match_flags & (FLAG_THREAT_MALWARE | FLAG_THREAT_MINER | FLAG_THREAT_FEED):
            threat_type = "Threat Intelligence"
            if match_flags & FLAG_THREAT_MINER:
                threat_type = "Cryptojacking"
            elif match_flags & FLAG_THREAT_MALWARE:
                threat_type = "Malware"
            return self.build_blocked_response(req, qname, f"Security: {threat_type} Signature", profile_id, client_ip, protocol)

        # Deep Focus
        if match_flags & FLAG_DEEP_FOCUS:
            meta = match_metadata or {}
            category = meta.get("category", "Distraction")
            return self.build_blocked_response(req, qname, f"Deep Focus: {category}", profile_id, client_ip, protocol)

        # SafeSearch VIP
        if match_flags & FLAG_SAFESEARCH:
            if "google" in qname:
                return self.build_safesearch_response(req, qname, "SafeSearch: Google VIP", GOOGLE_SAFESEARCH_IPV4, GOOGLE_SAFESEARCH_IPV6, profile_id, client_ip, protocol)
            elif "youtube" in qname:
                return self.build_safesearch_response(req, qname, "SafeSearch: YouTube Restricted VIP", YOUTUBE_RESTRICTED_IPV4, YOUTUBE_RESTRICTED_IPV6, profile_id, client_ip, protocol)
            elif "bing" in qname:
                return self.build_safesearch_response(req, qname, "SafeSearch: Bing VIP", BING_STRICT_IPV4, BING_STRICT_IPV6, profile_id, client_ip, protocol)
            elif "duckduckgo" in qname:
                return self.build_safesearch_response(req, qname, "SafeSearch: DuckDuckGo VIP", DUCKDUCKGO_SAFE_IPV4, DUCKDUCKGO_SAFE_IPV6, profile_id, client_ip, protocol)

        # 2. RFC 8767 Stale-While-Revalidate Cache Check
        cached_wire, cache_state, ttl_remaining = self.cache.get(qname, qtype_int)
        if cached_wire and cache_state in (CacheState.FRESH, CacheState.STALE):
            # Stamp client query ID onto cached answer
            hit_wire = bytearray(cached_wire)
            req_id = req.header.id
            hit_wire[0] = (req_id >> 8) & 0xFF
            hit_wire[1] = req_id & 0xFF

            reason = "Cache Hit (0ms)" if cache_state == CacheState.FRESH else "RFC 8767 Stale Served (0ms, Revalidating)"
            telemetry = {
                "profile_id": profile_id,
                "domain": qname,
                "subdomain": "",
                "qtype": qtype_str,
                "status": "allowed",
                "reason": reason,
                "ip": "",
                "rcode": "NOERROR",
                "client_ip": client_ip,
                "protocol": protocol,
            }
            db.log_query_async(profile_id, qname, "", "allowed", reason, client_ip)
            return bytes(hit_wire), telemetry

        # 3. Cache Miss -> Forward Upstream
        return self._execute_upstream_allowed(req, query_bytes, qname, qtype_int, qtype_str, profile_id, client_ip, protocol, "Clean Query")

    def _execute_upstream_allowed(
        self,
        req: DNSRecord,
        query_bytes: bytes,
        qname: str,
        qtype_int: int,
        qtype_str: str,
        profile_id: str,
        client_ip: str,
        protocol: str,
        reason: str,
    ) -> Tuple[bytes, Dict[str, Any]]:
        """Handles forwarding upstream, DNSSEC validation, and cache insertion."""
        upstream_bytes, status_code = self.forward_upstream(query_bytes)
        if not upstream_bytes or status_code == "SERVFAIL":
            reply = req.reply()
            reply.header.rcode = RCODE.SERVFAIL
            reply.header.ra = 1
            telemetry = {
                "profile_id": profile_id,
                "domain": qname,
                "subdomain": "",
                "qtype": qtype_str,
                "status": "error",
                "reason": "Upstream Resolution Failed",
                "ip": "",
                "rcode": "SERVFAIL",
                "client_ip": client_ip,
                "protocol": protocol,
            }
            db.log_query_async(profile_id, qname, "", "error", "Upstream Resolution Failed", client_ip)
            return reply.pack(), telemetry

        # Parse upstream reply
        try:
            upstream_reply = DNSRecord.parse(upstream_bytes)
        except Exception:
            reply = req.reply()
            reply.header.rcode = RCODE.SERVFAIL
            return reply.pack(), {"status": "error", "rcode": "SERVFAIL", "protocol": protocol}

        # DNSSEC Validation
        if self.enable_dnssec:
            dnssec_result = self.dnssec.validate_record(upstream_reply)
            if dnssec_result == DNSSECSignatureState.SECURE:
                with self._lock:
                    self._dnssec_verified += 1
                # Set AD (Authenticated Data) bit: flags byte 1, bit 5 (0x20)
                if len(upstream_bytes) >= 4:
                    raw_ba = bytearray(upstream_bytes)
                    raw_ba[3] |= 0x20
                    upstream_bytes = bytes(raw_ba)
            elif dnssec_result == DNSSECSignatureState.BOGUS:
                with self._lock:
                    self._dnssec_bogus += 1
                # MITM / DNS Spoofing Detected! Return SERVFAIL
                reply = req.reply()
                reply.header.rcode = RCODE.SERVFAIL
                telemetry = {
                    "profile_id": profile_id,
                    "domain": qname,
                    "subdomain": "",
                    "qtype": qtype_str,
                    "status": "blocked",
                    "reason": "Security: DNSSEC Cryptographic Validation BOGUS (MITM Detected)",
                    "ip": "",
                    "rcode": "SERVFAIL",
                    "client_ip": client_ip,
                    "protocol": protocol,
                }
                db.log_query_async(profile_id, qname, "", "blocked", "DNSSEC Spoofing Detected", client_ip)
                return reply.pack(), telemetry

        # Cache positive responses in RFC 8767 Cache
        upstream_rcode_str = RCODE.get(upstream_reply.header.rcode, "NOERROR")
        if upstream_rcode_str == "NOERROR" and upstream_reply.rr:
            ttls = [rr.ttl for rr in upstream_reply.rr if rr.ttl > 0]
            ttl = min(ttls) if ttls else 60
            self.cache.put(qname, qtype_int, upstream_bytes, ttl)

        # Extract first IP for logging
        resolved_ip = ""
        for rr in upstream_reply.rr:
            if rr.rtype in (QTYPE.A, QTYPE.AAAA):
                resolved_ip = str(rr.rdata)
                break

        telemetry = {
            "profile_id": profile_id,
            "domain": qname,
            "subdomain": "",
            "qtype": qtype_str,
            "status": "allowed" if upstream_rcode_str == "NOERROR" else "blocked",
            "reason": reason,
            "ip": resolved_ip,
            "rcode": upstream_rcode_str,
            "client_ip": client_ip,
            "protocol": protocol,
        }
        db.log_query_async(profile_id, qname, "", telemetry["status"], reason, client_ip)
        return upstream_bytes, telemetry

    def get_pipeline_metrics(self) -> Dict[str, Any]:
        """Returns unified engine performance and operational counters."""
        with self._lock:
            trie_stats = self.trie.get_stats()
            cache_stats = self.cache.get_stats()
            dnssec_stats = self.dnssec.get_stats()

            return {
                "total_queries": self._total_queries,
                "total_blocked": self._total_blocked,
                "trie_nodes": trie_stats["node_count"],
                "trie_exact_rules": trie_stats["exact_rules"],
                "trie_wildcard_rules": trie_stats["wildcard_rules"],
                "cache_entries": cache_stats["entry_count"],
                "cache_hits_fresh": cache_stats["hits_fresh"],
                "cache_hits_stale": cache_stats["hits_stale"],
                "cache_misses": cache_stats["misses"],
                "cache_hit_ratio": cache_stats["hit_ratio"],
                "cache_revalidations": cache_stats["revalidations_queued"],
                "dnssec_verified": self._dnssec_verified,
                "dnssec_bogus_blocked": self._dnssec_bogus,
                "dnssec_trust_anchors": dnssec_stats["trust_anchor_count"],
            }


_global_pipeline: Optional[DNSPipeline] = None
_global_pipeline_lock = threading.Lock()


def get_pipeline() -> DNSPipeline:
    """Returns singleton instance of the unified DNS engine pipeline."""
    global _global_pipeline
    with _global_pipeline_lock:
        if _global_pipeline is None:
            _global_pipeline = DNSPipeline()
        return _global_pipeline
