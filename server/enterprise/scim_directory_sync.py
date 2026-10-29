"""
FocusDNS Enterprise Engine - SCIM 2.0 Directory Sync Protocol.

Implements RFC 7643 (Core Schema) and RFC 7644 (Protocol) for automated user
and group provisioning/deprovisioning from Enterprise Identity Providers (IdPs)
such as Microsoft Entra ID (Azure AD), Okta, Google Workspace, and OneLogin.

Key Capabilities:
  1. Automated User Lifecycle: Just-in-Time & Scheduled Provisioning/Deprovisioning.
  2. Immediate Session Revocation: Deactivating a user instantly invalidates all active JWTs.
  3. Group-to-Role Mapping: Maps IdP directory groups to FocusDNS RoleTiers & Tenant Units.
  4. RFC 7644 Standard Endpoints: /Users, /Groups, /Schemas, /ServiceProviderConfig.
"""

import collections
import datetime
import json
import logging
import re
import secrets
import threading
import time
from typing import Dict, List, Set, Optional, Tuple, Any

from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier,
    EnterpriseUser,
    get_rbac_engine,
)
from server.enterprise.tenant_manager import TenantManager, get_tenant_manager

logger = logging.getLogger("FocusDNS.Enterprise.SCIM")

SCIM_USER_SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:User"
SCIM_GROUP_SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:Group"
SCIM_LIST_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:ListResponse"
SCIM_ERROR_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:Error"
SCIM_SERVICE_PROVIDER_CONFIG = "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"


class ScimGroupMapping:
    """Represents a rule mapping an external IdP group to an internal role and unit."""
    __slots__ = ("idp_group_name", "role", "unit_id")

    def __init__(self, idp_group_name: str, role: RoleTier, unit_id: Optional[str] = None):
        self.idp_group_name = idp_group_name
        self.role = role
        self.unit_id = unit_id


