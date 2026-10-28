"""
FocusDNS Engine - Authoritative Zone Engine, Split-Horizon Views & TSIG Dynamic DNS
Standards & Protocols:
- RFC 1035: Master Zone File Format & Authoritative Record Management
- RFC 2136: Dynamic Updates in the Domain Name System (DNS UPDATE)
- RFC 2845: Secret Key Transaction Authentication for DNS (TSIG)
- Split-Horizon DNS: Contextual resolution based on client network CIDR blocks
"""

import fnmatch
import hashlib
import hmac
import ipaddress
import struct
import threading
import time
from typing import Dict, List, Optional, Set, Tuple, Any

from dnslib import (
    DNSRecord,
    DNSHeader,
    DNSQuestion,
    RR,
    QTYPE,
    RCODE,
    CLASS,
    A,
    AAAA,
    CNAME,
    MX,
    NS,
    PTR,
    SOA,
    TXT,
    SRV,
    CAA,
)

# Supported TSIG Algorithms
TSIG_HMAC_MD5 = "hmac-md5.sig-alg.reg.int"
TSIG_HMAC_SHA1 = "hmac-sha1"
TSIG_HMAC_SHA256 = "hmac-sha256"
TSIG_HMAC_SHA512 = "hmac-sha512"

HASH_ALGORITHMS = {
    TSIG_HMAC_SHA256: hashlib.sha256,
    TSIG_HMAC_SHA512: hashlib.sha512,
    TSIG_HMAC_SHA1: hashlib.sha1,
    TSIG_HMAC_MD5: hashlib.md5,
}


class TSIGKey:
    """Represents a shared symmetric secret key for RFC 2845 TSIG verification."""

    def __init__(self, name: str, secret: bytes, algorithm: str = TSIG_HMAC_SHA256):
        self.name = name.strip().lower().rstrip(".")
        self.secret = secret
        self.algorithm = algorithm.lower()

    def generate_mac(self, message_wire: bytes, timestamp: int, fudge: int = 300) -> bytes:
        """Computes RFC 2845 HMAC signature over wire DNS message and TSIG pseudo-variables."""
        hash_func = HASH_ALGORITHMS.get(self.algorithm, hashlib.sha256)
        # TSIG signature encompasses message wire + Key Name + Class (ANY) + TTL (0) + Algorithm Name + Time + Fudge
        tsig_trailer = (
            self.name.encode("utf-8")
            + struct.pack("!H", 255)  # CLASS.ANY
            + struct.pack("!I", 0)    # TTL 0
            + self.algorithm.encode("utf-8")
            + struct.pack("!HIH", 0, timestamp, fudge)  # 48-bit unsigned timestamp in seconds + 16-bit fudge
        )
        data = message_wire + tsig_trailer
        return hmac.new(self.secret, data, hash_func).digest()

    def verify_mac(self, message_wire: bytes, mac: bytes, timestamp: int, fudge: int = 300) -> bool:
        """Verifies received TSIG MAC against recomputed digest with clock skew tolerance."""
        now = int(time.time())
        if abs(now - timestamp) > fudge:
            return False
        expected = self.generate_mac(message_wire, timestamp, fudge)
        return hmac.compare_digest(mac, expected)


