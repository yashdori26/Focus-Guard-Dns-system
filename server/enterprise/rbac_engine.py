"""
FocusDNS Enterprise Engine - Hierarchical Role-Based Access Control (RBAC).

Granular, multi-tenant permission tiers with cryptographic session tokens,
tamper-evident SHA-256 audit hash chaining, and ironclad enforcement of the
Conditional Whitelisting Law.

Role Hierarchy:
  1. SUPER_ADMIN: Global system-wide root; cross-tenant management, SIEM config, licensing.
  2. ORG_ADMIN: Organization authority; sub-tenant provisioning, staff management, fleet defaults.
  3. TEAM_LEAD: Departmental manager; fleet device monitoring, routine policy management.
  4. TEACHER_PARENT: Classroom or family custodian; local device visibility, temporary focus unlocks.
  5. COMPLIANCE_AUDITOR: Read-only regulatory inspector; audit log verification, compliance exports.
"""

import collections
import hashlib
import hmac
import json
import logging
import os
import secrets
import threading
import time
from enum import Enum
from typing import Dict, List, Set, Optional, Tuple, Any

logger = logging.getLogger("FocusDNS.Enterprise.RBAC")


class RoleTier(str, Enum):
    SUPER_ADMIN = "SUPER_ADMIN"
    ORG_ADMIN = "ORG_ADMIN"
    TEAM_LEAD = "TEAM_LEAD"
    TEACHER_PARENT = "TEACHER_PARENT"
    COMPLIANCE_AUDITOR = "COMPLIANCE_AUDITOR"

    @property
    def level(self) -> int:
        levels = {
            RoleTier.SUPER_ADMIN: 100,
            RoleTier.ORG_ADMIN: 80,
            RoleTier.TEAM_LEAD: 60,
            RoleTier.TEACHER_PARENT: 40,
            RoleTier.COMPLIANCE_AUDITOR: 20
        }
        return levels.get(self, 0)


class Permission(str, Enum):
    VIEW_ANALYTICS = "VIEW_ANALYTICS"
    EXPORT_COMPLIANCE = "EXPORT_COMPLIANCE"
    MANAGE_USERS = "MANAGE_USERS"
    MANAGE_FLEET = "MANAGE_FLEET"
    UPDATE_POLICY = "UPDATE_POLICY"
    OVERRIDE_FOCUS = "OVERRIDE_FOCUS"
    MANAGE_SIEM = "MANAGE_SIEM"
    AUDIT_LOG_READ = "AUDIT_LOG_READ"
    SYSTEM_CONFIG = "SYSTEM_CONFIG"


# Standardized Role-to-Permission Mapping
ROLE_PERMISSIONS: Dict[RoleTier, Set[Permission]] = {
    RoleTier.SUPER_ADMIN: {
        Permission.VIEW_ANALYTICS,
        Permission.EXPORT_COMPLIANCE,
        Permission.MANAGE_USERS,
        Permission.MANAGE_FLEET,
        Permission.UPDATE_POLICY,
        Permission.OVERRIDE_FOCUS,
        Permission.MANAGE_SIEM,
        Permission.AUDIT_LOG_READ,
        Permission.SYSTEM_CONFIG
    },
    RoleTier.ORG_ADMIN: {
        Permission.VIEW_ANALYTICS,
        Permission.EXPORT_COMPLIANCE,
        Permission.MANAGE_USERS,
        Permission.MANAGE_FLEET,
        Permission.UPDATE_POLICY,
        Permission.OVERRIDE_FOCUS,
        Permission.MANAGE_SIEM,
        Permission.AUDIT_LOG_READ
    },
    RoleTier.TEAM_LEAD: {
        Permission.VIEW_ANALYTICS,
        Permission.MANAGE_FLEET,
        Permission.UPDATE_POLICY,
        Permission.AUDIT_LOG_READ
    },
    RoleTier.TEACHER_PARENT: {
        Permission.VIEW_ANALYTICS,
        Permission.MANAGE_FLEET,
        Permission.OVERRIDE_FOCUS
    },
    RoleTier.COMPLIANCE_AUDITOR: {
        Permission.VIEW_ANALYTICS,
        Permission.EXPORT_COMPLIANCE,
        Permission.AUDIT_LOG_READ
        # Strictly READ-ONLY; CANNOT update policy, mutate fleet, or override focus
    }
}


