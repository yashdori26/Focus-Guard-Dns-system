"""
FocusDNS Engine - RFC 9114 HTTP/3 & RFC 8484 DNS-over-HTTP/3 (DoH3) Server
Features:
- Complete RFC 9114 HTTP/3 over QUIC implementation using aioquic.h3
- RFC 8484 DNS Queries:
  * GET /dns-query?dns=<base64url> (RFC 8484 §4.1.1)
  * POST /dns-query with Content-Type: application/dns-message (RFC 8484 §4.1.2)
- Fast base64url padding reconstruction
- HTTP/3 Response Framing with application/dns-message and Cache-Control
- 0-RTT session resumption support
- Standalone background thread runner with dedicated asyncio event loop
"""

import asyncio
import base64
import os
import sys
import threading
import time
import urllib.parse
from typing import Callable, Optional, Tuple, Dict, Any, List

from aioquic.asyncio import serve, QuicConnectionProtocol
from aioquic.asyncio.server import QuicServer
from aioquic.h3.connection import H3Connection
from aioquic.h3.events import HeadersReceived, DataReceived
from aioquic.quic.configuration import QuicConfiguration
from aioquic.tls import SessionTicket

from .certs import ensure_certificates
from .doq_server import SessionTicketStore

DEFAULT_DOH3_PORT = 8443
DOH_PATH = "/dns-query"


def decode_base64url_dns(encoded: str) -> Optional[bytes]:
    """
    Decodes RFC 8484 §4.1.1 base64url string with missing padding.
    """
    clean = encoded.strip().replace(" ", "+")
    # Restore missing '=' padding
    missing_padding = len(clean) % 4
    if missing_padding:
        clean += "=" * (4 - missing_padding)
    try:
        data = base64.urlsafe_b64decode(clean.encode("ascii"))
        return data if len(data) >= 12 else None
    except Exception:
        return None


class Doh3ServerProtocol(QuicConnectionProtocol):
    """
    Asynchronous connection protocol handling HTTP/3 stream events
    and multiplexing RFC 8484 DNS-over-HTTP/3 transactions.
    """

    def __init__(self, *args, **kwargs):
        self._handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = kwargs.pop("handler", None)
        self._stats_callback: Optional[Callable[[], None]] = kwargs.pop("stats_callback", None)
        super().__init__(*args, **kwargs)

        self._http: Optional[H3Connection] = None
        self._requests: Dict[int, Dict[str, Any]] = {}

    def quic_event_received(self, event):
        if self._http is None:
            self._http = H3Connection(self._quic)

        # Feed QUIC event into HTTP/3 state machine
        for h3_event in self._http.handle_event(event):
            self._process_h3_event(h3_event)

        # Transmit any pending frames
        self.transmit()

    def _process_h3_event(self, h3_event):
        stream_id = h3_event.stream_id

        if isinstance(h3_event, HeadersReceived):
            # Parse HTTP headers into lowercase dict
            raw_headers: List[Tuple[bytes, bytes]] = h3_event.headers
            hdr_dict = {}
            for k, v in raw_headers:
                hdr_dict[k.decode("ascii", errors="replace").lower()] = v.decode("ascii", errors="replace")

            self._requests[stream_id] = {
                "method": hdr_dict.get(":method", "GET").upper(),
                "path": hdr_dict.get(":path", "/"),
                "content_type": hdr_dict.get("content-type", ""),
                "body": bytearray(),
            }

            if h3_event.stream_ended:
                self._dispatch_request(stream_id)

        elif isinstance(h3_event, DataReceived):
            req = self._requests.get(stream_id)
            if req is not None:
                req["body"].extend(h3_event.data)
                if h3_event.stream_ended:
                    self._dispatch_request(stream_id)

    def _dispatch_request(self, stream_id: int):
        req = self._requests.pop(stream_id, None)
        if not req or not self._http:
            return

        method = req["method"]
        path = req["path"]
        content_type = req["content_type"]
        body = bytes(req["body"])

        peer = self._quic.get_extra_info("peername") if hasattr(self._quic, "get_extra_info") else None
        client_ip = peer[0] if peer else "127.0.0.1"

        if self._stats_callback:
            self._stats_callback()

        # Parse URL path and query string
        parsed_url = urllib.parse.urlparse(path)
        if parsed_url.path != DOH_PATH:
            self._send_response(stream_id, 404, b"Not Found", "text/plain")
            return

        query_bytes: Optional[bytes] = None

        if method == "GET":
            # RFC 8484 §4.1.1: GET /dns-query?dns=<base64url>
            query_params = urllib.parse.parse_qs(parsed_url.query)
            dns_param = query_params.get("dns", [None])[0]
            if not dns_param:
                self._send_response(stream_id, 400, b"Missing 'dns' parameter in GET query", "text/plain")
                return
            query_bytes = decode_base64url_dns(dns_param)
            if not query_bytes:
                self._send_response(stream_id, 400, b"Invalid base64url encoding", "text/plain")
                return

        elif method == "POST":
            # RFC 8484 §4.1.2: POST /dns-query with binary payload
            if "application/dns-message" not in content_type:
                self._send_response(stream_id, 415, b"Unsupported Media Type: expected application/dns-message", "text/plain")
                return
            if not body:
                self._send_response(stream_id, 400, b"Empty DNS query body", "text/plain")
                return
            query_bytes = body

        else:
            self._send_response(stream_id, 405, b"Method Not Allowed: use GET or POST", "text/plain")
            return

        # Execute query via handler
        reply_wire: Optional[bytes] = None
        if self._handler and query_bytes:
            try:
                reply_wire, _ = self._handler(query_bytes, client_ip)
            except Exception as e:
                sys.stderr.write(f"[DoH3 Resolution Error] {e}\n")
                reply_wire = None

        if reply_wire:
            self._send_response(
                stream_id,
                200,
                reply_wire,
                "application/dns-message",
                cache_control="max-age=60",
            )
        else:
            self._send_response(stream_id, 500, b"Internal Server Error", "text/plain")

    def _send_response(
        self,
        stream_id: int,
        status: int,
        body: bytes,
        content_type: str,
        cache_control: Optional[str] = None,
    ):
        if not self._http:
            return

        headers = [
            (b":status", str(status).encode("ascii")),
            (b"content-type", content_type.encode("ascii")),
            (b"content-length", str(len(body)).encode("ascii")),
            (b"server", b"FocusDNS-DoH3/2.0"),
        ]
        if cache_control:
            headers.append((b"cache-control", cache_control.encode("ascii")))

        self._http.send_headers(stream_id, headers, end_stream=False)
        self._http.send_data(stream_id, body, end_stream=True)


