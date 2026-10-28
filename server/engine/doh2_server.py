"""
FocusDNS Engine - Dedicated RFC 7540 HTTP/2 DNS-over-HTTPS (DoH2) Multiplexer
Standards & RFCs:
- RFC 7540: Hypertext Transfer Protocol Version 2 (HTTP/2)
- RFC 7541: HPACK Header Compression for HTTP/2
- RFC 8484: DNS Queries over HTTPS (DoH)
"""

import base64
import io
import os
import socket
import ssl
import struct
import sys
import threading
import time
import urllib.parse
from typing import Dict, List, Optional, Tuple, Any, Callable

from .certs import ensure_certificates, create_dot_ssl_context
from .doh3_server import decode_base64url_dns, DOH_PATH

DEFAULT_DOH2_PORT = 8444

# HTTP/2 Connection Preface (RFC 7540 §3.5)
H2_CONNECTION_PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

# RFC 7540 Frame Types
FRAME_DATA = 0x0
FRAME_HEADERS = 0x1
FRAME_PRIORITY = 0x2
FRAME_RST_STREAM = 0x3
FRAME_SETTINGS = 0x4
FRAME_PUSH_PROMISE = 0x5
FRAME_PING = 0x6
FRAME_GOAWAY = 0x7
FRAME_WINDOW_UPDATE = 0x8
FRAME_CONTINUATION = 0x9

# Frame Flags
FLAG_END_STREAM = 0x1
FLAG_END_HEADERS = 0x4
FLAG_ACK = 0x1


class H2Frame:
    """Represents a standard 9-octet framed RFC 7540 packet."""

    __slots__ = ("length", "frame_type", "flags", "stream_id", "payload")

    def __init__(self, frame_type: int, flags: int, stream_id: int, payload: bytes):
        self.length = len(payload)
        self.frame_type = frame_type
        self.flags = flags
        self.stream_id = stream_id & 0x7FFFFFFF
        self.payload = payload

    def serialize(self) -> bytes:
        # Header: 24-bit Length + 8-bit Type + 8-bit Flags + 32-bit Stream ID (bit 31 reserved 0)
        hdr = struct.pack("!HBBI", (self.length >> 8) & 0xFFFF, self.length & 0xFF, self.frame_type, self.flags)
        # Re-pack length properly into 3 bytes
        raw_len = struct.pack("!I", self.length)[1:]  # 3 bytes
        raw_hdr = raw_len + struct.pack("!BBI", self.frame_type, self.flags, self.stream_id & 0x7FFFFFFF)
        return raw_hdr + self.payload

    @classmethod
    def parse_header(cls, header_bytes: bytes) -> Tuple[int, int, int, int]:
        """Parses 9-octet frame header: (length, type, flags, stream_id)."""
        if len(header_bytes) < 9:
            raise ValueError("Incomplete frame header")
        length = (header_bytes[0] << 16) | (header_bytes[1] << 8) | header_bytes[2]
        frame_type = header_bytes[3]
        flags = header_bytes[4]
        stream_id = struct.unpack("!I", header_bytes[5:9])[0] & 0x7FFFFFFF
        return length, frame_type, flags, stream_id


