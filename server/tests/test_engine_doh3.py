"""
Unit and integration tests for FocusDNS RFC 9114 HTTP/3 and RFC 8484 DoH3 Server.
"""

import base64
import time
import unittest
from unittest.mock import MagicMock
from dnslib import DNSRecord, QTYPE

from server.engine.doh3_server import (
    decode_base64url_dns,
    Doh3ServerProtocol,
    Doh3ServerThread,
    DOH_PATH,
)


class TestDoh3ServerSubsystem(unittest.TestCase):
    def test_decode_base64url_dns(self):
        """Verify RFC 8484 §4.1.1 base64url decoding with automatic padding restoration."""
        req = DNSRecord.question("example.com", "A")
        raw_wire = req.pack()

        # Unpadded base64url (standard RFC 8484 query param)
        encoded_unpadded = base64.urlsafe_b64encode(raw_wire).decode("ascii").rstrip("=")
        decoded = decode_base64url_dns(encoded_unpadded)
        self.assertIsNotNone(decoded)
        self.assertEqual(decoded, raw_wire)

        # Padded base64url
        encoded_padded = base64.urlsafe_b64encode(raw_wire).decode("ascii")
        decoded_padded = decode_base64url_dns(encoded_padded)
        self.assertEqual(decoded_padded, raw_wire)

        # Invalid string
        self.assertIsNone(decode_base64url_dns("!@#$%^&*()"))

    def test_doh3_dispatch_get_request(self):
        """Verify DoH3 protocol dispatches GET /dns-query?dns=... correctly."""
        req = DNSRecord.question("focusdns.org", "A")
        query_bytes = req.pack()
        b64_dns = base64.urlsafe_b64encode(query_bytes).decode("ascii").rstrip("=")

        # Mock handler
        mock_handler = MagicMock(return_value=(b"dns_reply_bytes", {"status": "allowed"}))

        protocol = Doh3ServerProtocol.__new__(Doh3ServerProtocol)
        protocol._handler = mock_handler
        protocol._stats_callback = None
        protocol._http = MagicMock()
        protocol._requests = {
            1: {
                "method": "GET",
                "path": f"{DOH_PATH}?dns={b64_dns}",
                "content_type": "",
                "body": bytearray(),
            }
        }
        protocol._quic = MagicMock()
        protocol._quic.get_extra_info.return_value = ("127.0.0.1", 54321)

        # Dispatch
        protocol._dispatch_request(1)

        # Verify handler was called with decoded wire packet
        mock_handler.assert_called_once()
        call_args = mock_handler.call_args[0]
        self.assertEqual(call_args[0], query_bytes)
        self.assertEqual(call_args[1], "127.0.0.1")

        # Verify HTTP response was sent with status 200 and application/dns-message
        protocol._http.send_headers.assert_called_once()
        sent_headers = protocol._http.send_headers.call_args[0][1]
        hdr_dict = dict(sent_headers)
        self.assertEqual(hdr_dict[b":status"], b"200")
        self.assertEqual(hdr_dict[b"content-type"], b"application/dns-message")
        protocol._http.send_data.assert_called_once_with(1, b"dns_reply_bytes", end_stream=True)

    def test_doh3_dispatch_post_binary_request(self):
        """Verify DoH3 protocol dispatches POST /dns-query with binary body."""
        req = DNSRecord.question("secure.focusdns.org", "AAAA")
        query_bytes = req.pack()

        mock_handler = MagicMock(return_value=(b"post_reply_bytes", {"status": "allowed"}))

        protocol = Doh3ServerProtocol.__new__(Doh3ServerProtocol)
        protocol._handler = mock_handler
        protocol._stats_callback = None
        protocol._http = MagicMock()
        protocol._requests = {
            2: {
                "method": "POST",
                "path": DOH_PATH,
                "content_type": "application/dns-message",
                "body": bytearray(query_bytes),
            }
        }
        protocol._quic = MagicMock()
        protocol._quic.get_extra_info.return_value = ("192.168.1.100", 61234)

        protocol._dispatch_request(2)

        mock_handler.assert_called_once()
        self.assertEqual(mock_handler.call_args[0][0], query_bytes)
        protocol._http.send_data.assert_called_once_with(2, b"post_reply_bytes", end_stream=True)

    def test_doh3_dispatch_error_responses(self):
        """Verify DoH3 protocol generates appropriate HTTP error status codes."""
        protocol = Doh3ServerProtocol.__new__(Doh3ServerProtocol)
        protocol._handler = MagicMock()
        protocol._stats_callback = None
        protocol._http = MagicMock()
        protocol._quic = MagicMock()

        # 404 for wrong path
        protocol._requests = {
            1: {"method": "GET", "path": "/wrong-endpoint", "content_type": "", "body": bytearray()}
        }
        protocol._dispatch_request(1)
        sent_headers_404 = dict(protocol._http.send_headers.call_args[0][1])
        self.assertEqual(sent_headers_404[b":status"], b"404")

        # 415 for POST with invalid content type
        protocol._http.reset_mock()
        protocol._requests = {
            2: {"method": "POST", "path": DOH_PATH, "content_type": "application/json", "body": bytearray(b"{}")}
        }
        protocol._dispatch_request(2)
        sent_headers_415 = dict(protocol._http.send_headers.call_args[0][1])
        self.assertEqual(sent_headers_415[b":status"], b"415")

        # 405 for unsupported method (e.g. DELETE)
        protocol._http.reset_mock()
        protocol._requests = {
            3: {"method": "DELETE", "path": DOH_PATH, "content_type": "", "body": bytearray()}
        }
        protocol._dispatch_request(3)
        sent_headers_405 = dict(protocol._http.send_headers.call_args[0][1])
        self.assertEqual(sent_headers_405[b":status"], b"405")

    def test_doh3_server_thread_lifecycle(self):
        """Verify Doh3ServerThread starts and stops gracefully without leaking sockets."""
        thread = Doh3ServerThread(
            host="127.0.0.1",
            port=18443,
            handler=lambda q, ip: (b"ok", {}),
        )
        thread.start()
        time.sleep(0.3)
        self.assertTrue(thread.is_alive())

        # Clean shutdown
        thread.stop()
        thread.join(timeout=2.0)
        self.assertFalse(thread.is_alive())


if __name__ == "__main__":
    unittest.main()
