"""
FocusDNS Engine - RFC 8198 Aggressive Use of DNSSEC-Validated Cache Subsystem
Standards & RFCs:
- RFC 8198: Aggressive Use of DNSSEC-Validated Cache
- RFC 4034 Section 6.1: Canonical DNS Name Order
- RFC 4035 Section 4.5: Negative Answers (NSEC RRs)
"""

import threading
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from dnslib import DNSRecord, RR, QTYPE, RCODE, SOA, DNSLabel


def split_canonical_labels(name: str) -> List[str]:
    """Splits domain name into lowercased labels reversed (root-first) for canonical ordering."""
    clean = name.strip().lower().rstrip(".")
    if not clean:
        return []
    labels = clean.split(".")
    return list(reversed(labels))


def compare_canonical_names(name1: str, name2: str) -> int:
    """
    Compares two domain names per RFC 4034 Section 6.1 Canonical DNS Name Order:
    Labels are compared from right-to-left. At the first label mismatch,
    labels are compared as unsigned octets.
    Returns: -1 if name1 < name2, 0 if equal, 1 if name1 > name2.
    """
    labels1 = split_canonical_labels(name1)
    labels2 = split_canonical_labels(name2)

    min_len = min(len(labels1), len(labels2))
    for i in range(min_len):
        l1 = labels1[i].encode("latin-1")
        l2 = labels2[i].encode("latin-1")
        if l1 < l2:
            return -1
        elif l1 > l2:
            return 1

    # Labels matched up to min_len: shorter domain comes first
    if len(labels1) < len(labels2):
        return -1
    elif len(labels1) > len(labels2):
        return 1
    return 0


class NSECRange:
    """Represents an authenticated span of non-existence defined by an NSEC record."""

    def __init__(
        self,
        owner_name: str,
        next_domain_name: str,
        type_bitmaps: Optional[List[str]] = None,
        ttl: int = 300,
        zone_origin: str = ".",
    ):
        self.owner_name: str = owner_name.strip().lower().rstrip(".")
        self.next_domain_name: str = next_domain_name.strip().lower().rstrip(".")
        self.type_bitmaps: Set[str] = set(t.upper() for t in (type_bitmaps or []))
        self.ttl: int = ttl
        self.zone_origin: str = zone_origin.strip().lower().rstrip(".")
        self.created_at: float = time.time()
        self.expires_at: float = self.created_at + ttl

    @property
    def is_expired(self) -> bool:
        return time.time() >= self.expires_at

    @property
    def is_wrap_around(self) -> bool:
        """True if this NSEC record wraps around from end of zone back to apex."""
        return compare_canonical_names(self.owner_name, self.next_domain_name) >= 0

    def covers_name(self, name: str) -> bool:
        """
        Determines whether 'name' falls strictly within the non-existent span (owner, next_domain).
        Per RFC 8198 §5.1, returns True if owner < name < next_domain (or wrapped range).
        """
        clean = name.strip().lower().rstrip(".")

        cmp_owner = compare_canonical_names(self.owner_name, clean)
        cmp_next = compare_canonical_names(clean, self.next_domain_name)

        if not self.is_wrap_around:
            # Normal range: owner < name < next_domain
            return cmp_owner < 0 and cmp_next < 0
        else:
            # Wrap-around range: name > owner OR name < next_domain
            return cmp_owner < 0 or cmp_next < 0

    def covers_nodata(self, name: str, qtype: str) -> bool:
        """
        Determines whether 'name' matches owner and 'qtype' is NOT present in type bitmaps.
        Per RFC 8198 §5.2, proves NODATA without querying authoritative servers.
        """
        clean = name.strip().lower().rstrip(".")
        if clean == self.owner_name:
            return qtype.upper() not in self.type_bitmaps
        return False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "owner_name": self.owner_name,
            "next_domain_name": self.next_domain_name,
            "type_bitmaps": list(self.type_bitmaps),
            "zone_origin": self.zone_origin,
            "ttl": self.ttl,
            "remaining_ttl": max(0, int(self.expires_at - time.time())),
            "is_wrap_around": self.is_wrap_around,
        }