class HPACKCodec:
    """
    RFC 7541 HPACK Header Compression Encoder & Decoder.
    Supports static table indexing and literal representations.
    """

    # Selected common static table entries (RFC 7541 Appendix A)
    STATIC_TABLE = [
        (":authority", ""),
        (":method", "GET"),
        (":method", "POST"),
        (":path", "/"),
        (":path", "/index.html"),
        (":scheme", "http"),
        (":scheme", "https"),
        (":status", "200"),
        (":status", "204"),
        (":status", "206"),
        (":status", "304"),
        (":status", "400"),
        (":status", "404"),
        (":status", "500"),
        ("accept-charset", ""),
        ("accept-encoding", "gzip, deflate"),
        ("accept-language", ""),
        ("accept-ranges", ""),
        ("accept", ""),
        ("access-control-allow-origin", ""),
        ("age", ""),
        ("allow", ""),
        ("authorization", ""),
        ("cache-control", ""),
        ("content-dispose", ""),
        ("content-encoding", ""),
        ("content-language", ""),
        ("content-length", ""),
        ("content-location", ""),
        ("content-range", ""),
        ("content-type", ""),
    ]

    @classmethod
    def encode_headers(cls, headers: List[Tuple[str, str]]) -> bytes:
        """Encodes list of (key, value) pairs into RFC 7541 literal representations."""
        out = bytearray()
        for k, v in headers:
            k_bytes = k.lower().encode("ascii")
            v_bytes = v.encode("ascii")

            # Check if key matches static table
            matched_idx = -1
            for idx, (tk, tv) in enumerate(cls.STATIC_TABLE, start=1):
                if tk == k.lower():
                    matched_idx = idx
                    break

            if matched_idx != -1:
                # Literal Header Field with Incremental Indexing — Indexed Name (RFC 7541 §6.2.1)
                # 01xxxxxx pattern
                out.append(0x40 | (matched_idx & 0x3F))
                # Value string: length + raw string
                out.append(len(v_bytes))
                out.extend(v_bytes)
            else:
                # Literal Header Field without Indexing — New Name (RFC 7541 §6.2.2)
                out.append(0x00)
                out.append(len(k_bytes))
                out.extend(k_bytes)
                out.append(len(v_bytes))
                out.extend(v_bytes)
        return bytes(out)

    @classmethod
    def decode_headers(cls, raw: bytes) -> List[Tuple[str, str]]:
        """Parses RFC 7541 header block into list of (name, value) strings."""
        headers = []
        buf = io.BytesIO(raw)

        while buf.tell() < len(raw):
            first_byte_b = buf.read(1)
            if not first_byte_b:
                break
            b = first_byte_b[0]

            # 1. Indexed Header Field (starts with bit 1: 1xxxxxxx)
            if b & 0x80:
                idx = b & 0x7F
                if 1 <= idx <= len(cls.STATIC_TABLE):
                    k, v = cls.STATIC_TABLE[idx - 1]
                    headers.append((k, v))

            # 2. Literal Header Field with Incremental Indexing (01xxxxxx)
            elif (b & 0xC0) == 0x40:
                name_idx = b & 0x3F
                if name_idx > 0 and name_idx <= len(cls.STATIC_TABLE):
                    name = cls.STATIC_TABLE[name_idx - 1][0]
                else:
                    n_len = buf.read(1)[0]
                    name = buf.read(n_len).decode("ascii", errors="replace")
                v_len_b = buf.read(1)
                if not v_len_b:
                    break
                v_len = v_len_b[0] & 0x7F
                val = buf.read(v_len).decode("ascii", errors="replace")
                headers.append((name, val))

            # 3. Literal without indexing (0000xxxx)
            elif (b & 0xF0) == 0x00:
                name_idx = b & 0x0F
                if name_idx > 0 and name_idx <= len(cls.STATIC_TABLE):
                    name = cls.STATIC_TABLE[name_idx - 1][0]
                else:
                    n_len_b = buf.read(1)
                    if not n_len_b:
                        break
                    n_len = n_len_b[0] & 0x7F
                    name = buf.read(n_len).decode("ascii", errors="replace")
                v_len_b = buf.read(1)
                if not v_len_b:
                    break
                v_len = v_len_b[0] & 0x7F
                val = buf.read(v_len).decode("ascii", errors="replace")
                headers.append((name, val))
            else:
                # Skip unhandled pattern byte
                pass

        return headers


