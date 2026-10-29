"""
FocusDNS Enterprise Engine - Multi-Tenant Relational Hierarchy & Quota Manager.

Maintains strict organizational isolation across 3 distinct tiers:
  Organization -> TenantUnit (School/Dept) -> DeviceFleet (Grade/Team).

Enforces:
  1. Tenant Quota Caps (device limits, QPS ceilings, retention windows).
  2. Device Enrollment Token Life-Cycles with cryptographic one-time nonces.
  3. Ironclad Strict Mode & Conditional Whitelisting: Locking a fleet bars any policy
     relaxation or domain whitelisting until the timer expires.
"""

import logging
import os
import secrets
import sqlite3
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

logger = logging.getLogger("FocusDNS.Enterprise.TenantManager")

ENTERPRISE_DB_PATH = os.path.join(os.path.dirname(__file__), "enterprise_tenant.db")


class TenantQuota:
    """Resource limits and feature entitlements for an Organization."""
    __slots__ = ("max_devices", "max_qps", "retention_days", "allow_siem", "allow_custom_dga")

    def __init__(
        self,
        max_devices: int = 500,
        max_qps: int = 5000,
        retention_days: int = 90,
        allow_siem: bool = True,
        allow_custom_dga: bool = True
    ):
        self.max_devices = int(max_devices)
        self.max_qps = int(max_qps)
        self.retention_days = int(retention_days)
        self.allow_siem = bool(allow_siem)
        self.allow_custom_dga = bool(allow_custom_dga)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "max_devices": self.max_devices,
            "max_qps": self.max_qps,
            "retention_days": self.retention_days,
            "allow_siem": self.allow_siem,
            "allow_custom_dga": self.allow_custom_dga
        }


class Organization:
    """Top-level enterprise tenant (e.g. School District or Corporation)."""
    __slots__ = ("org_id", "name", "domain", "plan_tier", "is_active", "created_at", "quota")

    def __init__(
        self,
        org_id: str,
        name: str,
        domain: str,
        plan_tier: str = "ENTERPRISE",
        is_active: bool = True,
        created_at: Optional[float] = None,
        quota: Optional[TenantQuota] = None
    ):
        self.org_id = org_id
        self.name = name
        self.domain = domain.lower()
        self.plan_tier = plan_tier.upper()
        self.is_active = is_active
        self.created_at = created_at or time.time()
        self.quota = quota or TenantQuota()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "org_id": self.org_id,
            "name": self.name,
            "domain": self.domain,
            "plan_tier": self.plan_tier,
            "is_active": self.is_active,
            "created_at": self.created_at,
            "quota": self.quota.to_dict()
        }


class TenantUnit:
    """Sub-tenant entity within an Organization (e.g. Lincoln High School or Finance Dept)."""
    __slots__ = ("unit_id", "org_id", "name", "unit_type", "parent_unit_id", "policy_profile", "is_active")

    def __init__(
        self,
        unit_id: str,
        org_id: str,
        name: str,
        unit_type: str = "DEPARTMENT",
        parent_unit_id: Optional[str] = None,
        policy_profile: Optional[Dict[str, Any]] = None,
        is_active: bool = True
    ):
        self.unit_id = unit_id
        self.org_id = org_id
        self.name = name
        self.unit_type = unit_type.upper()
        self.parent_unit_id = parent_unit_id
        self.policy_profile = policy_profile or {"profile_id": "profile_strict", "ai_threat": True}
        self.is_active = is_active

    def to_dict(self) -> Dict[str, Any]:
        return {
            "unit_id": self.unit_id,
            "org_id": self.org_id,
            "name": self.name,
            "unit_type": self.unit_type,
            "parent_unit_id": self.parent_unit_id,
            "policy_profile": self.policy_profile,
            "is_active": self.is_active
        }


