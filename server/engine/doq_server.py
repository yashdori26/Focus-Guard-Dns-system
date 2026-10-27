"""
FocusDNS Engine - RFC 9250 DNS-over-QUIC (DoQ) Server
Features:
- Full RFC 9250 compliance using aioquic
- ALPN 'doq' negotiation
- RFC 9250 §4 bidirectional stream framing (2-octet length prefix)
- TLS 1.3 0-RTT session ticket resumption & caching
- Background thread runner with standalone asyncio event loop
- Thread-safe statistics reporting
"""

import asyncio
import datetime
import os
import struct
import sys
import threading
import time
from typing import Callable, Optional, Tuple, Dict, Any

from aioquic.asyncio import serve
from aioquic.asyncio.server import QuicServer
from aioquic.tls import SessionTicket

from .certs import create_doq_quic_configuration

DEFAULT_DOQ_PORT = 8854
STREAM_TIMEOUT = 10.0


class SessionTicketStore:
    """Thread-safe store for TLS 1.3 / QUIC 0-RTT session tickets."""

    def __init__(self, max_tickets: int = 1000):
        self._tickets: Dict[bytes, SessionTicket] = {}
        self._lock = threading.Lock()
        self._max_tickets = max_tickets

    def add(self, ticket: SessionTicket):
        with self._lock:
            if len(self._tickets) >= self._max_tickets:
                # Evict oldest entry
                oldest_key = next(iter(self._tickets))
                del self._tickets[oldest_key]
            self._tickets[ticket.ticket] = ticket

    def get(self, ticket_id: bytes) -> Optional[SessionTicket]:
        with self._lock:
            ticket = self._tickets.get(ticket_id)
            if ticket:
                now = datetime.datetime.now(datetime.timezone.utc)
                if ticket.not_valid_after and ticket.not_valid_after < now:
                    del self._tickets[ticket_id]
                    return None
            return ticket


class DoqServer:
    """
    High-performance RFC 9250 DNS-over-QUIC server.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOQ_PORT,
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
        self._active_streams = 0
        self._resumed_sessions = 0
        self._lock = threading.Lock()

    @property
    def is_running(self) -> bool:
        return self._is_running

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "is_running": self._is_running,
                "host": self.host,
                "port": self.port,
                "total_queries": self._total_queries,
                "active_streams": self._active_streams,
                "resumed_sessions": self._resumed_sessions,
            }

    async def _stream_handler(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ):
        """
        Processes a single DoQ bidirectional stream transaction (RFC 9250 §4).
        """
        peer = writer.get_extra_info("peername")
        client_ip = peer[0] if peer else "127.0.0.1"

        with self._lock:
            self._active_streams += 1

        try:
            # 1. Read 2-octet length prefix
            len_bytes = await asyncio.wait_for(
                reader.readexactly(2),
                timeout=STREAM_TIMEOUT,
            )
            query_len = struct.unpack("!H", len_bytes)[0]
            if query_len == 0 or query_len > 65535:
                return

            # 2. Read query payload
            query_payload = await asyncio.wait_for(
                reader.readexactly(query_len),
                timeout=STREAM_TIMEOUT,
            )

            with self._lock:
                self._total_queries += 1

            # 3. Resolve via pipeline / resolver callback
            reply_bytes: Optional[bytes] = None
            if self.handler:
                try:
                    reply_bytes, _ = self.handler(query_payload, client_ip)
                except Exception as ex:
                    sys.stderr.write(f"[DoQ Resolution Error] {ex}\n")
                    reply_bytes = None

            # 4. Write back framed response & close stream
            if reply_bytes:
                reply_len = len(reply_bytes)
                framed = struct.pack("!H", reply_len) + reply_bytes
                writer.write(framed)
                await writer.drain()

        except (asyncio.TimeoutError, asyncio.IncompleteReadError):
            pass
        except Exception as e:
            sys.stderr.write(f"[DoQ Stream Error] {e}\n")
        finally:
            with self._lock:
                self._active_streams = max(0, self._active_streams - 1)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    def _on_session_ticket(self, ticket: SessionTicket):
        self._ticket_store.add(ticket)

    def _fetch_session_ticket(self, ticket_id: bytes) -> Optional[SessionTicket]:
        t = self._ticket_store.get(ticket_id)
        if t:
            with self._lock:
                self._resumed_sessions += 1
        return t

    async def start_async(self):
        """Starts the QUIC server asynchronously within the current event loop."""
        quic_conf = create_doq_quic_configuration(self.cert_file, self.key_file)
        self._loop = asyncio.get_running_loop()

        self._server = await serve(
            host=self.host,
            port=self.port,
            configuration=quic_conf,
            stream_handler=self._stream_handler,
            session_ticket_handler=self._on_session_ticket,
            session_ticket_fetcher=self._fetch_session_ticket,
        )
        self._is_running = True
        print(f"⚡ FocusDNS RFC 9250 DNS-over-QUIC (DoQ) active on {self.host}:{self.port} (ALPN: doq, 0-RTT)")

        # Keep server running until stopped
        try:
            while self._is_running:
                await asyncio.sleep(1.0)
        finally:
            if self._server:
                self._server.close()

    def stop(self):
        """Stops the DoQ server."""
        self._is_running = False
        if self._server:
            self._server.close()
        if self._loop and self._loop.is_running():
            def _cleanup():
                for task in asyncio.all_tasks(self._loop):
                    task.cancel()
                self._loop.stop()
            self._loop.call_soon_threadsafe(_cleanup)



class DoqServerThread:
    """Background worker thread running the DoQ server on an independent event loop."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOQ_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        cert_file: Optional[str] = None,
        key_file: Optional[str] = None,
    ):
        self.server = DoqServer(
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
            except (asyncio.CancelledError, KeyboardInterrupt):
                pass
            except Exception as e:
                sys.stderr.write(f"[DoQ Server Thread Error] {e}\n")
            finally:
                self._loop.close()

        self._thread = threading.Thread(target=_runner, daemon=True, name="FocusDNS-DoQ")
        self._thread.start()

    def stop(self):
        self.server.stop()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
