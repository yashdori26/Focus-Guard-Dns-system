"""
Unit Test Suite for FocusDNS Enterprise - Compliance & Regulatory Audit Exporter.
Validates FERPA, COPPA, and GDPR report generation, client IP pseudonymization,
tamper seal hashing, and RBAC authorization barriers.
"""

import os
import tempfile
import time
import unittest
from server.enterprise.columnar_analytics import ColumnarAnalyticsEngine, DnsQueryEvent
from server.enterprise.rbac_engine import RbacEngine, RoleTier, Permission
from server.enterprise.tenant_manager import TenantManager
from server.enterprise.compliance_exporter import ComplianceExporter, ComplianceFramework


class TestEnterpriseCompliance(unittest.TestCase):

    def setUp(self):
        self.temp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.temp_db.close()

        self.rbac = RbacEngine(secret_key="Compliance-Test-Key")
        self.tenants = TenantManager(db_path=self.temp_db.name)
        self.analytics = ColumnarAnalyticsEngine(use_duckdb=False)
        self.exporter = ComplianceExporter(self.analytics, self.rbac, self.tenants)

        # Register Compliance Auditor
        self.auditor = self.rbac.register_user(
            username="auditor_maria",
            email="maria@audit.gov",
            password="secure",
            role=RoleTier.COMPLIANCE_AUDITOR,
            tenant_id="org_school_district"
        )

        # Register Regular Teacher (lacks EXPORT_COMPLIANCE)
        self.teacher = self.rbac.register_user(
            username="teacher_john",
            email="john@school.edu",
            password="secure",
            role=RoleTier.TEACHER_PARENT,
            tenant_id="org_school_district"
        )

        # Seed sample analytics queries
        now_us = int(time.time() * 1_000_000)
        self.analytics.log_batch([
            DnsQueryEvent(now_us - 100_000, "org_school_district", "unit_1", "dev_1", "192.168.1.105", "khanacademy.org"),
            DnsQueryEvent(now_us - 50_000, "org_school_district", "unit_1", "dev_2", "192.168.1.106", "gambling-portal.biz", action="BLOCKED_DISTRACTION", category="CRYPTO_GAMBLING"),
            DnsQueryEvent(now_us - 10_000, "org_school_district", "unit_1", "dev_3", "192.168.1.107", "dga-malware.top", action="BLOCKED_MALWARE", threat_type="DGA_MALWARE")
        ])
        self.analytics.flush()

    def tearDown(self):
        self.analytics.shutdown()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_ip_pseudonymization(self):
        """Verifies GDPR IP subnet zeroing."""
        raw_ip = "192.168.1.145"
        pseudo = self.exporter.pseudonymize_ip(raw_ip)
        self.assertEqual(pseudo, "192.168.1.0/24")

    def test_ferpa_report_generation_and_tamper_seal(self):
        """Generates FERPA compliance report and verifies cryptographic seal."""
        now = time.time()
        report = self.exporter.generate_report(
            framework=ComplianceFramework.FERPA,
            tenant_id="org_school_district",
            actor=self.auditor,
            period_start=now - 3600,
            period_end=now,
            pseudonymize=True
        )
        self.assertEqual(report.framework, "FERPA")
        self.assertEqual(report.tenant_id, "org_school_district")
        self.assertEqual(report.total_queries_analyzed, 3)
        self.assertEqual(report.threat_violations_detected, 1)

        # Verify tamper seal
        computed_seal = report.compute_seal()
        self.assertEqual(report.tamper_seal_hash, computed_seal)

    def test_unauthorized_user_blocked_from_export(self):
        """Teacher lacks EXPORT_COMPLIANCE permission; must raise PermissionError."""
        now = time.time()
        with self.assertRaises(PermissionError) as ctx:
            self.exporter.generate_report(
                framework=ComplianceFramework.COPPA,
                tenant_id="org_school_district",
                actor=self.teacher,
                period_start=now - 3600,
                period_end=now
            )
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_csv_export_format(self):
        """Validates CSV format output."""
        now = time.time()
        csv_data = self.exporter.export_csv(
            tenant_id="org_school_district",
            actor=self.auditor,
            period_start=now - 3600,
            period_end=now
        )
        self.assertIn("Domain,QueryCount,Action,Category", csv_data)
        self.assertIn("khanacademy.org", csv_data)


if __name__ == "__main__":
    unittest.main()