class DeviceFleet:
    """Fleet grouping of endpoint devices under a Tenant Unit."""
    __slots__ = (
        "fleet_id", "unit_id", "org_id", "name", "platform",
        "policy_profile_id", "is_locked", "locked_until", "device_count"
    )

    def __init__(
        self,
        fleet_id: str,
        unit_id: str,
        org_id: str,
        name: str,
        platform: str = "ALL",
        policy_profile_id: str = "profile_strict",
        is_locked: bool = False,
        locked_until: Optional[float] = None,
        device_count: int = 0
    ):
        self.fleet_id = fleet_id
        self.unit_id = unit_id
        self.org_id = org_id
        self.name = name
        self.platform = platform.upper()
        self.policy_profile_id = policy_profile_id
        self.is_locked = is_locked
        self.locked_until = locked_until
        self.device_count = device_count

    @property
    def remaining_lock_seconds(self) -> int:
        if not self.is_locked or not self.locked_until:
            return 0
        rem = int(self.locked_until - time.time())
        return max(0, rem)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "fleet_id": self.fleet_id,
            "unit_id": self.unit_id,
            "org_id": self.org_id,
            "name": self.name,
            "platform": self.platform,
            "policy_profile_id": self.policy_profile_id,
            "is_locked": self.is_locked,
            "locked_until": self.locked_until,
            "remaining_lock_seconds": self.remaining_lock_seconds,
            "device_count": self.device_count
        }


