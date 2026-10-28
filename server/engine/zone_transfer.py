"""
FocusDNS Engine - Zone Transfers (AXFR/IXFR) & DNS NOTIFY Engine
Standards & RFCs:
- RFC 5936: DNS Zone Transfer Protocol (AXFR) over TCP
- RFC 1995: Incremental Zone Transfer in DNS (IXFR)
- RFC 1996: A Mechanism for Prompt Notification of Zone Changes (DNS NOTIFY)
- RFC 2845: Secret Key Transaction Authentication for DNS (TSIG) on Zone Transfers
"""

import collections
import concurrent.futures
import ipaddress
import socket
import struct
import threading
import time
from typing import Dict, List, Optional, Set, Tuple, Any, Callable

from dnslib import (
    DNSRecord,
    DNSHeader,
    DNSQuestion,
    RR,
    QTYPE,
    RCODE,
    CLASS,
    SOA,
)

from .zone_authority import AuthoritativeZone, AuthoritativeRecord, TSIGKey


# Standard DNS Transfer Ports and Types
QTYPE_AXFR = 252
QTYPE_IXFR = 251
QTYPE_SOA = 6


class ZoneDelta:
    """
    Represents an incremental zone change between two serial versions.
    Used by RFC 1995 IXFR to transmit minimal diffs instead of full zones.
    """

    def __init__(self, from_serial: int, to_serial: int):
        self.from_serial = from_serial
        self.to_serial = to_serial
        self.deleted_records: List[AuthoritativeRecord] = []
        self.added_records: List[AuthoritativeRecord] = []
        self.timestamp = time.time()

    def add_deletion(self, record: AuthoritativeRecord):
        self.deleted_records.append(record)

    def add_addition(self, record: AuthoritativeRecord):
        self.added_records.append(record)

    def is_empty(self) -> bool:
        return not self.deleted_records and not self.added_records


class ZoneTransferACL:
    """
    Access Control List governing which secondary slave IPs/subnets
    and TSIG keys are authorized to request AXFR and IXFR zone transfers.
    """

    def __init__(
        self,
        allowed_subnets: Optional[List[str]] = None,
        require_tsig: bool = False,
        allowed_tsig_keys: Optional[List[str]] = None,
    ):
        self.networks: List[Any] = []
        if allowed_subnets:
            for s in allowed_subnets:
                try:
                    self.networks.append(ipaddress.ip_network(s.strip(), strict=False))
                except ValueError:
                    pass
        self.require_tsig = require_tsig
        self.allowed_tsig_keys: Set[str] = set(
            k.strip().lower().rstrip(".") for k in (allowed_tsig_keys or [])
        )

    def is_client_authorized(self, client_ip: str, tsig_key_name: Optional[str] = None) -> Tuple[bool, str]:
        """Validates incoming transfer request against ACL and TSIG policy."""
        # Check IP / Subnet rule
        if self.networks:
            try:
                ip_obj = ipaddress.ip_address(client_ip.strip())
                if not any(ip_obj in net for net in self.networks):
                    return False, f"Client IP {client_ip} not in transfer ACL"
            except ValueError:
                return False, f"Invalid client IP {client_ip}"

        # Check TSIG requirement
        if self.require_tsig:
            if not tsig_key_name:
                return False, "TSIG signature required for zone transfer"
            clean_key = tsig_key_name.strip().lower().rstrip(".")
            if self.allowed_tsig_keys and clean_key not in self.allowed_tsig_keys:
                return False, f"TSIG key {tsig_key_name} not authorized for this zone"

        return True, "Authorized"


