"""
Unit & Integration Tests for FocusDNS Traffic Replay & PCAP Dissector Subsystem
===============================================================================
Validates:
  1. Libpcap 2.4 binary PCAP file generation and framing
  2. Protocol layer dissection: L2 Ethernet, L3 IPv4, and L4 UDP
  3. Raw DNS payload extraction and round-trip parsing
  4. TrafficReplayEngine simulation, QPS throughput, and latency percentiles
"""

import io
import unittest
from dnslib import DNSRecord, QTYPE, RR, A
from server.engine.traffic_replay import (
    PCAP_MAGIC_MICROSECONDS,
    LINKTYPE_ETHERNET,
    PCAPPacket,
    PCAPDissector,
    TrafficReplayEngine,
)


class TestPCAPDissector(unittest.TestCase):
    """Tests Libpcap 2.4 generation and protocol layer dissection."""

    def test_synthetic_pcap_generation_and_dissection(self):
        domains = [f"replay-node-{i}.test.org" for i in range(10)]
        pcap_raw = PCAPDissector.generate_synthetic_pcap(
            domains=domains,
            qtype="A",
            src_ip="192.0.2.77",
            dst_ip="127.0.0.1",
            dst_port=5354,
        )

        self.assertGreater(len(pcap_raw), 500)
        # Verify PCAP file magic
        import struct
        magic = struct.unpack("!I", pcap_raw[:4])[0]
        self.assertEqual(magic, PCAP_MAGIC_MICROSECONDS)

        # Parse stream
        packets = PCAPDissector.parse_stream(io.BytesIO(pcap_raw))
        self.assertEqual(len(packets), 10)

        # Inspect first packet
        pkt0 = packets[0]
        self.assertEqual(pkt0.src_ip, "192.0.2.77")
        self.assertEqual(pkt0.dst_ip, "127.0.0.1")
        self.assertEqual(pkt0.dst_port, 5354)
        self.assertEqual(pkt0.protocol, "UDP")
        self.assertIsNotNone(pkt0.dns_payload)

        # Decode extracted DNS wire packet
        dns_req = DNSRecord.parse(pkt0.dns_payload)
        self.assertEqual(str(dns_req.q.qname), "replay-node-0.test.org.")
        self.assertEqual(dns_req.q.qtype, QTYPE.A)


class TestTrafficReplayEngine(unittest.TestCase):
    """Tests replay load simulation and latency tracking."""

    def setUp(self):
        domains = [f"host-{i}.example.com" for i in range(25)]
        pcap_raw = PCAPDissector.generate_synthetic_pcap(domains)
        self.packets = PCAPDissector.parse_stream(io.BytesIO(pcap_raw))

    def test_replay_execution_and_metrics(self):
        def mock_handler(wire_bytes: bytes, client_ip: str):
            req = DNSRecord.parse(wire_bytes)
            reply = req.reply()
            reply.add_answer(RR(str(req.q.qname), QTYPE.A, rdata=A("10.0.0.1")))
            return reply.pack(), {"status": "ok"}

        engine = TrafficReplayEngine(target_handler=mock_handler)
        res = engine.replay_packets(self.packets)

        self.assertEqual(res["total_packets_replayed"], 25)
        self.assertEqual(res["successful_responses"], 25)
        self.assertEqual(res["failed_responses"], 0)
        self.assertEqual(res["packet_loss_percent"], 0.0)
        self.assertGreater(res["sustained_qps"], 100)
        self.assertGreaterEqual(res["latency_p50_ms"], 0.0)
        self.assertGreaterEqual(res["latency_p99_ms"], res["latency_p50_ms"])


if __name__ == "__main__":
    unittest.main()
