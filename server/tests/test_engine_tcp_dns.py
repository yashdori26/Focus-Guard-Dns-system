"""
Unit & Integration Tests for FocusDNS RFC 7766 DNS-over-TCP Server Subsystem
============================================================================
Validates:
  1. RFC 7828 edns-tcp-keepalive binary codec
  2. RFC 1035 §4.2.2 2-octet big-endian framing
  3. TCPDNSServer client query handling and response serialization
  4. Query pipelining over a single persistent TCP connection
  5. TCPDNSClient query helper execution
"""

import socket
import struct
import time
import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE, RR, A
from server.engine.tcp_dns_server import (
    EDNSTCPKeepalive,
    TCPDNSServer,
    TCPDNSServerThread,
    TCPDNSClient,
    recv_exact,
)


class TestEDNSTCPKeepalive(unittest.TestCase):
    """Tests RFC 7828 keepalive option encoding."""

    def test_keepalive_codec(self):
        encoded = EDNSTCPKeepalive.encode(150)
        self.assertEqual(len(encoded), 2)
        decoded = EDNSTCPKeepalive.decode(encoded)
        self.assertEqual(decoded, 150)


class TestTCPDNSServer(unittest.TestCase):
    """Tests live TCP DNS server daemon and pipelined streaming."""

    @classmethod
    def setUpClass(cls):
        def echo_handler(wire_bytes: bytes, client_ip: str):
            req = DNSRecord.parse(wire_bytes)
            reply = req.reply()
            reply.add_answer(RR(str(req.q.qname), QTYPE.A, rdata=A("192.0.2.100")))
            return reply.pack(), {"status": "ok"}

        cls.port = 18555
        cls.server_thread = TCPDNSServerThread(
            host="127.0.0.1",
            port=cls.port,
            handler=echo_handler,
            idle_timeout_sec=2.0,
        )
        cls.server_thread.start()
        time.sleep(0.15)  # Wait for socket to bind

    @classmethod
    def tearDownClass(cls):
        cls.server_thread.stop()

    def test_single_tcp_query(self):
        q = DNSRecord(q=DNSQuestion("test-tcp.local", QTYPE.A))
        wire = q.pack()

        resp_bytes = TCPDNSClient.query(wire, host="127.0.0.1", port=self.port)
        self.assertIsNotNone(resp_bytes)

        resp = DNSRecord.parse(resp_bytes)
        self.assertEqual(resp.header.id, q.header.id)
        self.assertEqual(len(resp.rr), 1)
        self.assertEqual(str(resp.rr[0].rdata), "192.0.2.100")

    def test_pipelined_tcp_queries(self):
        # Open a single persistent TCP connection and stream 5 pipelined queries
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect(("127.0.0.1", self.port))

        try:
            questions = [f"pipe{i}.example.com" for i in range(5)]
            # Send all 5 frames without waiting
            for i, name in enumerate(questions):
                q = DNSRecord(q=DNSQuestion(name, QTYPE.A))
                q.header.id = 1000 + i
                wire = q.pack()
                sock.sendall(struct.pack("!H", len(wire)) + wire)

            # Receive all 5 replies
            for i in range(5):
                len_hdr = recv_exact(sock, 2)
                self.assertIsNotNone(len_hdr)
                resp_len = struct.unpack("!H", len_hdr)[0]
                resp_wire = recv_exact(sock, resp_len)
                self.assertIsNotNone(resp_wire)
                resp = DNSRecord.parse(resp_wire)
                self.assertEqual(resp.header.id, 1000 + i)
        finally:
            sock.close()

    def test_server_stats(self):
        stats = self.server_thread.server.get_stats()
        self.assertGreaterEqual(stats["total_connections"], 1)
        self.assertGreaterEqual(stats["queries_served"], 1)
        self.assertEqual(stats["rfc"], "RFC 7766")


if __name__ == "__main__":
    unittest.main()