class AggressiveNSECCache:
    """
    RFC 8198 Aggressive DNSSEC-Validated Cache Engine.
    Interprets cached NSEC authenticated spans to synthesize NXDOMAIN and NODATA answers,
    mitigating random subdomain / pseudo-random water torture attacks.
    """

    def __init__(self, max_ranges_per_zone: int = 5000):
        # zone_origin -> List[NSECRange]
        self._zones: Dict[str, List[NSECRange]] = {}
        self.max_ranges_per_zone: int = max_ranges_per_zone
        self._lock = threading.RLock()

        # Telemetry counters
        self.queries_evaluated: int = 0
        self.synthesized_nxdomain: int = 0
        self.synthesized_nodata: int = 0
        self.cache_hits: int = 0

    def store_nsec(
        self,
        owner_name: str,
        next_domain_name: str,
        type_bitmaps: Optional[List[str]] = None,
        ttl: int = 300,
        zone_origin: str = ".",
    ) -> NSECRange:
        """Caches an authenticated NSEC record range for future aggressive synthesis."""
        clean_zone = zone_origin.strip().lower().rstrip(".")
        nsec = NSECRange(
            owner_name=owner_name,
            next_domain_name=next_domain_name,
            type_bitmaps=type_bitmaps,
            ttl=ttl,
            zone_origin=clean_zone,
        )

        with self._lock:
            if clean_zone not in self._zones:
                self._zones[clean_zone] = []

            ranges = self._zones[clean_zone]
            # Replace existing range if owner matches
            for i, r in enumerate(ranges):
                if r.owner_name == nsec.owner_name:
                    ranges[i] = nsec
                    return nsec

            if len(ranges) >= self.max_ranges_per_zone:
                ranges.pop(0)

            ranges.append(nsec)
            return nsec

    def find_covering_nxdomain(self, qname: str, zone_origin: str) -> Optional[NSECRange]:
        """
        Synthesizes NXDOMAIN if qname falls strictly within an authenticated NSEC range.
        RFC 8198 Section 5.1: Synthesis of Negative Answers.
        """
        clean_zone = zone_origin.strip().lower().rstrip(".")
        clean_qname = qname.strip().lower().rstrip(".")

        now = time.time()
        with self._lock:
            self.queries_evaluated += 1
            ranges = self._zones.get(clean_zone, [])

            for r in ranges:
                if r.expires_at > now and r.covers_name(clean_qname):
                    self.synthesized_nxdomain += 1
                    self.cache_hits += 1
                    return r

        return None

    def find_covering_nodata(self, qname: str, qtype: str, zone_origin: str) -> Optional[NSECRange]:
        """
        Synthesizes NODATA (NOERROR) if qname matches owner and qtype is absent from bitmaps.
        RFC 8198 Section 5.2: Synthesis of NODATA Answers.
        """
        clean_zone = zone_origin.strip().lower().rstrip(".")
        clean_qname = qname.strip().lower().rstrip(".")

        now = time.time()
        with self._lock:
            self.queries_evaluated += 1
            ranges = self._zones.get(clean_zone, [])

            for r in ranges:
                if r.expires_at > now and r.covers_nodata(clean_qname, qtype):
                    self.synthesized_nodata += 1
                    self.cache_hits += 1
                    return r

        return None

    def purge_expired(self) -> int:
        """Removes expired NSEC ranges from all cached zones."""
        now = time.time()
        purged = 0
        with self._lock:
            for zone, ranges in list(self._zones.items()):
                valid_ranges = [r for r in ranges if r.expires_at > now]
                purged += len(ranges) - len(valid_ranges)
                self._zones[zone] = valid_ranges
        return purged

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            total_ranges = sum(len(r) for r in self._zones.values())
            return {
                "rfc": "RFC 8198",
                "cached_zones": len(self._zones),
                "total_cached_ranges": total_ranges,
                "queries_evaluated": self.queries_evaluated,
                "synthesized_nxdomain": self.synthesized_nxdomain,
                "synthesized_nodata": self.synthesized_nodata,
                "total_cache_hits": self.cache_hits,
            }