class AuthoritativeRecord:
    """Represents a single authoritative Resource Record within a zone."""

    def __init__(
        self,
        name: str,
        rtype: str,
        rdata: str,
        ttl: int = 300,
        rclass: str = "IN",
        priority: int = 10,
        weight: int = 10,
        port: int = 0,
    ):
        self.name = name.strip().lower().rstrip(".")
        self.rtype = rtype.strip().upper()
        self.rdata = rdata.strip()
        self.ttl = max(5, ttl)
        self.rclass = rclass.upper()
        self.priority = priority
        self.weight = weight
        self.port = port

    def to_dnslib_rr(self, zone_origin: str = "") -> Optional[RR]:
        """Constructs corresponding dnslib RR object."""
        fqdn = f"{self.name}." if not self.name.endswith(".") else self.name
        qtype_num = getattr(QTYPE, self.rtype, None)
        if qtype_num is None:
            return None

        try:
            if self.rtype == "A":
                rd = A(self.rdata)
            elif self.rtype == "AAAA":
                rd = AAAA(self.rdata)
            elif self.rtype == "CNAME":
                rd = CNAME(f"{self.rdata.rstrip('.')}." )
            elif self.rtype == "TXT":
                rd = TXT(self.rdata.strip('"'))
            elif self.rtype == "MX":
                rd = MX(f"{self.rdata.rstrip('.')}." , preference=self.priority)
            elif self.rtype == "NS":
                rd = NS(f"{self.rdata.rstrip('.')}." )
            elif self.rtype == "PTR":
                rd = PTR(f"{self.rdata.rstrip('.')}." )
            elif self.rtype == "SRV":
                rd = SRV(priority=self.priority, weight=self.weight, port=self.port, target=f"{self.rdata.rstrip('.')}." )
            elif self.rtype == "SOA":
                parts = self.rdata.split()
                mname = parts[0] if len(parts) > 0 else "ns1.focusdns.local."
                rname = parts[1] if len(parts) > 1 else "admin.focusdns.local."
                serial = int(parts[2]) if len(parts) > 2 else int(time.time())
                refresh = int(parts[3]) if len(parts) > 3 else 3600
                retry = int(parts[4]) if len(parts) > 4 else 600
                expire = int(parts[5]) if len(parts) > 5 else 604800
                minimum = int(parts[6]) if len(parts) > 6 else 300
                rd = SOA(mname, rname, (serial, refresh, retry, expire, minimum))
            else:
                return None

            return RR(fqdn, qtype_num, ttl=self.ttl, rdata=rd)
        except Exception:
            return None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "rtype": self.rtype,
            "rdata": self.rdata,
            "ttl": self.ttl,
            "priority": self.priority,
            "port": self.port,
        }