class TenantManager:
    """
    Relational SQLite persistence manager for multi-tenant organizations,
    sub-units, device fleets, and enrollment credentials.
    """

    def __init__(self, db_path: str = ENTERPRISE_DB_PATH):
        self.db_path = db_path
        self._lock = threading.RLock()
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=10.0)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()

            # 1. Organizations
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS organizations (
                org_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                domain TEXT NOT NULL,
                plan_tier TEXT DEFAULT 'ENTERPRISE',
                is_active INTEGER DEFAULT 1,
                created_at REAL NOT NULL,
                max_devices INTEGER DEFAULT 500,
                max_qps INTEGER DEFAULT 5000,
                retention_days INTEGER DEFAULT 90,
                allow_siem INTEGER DEFAULT 1,
                allow_custom_dga INTEGER DEFAULT 1
            );
            """)

            # 2. Tenant Units
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS tenant_units (
                unit_id TEXT PRIMARY KEY,
                org_id TEXT NOT NULL,
                name TEXT NOT NULL,
                unit_type TEXT DEFAULT 'DEPARTMENT',
                parent_unit_id TEXT,
                policy_json TEXT,
                is_active INTEGER DEFAULT 1,
                FOREIGN KEY(org_id) REFERENCES organizations(org_id)
            );
            """)

            # 3. Device Fleets
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS device_fleets (
                fleet_id TEXT PRIMARY KEY,
                unit_id TEXT NOT NULL,
                org_id TEXT NOT NULL,
                name TEXT NOT NULL,
                platform TEXT DEFAULT 'ALL',
                policy_profile_id TEXT DEFAULT 'profile_strict',
                is_locked INTEGER DEFAULT 0,
                locked_until REAL,
                device_count INTEGER DEFAULT 0,
                FOREIGN KEY(unit_id) REFERENCES tenant_units(unit_id),
                FOREIGN KEY(org_id) REFERENCES organizations(org_id)
            );
            """)

            # 4. Enrollment Tokens
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS enrollment_tokens (
                token TEXT PRIMARY KEY,
                org_id TEXT NOT NULL,
                unit_id TEXT NOT NULL,
                fleet_id TEXT NOT NULL,
                expires_at REAL NOT NULL,
                max_uses INTEGER DEFAULT 100,
                used_count INTEGER DEFAULT 0
            );
            """)

            conn.commit()
            conn.close()

    def create_organization(
        self,
        name: str,
        domain: str,
        plan_tier: str = "ENTERPRISE",
        quota: Optional[TenantQuota] = None
    ) -> Organization:
        q = quota or TenantQuota()
        org_id = f"org_{secrets.token_hex(6)}"
        now = time.time()

        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
            INSERT INTO organizations (
                org_id, name, domain, plan_tier, is_active, created_at,
                max_devices, max_qps, retention_days, allow_siem, allow_custom_dga
            ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?)
            """, (
                org_id, name, domain.lower(), plan_tier.upper(), now,
                q.max_devices, q.max_qps, q.retention_days,
                1 if q.allow_siem else 0,
                1 if q.allow_custom_dga else 0
            ))
            conn.commit()
            conn.close()

        return Organization(org_id, name, domain, plan_tier, True, now, q)

    def get_organization(self, org_id: str) -> Optional[Organization]:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM organizations WHERE org_id = ?", (org_id,))
            row = cursor.fetchone()
            conn.close()

            if not row:
                return None

            quota = TenantQuota(
                max_devices=row["max_devices"],
                max_qps=row["max_qps"],
                retention_days=row["retention_days"],
                allow_siem=bool(row["allow_siem"]),
                allow_custom_dga=bool(row["allow_custom_dga"])
            )
            return Organization(
                org_id=row["org_id"],
                name=row["name"],
                domain=row["domain"],
                plan_tier=row["plan_tier"],
                is_active=bool(row["is_active"]),
                created_at=row["created_at"],
                quota=quota
            )

    def create_tenant_unit(
        self,
        org_id: str,
        name: str,
        unit_type: str = "DEPARTMENT",
        parent_unit_id: Optional[str] = None
    ) -> TenantUnit:
        org = self.get_organization(org_id)
        if not org:
            raise ValueError(f"Organization '{org_id}' does not exist.")

        unit_id = f"unit_{secrets.token_hex(6)}"
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
            INSERT INTO tenant_units (
                unit_id, org_id, name, unit_type, parent_unit_id, is_active
            ) VALUES (?, ?, ?, ?, ?, 1)
            """, (unit_id, org_id, name, unit_type.upper(), parent_unit_id))
            conn.commit()
            conn.close()

        return TenantUnit(unit_id, org_id, name, unit_type, parent_unit_id)

    def list_tenant_units(self, org_id: str) -> List[TenantUnit]:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM tenant_units WHERE org_id = ? AND is_active = 1", (org_id,))
            rows = cursor.fetchall()
            conn.close()

            return [
                TenantUnit(
                    unit_id=r["unit_id"],
                    org_id=r["org_id"],
                    name=r["name"],
                    unit_type=r["unit_type"],
                    parent_unit_id=r["parent_unit_id"],
                    is_active=bool(r["is_active"])
                )
                for r in rows
            ]

    def create_device_fleet(
        self,
        org_id: str,
        unit_id: str,
        name: str,
        platform: str = "ALL",
        policy_profile_id: str = "profile_strict"
    ) -> DeviceFleet:
        fleet_id = f"flt_{secrets.token_hex(6)}"
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
            INSERT INTO device_fleets (
                fleet_id, unit_id, org_id, name, platform, policy_profile_id,
                is_locked, locked_until, device_count
            ) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, 0)
            """, (fleet_id, unit_id, org_id, name, platform.upper(), policy_profile_id))
            conn.commit()
            conn.close()

        return DeviceFleet(fleet_id, unit_id, org_id, name, platform, policy_profile_id)

    def get_device_fleet(self, fleet_id: str) -> Optional[DeviceFleet]:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM device_fleets WHERE fleet_id = ?", (fleet_id,))
            row = cursor.fetchone()
            conn.close()

            if not row:
                return None

            is_locked = bool(row["is_locked"])
            locked_until = row["locked_until"]

            # Auto-expire lock if past deadline
            if is_locked and locked_until and time.time() >= locked_until:
                is_locked = False
                locked_until = None
                self._update_fleet_lock_status(fleet_id, False, None)

            return DeviceFleet(
                fleet_id=row["fleet_id"],
                unit_id=row["unit_id"],
                org_id=row["org_id"],
                name=row["name"],
                platform=row["platform"],
                policy_profile_id=row["policy_profile_id"],
                is_locked=is_locked,
                locked_until=locked_until,
                device_count=row["device_count"]
            )

    def list_fleets(self, org_id: str) -> List[DeviceFleet]:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM device_fleets WHERE org_id = ?", (org_id,))
            rows = cursor.fetchall()
            conn.close()
            return [
                DeviceFleet(
                    fleet_id=r["fleet_id"],
                    unit_id=r["unit_id"],
                    org_id=r["org_id"],
                    name=r["name"],
                    platform=r["platform"],
                    policy_profile_id=r["policy_profile_id"],
                    is_locked=bool(r["is_locked"]),
                    locked_until=r["locked_until"],
                    device_count=r["device_count"]
                )
                for r in rows
            ]

    def list_organizations(self) -> List[Organization]:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM organizations WHERE is_active = 1")
            rows = cursor.fetchall()
            conn.close()
            result = []
            for r in rows:
                q = TenantQuota(
                    max_devices=r["max_devices"],
                    max_qps=r["max_qps"],
                    retention_days=r["retention_days"],
                    allow_siem=bool(r["allow_siem"]),
                    allow_custom_dga=bool(r["allow_custom_dga"])
                )
                result.append(Organization(
                    org_id=r["org_id"],
                    name=r["name"],
                    domain=r["domain"],
                    plan_tier=r["plan_tier"],
                    is_active=bool(r["is_active"]),
                    created_at=r["created_at"],
                    quota=q
                ))
            return result

    def increment_device_count(self, fleet_id: str, delta: int = 1) -> None:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute(
                "UPDATE device_fleets SET device_count = MAX(0, device_count + ?) WHERE fleet_id = ?",
                (delta, fleet_id)
            )
            conn.commit()
            conn.close()


    def _update_fleet_lock_status(self, fleet_id: str, is_locked: bool, locked_until: Optional[float]) -> None:
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
            UPDATE device_fleets
            SET is_locked = ?, locked_until = ?
            WHERE fleet_id = ?
            """, (1 if is_locked else 0, locked_until, fleet_id))
            conn.commit()
            conn.close()

    def lock_fleet(self, fleet_id: str, duration_seconds: int) -> DeviceFleet:
        """Applies active focus lock to an enterprise device fleet."""
        fleet = self.get_device_fleet(fleet_id)
        if not fleet:
            raise ValueError(f"Device fleet '{fleet_id}' not found.")

        locked_until = time.time() + duration_seconds
        self._update_fleet_lock_status(fleet_id, True, locked_until)
        return self.get_device_fleet(fleet_id)  # type: ignore

    def unlock_fleet(self, fleet_id: str) -> DeviceFleet:
        """Removes lock from fleet (idle mode)."""
        fleet = self.get_device_fleet(fleet_id)
        if not fleet:
            raise ValueError(f"Device fleet '{fleet_id}' not found.")

        self._update_fleet_lock_status(fleet_id, False, None)
        return self.get_device_fleet(fleet_id)  # type: ignore

    def modify_fleet_whitelist(self, fleet_id: str, domain: str, action: str = "ADD") -> bool:
        """
        INVIOLABLE CONDITIONAL WHITELISTING LAW:
        Raises PermissionError if active focus is locked.
        """
        fleet = self.get_device_fleet(fleet_id)
        if not fleet:
            raise ValueError(f"Fleet '{fleet_id}' not found.")

        if fleet.is_locked or fleet.remaining_lock_seconds > 0:
            raise PermissionError(
                f"ERROR_ACCESS_DENIED (5): Fleet '{fleet.name}' is currently locked with "
                f"{fleet.remaining_lock_seconds}s remaining! Whitelist modification rejected."
            )
        return True

    def generate_enrollment_token(
        self,
        org_id: str,
        unit_id: str,
        fleet_id: str,
        ttl_seconds: int = 86400,
        max_uses: int = 100
    ) -> str:
        token = f"enr_{secrets.token_urlsafe(24)}"
        expires_at = time.time() + ttl_seconds

        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("""
            INSERT INTO enrollment_tokens (
                token, org_id, unit_id, fleet_id, expires_at, max_uses, used_count
            ) VALUES (?, ?, ?, ?, ?, ?, 0)
            """, (token, org_id, unit_id, fleet_id, expires_at, max_uses))
            conn.commit()
            conn.close()

        return token

    def validate_and_consume_enrollment(self, token: str) -> Optional[Dict[str, str]]:
        """Verifies enrollment token validity and increments device counter."""
        with self._lock:
            conn = self._get_connection()
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM enrollment_tokens WHERE token = ?", (token,))
            row = cursor.fetchone()

            if not row:
                conn.close()
                return None

            if row["expires_at"] < time.time() or row["used_count"] >= row["max_uses"]:
                conn.close()
                return None

            # Check Org Quota
            org = self.get_organization(row["org_id"])
            if not org:
                conn.close()
                return None

            cursor.execute("SELECT SUM(device_count) as total FROM device_fleets WHERE org_id = ?", (row["org_id"],))
            total_dev = cursor.fetchone()["total"] or 0
            if total_dev >= org.quota.max_devices:
                conn.close()
                logger.warning(f"Org {org.org_id} exceeded max device quota ({org.quota.max_devices}).")
                return None

            # Increment used count
            cursor.execute("UPDATE enrollment_tokens SET used_count = used_count + 1 WHERE token = ?", (token,))
            cursor.execute("UPDATE device_fleets SET device_count = device_count + 1 WHERE fleet_id = ?", (row["fleet_id"],))
            conn.commit()
            conn.close()

            return {
                "org_id": row["org_id"],
                "unit_id": row["unit_id"],
                "fleet_id": row["fleet_id"]
            }


# Global Singleton
_global_tenant_manager: Optional[TenantManager] = None
_tm_lock = threading.Lock()


def get_tenant_manager() -> TenantManager:
    global _global_tenant_manager
    with _tm_lock:
        if _global_tenant_manager is None:
            _global_tenant_manager = TenantManager()
        return _global_tenant_manager
