"""
FocusDNS Engine - RFC 7858 DNS-over-TLS (DoT) Server
Features:
- Full RFC 7858 compliance on TCP port 853 (or configurable dev port 8853)
- TLS 1.3 & TLS 1.2 encrypted transport with ALPN 'dot'
- RFC 1035 §4.2.2 2-octet big-endian length prefix stream framing
- Persistent connection pipelining (multiple sequential DNS queries per session)
- Configurable idle timeouts and maximum concurrent connection limits
- Background thread runner with standalone asyncio event loop
"""

import asyncio
import os
import socket
import ssl
import struct
import sys
import threading
import time
from typing import Callable, Optional, Tuple, Dict, Any


from .certs import create_dot_ssl_context

# Standard RFC 7858 port is 853. Default to 8853 in non-root dev environments.
DEFAULT_DOT_PORT = 8853
DEFAULT_IDLE_TIMEOUT = 30.0
MAX_CONCURRENT_CONNECTIONS = 500


class DotServer:
    """
    High-performance asynchronous DNS-over-TLS server.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOT_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        cert_file: Optional[str] = None,
        key_file: Optional[str] = None,
        idle_timeout: float = DEFAULT_IDLE_TIMEOUT,
        max_connections: int = MAX_CONCURRENT_CONNECTIONS,
    ):
        self.host = host
        self.port = port
        self.handler = handler
        self.cert_file = cert_file
        self.key_file = key_file
        self.idle_timeout = idle_timeout
        self.max_connections = max_connections

        self._server: Optional[asyncio.AbstractServer] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._is_running = False
        self._active_connections = 0
        self._total_connections = 0
        self._total_queries = 0
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
                "active_connections": self._active_connections,
                "total_connections": self._total_connections,
                "total_queries": self._total_queries,
            }

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ):
        """
        Processes framed DNS queries from a single TLS connection.
        Adheres to RFC 7858 persistent connection model.
        """
        peer = writer.get_extra_info("peername")
        client_ip = peer[0] if peer else "127.0.0.1"

        with self._lock:
            if self._active_connections >= self.max_connections:
                writer.close()
                await writer.wait_closed()
                return
            self._active_connections += 1
            self._total_connections += 1

        try:
            while self._is_running:
                # 1. Read 2-octet length prefix with idle timeout
                try:
                    len_bytes = await asyncio.wait_for(
                        reader.readexactly(2),
                        timeout=self.idle_timeout,
                    )
                except (asyncio.TimeoutError, asyncio.IncompleteReadError):
                    break

                if len(len_bytes) < 2:
                    break

                query_len = struct.unpack("!H", len_bytes)[0]
                if query_len == 0 or query_len > 65535:
                    break

                # 2. Read query wire payload
                try:
                    query_payload = await asyncio.wait_for(
                        reader.readexactly(query_len),
                        timeout=self.idle_timeout,
                    )
                except (asyncio.TimeoutError, asyncio.IncompleteReadError):
                    break

                with self._lock:
                    self._total_queries += 1

                # 3. Resolve query via handler callback
                reply_bytes: Optional[bytes] = None
                if self.handler:
                    try:
                        reply_bytes, _ = self.handler(query_payload, client_ip)
                    except Exception as ex:
                        sys.stderr.write(f"[DoT Resolution Error] {ex}\n")
                        reply_bytes = None

                # 4. If handler produced a reply, frame and write back
                if reply_bytes:
                    reply_len = len(reply_bytes)
                    framed = struct.pack("!H", reply_len) + reply_bytes
                    writer.write(framed)
                    await writer.drain()

        except (ConnectionResetError, BrokenPipeError):
            pass
        except Exception as e:
            sys.stderr.write(f"[DoT Connection Error] {e}\n")
        finally:
            with self._lock:
                self._active_connections = max(0, self._active_connections - 1)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def start_async(self):
        """Asynchronous start method within an active asyncio event loop."""
        ssl_ctx = create_dot_ssl_context(self.cert_file, self.key_file)
        self._loop = asyncio.get_running_loop()
        self._server = await asyncio.start_server(
            self._handle_client,
            host=self.host,
            port=self.port,
            ssl=ssl_ctx,
            reuse_port=True if hasattr(socket, "SO_REUSEPORT") else False,
        )
        self._is_running = True
        print(f"🔒 FocusDNS RFC 7858 DNS-over-TLS (DoT) active on {self.host}:{self.port} (TLS 1.3/1.2)")

        async with self._server:
            await self._server.serve_forever()

    def stop(self):
        """Signals server to stop and closes listening sockets."""
        self._is_running = False
        if self._loop and self._loop.is_running():
            def _cleanup():
                if self._server:
                    try:
                        self._server.close()
                    except Exception:
                        pass
                for task in asyncio.all_tasks(self._loop):
                    task.cancel()
                self._loop.stop()
            try:
                self._loop.call_soon_threadsafe(_cleanup)
            except Exception:
                pass
        elif self._server:
            try:
                self._server.close()
            except Exception:
                pass



class DotServerThread:
    """
    Background worker thread that manages its own asyncio loop to run the DoT server.
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOT_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
        cert_file: Optional[str] = None,
        key_file: Optional[str] = None,
    ):
        self.server = DotServer(
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
                sys.stderr.write(f"[DoT Server Thread Error] {e}\n")
            finally:
                self._loop.close()

        self._thread = threading.Thread(target=_runner, daemon=True, name="FocusDNS-DoT")
        self._thread.start()

    def stop(self):
        self.server.stop()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