class Doh3Server:
    """
    High-performance RFC 9114 HTTP/3 and RFC 8484 DoH3 server.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOH3_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        cert_file: Optional[str] = None,
        key_file: Optional[str] = None,
    ):
        self.host = host
        self.port = port
        self.handler = handler
        self.cert_file = cert_file
        self.key_file = key_file

        self._server: Optional[QuicServer] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._is_running = False
        self._ticket_store = SessionTicketStore()

        self._total_queries = 0
        self._lock = threading.Lock()

    @property
    def is_running(self) -> bool:
        return self._is_running

    def _on_query(self):
        with self._lock:
            self._total_queries += 1

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "is_running": self._is_running,
                "host": self.host,
                "port": self.port,
                "protocol": "HTTP/3 (DoH3)",
                "total_queries": self._total_queries,
            }

    async def start_async(self):
        """Asynchronous start method within an active asyncio event loop."""
        cert_path, key_path = ensure_certificates(self.cert_file, self.key_file)

        quic_conf = QuicConfiguration(
            is_client=False,
            alpn_protocols=["h3"],
            max_datagram_frame_size=65536,
            idle_timeout=60.0,
        )
        quic_conf.load_cert_chain(certfile=cert_path, keyfile=key_path)

        def _protocol_factory(*args, **kwargs):
            return Doh3ServerProtocol(
                *args,
                handler=self.handler,
                stats_callback=self._on_query,
                **kwargs,
            )

        self._loop = asyncio.get_running_loop()
        self._server = await serve(
            host=self.host,
            port=self.port,
            configuration=quic_conf,
            create_protocol=_protocol_factory,
            session_ticket_handler=self._ticket_store.add,
            session_ticket_fetcher=self._ticket_store.get,
        )
        self._is_running = True
        print(f"🚀 FocusDNS RFC 9114 DNS-over-HTTP/3 (DoH3) active on {self.host}:{self.port} (ALPN: h3, 0-RTT)")

        try:
            while self._is_running:
                await asyncio.sleep(1.0)
        finally:
            if self._server:
                self._server.close()

    def stop(self):
        """Signals server to stop and closes QUIC UDP listening sockets."""
        self._is_running = False
        if self._server:
            self._server.close()
        if self._loop and self._loop.is_running():
            def _cleanup():
                for task in asyncio.all_tasks(self._loop):
                    task.cancel()
                self._loop.stop()
            self._loop.call_soon_threadsafe(_cleanup)


class Doh3ServerThread:
    """Background worker thread running DoH3 on an independent asyncio event loop."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOH3_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        cert_file: Optional[str] = None,
        key_file: Optional[str] = None,
    ):
        self.server = Doh3Server(
            host=host,
            port=port,
            handler=handler,
            cert_file=cert_file,
            key_file=key_file,
        )
        self._thread: Optional[threading.Thread] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def start(self):
        def _runner():
            self._loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._loop)
            try:
                self._loop.run_until_complete(self.server.start_async())
            except (asyncio.CancelledError, KeyboardInterrupt, RuntimeError):
                pass
            except Exception as e:
                sys.stderr.write(f"[DoH3 Server Thread Error] {e}\n")
            finally:
                self._loop.close()

        self._thread = threading.Thread(target=_runner, daemon=True, name="FocusDNS-DoH3")
        self._thread.start()

    def is_alive(self) -> bool:
        return self._thread.is_alive() if self._thread else False

    def join(self, timeout: Optional[float] = None):
        if self._thread:
            self._thread.join(timeout=timeout)

    def stop(self):
        self.server.stop()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