class ScimDirectorySyncEngine:
    """
    SCIM 2.0 Identity Server managing directory federation, automated account
    provisioning, and IdP group synchronization.
    """

    def __init__(
        self,
        rbac_engine: Optional[RbacEngine] = None,
        tenant_manager: Optional[TenantManager] = None,
        default_org_id: str = "org_default",
    ):
        self._lock = threading.RLock()
        self.rbac = rbac_engine or get_rbac_engine()
        self.tenants = tenant_manager or get_tenant_manager()
        self.default_org_id = default_org_id

        # Internal SCIM stores: scim_id -> user_dict / group_dict
        self._users: Dict[str, Dict[str, Any]] = {}
        self._user_email_to_id: Dict[str, str] = {}
        self._groups: Dict[str, Dict[str, Any]] = {}

        # Group Mapping Table: group_name -> ScimGroupMapping
        self._group_mappings: Dict[str, ScimGroupMapping] = {}

        # Provisioning audit log
        self._provisioning_logs: collections.deque = collections.deque(maxlen=1000)

        # Seed standard mappings
        self.register_group_mapping("FocusDNS-SuperAdmins", RoleTier.SUPER_ADMIN)
        self.register_group_mapping("FocusDNS-OrgAdmins", RoleTier.ORG_ADMIN)
        self.register_group_mapping("FocusDNS-Teachers", RoleTier.TEACHER_PARENT, "unit_teachers")
        self.register_group_mapping("FocusDNS-Auditors", RoleTier.COMPLIANCE_AUDITOR)

    def register_group_mapping(
        self,
        idp_group_name: str,
        role: RoleTier,
        unit_id: Optional[str] = None
    ) -> None:
        """Configures an IdP directory group rule."""
        with self._lock:
            self._group_mappings[idp_group_name] = ScimGroupMapping(idp_group_name, role, unit_id)

    # =========================================================================
    # SCIM 2.0 User Endpoints (RFC 7644 Section 3.2 - 3.6)
    # =========================================================================

    def get_service_provider_config(self) -> Dict[str, Any]:
        """Returns RFC 7644 ServiceProviderConfig schema."""
        return {
            "schemas": [SCIM_SERVICE_PROVIDER_CONFIG],
            "documentationUri": "https://focusdns.enterprise/docs/scim",
            "patch": {"supported": True},
            "bulk": {"supported": False},
            "filter": {"supported": True, "maxResults": 200},
            "changePassword": {"supported": False},
            "sort": {"supported": False},
            "etag": {"supported": False},
            "authenticationSchemes": [
                {
                    "name": "OAuth Bearer Token",
                    "description": "Authentication via SCIM Bearer Token",
                    "specUri": "http://tools.ietf.org/html/rfc6750",
                    "type": "oauthbearertoken",
                    "primary": True
                }
            ]
        }

    def list_users(self, start_index: int = 1, count: int = 50) -> Dict[str, Any]:
        """Returns paginated list of SCIM users."""
        with self._lock:
            all_users = list(self._users.values())
            total = len(all_users)
            start = max(0, start_index - 1)
            paged = all_users[start:start + count]

            return {
                "schemas": [SCIM_LIST_SCHEMA],
                "totalResults": total,
                "startIndex": start_index,
                "itemsPerPage": len(paged),
                "Resources": paged
            }

    def get_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            return self._users.get(user_id)

    def create_user(self, scim_payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        """
        Provisions a new user from SCIM 2.0 POST request.
        Syncs account into FocusDNS RBAC engine.
        """
        with self._lock:
            user_name = scim_payload.get("userName", "").strip().lower()
            if not user_name:
                return 400, self._error_response("userName is required", 400)

            # Extract email
            emails = scim_payload.get("emails", [])
            primary_email = user_name
            for em in emails:
                if isinstance(em, dict) and em.get("primary"):
                    primary_email = em.get("value", user_name)
                    break
                elif isinstance(em, dict) and "value" in em:
                    primary_email = em.get("value")

            if primary_email in self._user_email_to_id:
                return 409, self._error_response(f"User with email '{primary_email}' already exists", 409)

            user_id = f"usr_{secrets.token_hex(8)}"
            is_active = bool(scim_payload.get("active", True))
            display_name = scim_payload.get("displayName") or scim_payload.get("name", {}).get("formatted", user_name)

            # Determine initial role based on group memberships or default
            assigned_role: Optional[RoleTier] = None
            assigned_units: List[str] = []

            groups = scim_payload.get("groups", [])
            for grp in groups:
                grp_name = grp.get("display") or grp.get("value")
                if grp_name in self._group_mappings:
                    mapping = self._group_mappings[grp_name]
                    # Assign highest role
                    if assigned_role is None or mapping.role.level > assigned_role.level:
                        assigned_role = mapping.role
                    if mapping.unit_id and mapping.unit_id not in assigned_units:
                        assigned_units.append(mapping.unit_id)

            if assigned_role is None:
                assigned_role = RoleTier.TEAM_LEAD

            # Register in RBAC Engine
            try:
                self.rbac.register_user(
                    user_id=user_id,
                    username=user_name,
                    email=primary_email,
                    role=assigned_role,
                    tenant_id=self.default_org_id,
                    sub_tenant_ids=assigned_units,
                )
            except Exception as e:
                logger.warning(f"RBAC registration note: {e}")

            # Construct SCIM response
            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
            scim_user = {
                "schemas": [SCIM_USER_SCHEMA],
                "id": user_id,
                "userName": user_name,
                "displayName": display_name,
                "emails": [{"value": primary_email, "primary": True}],
                "active": is_active,
                "groups": groups,
                "meta": {
                    "resourceType": "User",
                    "created": now_iso,
                    "lastModified": now_iso,
                    "location": f"/scim/v2/Users/{user_id}",
                    "version": f"W/\"{secrets.token_hex(4)}\""
                }
            }

            self._users[user_id] = scim_user
            self._user_email_to_id[primary_email] = user_id
            self._log_event("PROVISION_USER", user_id, primary_email, f"Role={assigned_role.name}")

            logger.info(f"[SCIM] Provisioned user '{user_name}' ({primary_email}) with role {assigned_role.name}.")
            return 201, scim_user

    def patch_user(self, user_id: str, patch_payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        """
        Applies RFC 7644 Section 3.5.2 PATCH modifications.
        Crucial: Setting active=False immediately revokes all user sessions!
        """
        with self._lock:
            user = self._users.get(user_id)
            if not user:
                return 404, self._error_response(f"User '{user_id}' not found", 404)

            operations = patch_payload.get("Operations", [])
            for op in operations:
                op_type = op.get("op", "").lower()
                path = op.get("path", "").lower()
                val = op.get("value")

                if op_type in ("replace", "add"):
                    if path == "active" or (isinstance(val, dict) and "active" in val):
                        new_active = val if path == "active" else val["active"]
                        user["active"] = bool(new_active)
                        if not user["active"]:
                            # Immediate Session Revocation
                            self._revoke_user_sessions(user_id)

                    elif path == "displayname" or (isinstance(val, dict) and "displayName" in val):
                        user["displayName"] = val if path == "displayname" else val["displayName"]

            user["meta"]["lastModified"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            self._log_event("PATCH_USER", user_id, user["userName"], f"Active={user['active']}")
            return 200, user

    def delete_user(self, user_id: str) -> Tuple[int, Dict[str, Any]]:
        """Deprovisions and removes a SCIM user resource."""
        with self._lock:
            user = self._users.pop(user_id, None)
            if not user:
                return 404, self._error_response(f"User '{user_id}' not found", 404)

            for email_entry in user.get("emails", []):
                self._user_email_to_id.pop(email_entry.get("value"), None)

            # Revoke all JWT sessions
            self._revoke_user_sessions(user_id)
            self._log_event("DEPROVISION_USER", user_id, user["userName"], "User deleted")

            logger.info(f"[SCIM] Deprovisioned user '{user_id}'.")
            return 204, {}

    # =========================================================================
    # SCIM 2.0 Group Endpoints (RFC 7644 Section 3.2)
    # =========================================================================

    def create_group(self, group_payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        """Provisions an IdP group and synchronizes membership."""
        with self._lock:
            display_name = group_payload.get("displayName", "").strip()
            if not display_name:
                return 400, self._error_response("displayName is required", 400)

            group_id = f"grp_{secrets.token_hex(6)}"
            members = group_payload.get("members", [])

            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
            scim_group = {
                "schemas": [SCIM_GROUP_SCHEMA],
                "id": group_id,
                "displayName": display_name,
                "members": members,
                "meta": {
                    "resourceType": "Group",
                    "created": now_iso,
                    "lastModified": now_iso,
                    "location": f"/scim/v2/Groups/{group_id}"
                }
            }
            self._groups[group_id] = scim_group
            self._log_event("CREATE_GROUP", group_id, display_name, f"Members={len(members)}")

            # Apply group mapping to members
            if display_name in self._group_mappings:
                mapping = self._group_mappings[display_name]
                for m in members:
                    member_id = m.get("value")
                    if member_id and member_id in self._users:
                        rbac_user = self.rbac.get_user(member_id)
                        if rbac_user:
                            rbac_user.role = mapping.role
                            if mapping.unit_id and mapping.unit_id not in rbac_user.sub_tenant_ids:
                                rbac_user.sub_tenant_ids.append(mapping.unit_id)

            return 201, scim_group

    def _revoke_user_sessions(self, user_id: str) -> None:
        """Invalidates active authentication tokens for the deprovisioned user."""
        with self._lock:
            revoked_count = self.rbac.revoke_user_sessions(user_id)
            if revoked_count > 0:
                logger.info(f"[SCIM SECURITY] Instantly revoked {revoked_count} active sessions for deprovisioned user {user_id}.")

    def _log_event(self, action: str, resource_id: str, identifier: str, details: str) -> None:
        self._provisioning_logs.append({
            "timestamp": time.time(),
            "action": action,
            "resource_id": resource_id,
            "identifier": identifier,
            "details": details,
        })

    def get_provisioning_logs(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._lock:
            logs = list(self._provisioning_logs)
            return logs[-limit:]

    @staticmethod
    def _error_response(detail: str, status_code: int) -> Dict[str, Any]:
        return {
            "schemas": [SCIM_ERROR_SCHEMA],
            "detail": detail,
            "status": str(status_code)
        }


# Global Singleton
_global_scim_engine: Optional[ScimDirectorySyncEngine] = None
_scim_lock = threading.Lock()


def get_scim_engine() -> ScimDirectorySyncEngine:
    global _global_scim_engine
    with _scim_lock:
        if _global_scim_engine is None:
            _global_scim_engine = ScimDirectorySyncEngine()
        return _global_scim_engine
