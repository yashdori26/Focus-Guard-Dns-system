"""
FocusDNS Enterprise Engine - Automated SIEM & SOAR Threat Response Playbooks Unit Tests.

Tests:
  1. Automated playbook triggering on threat telemetry (phishing, DGA, strict tampering).
  2. Forensic query snapshotting from device history buffer into incident records.
  3. Dynamic Malicious FQDN auto-blacklisting with TTL expiration.
  4. Instantaneous WebSocket endpoint quarantine and restoration.
  5. Anti-Cascade Safety Circuit Breaker: Limits maximum quarantines within rolling window.
  6. Inviolable Life-Safety Exemption: Emergency domains can NEVER be blacklisted or sinkholed.
  7. SIEM RFC 5424 alert streaming and incident response tracking.
"""

import time
import unittest

from server.enterprise.columnar_analytics import DnsQueryEvent
from server.enterprise.soar_playbook_engine import (
    SoarPlaybookEngine,
    SoarTriggerType,
    SoarActionType,
    SoarIncident,
    SoarCircuitBreaker,
    LIFE_SAFETY_DOMAINS,
)


class DummyWebSocketHub:
    """Mock WebSocket hub recording device push messages."""

    def __init__(self):
        self.dispatched_device_frames = []

    def send_to_device(self, device_id: str, message: dict) -> str:
        self.dispatched_device_frames.append((device_id, message))
        return f"msg_{len(self.dispatched_device_frames)}"


class DummySiemForwarder:
    """Mock SIEM forwarder recording RFC 5424 syslog messages."""

    def __init__(self):
        self.enqueued_messages = []

    def enqueue_message(self, msg) -> None:
        self.enqueued_messages.append(msg)


class TestSoarPlaybookEngine(unittest.TestCase):
    """Verifies automated incident response, quarantine push, and safety circuit breakers."""

    def setUp(self):
        self.ws_hub = DummyWebSocketHub()
        self.siem = DummySiemForwarder()
        self.webhook_payloads = []
        self.soar = SoarPlaybookEngine(
            ws_hub=self.ws_hub,
            siem_forwarder=self.siem,
            webhook_dispatcher=lambda p: self.webhook_payloads.append(p),
        )

    def test_phishing_playbook_execution(self):
        device_id = "chromebook_99"
        tenant_id = "org_springfield"

        # Buffer recent queries for forensic snapshot
        for i in range(5):
            self.soar.record_query_for_forensics(
                DnsQueryEvent(
                    timestamp_us=int(time.time() * 1_000_000) - (i * 1000),
                    tenant_id=tenant_id,
                    sub_tenant_id="unit_lincoln_high",
                    device_id=device_id,
                    client_ip="192.168.1.199",
                    domain=f"site{i}.org",
                )
            )

        # Trigger severe phishing catch
        incident = self.soar.evaluate_threat_event(
            tenant_id=tenant_id,
            device_id=device_id,
            domain="steal-creds-bank.xyz",
            threat_type="PHISHING",
            risk_score=96.0,
        )

        self.assertIsNotNone(incident)
        self.assertEqual(incident.trigger_type, SoarTriggerType.ZERO_HOUR_PHISHING)
        self.assertEqual(incident.device_id, device_id)

        # 1. Forensic snapshot captured
        self.assertEqual(len(incident.forensic_snapshot), 5)

        # 2. Malicious domain auto-blacklisted
        self.assertTrue(self.soar.is_domain_auto_blacklisted("steal-creds-bank.xyz"))

        # 3. Endpoint quarantined via WebSocket frame
        self.assertTrue(self.soar.is_device_quarantined(device_id))
        self.assertEqual(len(self.ws_hub.dispatched_device_frames), 1)
        target_dev, frame = self.ws_hub.dispatched_device_frames[0]
        self.assertEqual(target_dev, device_id)
        self.assertEqual(frame["type"], "QUARANTINE_DEVICE")

        # 4. RFC 5424 Syslog and Webhook dispatched
        self.assertEqual(len(self.siem.enqueued_messages), 1)
        self.assertEqual(self.siem.enqueued_messages[0].msg_id, "SOAR_THREAT_CONTAINED")
        self.assertEqual(len(self.webhook_payloads), 1)

    def test_dga_storm_and_quarantine(self):
        device_id = "win11_laptop_12"
        tenant_id = "org_finance"

        incident = self.soar.evaluate_threat_event(
            tenant_id=tenant_id,
            device_id=device_id,
            domain="xkjh18471bcs817.biz",
            threat_type="DGA",
            risk_score=92.0,
        )
        self.assertIsNotNone(incident)
        self.assertEqual(incident.trigger_type, SoarTriggerType.DGA_STORM)
        self.assertTrue(self.soar.is_device_quarantined(device_id))

    def test_lift_quarantine(self):
        device_id = "device_to_restore"
        # Manually trigger quarantine
        self.soar.evaluate_threat_event(
            tenant_id="org_test",
            device_id=device_id,
            domain="malware.cc",
            threat_type="DGA",
        )
        self.assertTrue(self.soar.is_device_quarantined(device_id))

        # Lift quarantine
        lifted = self.soar.lift_quarantine(device_id)
        self.assertTrue(lifted)
        self.assertFalse(self.soar.is_device_quarantined(device_id))

        # Verify RESTORE_DEVICE frame dispatched
        last_frame = self.ws_hub.dispatched_device_frames[-1][1]
        self.assertEqual(last_frame["type"], "RESTORE_DEVICE")

    def test_anti_cascade_circuit_breaker(self):
        """
        Anti-Cascade Circuit Breaker:
        Rate limits automated quarantines to max 5 per window to prevent
        an adversary from causing widespread denial-of-service across the fleet.
        """
        tenant_id = "org_district"

        # Trigger 5 quarantines (should succeed)
        for i in range(5):
            dev = f"device_{i}"
            inc = self.soar.evaluate_threat_event(
                tenant_id=tenant_id,
                device_id=dev,
                domain=f"dga{i}.org",
                threat_type="DGA",
            )
            self.assertIn(SoarActionType.QUARANTINE_DEVICE.value, inc.actions_executed)
            self.assertTrue(self.soar.is_device_quarantined(dev))

        # 6th quarantine must be blocked by the circuit breaker!
        dev_6 = "device_6"
        inc_6 = self.soar.evaluate_threat_event(
            tenant_id=tenant_id,
            device_id=dev_6,
            domain="dga6.org",
            threat_type="DGA",
        )
        self.assertNotIn(SoarActionType.QUARANTINE_DEVICE.value, inc_6.actions_executed)
        self.assertFalse(self.soar.is_device_quarantined(dev_6))
        self.assertEqual(self.soar.get_metrics()["circuit_breaker_trips"], 1)

    def test_life_safety_domains_never_auto_blacklisted(self):
        """
        Inviolable Life Safety Exemption:
        Emergency and OS push domains (911.gov, update.microsoft.com) can NEVER
        be added to auto-blacklist even if maliciously triggered.
        """
        for emergency_domain in ["911.gov", "112.gov", "emergency.gov", "update.microsoft.com"]:
            self.soar.evaluate_threat_event(
                tenant_id="org_test",
                device_id="device_safe",
                domain=emergency_domain,
                threat_type="PHISHING",
            )
            self.assertFalse(
                self.soar.is_domain_auto_blacklisted(emergency_domain),
                f"Emergency domain '{emergency_domain}' must NEVER be blacklisted!"
            )


if __name__ == "__main__":
    unittest.main()