class EnterpriseUser:
    """Enterprise user profile with tenant bindings and role credentials."""
    __slots__ = (
        "user_id", "username", "email", "role", "tenant_id",
        "sub_tenant_ids", "password_hash", "salt", "is_active", "created_at"
    )

    def __init__(
        self,
        user_id: str,
        username: str,
        email: str,
        role: RoleTier,
        tenant_id: str,
        sub_tenant_ids: Optional[List[str]] = None,
        password_hash: str = "",
        salt: str = "",
        is_active: bool = True,
        created_at: Optional[float] = None
    ):
        self.user_id = user_id
        self.username = username
        self.email = email.lower()
        self.role = role if isinstance(role, RoleTier) else RoleTier(role)
        self.tenant_id = tenant_id
        self.sub_tenant_ids = sub_tenant_ids or []
        self.password_hash = password_hash
        self.salt = salt
        self.is_active = is_active
        self.created_at = created_at or time.time()

    def to_dict(self, include_secrets: bool = False) -> Dict[str, Any]:
        d = {
            "user_id": self.user_id,
            "username": self.username,
            "email": self.email,
            "role": self.role.value,
            "tenant_id": self.tenant_id,
            "sub_tenant_ids": self.sub_tenant_ids,
            "is_active": self.is_active,
            "created_at": self.created_at
        }
        if include_secrets:
            d["password_hash"] = self.password_hash
            d["salt"] = self.salt
        return d


class AuditLogEntry:
    """Tamper-evident audit entry protected with cryptographic hash chaining."""
    __slots__ = (
        "entry_id", "timestamp", "actor_user_id", "actor_role",
        "tenant_id", "action", "resource", "details", "status",
        "previous_hash", "entry_hash"
    )

    def __init__(
        self,
        entry_id: str,
        timestamp: float,
        actor_user_id: str,
        actor_role: str,
        tenant_id: str,
        action: str,
        resource: str,
        details: Dict[str, Any],
        status: str,
        previous_hash: str,
        entry_hash: str = ""
    ):
        self.entry_id = entry_id
        self.timestamp = timestamp
        self.actor_user_id = actor_user_id
        self.actor_role = actor_role
        self.tenant_id = tenant_id
        self.action = action
        self.resource = resource
        self.details = details
        self.status = status
        self.previous_hash = previous_hash
        self.entry_hash = entry_hash or self.compute_hash()

    def compute_hash(self, secret_key: str = "FocusDNS-Audit-Anchor-Secret") -> str:
        payload = (
            f"{self.entry_id}:{self.timestamp}:{self.actor_user_id}:"
            f"{self.actor_role}:{self.tenant_id}:{self.action}:"
            f"{self.resource}:{json.dumps(self.details, sort_keys=True)}:"
            f"{self.status}:{self.previous_hash}"
        )
        return hmac.new(
            secret_key.encode("utf-8"),
            payload.encode("utf-8"),
            hashlib.sha256
        ).hexdigest()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "entry_id": self.entry_id,
            "timestamp": self.timestamp,
            "actor_user_id": self.actor_user_id,
            "actor_role": self.actor_role,
            "tenant_id": self.tenant_id,
            "action": self.action,
            "resource": self.resource,
            "details": self.details,
            "status": self.status,
            "previous_hash": self.previous_hash,
            "entry_hash": self.entry_hash
        }