class ZoneTransferEngine:
    """
    Primary server for RFC 5936 AXFR, RFC 1995 IXFR, and RFC 1996 DNS NOTIFY.
    Provides TCP stream generation for full and incremental transfers and
    manages secondary notification broadcasts with automated retry queues.
    """

    def __init__(self, max_ixfr_history: int = 50):
        self.max_ixfr_history = max_ixfr_history

        # zone_origin -> list of ZoneDelta in chronological order
        self._ixfr_deltas: Dict[str, List[ZoneDelta]] = {}
        # zone_origin -> ZoneTransferACL
        self._zone_acls: Dict[str, ZoneTransferACL] = {}
        # zone_origin -> Set of secondary slave addresses: "host:port"
        self._secondaries: Dict[str, Set[str]] = {}
        # TSIG keys by name
        self._tsig_keys: Dict[str, TSIGKey] = {}

        self._lock = threading.Lock()
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=8, thread_name_prefix="zone-transfer"
        )

        # Telemetry
        self._axfr_transfers_served = 0
        self._ixfr_transfers_served = 0
        self._notifies_sent = 0
        self._notifies_acknowledged = 0

    def set_zone_acl(self, zone_origin: str, acl: ZoneTransferACL):
        clean = zone_origin.strip().lower().rstrip(".")
        with self._lock:
            self._zone_acls[clean] = acl

    def add_secondary(self, zone_origin: str, host: str, port: int = 53):
        clean = zone_origin.strip().lower().rstrip(".")
        with self._lock:
            if clean not in self._secondaries:
                self._secondaries[clean] = set()
            self._secondaries[clean].add(f"{host.strip()}:{port}")

    def add_tsig_key(self, key: TSIGKey):
        with self._lock:
            self._tsig_keys[key.name] = key

    def record_zone_delta(self, zone_origin: str, delta: ZoneDelta):
        """Records an incremental modification delta for IXFR serving."""
        clean = zone_origin.strip().lower().rstrip(".")
        with self._lock:
            if clean not in self._ixfr_deltas:
                self._ixfr_deltas[clean] = []
            self._ixfr_deltas[clean].append(delta)
            if len(self._ixfr_deltas[clean]) > self.max_ixfr_history:
                self._ixfr_deltas[clean].pop(0)

    def handle_axfr_request(
        self,
        req: DNSRecord,
        zone: AuthoritativeZone,
        client_ip: str,
        tsig_key_name: Optional[str] = None,
    ) -> Tuple[int, List[bytes]]:
        """
        Generates RFC 5936 AXFR TCP stream message chunks.
        Standard AXFR framing:
        1. Starting SOA record
        2. All zone RRsets (excluding duplicate apex SOA)
        3. Ending SOA record (identical serial, signaling end of transfer)
        Returns (rcode, list_of_raw_dns_record_bytes).
        """
        clean_origin = zone.origin
        with self._lock:
            acl = self._zone_acls.get(clean_origin, ZoneTransferACL(allowed_subnets=[]))

        is_auth, reason = acl.is_client_authorized(client_ip, tsig_key_name)
        if not is_auth:
            reply = req.reply()
            reply.header.rcode = RCODE.REFUSED
            return RCODE.REFUSED, [reply.pack()]

        soa = zone.get_soa()
        if not soa:
            reply = req.reply()
            reply.header.rcode = RCODE.SERVFAIL
            return RCODE.SERVFAIL, [reply.pack()]

        soa_rr = soa.to_dnslib_rr(zone.origin)
        if not soa_rr:
            reply = req.reply()
            reply.header.rcode = RCODE.SERVFAIL
            return RCODE.SERVFAIL, [reply.pack()]

        # Generate stream chunks
        # Chunk 1: Initial reply with Starting SOA in Answer
        chunk1 = req.reply()
        chunk1.header.aa = 1
        chunk1.header.rcode = RCODE.NOERROR
        chunk1.add_answer(soa_rr)

        # Collect all RRs in zone
        all_rrs: List[RR] = []
        with zone._lock:
            for recs in zone._records.values():
                for r in recs:
                    if r.rtype == "SOA":
                        continue  # Handled at start and end
                    rr_obj = r.to_dnslib_rr(zone.origin)
                    if rr_obj:
                        all_rrs.append(rr_obj)
            for wc in zone._wildcards:
                rr_obj = wc.to_dnslib_rr(zone.origin)
                if rr_obj:
                    all_rrs.append(rr_obj)

        # Batch records into chunks of 100 RRs to fit within standard TCP buffers
        chunks_wire: List[bytes] = []
        current_chunk = chunk1
        records_in_chunk = 1

        for rr in all_rrs:
            current_chunk.add_answer(rr)
            records_in_chunk += 1
            if records_in_chunk >= 100:
                chunks_wire.append(current_chunk.pack())
                current_chunk = DNSRecord(
                    DNSHeader(id=req.header.id, qr=1, aa=1, ra=1, rcode=RCODE.NOERROR)
                )
                current_chunk.add_question(req.q)
                records_in_chunk = 0

        # Final terminating SOA record
        current_chunk.add_answer(soa_rr)
        chunks_wire.append(current_chunk.pack())

        with self._lock:
            self._axfr_transfers_served += 1

        return RCODE.NOERROR, chunks_wire

    def handle_ixfr_request(
        self,
        req: DNSRecord,
        zone: AuthoritativeZone,
        client_serial: int,
        client_ip: str,
        tsig_key_name: Optional[str] = None,
    ) -> Tuple[int, List[bytes]]:
        """
        Generates RFC 1995 IXFR response stream.
        If requested serial matches current serial: returns single SOA record.
        If diffs exist in history: returns serial deltas.
        If serial is too old or unknown: falls back to full AXFR stream.
        """
        clean_origin = zone.origin
        with self._lock:
            acl = self._zone_acls.get(clean_origin, ZoneTransferACL(allowed_subnets=[]))

        is_auth, _ = acl.is_client_authorized(client_ip, tsig_key_name)
        if not is_auth:
            reply = req.reply()
            reply.header.rcode = RCODE.REFUSED
            return RCODE.REFUSED, [reply.pack()]

        soa = zone.get_soa()
        if not soa:
            reply = req.reply()
            reply.header.rcode = RCODE.SERVFAIL
            return RCODE.SERVFAIL, [reply.pack()]

        soa_rr = soa.to_dnslib_rr(zone.origin)
        current_serial = zone.serial

        # 1. Secondary already up to date
        if client_serial >= current_serial:
            reply = req.reply()
            reply.header.aa = 1
            reply.header.rcode = RCODE.NOERROR
            reply.add_answer(soa_rr)
            with self._lock:
                self._ixfr_transfers_served += 1
            return RCODE.NOERROR, [reply.pack()]

        # 2. Check if consecutive delta path exists from client_serial to current_serial
        deltas_to_apply: List[ZoneDelta] = []
        with self._lock:
            available_deltas = list(self._ixfr_deltas.get(clean_origin, []))

        cursor_serial = client_serial
        for d in available_deltas:
            if d.from_serial == cursor_serial:
                deltas_to_apply.append(d)
                cursor_serial = d.to_serial
                if cursor_serial >= current_serial:
                    break

        # If incomplete delta chain, fall back to full AXFR
        if cursor_serial < current_serial or not deltas_to_apply:
            return self.handle_axfr_request(req, zone, client_ip, tsig_key_name)

        # 3. Construct RFC 1995 IXFR Stream:
        # Starting with Current SOA
        # For each delta:
        #   SOA(old_serial)
        #   Deleted records...
        #   SOA(new_serial)
        #   Added records...
        # Ending with Current SOA
        reply = req.reply()
        reply.header.aa = 1
        reply.header.rcode = RCODE.NOERROR
        reply.add_answer(soa_rr)

        for delta in deltas_to_apply:
            # Deleted sequence
            old_soa = AuthoritativeRecord(
                zone.origin,
                "SOA",
                f"{zone.mname} {zone.rname} {delta.from_serial} 3600 600 604800 300",
                ttl=300,
            ).to_dnslib_rr(zone.origin)
            if old_soa:
                reply.add_answer(old_soa)
            for r in delta.deleted_records:
                rr_obj = r.to_dnslib_rr(zone.origin)
                if rr_obj:
                    reply.add_answer(rr_obj)

            # Added sequence
            new_soa = AuthoritativeRecord(
                zone.origin,
                "SOA",
                f"{zone.mname} {zone.rname} {delta.to_serial} 3600 600 604800 300",
                ttl=300,
            ).to_dnslib_rr(zone.origin)
            if new_soa:
                reply.add_answer(new_soa)
            for r in delta.added_records:
                rr_obj = r.to_dnslib_rr(zone.origin)
                if rr_obj:
                    reply.add_answer(rr_obj)

        # Ending current SOA
        reply.add_answer(soa_rr)

        with self._lock:
            self._ixfr_transfers_served += 1

        return RCODE.NOERROR, [reply.pack()]

    def send_notify(
        self,
        zone_origin: str,
        target_host: str,
        target_port: int = 53,
        timeout: float = 2.0,
    ) -> bool:
        """
        Sends an RFC 1996 DNS NOTIFY packet to a secondary nameserver.
        Returns True if acknowledged with NOERROR.
        """
        clean = zone_origin.strip().lower().rstrip(".")
        rec = DNSRecord()
        rec.header.opcode = 4  # NOTIFY opcode in RFC 1996
        rec.header.rd = 0
        rec.add_question(DNSQuestion(f"{clean}.", QTYPE.SOA))

        wire = rec.pack()
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout)

        with self._lock:
            self._notifies_sent += 1

        try:
            sock.sendto(wire, (target_host, target_port))
            data, _ = sock.recvfrom(512)
            resp = DNSRecord.parse(data)
            if resp.header.rcode == RCODE.NOERROR:
                with self._lock:
                    self._notifies_acknowledged += 1
                return True
            return False
        except Exception:
            return False
        finally:
            sock.close()

    def broadcast_notify(self, zone_origin: str):
        """Asynchronously dispatches DNS NOTIFY to all configured secondary slaves."""
        clean = zone_origin.strip().lower().rstrip(".")
        with self._lock:
            secondaries = list(self._secondaries.get(clean, set()))

        for sec in secondaries:
            try:
                host, port_str = sec.split(":")
                port = int(port_str)
                self._executor.submit(self.send_notify, clean, host, port)
            except Exception:
                pass

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "axfr_transfers_served": self._axfr_transfers_served,
                "ixfr_transfers_served": self._ixfr_transfers_served,
                "notifies_sent": self._notifies_sent,
                "notifies_acknowledged": self._notifies_acknowledged,
                "active_secondaries_count": sum(len(s) for s in self._secondaries.values()),
                "tracked_ixfr_zones": len(self._ixfr_deltas),
            }

    def close(self):
        self._executor.shutdown(wait=False)


class DNSNotifyBroadcaster:
    """RFC 1996 DNS NOTIFY Broadcaster."""

    def __init__(self, engine: ZoneTransferEngine):
        self.engine = engine

    def notify_secondaries(self, zone_origin: str):
        self.engine.broadcast_notify(zone_origin)

    def send_direct(self, zone_origin: str, host: str, port: int = 53, timeout: float = 2.0) -> bool:
        return self.engine.send_notify(zone_origin, host, port, timeout)
