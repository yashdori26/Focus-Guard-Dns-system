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
from .edns0 import (
    EDNSProcessor,
    EDNSMessage,
    EDE_BLOCKED,
    EDE_FILTERED,
    EDE_STALE_ANSWER,
    EDE_DNSSEC_BOGUS,
)
from .threat_analytics import ThreatAnalyticsEngine, ThreatVerdict
from .rate_limiter import DNSRateLimiter, RateLimitAction
from .upstream_pool import UpstreamPool, UpstreamNode, UpstreamRoutingStrategy
from .zone_authority import ZoneAuthorityEngine, AuthoritativeZone, AuthoritativeRecord, SplitHorizonView
from .cluster_sync import ClusterSyncEngine, ThreatIntelMessage
from .xdp_filter import XDPPacketFilter, XDPAction
from .dns64 import DNS64Engine
from .geodns import GeoDNSEngine, HealthState
from .catalog_zones import CatalogZoneEngine
from .zone_transfer import ZoneTransferEngine
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
        strip_ecs: bool = True,
    ):
        self.upstream_primary = upstream_primary
        self.upstream_secondary = upstream_secondary
        self.upstream_port = upstream_port
        self.upstream_timeout = upstream_timeout
        self.enable_dnssec = enable_dnssec
        self.strip_ecs = strip_ecs

        # High-performance engines
        self.trie = RadixTrieMatcher()
        self.cache = StaleCacheEngine(
            max_entries=cache_max_entries,
            revalidation_fetcher=self._revalidate_fetcher,
        )
        self.dnssec = DNSSECValidator()
        self.edns_processor = EDNSProcessor()
        self.threat_analytics = ThreatAnalyticsEngine()
        self.rate_limiter = DNSRateLimiter()
        self.upstream_pool = UpstreamPool(query_timeout=upstream_timeout)
        self.zone_authority = ZoneAuthorityEngine()
        self.cluster_sync = ClusterSyncEngine()
        self.xdp_filter = XDPPacketFilter()
        self.dns64 = DNS64Engine()
        self.geodns = GeoDNSEngine()
        self.catalog_zones = CatalogZoneEngine()
        self.zone_transfer = ZoneTransferEngine()

        # Telemetry & Operational Metrics
        self._total_queries = 0
        self._total_blocked = 0
        self._dnssec_verified = 0
        self._dnssec_bogus = 0
        self._lock = threading.Lock()

    def set_upstreams(self, primary: str, secondary: str):
        self.upstream_primary = primary.strip() if primary else "1.1.1.1"
        self.upstream_secondary = secondary.strip() if secondary else "8.8.8.8"
        self.upstream_pool.remove_node(self.upstream_primary)
        self.upstream_pool.add_node(UpstreamNode("Primary Upstream", self.upstream_primary, self.upstream_port, "UDP", weight=100))
        if self.upstream_secondary:
            self.upstream_pool.add_node(UpstreamNode("Secondary Upstream", self.upstream_secondary, self.upstream_port, "UDP", weight=50, is_backup=True))

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
        Routes query through resilient UpstreamPool with circuit breakers and failover.
        """
        reply, status = self.upstream_pool.resolve_wire(query_bytes)
        if reply:
            return reply, status
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
        ede_code: int = EDE_BLOCKED,
        edns_msg: Optional[EDNSMessage] = None,
    ) -> Tuple[bytes, Dict[str, Any]]:
        """Constructs RFC 2308 compliant NXDOMAIN negative response with RFC 8914 EDE diagnostics."""
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
        # Attach RFC 8914 Extended DNS Error diagnostic
        self.edns_processor.attach_error_diagnostics(reply, edns_msg, ede_code, reason)

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
            "ede_code": ede_code,
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

        # -1.5 eBPF / XDP Fast Packet Filter
        xdp_act, xdp_reason = self.xdp_filter.inspect_packet(client_ip, packet_len=len(query_bytes))
        if xdp_act == 1:  # XDP_DROP
            return b"", {"status": "dropped", "reason": f"eBPF/XDP Drop: {xdp_reason}", "client_ip": client_ip, "protocol": protocol}

        # -1. Response Rate Limiting (RRL) & Anti-Amplification Check
        rl_action = self.rate_limiter.check_query_rate(client_ip)
        if rl_action == RateLimitAction.DROP:
            return b"", {"status": "dropped", "reason": "Rate Limit Exceeded (Dropped)", "client_ip": client_ip, "protocol": protocol}
        elif rl_action == RateLimitAction.SLIP_TC:
            reply = req.reply()
            reply.header.tc = 1
            return reply.pack(), {"status": "slipped_tc", "reason": "Rate Limit Exceeded (SLIP TC=1)", "client_ip": client_ip, "protocol": protocol}

        # -0.8 Distributed Cluster Threat Intelligence Check
        is_ip_banned, ban_reason = self.cluster_sync.is_ip_blocked(client_ip)
        if is_ip_banned:
            return self.build_blocked_response(
                req, qname, f"Cluster Defense: {ban_reason}",
                profile_id, client_ip, protocol, ede_code=EDE_BLOCKED
            )

        is_dom_banned, dom_reason = self.cluster_sync.is_domain_blocked(qname)
        if is_dom_banned:
            return self.build_blocked_response(
                req, qname, f"Cluster Defense: {dom_reason}",
                profile_id, client_ip, protocol, ede_code=EDE_BLOCKED
            )

        # -0.5 EDNS(0) Input Processing (ECS Stripping & Cookie Handling)
        edns_msg, edns_info = self.edns_processor.process_incoming_query(req, client_ip, strip_ecs=self.strip_ecs)

        # -0.25 Threat Analytics & Anomaly Detection (DGA & DNS Tunneling)
        threat_verdict = self.threat_analytics.analyze_domain(qname, qtype_str, client_ip)
        if threat_verdict.verdict == ThreatVerdict.BLOCK:
            return self.build_blocked_response(
                req, qname, f"Security Threat: {', '.join(threat_verdict.reasons)}",
                profile_id, client_ip, protocol, ede_code=EDE_BLOCKED, edns_msg=edns_msg
            )

        # -0.1 Split-Horizon & Authoritative Local Zone Fast-Path
        auth_res = self.zone_authority.resolve_authoritative(req, client_ip)
        if auth_res:
            auth_wire, auth_telem = auth_res
            auth_telem.update({
                "profile_id": profile_id,
                "domain": qname,
                "subdomain": "",
                "qtype": qtype_str,
                "client_ip": client_ip,
                "protocol": protocol,
            })
            db.log_query_async(profile_id, qname, "", auth_telem["status"], auth_telem["reason"], client_ip)
            return auth_wire, auth_telem

        # 0. Global Safe Bypass Check
        is_bypass = (db.get_system_config("emergency_bypass", "0") == "1")
        if is_bypass:
            return self._execute_upstream_allowed(req, query_bytes, qname, qtype_int, qtype_str, profile_id, client_ip, protocol, "Emergency Bypass Active")

        # 0b. Firefox Canary Domain Check (Mozilla DoH opt-out standard)
        if qname == FIREFOX_CANARY_DOMAIN:
            return self.build_blocked_response(req, qname, "Bypass Prevention: Firefox Canary Domain", profile_id, client_ip, protocol, ede_code=EDE_BLOCKED, edns_msg=edns_msg)

        # 0c. GeoDNS Proximity & Geo-Fencing Fast Path
        clean_qname = qname.rstrip(".")
        if clean_qname in self.geodns.domain_pool_bindings:
            ecs_ip = edns_info.get("ecs_client_ip") if edns_info else None
            geo_dec = self.geodns.resolve(clean_qname, client_ip, ecs_ip=ecs_ip)
            if geo_dec.policy_action == "block":
                return self.build_blocked_response(
                    req, qname, f"Geo-Fence Policy: {geo_dec.reason}",
                    profile_id, client_ip, protocol, ede_code=EDE_BLOCKED, edns_msg=edns_msg
                )
            elif geo_dec.selected_endpoint:
                ep = geo_dec.selected_endpoint
                reply = req.reply()
                reply.header.rcode = RCODE.NOERROR
                reply.header.ra = 1
                ans_ip = ""
                if req.q.qtype == QTYPE.A:
                    reply.add_answer(RR(f"{qname}.", QTYPE.A, ttl=60, rdata=A(ep.ipv4_address)))
                    ans_ip = ep.ipv4_address
                elif req.q.qtype == QTYPE.AAAA and ep.ipv6_address:
                    reply.add_answer(RR(f"{qname}.", QTYPE.AAAA, ttl=60, rdata=AAAA(ep.ipv6_address)))
                    ans_ip = ep.ipv6_address
                if ans_ip:
                    telem = {
                        "profile_id": profile_id,
                        "domain": qname,
                        "subdomain": "",
                        "qtype": qtype_str,
                        "status": "allowed",
                        "reason": f"GeoDNS Routed ({ep.name}, {geo_dec.distance_km} km)",
                        "ip": ans_ip,
                        "rcode": "NOERROR",
                        "client_ip": client_ip,
                        "protocol": protocol,
                    }
                    db.log_query_async(profile_id, qname, "", "allowed", telem["reason"], client_ip)
                    return reply.pack(), telem

        # 1. Trie Matcher Fast-Path
        match_flags, match_rule, match_metadata = self.trie.match(qname)

        # Allowlist has absolute priority
        if match_flags & FLAG_ALLOWED:
            return self._execute_upstream_allowed(req, query_bytes, qname, qtype_int, qtype_str, profile_id, client_ip, protocol, f"Allowlist: {match_rule or qname}")

        # Blocked domains
        if match_flags & FLAG_BLOCKED:
            return self.build_blocked_response(req, qname, f"Denylist: {match_rule or qname}", profile_id, client_ip, protocol, ede_code=EDE_BLOCKED, edns_msg=edns_msg)

        # Threat signatures
        if match_flags & (FLAG_THREAT_MALWARE | FLAG_THREAT_MINER | FLAG_THREAT_FEED):
            threat_type = "Threat Intelligence"
            if match_flags & FLAG_THREAT_MINER:
                threat_type = "Cryptojacking"
            elif match_flags & FLAG_THREAT_MALWARE:
                threat_type = "Malware"
            return self.build_blocked_response(req, qname, f"Security: {threat_type} Signature", profile_id, client_ip, protocol, ede_code=EDE_BLOCKED, edns_msg=edns_msg)

        # Deep Focus
        if match_flags & FLAG_DEEP_FOCUS:
            meta = match_metadata or {}
            category = meta.get("category", "Distraction")
            return self.build_blocked_response(req, qname, f"Deep Focus: {category}", profile_id, client_ip, protocol, ede_code=EDE_FILTERED, edns_msg=edns_msg)


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

        # RFC 6147 DNS64 IPv6 Synthesis: If AAAA query resulted in NO AAAA records, synthesize from A records
        if self.dns64.enabled and req.q.qtype == QTYPE.AAAA and RCODE.get(upstream_reply.header.rcode, "NOERROR") == "NOERROR":
            has_aaaa = any(rr.rtype == QTYPE.AAAA for rr in upstream_reply.rr)
            if not has_aaaa:
                a_req = DNSRecord.question(qname, "A")
                a_bytes, _ = self.forward_upstream(a_req.pack())
                if a_bytes:
                    try:
                        a_rep = DNSRecord.parse(a_bytes)
                        a_addrs = [str(rr.rdata) for rr in a_rep.rr if rr.rtype == QTYPE.A]
                        synth_rrs = self.dns64.synthesize_aaaa_records(qname, a_addrs)
                        if synth_rrs:
                            for s_rr in synth_rrs:
                                upstream_reply.add_answer(s_rr)
                            upstream_bytes = upstream_reply.pack()
                            reason = f"DNS64 Synthesized ({synth_rrs[0].rdata})"
                    except Exception:
                        pass

        # Cache positive responses in RFC 8767 Cache
        upstream_rcode_str = RCODE.get(upstream_reply.header.rcode, "NOERROR")
        if upstream_rcode_str == "NOERROR" and upstream_reply.rr:
            ttls = [rr.ttl for rr in upstream_reply.rr if rr.ttl > 0]
            ttl = min(ttls) if ttls else 60
            self.cache.put(qname, qtype_int, upstream_bytes, ttl)

        # Extract IPs for fast-flux detection & logging
        resolved_ips = []
        for rr in upstream_reply.rr:
            if rr.rtype in (QTYPE.A, QTYPE.AAAA):
                resolved_ips.append(str(rr.rdata))
        if resolved_ips:
            resolved_ip = resolved_ips[0]
            self.threat_analytics.record_resolution(qname, resolved_ips, ttl=ttl if 'ttl' in locals() else 60)
        else:
            resolved_ip = ""

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
            threat_stats = self.threat_analytics.get_stats()
            rate_limiter_stats = self.rate_limiter.get_stats()
            upstream_pool_stats = self.upstream_pool.get_stats()

            zone_stats = self.zone_authority.get_stats()
            cluster_stats = self.cluster_sync.get_stats()

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
                "threat_queries_analyzed": threat_stats["total_analyzed"],
                "threat_dga_detected": threat_stats["dga_detected"],
                "threat_tunneling_detected": threat_stats["tunneling_detected"],
                "threat_fast_flux_detected": threat_stats["fast_flux_detected"],
                "threat_high_risk_blocked": threat_stats["high_risk_blocked"],
                "rate_limiter_tracked_ips": rate_limiter_stats["tracked_ips"],
                "rate_limiter_dropped": rate_limiter_stats["total_dropped"],
                "rate_limiter_slipped_tc": rate_limiter_stats["total_slipped"],
                "upstream_total_queries": upstream_pool_stats["total_queries"],
                "upstream_failovers": upstream_pool_stats["failover_count"],
                "upstream_active_nodes": upstream_pool_stats["active_nodes"],
                "zone_authority_hits": zone_stats["authoritative_hits"],
                "zone_authority_zones": zone_stats["total_zones"],
                "cluster_size": cluster_stats["cluster_size"],
                "cluster_distributed_blocked_ips": cluster_stats["distributed_blocked_ips"],
                "xdp_frames_inspected": self.xdp_filter.get_stats()["total_frames_inspected"],
                "xdp_frames_dropped": self.xdp_filter.get_stats()["total_frames_dropped"],
                "dns64_synthetic_aaaa": self.dns64.get_stats()["synthetic_aaaa_generated"],
                "geodns_queries": self.geodns.get_stats()["total_queries"],
                "geodns_blocked": self.geodns.get_stats()["blocked_by_geofence"],
                "catalog_members": self.catalog_zones.get_stats()["member_count"],
                "zone_transfers_served": self.zone_transfer.get_stats()["axfr_transfers_served"] + self.zone_transfer.get_stats()["ixfr_transfers_served"],
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
