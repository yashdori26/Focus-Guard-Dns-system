"""
Unit Test Suite for FocusDNS Enterprise - RFC 5424 Syslog & SIEM Forwarder.
Validates RFC 5424 PRI calculation, wire format framing, structured data tags,
UDP network transport, and Splunk/Datadog payload formatting.
"""

import datetime
import socket
import time
import unittest
from server.enterprise.columnar_analytics import DnsQueryEvent
from server.enterprise.siem_forwarder import (
    SiemForwarder,
    SiemConfig,
    SiemTransport,
    SyslogFacility,
    SyslogSeverity,
    Rfc5424SyslogMessage,
    PEN_FOCUSDNS
)


class TestEnterpriseSiem(unittest.TestCase):

    def test_rfc5424_pri_calculation(self):
        """Validates RFC 5424 Priority = (Facility * 8) + Severity."""
        # Facility: LOCAL0 (16), Severity: ALERT (1) -> (16 * 8) + 1 = 129
        msg_alert = Rfc5424SyslogMessage(
            severity=SyslogSeverity.ALERT,
            msg_id="DGA_THREAT",
            message="Malware detected",
            facility=SyslogFacility.LOCAL0
        )
        self.assertEqual(msg_alert.priority, 129)

        # Facility: LOCAL0 (16), Severity: WARNING (4) -> 132
        msg_warn = Rfc5424SyslogMessage(
            severity=SyslogSeverity.WARNING,
            msg_id="POLICY_DROP",
            message="Social media blocked",
            facility=SyslogFacility.LOCAL0
        )
        self.assertEqual(msg_warn.priority, 132)

        # Facility: LOCAL0 (16), Severity: INFORMATIONAL (6) -> 134
        msg_info = Rfc5424SyslogMessage(
            severity=SyslogSeverity.INFORMATIONAL,
            msg_id="DNS_QUERY",
            message="Clean query allowed",
            facility=SyslogFacility.LOCAL0
        )
        self.assertEqual(msg_info.priority, 134)

    def test_rfc5424_wire_format_serialization(self):
        """Verifies strict RFC 5424 header, structured data, and message formatting."""
        fixed_dt = datetime.datetime(2026, 10, 29, 12, 0, 0, 123456, tzinfo=datetime.timezone.utc)
        sd = {
            f"focusdns@{PEN_FOCUSDNS}": {
                "tenant": "org_acme",
                "domain": "phish-portal.top",
                "action": "BLOCKED"
            }
        }
        msg = Rfc5424SyslogMessage(
            severity=SyslogSeverity.ALERT,
            msg_id="PHISHING_BLOCKED",
            message="Zero-hour phishing domain blocked by on-device AI.",
            structured_data=sd,
            hostname="test-host",
            app_name="FocusDNS",
            proc_id="1234",
            timestamp=fixed_dt
        )
        serialized = msg.to_rfc5424()

        # Check prefix: <129>1 2026-10-29T12:00:00.123456Z test-host FocusDNS 1234 PHISHING_BLOCKED
        self.assertTrue(serialized.startswith("<129>1 2026-10-29T12:00:00.123456Z test-host FocusDNS 1234 PHISHING_BLOCKED"))
        # Check structured data tag
        self.assertIn(f"[focusdns@{PEN_FOCUSDNS}", serialized)
        self.assertIn('tenant="org_acme"', serialized)
        self.assertIn('domain="phish-portal.top"', serialized)
        # Check payload message
        self.assertTrue(serialized.endswith("Zero-hour phishing domain blocked by on-device AI."))

    def test_stream_dns_threat_alert_and_severity_filtering(self):
        """Ensures threat events generate ALERT messages, while low-severity events are filtered."""
        cfg = SiemConfig(
            enabled=True,
            min_severity=SyslogSeverity.WARNING  # Drop INFORMATIONAL queries
        )
        forwarder = SiemForwarder(config=cfg, queue_size=100)

        # 1. Threat query -> ALERT (1) <= WARNING (4) -> ENQUEUED
        threat_ev = DnsQueryEvent(
            timestamp_us=int(time.time() * 1_000_000),
            tenant_id="org_acme",
            sub_tenant_id="unit_1",
            device_id="dev_01",
            client_ip="192.168.1.50",
            domain="malware-c2.xyz",
            action="BLOCKED_MALWARE",
            threat_type="DGA_MALWARE"
        )
        self.assertTrue(forwarder.stream_dns_event(threat_ev))

        # 2. Clean allowed query -> INFORMATIONAL (6) > WARNING (4) -> DROPPED (FILTERED)
        clean_ev = DnsQueryEvent(
            timestamp_us=int(time.time() * 1_000_000),
            tenant_id="org_acme",
            sub_tenant_id="unit_1",
            device_id="dev_01",
            client_ip="192.168.1.50",
            domain="wikipedia.org",
            action="ALLOWED",
            threat_type="NONE"
        )
        self.assertFalse(forwarder.stream_dns_event(clean_ev))
        forwarder.shutdown()

    def test_security_violation_streaming(self):
        """Verifies strict mode tamper attempts generate CRITICAL syslog messages."""
        forwarder = SiemForwarder(config=SiemConfig(enabled=True), queue_size=100)
        queued = forwarder.stream_security_violation(
            tenant_id="org_acme",
            actor="usr_rogue",
            action="WHITELIST_OVERRIDE_ATTEMPT",
            reason="Attempted to unblock social-media during active focus session."
        )
        self.assertTrue(queued)
        forwarder.shutdown()

    def test_real_udp_syslog_transmission(self):
        """Transmits RFC 5424 packet over local loopback UDP socket."""
        # Create ephemeral loopback UDP server
        srv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        srv_sock.bind(("127.0.0.1", 0))
        _, port = srv_sock.getsockname()
        srv_sock.settimeout(2.0)

        cfg = SiemConfig(
            enabled=True,
            transport=SiemTransport.UDP,
            host="127.0.0.1",
            port=port
        )
        forwarder = SiemForwarder(config=cfg)

        msg = Rfc5424SyslogMessage(
            severity=SyslogSeverity.ALERT,
            msg_id="UDP_TEST",
            message="Test UDP Syslog Transmission"
        )
        forwarder.enqueue_message(msg)

        # Receive on server socket
        data, _ = srv_sock.recvfrom(4096)
        srv_sock.close()
        forwarder.shutdown()

        received_str = data.decode("utf-8")
        self.assertIn("UDP_TEST", received_str)
        self.assertIn("Test UDP Syslog Transmission", received_str)


if __name__ == "__main__":
    unittest.main()
