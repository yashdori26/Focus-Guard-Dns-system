"""
Unit & Integration Tests for FocusDNS RFC 9432 DNS Catalog Zones Subsystem
===========================================================================
Validates:
  1. RFC 9432 Schema Version 2 zone record generation (TXT '2', member PTR, group TXT)
  2. Member zone dynamic addition, modification, and retirement
  3. Change listeners dispatching asynchronous addition/removal hooks
  4. Parsing and round-trip ingestion of catalog zones from raw AuthoritativeZone
  5. Deterministic member unique identifier hashing (SHA-256 prefix)
  6. Incremental zone serial numbering and statistics reporting
"""

import unittest
from server.engine.catalog_zones import (
    CatalogMember,
    CatalogZoneManager,
    CatalogZoneEngine,
    CatalogZoneDelta,
    CatalogZoneDiffEngine,
    CatalogAuditEntry,
    CatalogAuditLogger,
    CATALOG_SCHEMA_VERSION,
)
from server.engine.zone_authority import AuthoritativeZone, AuthoritativeRecord


class TestCatalogMember(unittest.TestCase):
    """Tests CatalogMember serialization and unique hash generation."""

    def test_member_unique_id_generation(self):
        m1 = CatalogMember("customer1.example.com")
        m2 = CatalogMember("customer1.example.com")
        m3 = CatalogMember("customer2.example.com")

        # Deterministic hashing: same zone origin yields same unique_id
        self.assertEqual(m1.unique_id, m2.unique_id)
        self.assertNotEqual(m1.unique_id, m3.unique_id)
        self.assertEqual(len(m1.unique_id), 16)

    def test_explicit_unique_id(self):
        m = CatalogMember("custom.org", unique_id="static-uid-1234", group="vip")
        self.assertEqual(m.unique_id, "static-uid-1234")
        self.assertEqual(m.group, "vip")

    def test_to_dict(self):
        m = CatalogMember("demo.net", group="staging", properties={"coo": "admin@demo.net"})
        d = m.to_dict()
        self.assertEqual(d["zone_origin"], "demo.net")
        self.assertEqual(d["group"], "staging")
        self.assertEqual(d["properties"]["coo"], "admin@demo.net")


class TestCatalogZoneManager(unittest.TestCase):
    """Tests RFC 9432 catalog zone synthesis, query handling, and parsing."""

    def setUp(self):
        self.catalog = CatalogZoneManager("catalog.focusdns.local")

    def test_generate_empty_catalog_records(self):
        # Empty catalog must contain version.<catalog> TXT "2"
        zone = self.catalog.generate_authoritative_zone()
        self.assertEqual(zone.origin, "catalog.focusdns.local")

        version_recs = zone.get_records("version.catalog.focusdns.local", "TXT")
        self.assertEqual(len(version_recs), 1)
        self.assertEqual(version_recs[0].rdata.strip('"'), CATALOG_SCHEMA_VERSION)

    def test_add_member_and_generate_records(self):
        init_serial = self.catalog.serial
        member = self.catalog.add_member("tenant-alpha.io", group="enterprise", properties={"region": "us-east"})

        self.assertEqual(self.catalog.serial, init_serial + 1)
        self.assertIsNotNone(self.catalog.get_member("tenant-alpha.io"))

        zone = self.catalog.generate_authoritative_zone()

        # Check member PTR: <uid>.zones.catalog.focusdns.local. PTR tenant-alpha.io.
        ptr_name = f"{member.unique_id}.zones.catalog.focusdns.local"
        ptr_recs = zone.get_records(ptr_name, "PTR")
        self.assertEqual(len(ptr_recs), 1)
        self.assertEqual(ptr_recs[0].rdata, "tenant-alpha.io.")

        # Check group property: group.<uid>.zones.catalog.focusdns.local. TXT "enterprise"
        grp_name = f"group.{member.unique_id}.zones.catalog.focusdns.local"
        grp_recs = zone.get_records(grp_name, "TXT")
        self.assertEqual(len(grp_recs), 1)
        self.assertEqual(grp_recs[0].rdata.strip('"'), "enterprise")

        # Check custom property: region.<uid>.zones.catalog.focusdns.local. TXT "us-east"
        reg_name = f"region.{member.unique_id}.zones.catalog.focusdns.local"
        reg_recs = zone.get_records(reg_name, "TXT")
        self.assertEqual(len(reg_recs), 1)
        self.assertEqual(reg_recs[0].rdata.strip('"'), "us-east")

    def test_remove_member(self):
        self.catalog.add_member("temp-zone.org")
        self.assertIsNotNone(self.catalog.get_member("temp-zone.org"))

        serial_before = self.catalog.serial
        removed = self.catalog.remove_member("temp-zone.org")
        self.assertTrue(removed)
        self.assertEqual(self.catalog.serial, serial_before + 1)
        self.assertIsNone(self.catalog.get_member("temp-zone.org"))

        # Removing non-existent returns False
        self.assertFalse(self.catalog.remove_member("nonexistent.org"))

    def test_change_event_listeners(self):
        added_zones = []
        removed_zones = []

        self.catalog.on_add(lambda m: added_zones.append(m.zone_origin))
        self.catalog.on_remove(lambda m: removed_zones.append(m.zone_origin))

        self.catalog.add_member("event-zone-1.net")
        self.catalog.add_member("event-zone-2.net")
        self.catalog.remove_member("event-zone-1.net")

        self.assertEqual(added_zones, ["event-zone-1.net", "event-zone-2.net"])
        self.assertEqual(removed_zones, ["event-zone-1.net"])

    def test_parse_catalog_zone_roundtrip(self):
        # 1. Populate catalog
        self.catalog.add_member("member-a.com", group="gold", properties={"coo": "secops"})
        self.catalog.add_member("member-b.com", group="silver")

        # 2. Export to authoritative zone
        auth_zone = self.catalog.generate_authoritative_zone()

        # 3. Create a fresh secondary catalog manager and ingest
        secondary_catalog = CatalogZoneManager("catalog.focusdns.local")
        imported_count = secondary_catalog.parse_catalog_zone(auth_zone)

        self.assertEqual(imported_count, 2)
        self.assertEqual(len(secondary_catalog.list_members()), 2)

        mem_a = secondary_catalog.get_member("member-a.com")
        self.assertIsNotNone(mem_a)
        self.assertEqual(mem_a.group, "gold")
        self.assertEqual(mem_a.properties.get("coo"), "secops")

        mem_b = secondary_catalog.get_member("member-b.com")
        self.assertIsNotNone(mem_b)
        self.assertEqual(mem_b.group, "silver")