class AuthoritativeZone:
    """
    Represents an RFC 1035 Authoritative DNS Zone.
    Stores and queries RRsets, handles wildcards (*.domain), and generates SOAs.
    """

    def __init__(
        self,
        origin: str,
        default_ttl: int = 3600,
        mname: str = "ns1.focusdns.local.",
        rname: str = "admin.focusdns.local.",
    ):
        self.origin = origin.strip().lower().rstrip(".")
        self.default_ttl = default_ttl
        self.serial = int(time.time())
        self.mname = mname
        self.rname = rname

        # (name, rtype) -> List[AuthoritativeRecord]
        self._records: Dict[Tuple[str, str], List[AuthoritativeRecord]] = {}
        # Wildcard rules
        self._wildcards: List[AuthoritativeRecord] = []
        self._lock = threading.Lock()

        # Insert default apex SOA and NS
        self._init_soa()

    def _init_soa(self):
        soa_data = f"{self.mname} {self.rname} {self.serial} 3600 600 604800 300"
        soa_rec = AuthoritativeRecord(self.origin, "SOA", soa_data, ttl=300)
        self.add_record(soa_rec)
        ns_rec = AuthoritativeRecord(self.origin, "NS", self.mname, ttl=3600)
        self.add_record(ns_rec)

    def add_record(self, record: AuthoritativeRecord):
        """Adds or appends an authoritative record into the zone."""
        with self._lock:
            key = (record.name, record.rtype)
            if record.name.startswith("*."):
                self._wildcards.append(record)
            else:
                if key not in self._records:
                    self._records[key] = []
                self._records[key].append(record)
            self.serial += 1

    def remove_record(self, name: str, rtype: Optional[str] = None, rdata: Optional[str] = None) -> int:
        """Removes matching records from zone."""
        clean_name = name.strip().lower().rstrip(".")
        removed = 0
        with self._lock:
            keys_to_check = [k for k in self._records.keys() if k[0] == clean_name]
            for key in keys_to_check:
                if rtype and key[1] != rtype.upper():
                    continue
                if rdata:
                    before_len = len(self._records[key])
                    self._records[key] = [r for r in self._records[key] if r.rdata != rdata.strip()]
                    removed += before_len - len(self._records[key])
                else:
                    removed += len(self._records[key])
                    del self._records[key]

            # Wildcard removal
            if clean_name.startswith("*."):
                before = len(self._wildcards)
                self._wildcards = [
                    w for w in self._wildcards
                    if not (w.name == clean_name and (not rtype or w.rtype == rtype.upper()))
                ]
                removed += before - len(self._wildcards)

            if removed > 0:
                self.serial += 1
        return removed

    def get_records(self, name: str, rtype: str) -> List[AuthoritativeRecord]:
        """Returns direct list of authoritative records matching name and type."""
        clean = name.strip().lower().rstrip(".")
        clean_rtype = rtype.strip().upper()
        with self._lock:
            return list(self._records.get((clean, clean_rtype), []))

    def query(self, qname: str, qtype: str) -> Tuple[List[AuthoritativeRecord], bool, bool]:
        """
        Queries the zone for matching RRsets.
        Returns (records, is_authoritative, name_exists).
        """
        clean = qname.strip().lower().rstrip(".")
        qtype_upper = qtype.upper()

        # Check if query is within zone origin boundary
        if clean != self.origin and not clean.endswith(f".{self.origin}"):
            return [], False, False

        with self._lock:
            # 1. Exact match on (qname, qtype)
            key = (clean, qtype_upper)
            if key in self._records and self._records[key]:
                return list(self._records[key]), True, True

            # 2. Check for CNAME at qname
            cname_key = (clean, "CNAME")
            if cname_key in self._records and self._records[cname_key]:
                return list(self._records[cname_key]), True, True

            # 3. Check ANY query
            if qtype_upper == "ANY":
                any_matches = []
                for (n, rt), recs in self._records.items():
                    if n == clean:
                        any_matches.extend(recs)
                if any_matches:
                    return any_matches, True, True

            # Check if name exists under any other record type (NODATA condition)
            name_exists = any(k[0] == clean for k in self._records.keys())

            # 4. Check Wildcards (e.g. *.corp.focusdns.local)
            for wc in self._wildcards:
                pattern = wc.name  # e.g. *.corp.focusdns.local
                if fnmatch.fnmatch(clean, pattern):
                    if qtype_upper in (wc.rtype, "ANY"):
                        # Synthetic record matching query name
                        synthetic = AuthoritativeRecord(
                            name=clean,
                            rtype=wc.rtype,
                            rdata=wc.rdata,
                            ttl=wc.ttl,
                            priority=wc.priority,
                            port=wc.port,
                        )
                        return [synthetic], True, True

            return [], True, name_exists

    def get_soa(self) -> Optional[AuthoritativeRecord]:
        """Returns apex SOA record."""
        with self._lock:
            recs = self._records.get((self.origin, "SOA"), [])
            return recs[0] if recs else None

    def export_zone_file(self) -> str:
        """Serializes zone into standard RFC 1035 zone file syntax."""
        lines = [
            f"; FocusDNS Zone File for {self.origin}",
            f"$ORIGIN {self.origin}.",
            f"$TTL {self.default_ttl}",
            "",
        ]
        with self._lock:
            for recs in self._records.values():
                for r in recs:
                    rel_name = "@" if r.name == self.origin else f"{r.name}."
                    lines.append(f"{rel_name:<30} {r.ttl:<6} {r.rclass:<4} {r.rtype:<6} {r.rdata}")
            for r in self._wildcards:
                rel_name = f"{r.name}."
                lines.append(f"{rel_name:<30} {r.ttl:<6} {r.rclass:<4} {r.rtype:<6} {r.rdata}")
        return "\n".join(lines) + "\n"

    def import_zone_file(self, text: str):
        """Parses standard master zone file lines."""
        current_origin = self.origin
        current_ttl = self.default_ttl

        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line or line.startswith(";"):
                continue

            if line.startswith("$ORIGIN"):
                parts = line.split()
                if len(parts) > 1:
                    current_origin = parts[1].rstrip(".")
                continue

            if line.startswith("$TTL"):
                parts = line.split()
                if len(parts) > 1:
                    try:
                        current_ttl = int(parts[1])
                    except ValueError:
                        pass
                continue

            # Standard RR: name [ttl] [class] type rdata...
            tokens = line.split()
            if len(tokens) < 3:
                continue

            idx = 0
            name_token = tokens[idx]
            idx += 1

            if name_token == "@":
                rname = current_origin
            elif name_token.endswith("."):
                rname = name_token.rstrip(".")
            else:
                rname = f"{name_token}.{current_origin}"

            ttl = current_ttl
            if tokens[idx].isdigit():
                ttl = int(tokens[idx])
                idx += 1

            rclass = "IN"
            if tokens[idx].upper() in ("IN", "CH", "HS"):
                rclass = tokens[idx].upper()
                idx += 1

            if idx >= len(tokens):
                continue
            rtype = tokens[idx].upper()
            idx += 1

            rdata = " ".join(tokens[idx:])
            self.add_record(AuthoritativeRecord(rname, rtype, rdata, ttl=ttl, rclass=rclass))


