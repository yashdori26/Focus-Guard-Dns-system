"""
FocusDNS Enterprise Engine - Usage Metering & Billing Reconciliation Unit Tests.

Tests:
  1. Multi-tenant DNS query aggregation and active device tracking.
  2. Multi-tier quota threshold alarms (80% Warning, 95% Critical, 100% Hard Cap).
  3. SIEM telemetry egress and Parquet storage disk footprint metering.
  4. Cryptographically signed billing invoices (HMAC-SHA256).
  5. Invoice signature verification and tamper detection.
"""

import time
import unittest

from server.enterprise.tenant_manager import (
    TenantManager,
    Organization,
    TenantQuota,
)
from server.enterprise.usage_metering import (
    UsageMeteringEngine,
    TenantBillingUsage,
    HMAC_BILLING_SECRET,
)


class TestUsageMeteringEngine(unittest.TestCase):
    """Verifies commercial usage aggregation, quota alarms, and cryptographic billing."""

    def setUp(self):
        self.tenants = TenantManager()
        self.metering = UsageMeteringEngine(tenant_manager=self.tenants)

        # Create organization with a quota of 10 devices
        org = self.tenants.create_organization(
            name="Acme Corporation",
            domain="acme.com",
            plan_tier="ENTERPRISE",
            quota=TenantQuota(max_devices=10, max_qps=500),
        )
        self.org_id = org.org_id

    def test_record_query_usage_and_aggregations(self):
        # Record queries across 3 devices
        self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="laptop_01",
            query_count=50,
            instantaneous_qps=12.5,
        )
        self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="laptop_02",
            query_count=100,
            instantaneous_qps=25.0,
        )
        self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="laptop_03",
            query_count=150,
            instantaneous_qps=18.0,
        )

        usage = self.metering.get_current_usage(self.org_id)
        self.assertEqual(usage["query_count"], 300)
        self.assertEqual(usage["active_device_count"], 3)
        self.assertEqual(usage["peak_qps"], 25.0)

    def test_quota_threshold_alarms(self):
        # Max devices is 10
        # 1. Add 7 devices -> 70% (no alarm)
        for i in range(1, 8):
            alarm = self.metering.record_query_usage(
                org_id=self.org_id,
                device_id=f"dev_{i}",
                query_count=10,
            )
            self.assertIsNone(alarm)

        # 2. Add 8th device -> 80% threshold alarm!
        alarm80 = self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="dev_8",
            query_count=10,
        )
        self.assertEqual(alarm80, 80)

        # 3. Add 9th device -> (already warned 80, but < 95%)
        alarm9 = self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="dev_9",
            query_count=10,
        )
        self.assertIsNone(alarm9)

        # 4. Add 10th device -> 100% hard quota alarm!
        alarm100 = self.metering.record_query_usage(
            org_id=self.org_id,
            device_id="dev_10",
            query_count=10,
        )
        self.assertEqual(alarm100, 100)

    def test_siem_and_storage_metering(self):
        self.metering.record_siem_egress(self.org_id, 1024 * 1024 * 50)  # 50 MB
        self.metering.update_storage_footprint(self.org_id, 1024 * 1024 * 200)  # 200 MB

        usage = self.metering.get_current_usage(self.org_id)
        self.assertEqual(usage["siem_egress_megabytes"], 50.0)
        self.assertEqual(usage["storage_megabytes"], 200.0)

    def test_generate_and_verify_invoice(self):
        # Accumulate usage
        for i in range(5):
            self.metering.record_query_usage(
                org_id=self.org_id,
                device_id=f"workstation_{i}",
                query_count=200_000,
            )
        self.metering.record_siem_egress(self.org_id, 1024 * 1024 * 1024 * 2)  # 2 GB
        self.metering.update_storage_footprint(self.org_id, 1024 * 1024 * 1024 * 5)  # 5 GB

        invoice = self.metering.generate_signed_invoice(self.org_id)
        self.assertIn("invoice_id", invoice)
        self.assertEqual(invoice["org_id"], self.org_id)
        self.assertEqual(invoice["metrics"]["total_queries"], 1_000_000)
        self.assertEqual(invoice["metrics"]["active_devices"], 5)
        self.assertGreater(invoice["charges_usd"]["total"], 0)
        self.assertTrue(len(invoice["signature_sha256"]) == 64)

        # Verify cryptographic HMAC signature
        is_valid = self.metering.verify_invoice_signature(invoice)
        self.assertTrue(is_valid)

    def test_tampered_invoice_fails_verification(self):
        invoice = self.metering.generate_signed_invoice(self.org_id)
        self.assertTrue(self.metering.verify_invoice_signature(invoice))

        # Attacker tampers total amount to 99999.99
        tampered = dict(invoice)
        tampered["charges_usd"] = dict(invoice["charges_usd"])
        tampered["charges_usd"]["total"] = 99999.99

        is_valid = self.metering.verify_invoice_signature(tampered)
        self.assertFalse(is_valid, "Tampered invoice must fail HMAC-SHA256 signature verification!")


if __name__ == "__main__":
    unittest.main()
