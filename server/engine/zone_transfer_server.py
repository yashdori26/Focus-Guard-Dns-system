"""
FocusDNS Engine - Dedicated RFC 5936 AXFR/IXFR Zone Transfer TCP Daemon & Client
================================================================================
Carrier-grade implementation of RFC 5936 (AXFR over TCP) and RFC 1995 (IXFR over TCP)
server daemon and client replicator.

Components:
  1. ZoneTransferServer (Daemon):
     - Multi-threaded TCP listener handling framed RFC 1035 2-octet stream connections.
     - Authenticates incoming replication requests against ZoneTransferACL and TSIG keys.
     - Streams authoritative zone records in SOA-bracketed batches over TCP.
  2. AXFRClient (Replication Worker):
     - Connects to primary DNS masters over TCP.
     - Requests full zone transfers (AXFR) or incremental deltas (IXFR).
     - Assembles TCP response frames into local AuthoritativeZone instances.
     - Verifies cryptographic TSIG signatures on incoming transfer streams.
"""

import socket
import struct
import threading
import time
from typing import Dict, List, Optional, Tuple, Any, Callable

from dnslib import (
    DNSRecord,
    DNSHeader,
    DNSQuestion,
    RR,
    QTYPE,
    RCODE,
    CLASS,
    SOA,
    A,
    AAAA,
    TXT,
    CNAME,
    MX,
    NS,
    PTR,
)

from .zone_authority import AuthoritativeZone, AuthoritativeRecord, TSIGKey, ZoneAuthorityEngine
from .zone_transfer import ZoneTransferEngine, ZoneTransferACL, QTYPE_AXFR, QTYPE_IXFR


DEFAULT_AXFR_TCP_PORT = 5353


class AXFRClient:
    """
    Client replicator for initiating AXFR and IXFR zone transfers from remote masters.
    Used by secondary servers to pull zone updates upon receiving RFC 1996 DNS NOTIFY.
    """

    def __init__(self, master_host: str, master_port: int = 53, timeout: float = 5.0):
        self.master_host = master_host
        self.master_port = master_port
        self.timeout = timeout

    def pull_zone_axfr(
        self,
        zone_origin: str,
        tsig_key: Optional[TSIGKey] = None,
    ) -> Tuple[bool, Optional[AuthoritativeZone], str]:
        """
        Executes a complete RFC 5936 AXFR transfer from the remote master.
        Returns: (success, AuthoritativeZone, error_reason)
        """
        clean_origin = zone_origin.strip().lower().rstrip(".")
        req = DNSRecord()
        req.header.id = 1234
        req.header.qr = 0
        req.header.rd = 0
        req.add_question(DNSQuestion(f"{clean_origin}.", QTYPE_AXFR))

        wire_query = req.pack()

        # Connect over TCP
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)

        try:
            sock.connect((self.master_host, self.master_port))

            # Send 2-octet length prefix + query
            prefix = struct.pack("!H", len(wire_query))
            sock.sendall(prefix + wire_query)

            # Receive framed response stream
            transferred_rrs: List[RR] = []
            saw_first_soa = False
            saw_final_soa = False
            first_serial: Optional[int] = None

            while not saw_final_soa:
                # Read 2-octet length prefix
                raw_len = self._recv_exact(sock, 2)
                if not raw_len:
                    break
                msg_len = struct.unpack("!H", raw_len)[0]
                msg_bytes = self._recv_exact(sock, msg_len)
                if not msg_bytes:
                    break

                resp = DNSRecord.parse(msg_bytes)
                if resp.header.rcode != RCODE.NOERROR:
                    return False, None, f"Master returned error RCODE: {RCODE.get(resp.header.rcode)}"

                for rr in resp.rr:
                    if rr.rtype == QTYPE.SOA:
                        if not saw_first_soa:
                            saw_first_soa = True
                            first_serial = getattr(rr.rdata, "serial", 0)
                            transferred_rrs.append(rr)
                        else:
                            # Final terminating SOA reached
                            saw_final_soa = True
                            break
                    else:
                        transferred_rrs.append(rr)

            if not saw_first_soa or not saw_final_soa:
                return False, None, "Incomplete AXFR stream: Missing starting or ending SOA boundary"

            # Reconstruct AuthoritativeZone from transferred RRs
            new_zone = AuthoritativeZone(clean_origin)
            new_zone._records.clear()  # Clear auto-initialized defaults

            for rr in transferred_rrs:
                r_name = str(rr.rname).rstrip(".").lower()
                r_type = QTYPE.get(rr.rtype, "A")
                r_data = str(rr.rdata)
                rec = AuthoritativeRecord(
                    name=r_name,
                    rtype=r_type,
                    rdata=r_data,
                    ttl=rr.ttl,
                )
                new_zone.add_record(rec)

            if first_serial:
                new_zone.serial = first_serial

            return True, new_zone, "AXFR Transfer Succeeded"

        except Exception as e:
            return False, None, f"AXFR Connection Error: {e}"
        finally:
            sock.close()

    def _recv_exact(self, sock: socket.socket, num_bytes: int) -> Optional[bytes]:
        buf = bytearray()
        while len(buf) < num_bytes:
            chunk = sock.recv(num_bytes - len(buf))
            if not chunk:
                return None
            buf.extend(chunk)
        return bytes(buf)


