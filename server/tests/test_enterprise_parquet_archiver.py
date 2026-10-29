"""
Unit Test Suite for FocusDNS Enterprise - Parquet Archiver & CEF Audit Exporter.
Validates Hive-style Parquet partitioning, ZSTD compression, federated queries,
CEF serialization, and external cryptographic audit chain verification.
"""

import os
import shutil
import tempfile
import time
import unittest
from server.enterprise.columnar_analytics import DnsQueryEvent, HAS_DUCKDB
from server.enterprise.parquet_archiver import ParquetArchiver
from server.enterprise.audit_log_exporter import AuditLogExporter
from server.enterprise.rbac_engine import RbacEngine


class TestEnterpriseParquetAndAudit(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.archiver = ParquetArchiver(base_dir=self.temp_dir)
        self.rbac = RbacEngine(secret_key="Audit-Exporter-Test-Secret")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @unittest.skipUnless(HAS_DUCKDB, "DuckDB required for Parquet export")
    def test_parquet_export_and_federated_query(self):
        """Exports batch of queries to ZSTD Parquet partition and queries via SQL."""
        now_us = int(time.time() * 1_000_000)
        events = [
            DnsQueryEvent(now_us, "org_test", "unit_1", "dev_1", "10.0.0.1", "alpha.com"),
            DnsQueryEvent(now_us + 1000, "org_test", "unit_1", "dev_1", "10.0.0.1", "beta.com"),
            DnsQueryEvent(now_us + 2000, "org_test", "unit_1", "dev_1", "10.0.0.1", "c2-malware.top", action="BLOCKED", threat_type="DGA")
        ]

        file_path = self.archiver.export_batch_to_parquet("org_test", events, compression="ZSTD")
        self.assertIsNotNone(file_path)
        self.assertTrue(os.path.exists(file_path))
        self.assertIn("tenant=org_test", file_path)

        # Federated query across all parquet files for org_test
        sql = "SELECT COUNT(*), COUNT(CASE WHEN action = 'BLOCKED' THEN 1 END) FROM queries"
        rows = self.archiver.query_historical_parquet("org_test", sql)
        self.assertEqual(len(rows), 1)
        total, blocked = rows[0]
        self.assertEqual(total, 3)
        self.assertEqual(blocked, 1)

    def test_cef_and_jsonl_audit_export(self):
        """Validates CEF and JSONL formatting."""
        self.rbac.record_audit_event("usr_admin", "SUPER_ADMIN", "org_1", "UPDATE_POLICY", "fleet/1", {"locked": True})
        trail = self.rbac.get_audit_trail(tenant_id="org_1", limit=10)

        # 1. CEF formatting
        cef_output = AuditLogExporter.export_cef_stream(trail)
        self.assertIn("CEF:0|FocusDNS|EnterprisePlatform|7.0.0|UPDATE_POLICY", cef_output)
        self.assertIn("suser=usr_admin", cef_output)
        self.assertIn("cs1=org_1", cef_output)

        # 2. JSONL formatting
        jsonl_output = AuditLogExporter.export_jsonl_stream(trail)
        self.assertIn('"action": "UPDATE_POLICY"', jsonl_output)

    def test_external_auditor_chain_verification(self):
        """Verifies external auditor can validate cryptographic hash chain independently."""
        # Record series
        self.rbac.record_audit_event("usr_1", "ADMIN", "org_1", "ACT_1", "res/1", {})
        self.rbac.record_audit_event("usr_2", "ADMIN", "org_1", "ACT_2", "res/2", {})

        trail = list(reversed(self.rbac.get_audit_trail(limit=10)))
        # Verify valid chain
        is_valid, err = AuditLogExporter.verify_exported_chain(trail, secret_key="FocusDNS-Audit-Anchor-Secret")
        self.assertTrue(is_valid)
        self.assertIsNone(err)

        # Tamper entry
        trail[1]["action"] = "TAMPERED_ACTION"
        is_valid_after, err_msg = AuditLogExporter.verify_exported_chain(trail, secret_key="FocusDNS-Audit-Anchor-Secret")
        self.assertFalse(is_valid_after)
        self.assertIn("Tampered hash signature", str(err_msg))


if __name__ == "__main__":
    unittest.main()
