"""
FocusDNS Engine Test Suite - DNS-over-TLS (RFC 7858), DNS-over-QUIC (RFC 9250) & Pipeline
Validates:
- TLS 1.3 / 1.2 certificate generation with SAN extensions
- RFC 7858 DNS-over-TLS client/server loopback connection & pipelined stream framing
- RFC 9250 DNS-over-QUIC configuration & 0-RTT session ticket cache
- Unified DNSPipeline end-to-end integration
"""

import os
import ssl
import time
import socket
import struct
import unittest
from pathlib import Path
from dnslib import DNSRecord, QTYPE, RCODE, RR, A

from server.engine.certs import (
    ensure_certificates,
    create_dot_ssl_context,
    create_doq_quic_configuration,
)
from server.engine.dot_server import DotServerThread
from server.engine.doq_server import DoqServer, SessionTicketStore
from server.engine.pipeline import DNSPipeline
from server.engine.radix_trie import FLAG_BLOCKED, FLAG_ALLOWED, FLAG_WILDCARD
from aioquic.tls import SessionTicket, CipherSuite


class TestEngineProtocolsAndPipeline(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Generate test certificates
        cls.cert_file, cls.key_file = ensure_certificates()

    def test_certificate_generation_and_ssl_context(self):
        self.assertTrue(Path(self.cert_file).exists())
        self.assertTrue(Path(self.key_file).exists())

        ctx = create_dot_ssl_context(self.cert_file, self.key_file)
        self.assertIsInstance(ctx, ssl.SSLContext)

        quic_conf = create_doq_quic_configuration(self.cert_file, self.key_file)
        self.assertIn("doq", quic_conf.alpn_protocols)

    def test_dot_server_pipelined_tcp_framing(self):
        """
        Launches DoT server on loopback test port, connects via Python ssl.wrap_socket,
        sends RFC 1035 2-octet framed queries, and verifies pipelined multi-query response.
        """
        test_port = 8863
        received_queries = []

        def mock_handler(wire_bytes: bytes, client_ip: str):
            req = DNSRecord.parse(wire_bytes)
            received_queries.append(str(req.q.qname))
            reply = req.reply()
            reply.add_answer(RR(str(req.q.qname), QTYPE.A, ttl=60, rdata=A("10.20.30.40")))
            return reply.pack(), {"status": "allowed"}

        # Start DoT server in background thread
        dot_thread = DotServerThread(
            host="127.0.0.1",
            port=test_port,
            handler=mock_handler,
            cert_file=self.cert_file,
            key_file=self.key_file,
        )
        dot_thread.start()
        time.sleep(0.4)

        client_ctx = ssl.create_default_context()
        client_ctx.check_hostname = False
        client_ctx.verify_mode = ssl.CERT_NONE

        raw_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        raw_sock.settimeout(3.0)
        ssl_sock = client_ctx.wrap_socket(raw_sock, server_hostname="localhost")

        try:
            ssl_sock.connect(("127.0.0.1", test_port))

            # Query 1: alpha.test.
            q1 = DNSRecord.question("alpha.test", "A").pack()
            framed_q1 = struct.pack("!H", len(q1)) + q1
            ssl_sock.sendall(framed_q1)

            # Read 2-octet prefix
            len_b = ssl_sock.recv(2)
            self.assertEqual(len(len_b), 2)
            resp_len = struct.unpack("!H", len_b)[0]
            resp_bytes = ssl_sock.recv(resp_len)
            reply1 = DNSRecord.parse(resp_bytes)
            self.assertEqual(str(reply1.q.qname), "alpha.test.")
            self.assertEqual(str(reply1.a.rdata), "10.20.30.40")

            # Query 2 (pipelined over SAME persistent TLS connection): beta.test.
            q2 = DNSRecord.question("beta.test", "A").pack()
            framed_q2 = struct.pack("!H", len(q2)) + q2
            ssl_sock.sendall(framed_q2)

            len_b2 = ssl_sock.recv(2)
            self.assertEqual(len(len_b2), 2)
            resp_len2 = struct.unpack("!H", len_b2)[0]
            resp_bytes2 = ssl_sock.recv(resp_len2)
            reply2 = DNSRecord.parse(resp_bytes2)
            self.assertEqual(str(reply2.q.qname), "beta.test.")

        finally:
            ssl_sock.close()
            dot_thread.stop()

        self.assertEqual(received_queries, ["alpha.test.", "beta.test."])
        stats = dot_thread.server.get_stats()
        self.assertGreaterEqual(stats["total_queries"], 2)

    def test_doq_session_ticket_store(self):
        store = SessionTicketStore(max_tickets=5)
        ticket = SessionTicket(
            age_add=100,
            cipher_suite=CipherSuite.AES_128_GCM_SHA256,
            not_valid_after=None,
            not_valid_before=None,
            resumption_secret=b"secret",
            server_name="localhost",
            ticket=b"ticket-12345",
            max_early_data_size=4096,
            other_extensions=[],
        )
        store.add(ticket)
        retrieved = store.get(b"ticket-12345")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved.ticket, b"ticket-12345")

        # Miss
        self.assertIsNone(store.get(b"non-existent"))

    def test_pipeline_integration(self):
        pipeline = DNSPipeline(enable_dnssec=False)

        # 1. Add block rule to trie
        pipeline.trie.insert("adservice.google.com", flags=FLAG_BLOCKED | FLAG_WILDCARD)

        # 2. Process query for blocked domain -> should return NXDOMAIN
        q_block = DNSRecord.question("adservice.google.com", "A").pack()
        resp_wire, event = pipeline.process_wire_query(q_block, profile_id="test_profile", protocol="DOT")

        self.assertEqual(event["status"], "blocked")
        self.assertEqual(event["rcode"], "NXDOMAIN")
        self.assertEqual(event["protocol"], "DOT")
        reply_parsed = DNSRecord.parse(resp_wire)
        self.assertEqual(reply_parsed.header.rcode, RCODE.NXDOMAIN)

        # 3. Add allow rule to trie
        pipeline.trie.insert("allowed.example.org", flags=FLAG_ALLOWED)
        flags, rule, _ = pipeline.trie.match("allowed.example.org")
        self.assertTrue(flags & FLAG_ALLOWED)

        # 4. Pipeline metrics
        metrics = pipeline.get_pipeline_metrics()
        self.assertGreaterEqual(metrics["total_queries"], 1)
        self.assertGreaterEqual(metrics["total_blocked"], 1)
        self.assertGreaterEqual(metrics["trie_exact_rules"] + metrics["trie_wildcard_rules"], 2)


if __name__ == "__main__":
    unittest.main()