class SplitHorizonView:
    """
    Represents an isolated view with distinct client CIDR access rules.
    Allows returning internal 10.0.0.0/8 IPs for office LAN and public IPs for guests.
    """

    def __init__(self, name: str, subnets: Optional[List[str]] = None, priority: int = 100):
        self.name = name.strip()
        self.priority = priority
        self.networks: List[Any] = []
        if subnets:
            for s in subnets:
                try:
                    self.networks.append(ipaddress.ip_network(s.strip(), strict=False))
                except ValueError:
                    pass

        self._zones: Dict[str, AuthoritativeZone] = {}
        self._lock = threading.Lock()

    def matches_client(self, client_ip: str) -> bool:
        """Checks if client IP falls within any subnet associated with this view."""
        if not self.networks:
            return True  # Default catch-all view
        try:
            ip_obj = ipaddress.ip_address(client_ip.strip())
            return any(ip_obj in net for net in self.networks)
        except ValueError:
            return False

    def add_zone(self, zone: AuthoritativeZone):
        with self._lock:
            self._zones[zone.origin] = zone

    def get_zone(self, origin: str) -> Optional[AuthoritativeZone]:
        clean = origin.strip().lower().rstrip(".")
        with self._lock:
            return self._zones.get(clean)

    def find_zone_for_domain(self, domain: str) -> Optional[AuthoritativeZone]:
        """Finds most specific matching zone origin."""
        clean = domain.strip().lower().rstrip(".")
        parts = clean.split(".")
        with self._lock:
            for i in range(len(parts)):
                sub_origin = ".".join(parts[i:])
                if sub_origin in self._zones:
                    return self._zones[sub_origin]
        return None


