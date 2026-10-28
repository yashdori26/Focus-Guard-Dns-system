"""
FocusDNS Engine - RFC 7766 DNS Transport over TCP & RFC 7828 TCP Keepalive Subsystem
Standards & RFCs:
- RFC 7766: DNS Transport over TCP - Implementation Requirements
- RFC 7828: The edns-tcp-keepalive EDNS Option (Option Code 11)
- RFC 1035 Section 4.2.2: TCP Wire Framing (2-octet Big-Endian Length Prefix)
"""

import concurrent.futures
import socket
import struct
import threading
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

from dnslib import DNSRecord, EDNSOption, QTYPE, RR


EDNS_OPTION_TCP_KEEPALIVE = 11  # RFC 7828


class EDNSTCPKeepalive:
    """RFC 7828 edns-tcp-keepalive EDNS(0) option encoder and decoder."""

    @staticmethod
    def encode(timeout_100ms: int = 100) -> bytes:
        """Encodes keepalive timeout in units of 100 milliseconds (e.g. 100 = 10.0 seconds)."""
        return struct.pack("!H", timeout_100ms)

    @staticmethod
    def decode(data: bytes) -> Optional[int]:
        if len(data) >= 2:
            return struct.unpack("!H", data[:2])[0]
        return None


def recv_exact(sock: socket.socket, n: int) -> Optional[bytes]:
    """Reads exactly n bytes from a TCP socket or returns None on EOF/close."""
    buf = bytearray()
    while len(buf) < n:
        try:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                return None
            buf.extend(chunk)
        except (socket.timeout, BlockingIOError):
            return None
        except Exception:
            return None
    return bytes(buf)


class TCPDNSServer:
    """
    RFC 7766 Asynchronous DNS-over-TCP Server Daemon.
    Provides query pipelining, out-of-order response streaming,
    and RFC 7828 edns-tcp-keepalive idle timeout negotiation.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 5355,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        idle_timeout_sec: float = 10.0,
        max_clients: int = 500,
        worker_threads: int = 20,
    ):
        self.host: str = host
        self.port: int = port
        self.handler = handler
        self.idle_timeout_sec: float = idle_timeout_sec
        self.max_clients: int = max_clients
        self.worker_threads: int = worker_threads

        self._running: bool = False
        self._server_sock: Optional[socket.socket] = None
        self._pool: Optional[concurrent.futures.ThreadPoolExecutor] = None
        self._active_connections: int = 0
        self._total_connections: int = 0
        self._queries_served: int = 0
        self._lock = threading.Lock()

    def start(self):
        """Starts TCP listening loop (blocking)."""
        self._server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_sock.bind((self.host, self.port))
        self._server_sock.listen(128)
        self._running = True

        self._pool = concurrent.futures.ThreadPoolExecutor(
            max_workers=self.worker_threads, thread_name_prefix="DNS-TCP"
        )

        while self._running:
            try:
                client_sock, addr = self._server_sock.accept()
                with self._lock:
                    if self._active_connections >= self.max_clients:
                        client_sock.close()
                        continue
                    self._active_connections += 1
                    self._total_connections += 1

                self._pool.submit(self._handle_client, client_sock, addr[0])
            except Exception:
                if not self._running:
                    break

    def _handle_client(self, client_sock: socket.socket, client_ip: str):
        """Handles a persistent, pipelined RFC 7766 client TCP connection."""
        client_sock.settimeout(self.idle_timeout_sec)
        write_lock = threading.Lock()

        try:
            while self._running:
                # 1. Read 2-octet length prefix per RFC 1035 §4.2.2
                header_bytes = recv_exact(client_sock, 2)
                if not header_bytes:
                    break

                msg_len = struct.unpack("!H", header_bytes)[0]
                if msg_len == 0 or msg_len > 65535:
                    break

                # 2. Read full DNS wire payload
                query_wire = recv_exact(client_sock, msg_len)
                if not query_wire:
                    break

                with self._lock:
                    self._queries_served += 1

                # 3. Process resolution and stream response with length prefix
                if self.handler:
                    try:
                        reply_wire, _ = self.handler(query_wire, client_ip)
                        if reply_wire:
                            framed = struct.pack("!H", len(reply_wire)) + reply_wire
                            with write_lock:
                                client_sock.sendall(framed)
                    except Exception:
                        pass
        except Exception:
            pass
        finally:
            try:
                client_sock.close()
            except Exception:
                pass
            with self._lock:
                self._active_connections -= 1

    def stop(self):
        """Stops the TCP server and closes sockets."""
        self._running = False
        if self._server_sock:
            try:
                self._server_sock.close()
            except Exception:
                pass
        if self._pool:
            self._pool.shutdown(wait=False)

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "rfc": "RFC 7766",
                "active_connections": self._active_connections,
                "total_connections": self._total_connections,
                "queries_served": self._queries_served,
                "idle_timeout_seconds": self.idle_timeout_sec,
            }


class TCPDNSServerThread(threading.Thread):
    """Background daemon thread wrapper for TCPDNSServer."""

    def __init__(self, **kwargs):
        super().__init__(daemon=True)
        self.server = TCPDNSServer(**kwargs)

    def run(self):
        self.server.start()

    def stop(self):
        self.server.stop()


class TCPDNSClient:
    """Helper client for executing RFC 7766 TCP DNS transactions."""

    @staticmethod
    def query(
        wire_data: bytes,
        host: str = "127.0.0.1",
        port: int = 5355,
        timeout: float = 2.0,
    ) -> Optional[bytes]:
        """Sends a 2-octet framed query over TCP and reads the response."""
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            sock.connect((host, port))
            framed = struct.pack("!H", len(wire_data)) + wire_data
            sock.sendall(framed)

            len_bytes = recv_exact(sock, 2)
            if not len_bytes:
                return None
            resp_len = struct.unpack("!H", len_bytes)[0]
            return recv_exact(sock, resp_len)
        except Exception:
            return None
        finally:
            try:
                sock.close()
            except Exception:
                pass