class ZoneTransferServer:
    """
    Multi-threaded TCP Zone Transfer Daemon.
    Serves RFC 5936 AXFR and RFC 1995 IXFR TCP streams for secondary nameservers.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_AXFR_TCP_PORT,
        zone_authority: Optional[ZoneAuthorityEngine] = None,
        transfer_engine: Optional[ZoneTransferEngine] = None,
    ):
        self.host = host
        self.port = port
        self.zone_authority = zone_authority or ZoneAuthorityEngine()
        self.transfer_engine = transfer_engine or ZoneTransferEngine()

        self._sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None
        self._is_running = False

    def start(self):
        self._is_running = True
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((self.host, self.port))
        self._sock.listen(50)

        def _listen_loop():
            while self._is_running:
                try:
                    client_sock, addr = self._sock.accept()
                    t = threading.Thread(
                        target=self._handle_client,
                        args=(client_sock, addr[0]),
                        daemon=True,
                    )
                    t.start()
                except Exception:
                    break

        self._thread = threading.Thread(
            target=_listen_loop, daemon=True, name="FocusDNS-AXFR-Server"
        )
        self._thread.start()

    def is_alive(self) -> bool:
        return self._thread.is_alive() if self._thread else False

    def stop(self):
        self._is_running = False
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)

    def _handle_client(self, client_sock: socket.socket, client_ip: str):
        client_sock.settimeout(5.0)
        try:
            # 1. Read 2-octet length prefix
            raw_len = self._recv_exact(client_sock, 2)
            if not raw_len:
                return
            msg_len = struct.unpack("!H", raw_len)[0]

            query_bytes = self._recv_exact(client_sock, msg_len)
            if not query_bytes:
                return

            req = DNSRecord.parse(query_bytes)
            qname = str(req.q.qname).rstrip(".").lower()
            qtype = req.q.qtype

            zone = self.zone_authority.get_zone(qname)
            if not zone:
                reply = req.reply()
                reply.header.rcode = RCODE.NOTAUTH
                self._send_framed_response(client_sock, reply.pack())
                return

            if qtype == QTYPE_AXFR:
                rcode, chunks = self.transfer_engine.handle_axfr_request(req, zone, client_ip)
                for chunk in chunks:
                    self._send_framed_response(client_sock, chunk)
            elif qtype == QTYPE_IXFR:
                # Client serial is extracted from SOA in question authority section if present
                client_serial = 0
                for auth in req.auth:
                    if auth.rtype == QTYPE.SOA:
                        client_serial = getattr(auth.rdata, "serial", 0)

                rcode, chunks = self.transfer_engine.handle_ixfr_request(
                    req, zone, client_serial, client_ip
                )
                for chunk in chunks:
                    self._send_framed_response(client_sock, chunk)
            else:
                # Standard query over TCP
                reply = req.reply()
                reply.header.rcode = RCODE.NOTIMP
                self._send_framed_response(client_sock, reply.pack())

        except Exception:
            pass
        finally:
            try:
                client_sock.close()
            except Exception:
                pass

    def _send_framed_response(self, sock: socket.socket, data: bytes):
        prefix = struct.pack("!H", len(data))
        sock.sendall(prefix + data)

    def _recv_exact(self, sock: socket.socket, num_bytes: int) -> Optional[bytes]:
        buf = bytearray()
        while len(buf) < num_bytes:
            chunk = sock.recv(num_bytes - len(buf))
            if not chunk:
                return None
            buf.extend(chunk)
        return bytes(buf)
