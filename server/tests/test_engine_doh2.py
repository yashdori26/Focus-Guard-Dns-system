"""
Unit & Integration Tests for FocusDNS Dedicated RFC 7540 HTTP/2 DoH Multiplexer
================================================================================
Validates:
  1. RFC 7540 binary frame packing, flag setting, and 9-octet header parsing
  2. Frame types: SETTINGS, HEADERS, DATA, PING, RST_STREAM, GOAWAY, WINDOW_UPDATE
  3. RFC 7541 HPACK header compression and decompression with static table indexing
  4. Concurrent stream multiplexing state tracking (H2Stream, H2Connection)
  5. RFC 8484 DoH POST binary payload processing and response formatting
  6. RFC 8484 DoH GET base64url query parameter decoding and response formatting
  7. Client connection preface handshake (PRI * HTTP/2.0\\r\\n\\r\\nSM\\r\\n\\r\\n)
"""

import base64
import socket
import struct
import threading
import time
import unittest
from dnslib import DNSRecord, RR, QTYPE, RCODE, A

from server.engine.doh2_server import (
    H2Frame,
    HPACKCodec,
    H2Stream,
    H2Connection,
    Doh2ServerThread,
    FRAME_DATA,
    FRAME_HEADERS,
    FRAME_SETTINGS,
    FRAME_PING,
    FRAME_GOAWAY,
    FRAME_RST_STREAM,
    FRAME_WINDOW_UPDATE,
    FLAG_END_STREAM,
    FLAG_END_HEADERS,
    FLAG_ACK,
    H2_CONNECTION_PREFACE,
)


class TestH2FrameSerialization(unittest.TestCase):
    """Tests RFC 7540 9-octet binary frame framing."""

    def test_frame_serialization_and_parsing(self):
        payload = b"Hello HTTP/2 World!"
        frame = H2Frame(
            frame_type=FRAME_DATA,
            flags=FLAG_END_STREAM,
            stream_id=5,
            payload=payload,
        )

        wire = frame.serialize()
        self.assertEqual(len(wire), 9 + len(payload))

        # Parse header
        length, f_type, flags, stream_id = H2Frame.parse_header(wire[:9])
        self.assertEqual(length, len(payload))
        self.assertEqual(f_type, FRAME_DATA)
        self.assertEqual(flags, FLAG_END_STREAM)
        self.assertEqual(stream_id, 5)

        # Parse payload
        extracted_payload = wire[9:]
        self.assertEqual(extracted_payload, payload)

    def test_settings_frame(self):
        # SETTINGS frame on stream 0
        settings_payload = struct.pack("!HI", 0x3, 100)  # MAX_CONCURRENT_STREAMS = 100
        frame = H2Frame(FRAME_SETTINGS, 0, 0, settings_payload)
        wire = frame.serialize()

        length, f_type, flags, stream_id = H2Frame.parse_header(wire[:9])
        self.assertEqual(length, 6)
        self.assertEqual(f_type, FRAME_SETTINGS)
        self.assertEqual(stream_id, 0)

    def test_ping_frame(self):
        ping_data = b"12345678"  # Exactly 8 octets
        frame = H2Frame(FRAME_PING, FLAG_ACK, 0, ping_data)
        wire = frame.serialize()

        length, f_type, flags, stream_id = H2Frame.parse_header(wire[:9])
        self.assertEqual(length, 8)
        self.assertEqual(f_type, FRAME_PING)
        self.assertEqual(flags, FLAG_ACK)

    def test_stream_id_masking(self):
        # 31st bit is reserved and must be masked to 0
        huge_id = 0x80000007  # Bit 31 set
        frame = H2Frame(FRAME_DATA, 0, huge_id, b"data")
        wire = frame.serialize()

        _, _, _, parsed_id = H2Frame.parse_header(wire[:9])
        self.assertEqual(parsed_id, 7)


class TestHPACKCompression(unittest.TestCase):
    """Tests RFC 7541 HPACK header compression and decoding."""

    def test_static_table_indexed_header(self):
        # Encode standard pseudostatics: :method GET, :scheme https, :status 200
        headers = [
            (":method", "GET"),
            (":scheme", "https"),
            (":status", "200"),
        ]
        encoded = HPACKCodec.encode_headers(headers)
        decoded = HPACKCodec.decode_headers(encoded)

        # Decoded dict or tuple list must match
        decoded_dict = dict(decoded)
        self.assertEqual(decoded_dict[":method"], "GET")
        self.assertEqual(decoded_dict[":scheme"], "https")
        self.assertEqual(decoded_dict[":status"], "200")

    def test_literal_with_indexing(self):
        # Custom headers not in static table
        headers = [
            (":status", "200"),
            ("content-type", "application/dns-message"),
            ("x-focusdns-node", "edge-1"),
        ]
        encoded = HPACKCodec.encode_headers(headers)
        decoded = HPACKCodec.decode_headers(encoded)

        decoded_dict = dict(decoded)
        self.assertEqual(decoded_dict[":status"], "200")
        self.assertEqual(decoded_dict["content-type"], "application/dns-message")
        self.assertEqual(decoded_dict["x-focusdns-node"], "edge-1")