class RbacEngine:
    """
    Enterprise RBAC Engine enforcing multi-tenant role authorization,
    tamper-evident audit logging, and Strict Mode / Conditional Whitelisting.
    """

    GENESIS_HASH = "0000000000000000000000000000000000000000000000000000000000000000"

    def __init__(self, secret_key: Optional[str] = None):
        self.secret_key = secret_key or secrets.token_hex(32)
        self._lock = threading.RLock()
        self._users: Dict[str, EnterpriseUser] = {}
        self._active_sessions: Dict[str, EnterpriseUser] = {}
        self._audit_chain: List[AuditLogEntry] = []
        self._latest_hash = self.GENESIS_HASH

        # Provision default system Super Admin
        self._init_default_super_admin()

    def _init_default_super_admin(self) -> None:
        admin_salt = secrets.token_hex(16)
        admin_pass_hash = self.hash_password("admin123", admin_salt)
        super_admin = EnterpriseUser(
            user_id="usr_super_admin",
            username="superadmin",
            email="admin@focusdns.internal",
            role=RoleTier.SUPER_ADMIN,
            tenant_id="global",
            password_hash=admin_pass_hash,
            salt=admin_salt
        )
        self._users[super_admin.user_id] = super_admin

    @staticmethod
    def hash_password(password: str, salt: str) -> str:
        return hashlib.sha256(f"{salt}:{password}".encode("utf-8")).hexdigest()

    def register_user(
        self,
        username: str,
        email: str,
        password: Optional[str] = None,
        role: RoleTier = RoleTier.TEAM_LEAD,
        tenant_id: str = "default",
        sub_tenant_ids: Optional[List[str]] = None,
        actor_user_id: str = "system",
        user_id: Optional[str] = None,
    ) -> EnterpriseUser:
        with self._lock:
            clean_email = email.lower().strip()
            # Check duplicates
            for u in self._users.values():
                if u.username == username or u.email == clean_email:
                    raise ValueError(f"User with username '{username}' or email '{email}' already exists.")

            salt = secrets.token_hex(16)
            effective_pwd = password or secrets.token_hex(20)
            pwd_hash = self.hash_password(effective_pwd, salt)
            effective_user_id = user_id or f"usr_{secrets.token_hex(8)}"

            new_user = EnterpriseUser(
                user_id=effective_user_id,
                username=username,
                email=clean_email,
                role=role,
                tenant_id=tenant_id,
                sub_tenant_ids=sub_tenant_ids,
                password_hash=pwd_hash,
                salt=salt
            )
            self._users[effective_user_id] = new_user

            self.record_audit_event(
                actor_user_id=actor_user_id,
                actor_role="ADMIN",
                tenant_id=tenant_id,
                action="USER_REGISTER",
                resource=f"user/{effective_user_id}",
                details={"username": username, "role": role.value, "tenant_id": tenant_id},
                status="SUCCESS"
            )
            return new_user

    def get_user(self, user_id: str) -> Optional[EnterpriseUser]:
        with self._lock:
            return self._users.get(user_id)

    def get_user_by_email(self, email: str) -> Optional[EnterpriseUser]:
        clean = email.strip().lower()
        with self._lock:
            for u in self._users.values():
                if u.email == clean:
                    return u
            return None

    def authenticate(self, username_or_email: str, password: str) -> Optional[Tuple[EnterpriseUser, str]]:
        """Verifies credentials and issues a cryptographic session token."""
        with self._lock:
            target: Optional[EnterpriseUser] = None
            clean_identifier = username_or_email.lower().strip()

            for u in self._users.values():
                if u.username.lower() == clean_identifier or u.email == clean_identifier:
                    target = u
                    break

            if not target or not target.is_active:
                return None

            expected_hash = self.hash_password(password, target.salt)
            if not hmac.compare_digest(target.password_hash, expected_hash):
                self.record_audit_event(
                    actor_user_id=target.user_id,
                    actor_role=target.role.value,
                    tenant_id=target.tenant_id,
                    action="AUTH_LOGIN_FAIL",
                    resource=f"user/{target.user_id}",
                    details={"identifier": username_or_email},
                    status="FAILURE"
                )
                return None

            token = self.create_session_token(target)
            self.record_audit_event(
                actor_user_id=target.user_id,
                actor_role=target.role.value,
                tenant_id=target.tenant_id,
                action="AUTH_LOGIN_SUCCESS",
                resource=f"user/{target.user_id}",
                details={"role": target.role.value},
                status="SUCCESS"
            )
            return target, token

    def create_session_token(self, user: EnterpriseUser, ttl_seconds: int = 86400) -> str:
        """Generates an HMAC-SHA256 authenticated session token."""
        expires_at = int(time.time()) + ttl_seconds
        payload = {
            "uid": user.user_id,
            "tid": user.tenant_id,
            "role": user.role.value,
            "exp": expires_at,
            "nonce": secrets.token_hex(8)
        }
        encoded_payload = json.dumps(payload, separators=(',', ':'))
        sig = hmac.new(
            self.secret_key.encode("utf-8"),
            encoded_payload.encode("utf-8"),
            hashlib.sha256
        ).hexdigest()
        token = f"{encoded_payload}.{sig}"
        with self._lock:
            self._active_sessions[token] = user
        return token

    def verify_session_token(self, token_str: str) -> Optional[EnterpriseUser]:
        """Validates signature and expiration of a session token."""
        try:
            with self._lock:
                if token_str not in self._active_sessions:
                    return None

            parts = token_str.rsplit(".", 1)
            if len(parts) != 2:
                return None
            encoded_payload, sig = parts

            expected_sig = hmac.new(
                self.secret_key.encode("utf-8"),
                encoded_payload.encode("utf-8"),
                hashlib.sha256
            ).hexdigest()

            if not hmac.compare_digest(sig, expected_sig):
                return None

            payload = json.loads(encoded_payload)
            if payload.get("exp", 0) < time.time():
                return None  # Expired

            user_id = payload.get("uid")
            with self._lock:
                user = self._users.get(user_id)
                if user and user.is_active:
                    return user
            return None
        except Exception:
            return None

    def revoke_user_sessions(self, user_id: str) -> int:
        """Purges active sessions and deactivates account upon deprovisioning."""
        with self._lock:
            user = self._users.get(user_id)
            if user:
                user.is_active = False
            revoked_count = 0
            for token, u in list(self._active_sessions.items()):
                if u.user_id == user_id:
                    del self._active_sessions[token]
                    revoked_count += 1
            return revoked_count

    def authorize(
        self,
        user: EnterpriseUser,
        permission: Permission,
        target_tenant_id: str,
        target_sub_tenant_id: Optional[str] = None
    ) -> bool:
        """
        Enforces hierarchical permissions and strict multi-tenant boundary isolation.
        """
        # 1. Super Admin has universal access
        if user.role == RoleTier.SUPER_ADMIN:
            return True

        # 2. Check if the role grants the required permission
        allowed_permissions = ROLE_PERMISSIONS.get(user.role, set())
        if permission not in allowed_permissions:
            return False

        # 3. Tenant Boundary Isolation Check
        if user.tenant_id != target_tenant_id:
            # Cannot access a different organization
            return False

        # 4. Sub-tenant boundary for restricted roles (e.g. Teacher/Parent or Team Lead)
        if target_sub_tenant_id and user.sub_tenant_ids:
            if target_sub_tenant_id not in user.sub_tenant_ids:
                return False

        return True

    def check_whitelist_mutation(
        self,
        user: EnterpriseUser,
        target_tenant_id: str,
        is_locked: bool,
        countdown_seconds: int = 0
    ) -> None:
        """
        INVIOLABLE CONDITIONAL WHITELISTING LAW ENFORCEMENT:
        Even Super-Admins and Org-Admins CANNOT whitelist or bypass security
        if the target session is locked or active countdown is running.
        Strictly raises PermissionError: ERROR_ACCESS_DENIED (5).
        """
        if is_locked or countdown_seconds > 0:
            err_msg = (
                f"ERROR_ACCESS_DENIED (5): Enterprise policy violation! "
                f"Cannot whitelist domains or disable protection for tenant '{target_tenant_id}' "
                f"during active locked session with {countdown_seconds}s remaining."
            )
            self.record_audit_event(
                actor_user_id=user.user_id,
                actor_role=user.role.value,
                tenant_id=target_tenant_id,
                action="WHITELIST_MUTATION_REJECTED",
                resource=f"tenant/{target_tenant_id}",
                details={"is_locked": is_locked, "countdown_seconds": countdown_seconds},
                status="BLOCKED_BY_STRICT_MODE"
            )
            raise PermissionError(err_msg)

    def record_audit_event(
        self,
        actor_user_id: str,
        actor_role: str,
        tenant_id: str,
        action: str,
        resource: str,
        details: Dict[str, Any],
        status: str = "SUCCESS"
    ) -> AuditLogEntry:
        """Appends a cryptographic tamper-evident audit record to the ledger."""
        with self._lock:
            entry_id = f"aud_{secrets.token_hex(10)}"
            entry = AuditLogEntry(
                entry_id=entry_id,
                timestamp=time.time(),
                actor_user_id=actor_user_id,
                actor_role=actor_role,
                tenant_id=tenant_id,
                action=action,
                resource=resource,
                details=details,
                status=status,
                previous_hash=self._latest_hash
            )
            self._audit_chain.append(entry)
            self._latest_hash = entry.entry_hash
            return entry

    def verify_audit_chain(self) -> Tuple[bool, Optional[str]]:
        """
        Validates the complete SHA-256 hash chain of the audit ledger.
        Returns (True, None) if unbroken, or (False, failure_reason) if tampered.
        """
        with self._lock:
            expected_prev = self.GENESIS_HASH
            for idx, entry in enumerate(self._audit_chain):
                if entry.previous_hash != expected_prev:
                    return False, f"Broken link at entry {idx} (ID: {entry.entry_id}): previous_hash mismatch"
                computed = entry.compute_hash()
                if entry.entry_hash != computed:
                    return False, f"Tampered entry at index {idx} (ID: {entry.entry_id}): hash signature mismatch"
                expected_prev = entry.entry_hash
            return True, None

    def get_audit_trail(
        self,
        tenant_id: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict[str, Any]]:
        with self._lock:
            entries = []
            for entry in reversed(self._audit_chain):
                if tenant_id and entry.tenant_id != "global" and entry.tenant_id != tenant_id:
                    continue
                entries.append(entry.to_dict())
                if len(entries) >= limit:
                    break
            return entries


# Global Singleton
_global_rbac_engine: Optional[RbacEngine] = None
_rbac_lock = threading.Lock()


def get_rbac_engine() -> RbacEngine:
    global _global_rbac_engine
    with _rbac_lock:
        if _global_rbac_engine is None:
            _global_rbac_engine = RbacEngine()
        return _global_rbac_engine