class Doh2ConnectionHandler:
    """Handles an individual RFC 7540 HTTP/2 multiplexed socket connection."""

    def __init__(
        self,
        sock: socket.socket,
        client_ip: str,
        dns_handler: Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]],
    ):
        self.sock = sock
        self.client_ip = client_ip
        self.dns_handler = dns_handler
        # stream_id -> dict of request state
        self._streams: Dict[int, Dict[str, Any]] = {}
        self._is_active = True

    def run(self):
        try:
            self.sock.settimeout(5.0)
            # 1. Read Connection Preface (24 octets)
            preface = self.sock.recv(len(H2_CONNECTION_PREFACE))
            if preface != H2_CONNECTION_PREFACE:
                return

            # 2. Transmit Initial Server SETTINGS Frame (Stream 0)
            server_settings = H2Frame(FRAME_SETTINGS, 0, 0, b"").serialize()
            self.sock.sendall(server_settings)

            # 3. Event Loop for incoming frames
            while self._is_active:
                hdr_bytes = self._recv_exact(9)
                if not hdr_bytes:
                    break
                length, frame_type, flags, stream_id = H2Frame.parse_header(hdr_bytes)
                payload = self._recv_exact(length) if length > 0 else b""

                self._process_frame(frame_type, flags, stream_id, payload)
        except Exception:
            pass
        finally:
            try:
                self.sock.close()
            except Exception:
                pass

    def _recv_exact(self, num_bytes: int) -> Optional[bytes]:
        buf = bytearray()
        while len(buf) < num_bytes:
            chunk = self.sock.recv(num_bytes - len(buf))
            if not chunk:
                return None
            buf.extend(chunk)
        return bytes(buf)

    def _process_frame(self, frame_type: int, flags: int, stream_id: int, payload: bytes):
        if frame_type == FRAME_SETTINGS:
            if not (flags & FLAG_ACK):
                # Send SETTINGS ACK
                ack = H2Frame(FRAME_SETTINGS, FLAG_ACK, 0, b"").serialize()
                self.sock.sendall(ack)

        elif frame_type == FRAME_PING:
            if not (flags & FLAG_ACK):
                # Echo payload in PING ACK
                ping_ack = H2Frame(FRAME_PING, FLAG_ACK, 0, payload).serialize()
                self.sock.sendall(ping_ack)

        elif frame_type == FRAME_HEADERS:
            headers = HPACKCodec.decode_headers(payload)
            hdr_dict = {k.lower(): v for k, v in headers}
            self._streams[stream_id] = {
                "method": hdr_dict.get(":method", "GET").upper(),
                "path": hdr_dict.get(":path", "/"),
                "content_type": hdr_dict.get("content-type", ""),
                "body": bytearray(),
            }
            if flags & FLAG_END_STREAM:
                self._dispatch_stream(stream_id)

        elif frame_type == FRAME_DATA:
            if stream_id in self._streams:
                self._streams[stream_id]["body"].extend(payload)
                if flags & FLAG_END_STREAM:
                    self._dispatch_stream(stream_id)

        elif frame_type == FRAME_GOAWAY:
            self._is_active = False

    def _dispatch_stream(self, stream_id: int):
        stream = self._streams.pop(stream_id, None)
        if not stream:
            return

        method = stream["method"]
        path = stream["path"]
        content_type = stream["content_type"]
        body = bytes(stream["body"])

        parsed_url = urllib.parse.urlparse(path)
        if parsed_url.path != DOH_PATH:
            self._send_response(stream_id, "404", b"Not Found", "text/plain")
            return

        query_bytes: Optional[bytes] = None
        if method == "GET":
            query_params = urllib.parse.parse_qs(parsed_url.query)
            dns_b64 = query_params.get("dns", [None])[0]
            if not dns_b64:
                self._send_response(stream_id, "400", b"Missing dns parameter", "text/plain")
                return
            query_bytes = decode_base64url_dns(dns_b64)
        elif method == "POST":
            query_bytes = body
        else:
            self._send_response(stream_id, "405", b"Method Not Allowed", "text/plain")
            return

        if not query_bytes:
            self._send_response(stream_id, "400", b"Malformed DNS query", "text/plain")
            return

        reply_wire, _ = self.dns_handler(query_bytes, self.client_ip)
        if reply_wire:
            self._send_response(stream_id, "200", reply_wire, "application/dns-message", cache_control="max-age=60")
        else:
            self._send_response(stream_id, "500", b"Resolution Error", "text/plain")

    def _send_response(
        self,
        stream_id: int,
        status: str,
        body: bytes,
        content_type: str,
        cache_control: Optional[str] = None,
    ):
        response_headers = [
            (":status", status),
            ("content-type", content_type),
            ("content-length", str(len(body))),
            ("server", "FocusDNS-DoH2/2.0"),
        ]
        if cache_control:
            response_headers.append(("cache-control", cache_control))

        hpack_bytes = HPACKCodec.encode_headers(response_headers)

        # 1. Send HEADERS frame (without END_STREAM if body present)
        h_frame = H2Frame(
            FRAME_HEADERS,
            FLAG_END_HEADERS if body else (FLAG_END_HEADERS | FLAG_END_STREAM),
            stream_id,
            hpack_bytes,
        )
        self.sock.sendall(h_frame.serialize())

        # 2. Send DATA frame
        if body:
            d_frame = H2Frame(FRAME_DATA, FLAG_END_STREAM, stream_id, body)
            self.sock.sendall(d_frame.serialize())


class Doh2ServerThread:
    """Dedicated background multi-threaded server running RFC 7540 HTTP/2 DoH."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = DEFAULT_DOH2_PORT,
        handler: Optional[Callable[[bytes, str], Tuple[bytes, Dict[str, Any]]]] = None,
    ):
        self.host = host
        self.port = port
        self.handler = handler
        self._thread: Optional[threading.Thread] = None
        self._sock: Optional[socket.socket] = None
        self._is_running = False

    def start(self):
        self._is_running = True
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind((self.host, self.port))
        self._sock.listen(50)

        def _accept_loop():
            while self._is_running:
                try:
                    client_sock, addr = self._sock.accept()
                    h = Doh2ConnectionHandler(client_sock, addr[0], self.handler)
                    t = threading.Thread(target=h.run, daemon=True)
                    t.start()
                except Exception:
                    break

        self._thread = threading.Thread(target=_accept_loop, daemon=True, name="FocusDNS-DoH2")
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


class H2Stream:
    """Represents an active HTTP/2 multiplexed stream state."""

    def __init__(self, stream_id: int):
        self.stream_id = stream_id
        self.headers: List[Tuple[str, str]] = []
        self.data = bytearray()
        self.state: str = "open"  # 'idle', 'open', 'half_closed_remote', 'closed'
        self.created_at = time.time()


class H2Connection:
    """Manages collection of concurrent streams for an HTTP/2 connection."""

    def __init__(self):
        self.streams: Dict[int, H2Stream] = {}
        self.last_stream_id = 0

    def get_or_create_stream(self, stream_id: int) -> H2Stream:
        if stream_id not in self.streams:
            self.streams[stream_id] = H2Stream(stream_id)
            if stream_id > self.last_stream_id:
                self.last_stream_id = stream_id
        return self.streams[stream_id]

    def close_stream(self, stream_id: int):
        if stream_id in self.streams:
            self.streams[stream_id].state = "closed"


# Compatibility alias
Doh2Server = Doh2ServerThread
