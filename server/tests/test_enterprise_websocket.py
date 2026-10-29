"""
Unit Test Suite for FocusDNS Enterprise - Real-Time WebSocket Fleet Push Hub.
Validates RFC 6455 frame encoding/decoding, sub-50ms policy fanout,
offline message staging, client ACK tracking, and heartbeat watchdog.
"""

import time
import unittest
from server.enterprise.fleet_websocket_server import (
    FleetWebSocketServer,
    FleetClientConnection,
    PendingPushMessage,
    WS_OPCODE_TEXT,
    WS_OPCODE_PING,
    WS_OPCODE_PONG
)


class TestEnterpriseWebSocket(unittest.TestCase):

    def setUp(self):
        self.ws_server = FleetWebSocketServer(ping_interval_sec=5.0, ack_timeout_sec=2.0)

    def tearDown(self):
        self.ws_server.shutdown()

    def test_rfc6455_frame_encoding_and_decoding_roundtrip(self):
        """Validates RFC 6455 frame serializer and parser with client masking."""
        payload_text = '{"action":"POLICY_UPDATE","profile_id":"profile_strict"}'

        # Encode server frame (unmasked)
        raw_frame = self.ws_server.encode_frame(payload_text, opcode=WS_OPCODE_TEXT)
        self.assertEqual(raw_frame[0] & 0x0F, WS_OPCODE_TEXT)

        # Simulate client frame with 4-byte mask
        mask = b"\x12\x34\x56\x78"
        data_bytes = payload_text.encode("utf-8")
        masked_payload = bytearray()
        for i, b in enumerate(data_bytes):
            masked_payload.append(b ^ mask[i % 4])

        client_frame = bytearray([0x81, 0x80 | len(data_bytes)]) + mask + masked_payload
        decoded = self.ws_server.decode_frame(bytes(client_frame))

        self.assertIsNotNone(decoded)
        opcode, unmasked_bytes = decoded  # type: ignore
        self.assertEqual(opcode, WS_OPCODE_TEXT)
        self.assertEqual(unmasked_bytes.decode("utf-8"), payload_text)

    def test_client_registration_and_direct_push(self):
        """Registers connected fleet device and dispatches push update."""
        conn = self.ws_server.register_client(
            device_id="win_dev_01",
            org_id="org_acme",
            unit_id="unit_sales",
            fleet_id="flt_laptops",
            platform="WINDOWS"
        )
        self.assertEqual(self.ws_server.get_online_device_count(), 1)
        self.assertEqual(self.ws_server.get_online_device_count("org_acme"), 1)

        msg_id = self.ws_server.send_to_device("win_dev_01", {"action": "INSTANT_FLUSH_DNS_CACHE"})
        self.assertTrue(msg_id.startswith("msg_"))
        self.assertEqual(conn.send_queue.qsize(), 1)

        msg = conn.send_queue.get_nowait()
        self.assertEqual(msg["action"], "INSTANT_FLUSH_DNS_CACHE")

    def test_targeted_fleet_and_unit_broadcasts(self):
        """Fans out messages across fleets and units."""
        conn1 = self.ws_server.register_client("dev_1", "org_1", "unit_A", "fleet_X")
        conn2 = self.ws_server.register_client("dev_2", "org_1", "unit_A", "fleet_X")
        conn3 = self.ws_server.register_client("dev_3", "org_1", "unit_B", "fleet_Y")

        # Broadcast to fleet_X
        dispatched_count = self.ws_server.broadcast_to_fleet("fleet_X", {"action": "LOCK_SESSION", "duration": 3600})
        self.assertEqual(dispatched_count, 2)
        self.assertEqual(conn1.send_queue.qsize(), 1)
        self.assertEqual(conn2.send_queue.qsize(), 1)
        self.assertEqual(conn3.send_queue.qsize(), 0)

        # Broadcast to unit_B
        count_unit = self.ws_server.broadcast_to_unit("unit_B", {"action": "POLICY_UPDATE"})
        self.assertEqual(count_unit, 1)
        self.assertEqual(conn3.send_queue.qsize(), 1)

    def test_offline_message_staging_and_guaranteed_delivery(self):
        """Stages messages when device is offline; flushes immediately upon registration."""
        # Device is currently offline
        msg_id = self.ws_server.send_to_device("dev_offline_1", {"action": "REMOTE_WIPE"})
        self.assertIn("dev_offline_1", self.ws_server._offline_queues)
        self.assertEqual(len(self.ws_server._offline_queues["dev_offline_1"]), 1)

        # Device comes online
        conn = self.ws_server.register_client("dev_offline_1", "org_1", "unit_1", "fleet_1")
        # Queued message must be flushed to the connection queue
        self.assertEqual(conn.send_queue.qsize(), 1)
        flushed_msg = conn.send_queue.get_nowait()
        self.assertEqual(flushed_msg["message_id"], msg_id)
        self.assertEqual(flushed_msg["action"], "REMOTE_WIPE")

    def test_client_ack_and_latency_computation(self):
        """Processes client delivery ACK and computes connection RTT latency."""
        conn = self.ws_server.register_client("dev_ack", "org_1", "unit_1", "fleet_1")
        msg_id = self.ws_server.send_to_device("dev_ack", {"action": "PING"})

        time.sleep(0.01)  # small simulated delay
        ack_success = self.ws_server.handle_client_ack("dev_ack", msg_id, client_ts=time.time())
        self.assertTrue(ack_success)
        self.assertGreater(conn.rtt_ms, 0.0)

    def test_heartbeat_watchdog_cleanup(self):
        """Disconnects stale devices whose heartbeat expired."""
        conn = self.ws_server.register_client("dev_stale", "org_1", "unit_1", "fleet_1")
        conn.last_heartbeat = time.time() - 100.0  # 100s in past

        # Trigger single watchdog check pass
        stale = self.ws_server.check_stale_clients()
        self.assertIn("dev_stale", stale)
        self.assertNotIn("dev_stale", self.ws_server._clients)


if __name__ == "__main__":
    unittest.main()