class TestCatalogZoneDiffEngine(unittest.TestCase):
    """Tests differential comparison, delta serialization, and reversible application."""

    def test_delta_empty(self):
        delta = CatalogZoneDelta()
        self.assertFalse(delta.has_changes)
        self.assertEqual(delta.total_changes, 0)
        self.assertEqual(delta.summary(), "no changes")

    def test_delta_summary_and_serialization(self):
        m_add = CatalogMember("added.com")
        m_rem = CatalogMember("removed.com")
        mod = {"zone_origin": "mod.com", "group_changed": True}

        delta = CatalogZoneDelta(
            added_members=[m_add],
            removed_members=[m_rem],
            modified_members=[mod],
        )
        self.assertTrue(delta.has_changes)
        self.assertEqual(delta.total_changes, 3)
        self.assertIn("+1 added", delta.summary())
        self.assertIn("-1 removed", delta.summary())
        self.assertIn("~1 modified", delta.summary())

        d = delta.to_dict()
        self.assertEqual(len(d["added"]), 1)
        self.assertEqual(len(d["removed"]), 1)
        self.assertEqual(len(d["modified"]), 1)

    def test_diff_managers_and_delta_application(self):
        old_mgr = CatalogZoneManager("catalog.example.com")
        old_mgr.add_member("zone1.net", group="prod")
        old_mgr.add_member("zone2.net", group="dev", properties={"env": "dev"})

        new_mgr = CatalogZoneManager("catalog.example.com")
        # zone1 modified (properties changed)
        new_mgr.add_member("zone1.net", group="prod", properties={"coo": "secops"})
        # zone2 removed
        # zone3 added
        new_mgr.add_member("zone3.net", group="staging")

        delta = CatalogZoneDiffEngine.diff_managers(old_mgr, new_mgr)
        self.assertTrue(delta.has_changes)
        self.assertEqual(len(delta.added_members), 1)
        self.assertEqual(delta.added_members[0].zone_origin, "zone3.net")
        self.assertEqual(len(delta.removed_members), 1)
        self.assertEqual(delta.removed_members[0].zone_origin, "zone2.net")
        self.assertEqual(len(delta.modified_members), 1)
        self.assertEqual(delta.modified_members[0]["zone_origin"], "zone1.net")

        # Apply delta to target manager that starts matching old_mgr
        target = CatalogZoneManager("catalog.example.com")
        target.add_member("zone1.net", group="prod")
        target.add_member("zone2.net", group="dev", properties={"env": "dev"})

        applied_count = CatalogZoneDiffEngine.apply_delta(target, delta)
        self.assertEqual(applied_count, 3)
        self.assertIsNotNone(target.get_member("zone3.net"))
        self.assertIsNone(target.get_member("zone2.net"))
        self.assertEqual(target.get_member("zone1.net").properties.get("coo"), "secops")

        # Revert delta on target
        reverted_count = CatalogZoneDiffEngine.revert_delta(target, delta)
        self.assertEqual(reverted_count, 3)
        self.assertIsNone(target.get_member("zone3.net"))
        self.assertIsNotNone(target.get_member("zone2.net"))
        self.assertNotIn("coo", target.get_member("zone1.net").properties)

    def test_diff_zones_from_authoritative_records(self):
        mgr1 = CatalogZoneManager("catalog.test")
        mgr1.add_member("site-a.com")
        zone1 = mgr1.generate_authoritative_zone()

        mgr2 = CatalogZoneManager("catalog.test")
        mgr2.add_member("site-a.com")
        mgr2.add_member("site-b.com")
        zone2 = mgr2.generate_authoritative_zone()

        delta = CatalogZoneDiffEngine.diff_zones(zone1, zone2, catalog_origin="catalog.test")
        self.assertTrue(delta.has_changes)
        self.assertEqual(len(delta.added_members), 1)
        self.assertEqual(delta.added_members[0].zone_origin, "site-b.com")
        self.assertEqual(len(delta.removed_members), 0)