class ZoneAuthorityEngine:
    """
    Master coordinator for authoritative zone management, split-horizon routing,
    and RFC 2136 / RFC 2845 Dynamic DNS updates.
    """

    def __init__(self):
        # Views ordered by priority descending
        self._views: List[SplitHorizonView] = []
        # TSIG keys by name
        self._tsig_keys: Dict[str, TSIGKey] = {}
        self._default_view = SplitHorizonView("default", subnets=[], priority=0)
        self._views.append(self._default_view)
        self._lock = threading.Lock()

        # Telemetry
        self._authoritative_hits = 0
        self._updates_processed = 0

    @property
    def default_view(self) -> SplitHorizonView:
        return self._default_view

    def add_zone(self, zone: AuthoritativeZone):
        self._default_view.add_zone(zone)

    def get_zone(self, origin: str) -> Optional[AuthoritativeZone]:
        return self._default_view.get_zone(origin)

    def add_view(self, view: SplitHorizonView):
        with self._lock:
            self._views = [v for v in self._views if v.name != view.name]
            self._views.append(view)
            self._views.sort(key=lambda v: v.priority, reverse=True)

    def add_tsig_key(self, key: TSIGKey):
        with self._lock:
            self._tsig_keys[key.name] = key

    def select_view(self, client_ip: str) -> SplitHorizonView:
        """Selects highest-priority view matching client IP subnet."""
        with self._lock:
            for view in self._views:
                if view.matches_client(client_ip):
                    return view
            return self._default_view

    def resolve_authoritative(
        self,
        req: DNSRecord,
        client_ip: str = "127.0.0.1",
    ) -> Optional[Tuple[bytes, Dict[str, Any]]]:
        """
        Attempts to resolve query using authoritative zones in client's view.
        Returns (reply_bytes, telemetry) if authoritative, or None if external.
        """
        if not req.q:
            return None

        qname = str(req.q.qname).rstrip(".").lower()
        qtype_str = QTYPE.get(req.q.qtype, "A")

        view = self.select_view(client_ip)
        zone = view.find_zone_for_domain(qname)
        if not zone:
            return None

        with self._lock:
            self._authoritative_hits += 1

        records, is_auth, name_exists = zone.query(qname, qtype_str)

        reply = req.reply()
        reply.header.aa = 1  # Authoritative Answer bit
        reply.header.ra = 1

        if records:
            # Positive response
            reply.header.rcode = RCODE.NOERROR
            for r in records:
                rr_obj = r.to_dnslib_rr(zone.origin)
                if rr_obj:
                    reply.add_answer(rr_obj)
            return reply.pack(), {
                "status": "allowed",
                "reason": f"Authoritative Zone [{zone.origin}] ({view.name})",
                "rcode": "NOERROR",
                "view": view.name,
                "authoritative": True,
            }
        elif name_exists:
            # NODATA response (NOERROR with SOA in auth section)
            reply.header.rcode = RCODE.NOERROR
            soa = zone.get_soa()
            if soa:
                soa_rr = soa.to_dnslib_rr(zone.origin)
                if soa_rr:
                    reply.add_auth(soa_rr)
            return reply.pack(), {
                "status": "allowed",
                "reason": f"Authoritative NODATA [{zone.origin}] ({view.name})",
                "rcode": "NOERROR",
                "view": view.name,
                "authoritative": True,
            }
        else:
            # NXDOMAIN (Name Error)
            reply.header.rcode = RCODE.NXDOMAIN
            soa = zone.get_soa()
            if soa:
                soa_rr = soa.to_dnslib_rr(zone.origin)
                if soa_rr:
                    reply.add_auth(soa_rr)
            return reply.pack(), {
                "status": "blocked",
                "reason": f"Authoritative NXDOMAIN [{zone.origin}] ({view.name})",
                "rcode": "NXDOMAIN",
                "view": view.name,
                "authoritative": True,
            }

    def process_dynamic_update(
        self,
        update_bytes: bytes,
        client_ip: str,
        tsig_key_name: Optional[str] = None,
        tsig_mac: Optional[bytes] = None,
        tsig_time: Optional[int] = None,
    ) -> Tuple[int, str]:
        """
        Executes RFC 2136 Dynamic DNS UPDATE with optional RFC 2845 TSIG authentication.
        Returns (rcode, status_message).
        """
        try:
            rec = DNSRecord.parse(update_bytes)
        except Exception:
            return RCODE.FORMERR, "Malformed DNS UPDATE wire packet"

        # Verify TSIG if specified
        if tsig_key_name:
            clean_key = tsig_key_name.strip().lower().rstrip(".")
            with self._lock:
                key = self._tsig_keys.get(clean_key)
            if not key or not tsig_mac or tsig_time is None:
                return RCODE.REFUSED, "TSIG Authentication Required / Unknown Key"
            if not key.verify_mac(update_bytes, tsig_mac, tsig_time):
                return RCODE.NOTAUTH, "TSIG HMAC Signature Verification Failed"

        if not rec.questions:
            return RCODE.FORMERR, "DNS UPDATE missing Zone section"

        zone_name = str(rec.questions[0].qname).rstrip(".").lower()
        view = self.select_view(client_ip)
        zone = view.get_zone(zone_name)
        if not zone:
            return RCODE.NOTAUTH, f"Server Not Authoritative for zone {zone_name}"

        # In RFC 2136:
        # Zone section = Question
        # Prerequisite section = Answer
        # Update section = Authority (NS section)
        # Additional section = Additional

        updated_count = 0
        for rr in rec.auth:
            rname = str(rr.rname).rstrip(".").lower()
            rtype_str = QTYPE.get(rr.rtype, "A")
            ttl = rr.ttl
            rdata_str = str(rr.rdata)

            if rr.rclass == 255:  # CLASS.ANY in RFC 2136
                # Delete RRset
                zone.remove_record(rname, rtype_str)
                updated_count += 1
            elif rr.rclass == 254:  # CLASS.NONE in RFC 2136
                # Delete specific RR from RRset
                zone.remove_record(rname, rtype_str, rdata_str)
                updated_count += 1
            elif rr.rclass == 1:  # CLASS.IN
                # Add RR to RRset
                rec_obj = AuthoritativeRecord(rname, rtype_str, rdata_str, ttl=ttl)
                zone.add_record(rec_obj)
                updated_count += 1

        with self._lock:
            self._updates_processed += 1

        return RCODE.NOERROR, f"Dynamic DNS UPDATE successful: {updated_count} modifications"

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            total_zones = sum(len(v._zones) for v in self._views)
            return {
                "total_views": len(self._views),
                "total_zones": total_zones,
                "authoritative_hits": self._authoritative_hits,
                "updates_processed": self._updates_processed,
                "tsig_keys_configured": len(self._tsig_keys),
            }