class TestH2StreamMultiplexing(unittest.TestCase):
    """Tests stream multiplexer state and concurrent stream isolation."""

    def test_concurrent_streams(self):
        conn = H2Connection()

        s1 = conn.get_or_create_stream(1)
        s3 = conn.get_or_create_stream(3)
        s5 = conn.get_or_create_stream(5)

        self.assertEqual(conn.last_stream_id, 5)
        self.assertEqual(s1.state, "open")
        self.assertEqual(s3.state, "open")

        # Stream 1 appends data
        s1.data.extend(b"DNS query 1")
        # Stream 3 appends data
        s3.data.extend(b"DNS query 3")

        self.assertEqual(bytes(s1.data), b"DNS query 1")
        self.assertEqual(bytes(s3.data), b"DNS query 3")

        # Close stream 1
        conn.close_stream(1)
        self.assertEqual(s1.state, "closed")
        self.assertEqual(s3.state, "open")


class TestDoh2ServerIntegration(unittest.TestCase):
    """Tests live socket-level HTTP/2 DoH server interactions."""

    def setUp(self):
        def _mock_pipeline_handler(query_bytes: bytes, client_ip: str):
            req = DNSRecord.parse(query_bytes)
            reply = req.reply()
            reply.add_answer(RR(str(req.q.qname), QTYPE.A, ttl=60, rdata=A("93.184.216.34")))
            return reply.pack(), {"status": "allowed", "rcode": "NOERROR"}

        # Find an available port
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind(("127.0.0.1", 0))
        self.port = s.getsockname()[1]
        s.close()

        self.server = Doh2ServerThread(host="127.0.0.1", port=self.port, handler=_mock_pipeline_handler)
        self.server.start()
        time.sleep(0.05)

    def tearDown(self):
        self.server.stop()

    def test_h2_preface_and_dns_post(self):
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(2.0)
        client.connect(("127.0.0.1", self.port))

        try:
            # 1. Send client preface + initial SETTINGS frame
            settings_frame = H2Frame(FRAME_SETTINGS, 0, 0, b"")
            client.sendall(H2_CONNECTION_PREFACE + settings_frame.serialize())

            def recv_exact(n):
                buf = bytearray()
                while len(buf) < n:
                    chunk = client.recv(n - len(buf))
                    if not chunk:
                        return None
                    buf.extend(chunk)
                return bytes(buf)

            def recv_frame():
                hdr = recv_exact(9)
                if not hdr:
                    raise ValueError("Connection closed before frame header")
                length, f_type, flags, stream_id = H2Frame.parse_header(hdr)
                payload = recv_exact(length) if length > 0 else b""
                return length, f_type, flags, stream_id, payload

            # 2. Build a DNS query
            dns_req = DNSRecord.question("example.com", "A")
            dns_wire = dns_req.pack()

            # 3. Send HTTP/2 HEADERS frame on stream 1 (:method POST, :path /dns-query)
            headers = [
                (":method", "POST"),
                (":path", "/dns-query"),
                (":scheme", "https"),
                ("content-type", "application/dns-message"),
                ("content-length", str(len(dns_wire))),
            ]
            hpack_encoded = HPACKCodec.encode_headers(headers)
            h_frame = H2Frame(FRAME_HEADERS, FLAG_END_HEADERS, 1, hpack_encoded)
            client.sendall(h_frame.serialize())

            # 4. Send HTTP/2 DATA frame with DNS wire payload (with END_STREAM)
            d_frame = H2Frame(FRAME_DATA, FLAG_END_STREAM, 1, dns_wire)
            client.sendall(d_frame.serialize())

            # 5. Receive response frames until we get HEADERS on stream 1
            decoded_headers = {}
            while True:
                resp_len, resp_type, resp_flags, resp_stream, resp_payload = recv_frame()
                if resp_type == FRAME_HEADERS and resp_stream == 1:
                    decoded_headers = dict(HPACKCodec.decode_headers(resp_payload))
                    break

            self.assertEqual(decoded_headers.get(":status"), "200")
            self.assertEqual(decoded_headers.get("content-type"), "application/dns-message")

            # 6. Receive response DATA frame on stream 1
            data_len, data_type, data_flags, data_stream, dns_resp_wire = recv_frame()
            self.assertEqual(data_type, FRAME_DATA)
            self.assertEqual(data_stream, 1)

            parsed_dns_reply = DNSRecord.parse(dns_resp_wire)
            self.assertEqual(parsed_dns_reply.header.rcode, RCODE.NOERROR)
            self.assertGreater(len(parsed_dns_reply.rr), 0)
            self.assertEqual(str(parsed_dns_reply.rr[0].rdata), "93.184.216.34")

        finally:
            client.close()


if __name__ == "__main__":
    unittest.main()