class TestCatalogAuditLogger(unittest.TestCase):
    """Tests cryptographically verifiable append-only audit logging and snapshots."""

    def setUp(self):
        self.logger = CatalogAuditLogger(max_entries=100)
        self.catalog = CatalogZoneManager("catalog.audit.local")

    def test_audit_hash_chain_integrity(self):
        # Record three discrete mutations
        e1 = self.logger.record_action("MEMBER_ADD", {"domain": "alpha.io"}, actor="admin1")
        e2 = self.logger.record_action("MEMBER_ADD", {"domain": "beta.io"}, actor="admin2")
        e3 = self.logger.record_action("MEMBER_REMOVE", {"domain": "alpha.io"}, actor="admin1")

        self.assertEqual(e1.entry_id, 1)
        self.assertEqual(e2.entry_id, 2)
        self.assertEqual(e3.entry_id, 3)

        self.assertEqual(e2.prev_hash, e1.hash)
        self.assertEqual(e3.prev_hash, e2.hash)

        # Hash chain must verify 100% valid
        is_valid, broken_idx = self.logger.verify_integrity()
        self.assertTrue(is_valid)
        self.assertIsNone(broken_idx)

    def test_audit_tamper_detection(self):
        self.logger.record_action("A1", {"data": 1})
        self.logger.record_action("A2", {"data": 2})
        self.logger.record_action("A3", {"data": 3})

        is_valid, _ = self.logger.verify_integrity()
        self.assertTrue(is_valid)

        # Maliciously modify the payload of entry index 1
        with self.logger._lock:
            self.logger._entries[1].details = {"data": 999}

        is_valid, broken_idx = self.logger.verify_integrity()
        self.assertFalse(is_valid)
        self.assertEqual(broken_idx, 1)

    def test_snapshot_creation_and_rollback(self):
        # 1. Setup initial state
        self.catalog.add_member("tenant1.com", group="enterprise")
        self.catalog.add_member("tenant2.com", group="standard")

        # 2. Capture snapshot
        snapshot_id = self.logger.create_snapshot(self.catalog, tag="v1.0-release")
        self.assertTrue(snapshot_id.startswith("snap-"))

        # Verify snapshot recorded in audit trail
        snapshots = self.logger.get_snapshots()
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0]["member_count"], 2)

        # 3. Mutate catalog (remove tenant1, add tenant3)
        self.catalog.remove_member("tenant1.com")
        self.catalog.add_member("tenant3.com", group="pro")
        self.assertIsNone(self.catalog.get_member("tenant1.com"))
        self.assertIsNotNone(self.catalog.get_member("tenant3.com"))

        # 4. Perform rollback
        success = self.logger.rollback_to_snapshot(snapshot_id, self.catalog)
        self.assertTrue(success)

        # Verify catalog restored exactly to snapshot state
        self.assertIsNotNone(self.catalog.get_member("tenant1.com"))
        self.assertIsNotNone(self.catalog.get_member("tenant2.com"))
        self.assertIsNone(self.catalog.get_member("tenant3.com"))

        # Verify rollback recorded in audit log
        entries = self.logger.get_entries(limit=5)
        self.assertEqual(entries[0]["action"], "SNAPSHOT_ROLLBACK")

    def test_export_json_and_stats(self):
        self.logger.record_action("INIT", {"status": "ok"})
        json_out = self.logger.export_audit_log_json()
        self.assertIn('"integrity_valid": true', json_out)
        self.assertIn('"INIT"', json_out)

        stats = self.logger.get_stats()
        self.assertEqual(stats["total_entries_recorded"], 1)
        self.assertTrue(stats["integrity_valid"])


if __name__ == "__main__":
    unittest.main()

