"""
FocusDNS Engine - RFC 9432 DNS Catalog Zones Subsystem
Standards & RFCs:
- RFC 9432: DNS Catalog Zones
- Automated dynamic provisioning, modification, and retirement of secondary member zones
"""

import hashlib
import json
import threading
import time
from typing import Dict, List, Optional, Set, Tuple, Any

from dnslib import DNSRecord, RR, QTYPE, TXT, PTR, SOA

from .zone_authority import AuthoritativeZone, AuthoritativeRecord, SplitHorizonView

CATALOG_SCHEMA_VERSION = "2"


class CatalogMember:
    """Represents a member zone cataloged under an RFC 9432 Catalog Zone."""

    def __init__(
        self,
        zone_origin: str,
        unique_id: Optional[str] = None,
        group: str = "default",
        properties: Optional[Dict[str, str]] = None,
    ):
        self.zone_origin = zone_origin.strip().lower().rstrip(".")
        if unique_id is None:
            # Deterministic SHA-256 hash label based on member name
            self.unique_id = hashlib.sha256(self.zone_origin.encode("utf-8")).hexdigest()[:16]
        else:
            self.unique_id = unique_id.strip().lower()

        self.group = group.strip()
        self.properties = properties or {}
        self.created_at = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "zone_origin": self.zone_origin,
            "unique_id": self.unique_id,
            "group": self.group,
            "properties": self.properties,
            "created_at": self.created_at,
        }


class CatalogZoneManager:
    """
    Manages RFC 9432 DNS Catalog Zones.
    Enables automatic zero-touch provisioning of hundreds of secondary zones
    across DNS server clusters simply by adding a single catalog PTR entry.
    """

    def __init__(self, catalog_origin: str = "catalog.focusdns.local"):
        self.catalog_origin = catalog_origin.strip().lower().rstrip(".")
        # unique_id -> CatalogMember
        self._members: Dict[str, CatalogMember] = {}
        # zone_origin -> unique_id
        self._origin_index: Dict[str, str] = {}

        self.serial = int(time.time())
        self._lock = threading.Lock()

        # Callbacks triggered when member zones are provisioned or retired
        self._on_zone_added: List[Any] = []
        self._on_zone_removed: List[Any] = []

    def add_member(
        self,
        zone_origin: str,
        group: str = "default",
        properties: Optional[Dict[str, str]] = None,
    ) -> CatalogMember:
        """Adds a new member zone to the catalog, triggering auto-provisioning."""
        clean = zone_origin.strip().lower().rstrip(".")
        member = CatalogMember(clean, group=group, properties=properties)

        with self._lock:
            # If already exists, update
            if clean in self._origin_index:
                old_id = self._origin_index[clean]
                self._members.pop(old_id, None)

            self._members[member.unique_id] = member
            self._origin_index[clean] = member.unique_id
            self.serial += 1

        # Dispatch listeners
        for cb in self._on_zone_added:
            try:
                cb(member)
            except Exception:
                pass

        return member

    def remove_member(self, zone_origin: str) -> bool:
        """Removes member zone from catalog, triggering retirement."""
        clean = zone_origin.strip().lower().rstrip(".")
        removed_member = None

        with self._lock:
            uid = self._origin_index.pop(clean, None)
            if uid and uid in self._members:
                removed_member = self._members.pop(uid)
                self.serial += 1

        if removed_member:
            for cb in self._on_zone_removed:
                try:
                    cb(removed_member)
                except Exception:
                    pass
            return True
        return False

    def get_member(self, zone_origin: str) -> Optional[CatalogMember]:
        clean = zone_origin.strip().lower().rstrip(".")
        with self._lock:
            uid = self._origin_index.get(clean)
            return self._members.get(uid) if uid else None

    def list_members(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [m.to_dict() for m in self._members.values()]

    def generate_authoritative_zone(self) -> AuthoritativeZone:
        """
        Synthesizes an RFC 9432 compliant AuthoritativeZone object containing:
        - version.<catalog>. IN TXT "2"
        - <unique_id>.zones.<catalog>. IN PTR <member_origin>.
        - group.<unique_id>.zones.<catalog>. IN TXT "<group>"
        """
        zone = AuthoritativeZone(self.catalog_origin)
        zone.serial = self.serial

        # Schema version record
        version_rec = AuthoritativeRecord(
            name=f"version.{self.catalog_origin}",
            rtype="TXT",
            rdata=f'"{CATALOG_SCHEMA_VERSION}"',
            ttl=3600,
        )
        zone.add_record(version_rec)

        with self._lock:
            for m in self._members.values():
                # Member PTR: <id>.zones.<catalog>. PTR <origin>.
                ptr_name = f"{m.unique_id}.zones.{self.catalog_origin}"
                ptr_rec = AuthoritativeRecord(
                    name=ptr_name,
                    rtype="PTR",
                    rdata=f"{m.zone_origin}.",
                    ttl=3600,
                )
                zone.add_record(ptr_rec)

                # Group property: group.<id>.zones.<catalog>. TXT "<group>"
                if m.group:
                    grp_name = f"group.{m.unique_id}.zones.{self.catalog_origin}"
                    grp_rec = AuthoritativeRecord(
                        name=grp_name,
                        rtype="TXT",
                        rdata=f'"{m.group}"',
                        ttl=3600,
                    )
                    zone.add_record(grp_rec)

                # Custom properties: <key>.<id>.zones.<catalog>. TXT "<val>"
                for prop_k, prop_v in m.properties.items():
                    prop_name = f"{prop_k}.{m.unique_id}.zones.{self.catalog_origin}"
                    prop_rec = AuthoritativeRecord(
                        name=prop_name,
                        rtype="TXT",
                        rdata=f'"{prop_v}"',
                        ttl=3600,
                    )
                    zone.add_record(prop_rec)

        return zone

    def parse_catalog_zone(self, zone: AuthoritativeZone) -> int:
        """
        Ingests an RFC 9432 Catalog Zone received via AXFR or master file,
        rebuilding local member index and auto-provisioning zones.
        Returns number of members updated.
        """
        clean_catalog = zone.origin
        new_members: Dict[str, CatalogMember] = {}

        with zone._lock:
            # First pass: find member PTR records under zones.<catalog>
            for (rname, rtype), recs in zone._records.items():
                if rtype == "PTR" and f".zones.{clean_catalog}" in rname:
                    # Extracts unique_id: <unique_id>.zones.<catalog>
                    prefix = rname[:rname.find(f".zones.{clean_catalog}")]
                    if "." in prefix:
                        continue  # Sub-property, not the member PTR itself
                    uid = prefix
                    member_origin = recs[0].rdata.rstrip(".").lower()
                    new_members[uid] = CatalogMember(member_origin, unique_id=uid)

            # Second pass: extract properties (group, coo, etc.)
            for (rname, rtype), recs in zone._records.items():
                if rtype == "TXT" and f".zones.{clean_catalog}" in rname:
                    suffix = f".zones.{clean_catalog}"
                    prefix = rname[:rname.find(suffix)]
                    parts = prefix.split(".")
                    if len(parts) == 2:
                        prop_name, uid = parts[0], parts[1]
                        if uid in new_members:
                            val = recs[0].rdata.strip('"')
                            if prop_name == "group":
                                new_members[uid].group = val
                            else:
                                new_members[uid].properties[prop_name] = val

        with self._lock:
            self._members = new_members
            self._origin_index = {m.zone_origin: m.unique_id for m in new_members.values()}
            self.serial = zone.serial

        return len(new_members)

    def on_add(self, callback: Any):
        self._on_zone_added.append(callback)

    def on_remove(self, callback: Any):
        self._on_zone_removed.append(callback)

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "catalog_origin": self.catalog_origin,
                "serial": self.serial,
                "member_count": len(self._members),
                "listeners_configured": len(self._on_zone_added) + len(self._on_zone_removed),
            }


# Aliases for architectural uniformity
CatalogZoneEngine = CatalogZoneManager
CatalogZoneMember = CatalogMember


class CatalogZoneDelta:
    """
    Represents differential changes between two catalog zone states (RFC 9432).
    Tracks additions, removals, and deep property modifications.
    """

    def __init__(
        self,
        added_members: Optional[List[CatalogMember]] = None,
        removed_members: Optional[List[CatalogMember]] = None,
        modified_members: Optional[List[Dict[str, Any]]] = None,
    ):
        self.added_members: List[CatalogMember] = added_members or []
        self.removed_members: List[CatalogMember] = removed_members or []
        self.modified_members: List[Dict[str, Any]] = modified_members or []
        self.timestamp: float = time.time()

    @property
    def has_changes(self) -> bool:
        """Returns True if there are any additions, removals, or modifications."""
        return bool(self.added_members or self.removed_members or self.modified_members)

    @property
    def total_changes(self) -> int:
        """Returns total count of affected member zones."""
        return len(self.added_members) + len(self.removed_members) + len(self.modified_members)

    def summary(self) -> str:
        """Returns concise human-readable delta summary."""
        parts = []
        if self.added_members:
            parts.append(f"+{len(self.added_members)} added")
        if self.removed_members:
            parts.append(f"-{len(self.removed_members)} removed")
        if self.modified_members:
            parts.append(f"~{len(self.modified_members)} modified")
        return ", ".join(parts) if parts else "no changes"

    def to_dict(self) -> Dict[str, Any]:
        """Serializes delta to JSON-compatible dictionary."""
        return {
            "timestamp": self.timestamp,
            "has_changes": self.has_changes,
            "total_changes": self.total_changes,
            "summary": self.summary(),
            "added": [m.to_dict() for m in self.added_members],
            "removed": [m.to_dict() for m in self.removed_members],
            "modified": self.modified_members,
        }


class CatalogZoneDiffEngine:
    """
    High-performance differential analysis engine for RFC 9432 Catalog Zones.
    Enables zero-touch secondary synchronization, dry-run change detection,
    and reversible delta application.
    """

    @staticmethod
    def diff_managers(
        old_mgr: CatalogZoneManager, new_mgr: CatalogZoneManager
    ) -> CatalogZoneDelta:
        """
        Computes the differential state change between two CatalogZoneManager instances.
        Detects additions, removals, and group/property modifications.
        """
        old_list = old_mgr.list_members()
        new_list = new_mgr.list_members()

        old_map: Dict[str, Dict[str, Any]] = {m["zone_origin"]: m for m in old_list}
        new_map: Dict[str, Dict[str, Any]] = {m["zone_origin"]: m for m in new_list}

        added: List[CatalogMember] = []
        removed: List[CatalogMember] = []
        modified: List[Dict[str, Any]] = []

        # Find added members
        for origin, data in new_map.items():
            if origin not in old_map:
                added.append(
                    CatalogMember(
                        origin,
                        unique_id=data.get("unique_id"),
                        group=data.get("group", "default"),
                        properties=data.get("properties", {}),
                    )
                )

        # Find removed members
        for origin, data in old_map.items():
            if origin not in new_map:
                removed.append(
                    CatalogMember(
                        origin,
                        unique_id=data.get("unique_id"),
                        group=data.get("group", "default"),
                        properties=data.get("properties", {}),
                    )
                )

        # Find modified members
        for origin, new_data in new_map.items():
            if origin in old_map:
                old_data = old_map[origin]
                group_changed = old_data.get("group") != new_data.get("group")
                old_props = old_data.get("properties", {})
                new_props = new_data.get("properties", {})

                # Find property level differences
                prop_diffs: Dict[str, Tuple[Any, Any]] = {}
                all_keys = set(old_props.keys()) | set(new_props.keys())
                for k in all_keys:
                    old_v = old_props.get(k)
                    new_v = new_props.get(k)
                    if old_v != new_v:
                        prop_diffs[k] = (old_v, new_v)

                if group_changed or prop_diffs:
                    modified.append({
                        "zone_origin": origin,
                        "unique_id": new_data.get("unique_id"),
                        "old_group": old_data.get("group"),
                        "new_group": new_data.get("group"),
                        "group_changed": group_changed,
                        "old_properties": old_props,
                        "new_properties": new_props,
                        "property_changes": prop_diffs,
                    })

        return CatalogZoneDelta(
            added_members=added,
            removed_members=removed,
            modified_members=modified,
        )

    @classmethod
    def diff_zones(
        cls,
        old_zone: AuthoritativeZone,
        new_zone: AuthoritativeZone,
        catalog_origin: str = "catalog.focusdns.local",
    ) -> CatalogZoneDelta:
        """
        Parses two raw AuthoritativeZone catalog representations and computes deltas.
        """
        old_mgr = CatalogZoneManager(catalog_origin)
        old_mgr.parse_catalog_zone(old_zone)

        new_mgr = CatalogZoneManager(catalog_origin)
        new_mgr.parse_catalog_zone(new_zone)

        return cls.diff_managers(old_mgr, new_mgr)

    @staticmethod
    def apply_delta(target_mgr: CatalogZoneManager, delta: CatalogZoneDelta) -> int:
        """
        Applies a CatalogZoneDelta to a target CatalogZoneManager instance.
        Returns total number of operations performed.
        """
        ops_applied = 0

        # 1. Process additions
        for m in delta.added_members:
            target_mgr.add_member(
                zone_origin=m.zone_origin,
                group=m.group,
                properties=dict(m.properties),
            )
            ops_applied += 1

        # 2. Process removals
        for m in delta.removed_members:
            if target_mgr.remove_member(m.zone_origin):
                ops_applied += 1

        # 3. Process modifications
        for mod in delta.modified_members:
            origin = mod["zone_origin"]
            new_grp = mod.get("new_group", "default")
            new_props = dict(mod.get("new_properties", {}))
            target_mgr.add_member(
                zone_origin=origin,
                group=new_grp,
                properties=new_props,
            )
            ops_applied += 1

        return ops_applied

    @staticmethod
    def revert_delta(target_mgr: CatalogZoneManager, delta: CatalogZoneDelta) -> int:
        """
        Inverts and applies a CatalogZoneDelta to rollback changes.
        Returns total number of reversion operations performed.
        """
        ops_reverted = 0

        # 1. Reverse additions by removing
        for m in delta.added_members:
            if target_mgr.remove_member(m.zone_origin):
                ops_reverted += 1

        # 2. Reverse removals by re-adding
        for m in delta.removed_members:
            target_mgr.add_member(
                zone_origin=m.zone_origin,
                group=m.group,
                properties=dict(m.properties),
            )
            ops_reverted += 1

        # 3. Reverse modifications by restoring old state
        for mod in delta.modified_members:
            origin = mod["zone_origin"]
            old_grp = mod.get("old_group", "default")
            old_props = dict(mod.get("old_properties", {}))
            target_mgr.add_member(
                zone_origin=origin,
                group=old_grp,
                properties=old_props,
            )
            ops_reverted += 1

        return ops_reverted


class CatalogAuditEntry:
    """
    Cryptographically verifiable append-only audit entry.
    Features SHA-256 hash chaining to ensure tamper evidence.
    """

    def __init__(
        self,
        entry_id: int,
        action: str,
        details: Dict[str, Any],
        actor: str = "system",
        prev_hash: str = "0" * 64,
        timestamp: Optional[float] = None,
    ):
        self.entry_id: int = entry_id
        self.action: str = action
        self.details: Dict[str, Any] = details
        self.actor: str = actor
        self.prev_hash: str = prev_hash
        self.timestamp: float = timestamp or time.time()
        self.hash: str = self.compute_hash()

    def compute_hash(self) -> str:
        """Generates deterministic SHA-256 hash of entry metadata and payload."""
        canonical_details = json.dumps(self.details, sort_keys=True, separators=(",", ":"))
        payload = (
            f"{self.entry_id}|{self.action}|{self.actor}|"
            f"{self.timestamp:.6f}|{canonical_details}|{self.prev_hash}"
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    def verify(self) -> bool:
        """Validates that this entry's stored hash matches its computed content."""
        return self.hash == self.compute_hash()

    def to_dict(self) -> Dict[str, Any]:
        """Serializes entry to dictionary representation."""
        return {
            "entry_id": self.entry_id,
            "action": self.action,
            "details": self.details,
            "actor": self.actor,
            "timestamp": self.timestamp,
            "prev_hash": self.prev_hash,
            "hash": self.hash,
        }


class CatalogAuditLogger:
    """
    Append-only cryptographically verifiable audit log and snapshot manager
    for RFC 9432 Catalog Zone provisioning workflows.
    Maintains SHA-256 hash chaining to guarantee audit trail non-repudiation.
    Supports point-in-time snapshots and instant rollbacks.
    """

    def __init__(self, max_entries: int = 5000):
        self._entries: List[CatalogAuditEntry] = []
        self._snapshots: Dict[str, Dict[str, Any]] = {}
        self._lock = threading.RLock()
        self.max_entries: int = max_entries
        self._last_hash: str = "0" * 64
        self._next_id: int = 1

    def record_action(
        self, action: str, details: Dict[str, Any], actor: str = "system"
    ) -> CatalogAuditEntry:
        """Records an action in the tamper-evident cryptographic log."""
        with self._lock:
            entry = CatalogAuditEntry(
                entry_id=self._next_id,
                action=action,
                details=details,
                actor=actor,
                prev_hash=self._last_hash,
            )
            self._entries.append(entry)
            self._last_hash = entry.hash
            self._next_id += 1

            # Cap entries if exceeding buffer size while preserving recent history
            if len(self._entries) > self.max_entries:
                self._entries.pop(0)

            return entry

    def create_snapshot(
        self, manager: CatalogZoneManager, tag: str = "", actor: str = "system"
    ) -> str:
        """
        Creates an immutable point-in-time snapshot of the catalog manager state.
        Returns a unique snapshot ID.
        """
        members_copy = manager.list_members()
        ts = time.time()
        snapshot_id = f"snap-{int(ts)}-{hashlib.sha256(str(ts).encode()).hexdigest()[:8]}"

        snapshot_data = {
            "snapshot_id": snapshot_id,
            "tag": tag or f"Snapshot at {time.ctime(ts)}",
            "timestamp": ts,
            "serial": manager.serial,
            "catalog_origin": manager.catalog_origin,
            "member_count": len(members_copy),
            "members": members_copy,
        }

        with self._lock:
            self._snapshots[snapshot_id] = snapshot_data

        self.record_action(
            action="SNAPSHOT_CREATED",
            details={
                "snapshot_id": snapshot_id,
                "tag": tag,
                "serial": manager.serial,
                "member_count": len(members_copy),
            },
            actor=actor,
        )
        return snapshot_id

    def rollback_to_snapshot(
        self, snapshot_id: str, manager: CatalogZoneManager, actor: str = "system"
    ) -> bool:
        """
        Restores a CatalogZoneManager to a previously saved snapshot.
        Records the rollback event in the tamper-evident audit log.
        """
        with self._lock:
            snap = self._snapshots.get(snapshot_id)
            if not snap:
                return False
            target_members = snap["members"]

        # Calculate delta between current state and snapshot target
        current_members = {m["zone_origin"]: m for m in manager.list_members()}
        target_map = {m["zone_origin"]: m for m in target_members}

        # Remove members not in target snapshot
        for origin in list(current_members.keys()):
            if origin not in target_map:
                manager.remove_member(origin)

        # Restore target members with exact groups and properties
        for origin, data in target_map.items():
            manager.add_member(
                zone_origin=origin,
                group=data.get("group", "default"),
                properties=data.get("properties", {}),
            )

        self.record_action(
            action="SNAPSHOT_ROLLBACK",
            details={
                "snapshot_id": snapshot_id,
                "tag": snap.get("tag", ""),
                "restored_member_count": len(target_members),
            },
            actor=actor,
        )
        return True

    def verify_integrity(self) -> Tuple[bool, Optional[int]]:
        """
        Validates the entire cryptographic hash chain.
        Returns (True, None) if completely intact, or (False, broken_index) if tampered.
        """
        with self._lock:
            expected_prev = "0" * 64
            for idx, entry in enumerate(self._entries):
                # 1. Verify internal self-hash
                if not entry.verify():
                    return False, idx

                # 2. Verify chain linkage
                if idx > 0 and entry.prev_hash != expected_prev:
                    return False, idx

                expected_prev = entry.hash

            return True, None

    def get_entries(
        self, limit: int = 100, reverse: bool = True
    ) -> List[Dict[str, Any]]:
        """Retrieves recent audit entries up to limit."""
        with self._lock:
            entries = self._entries[:]

        if reverse:
            entries = list(reversed(entries))

        return [e.to_dict() for e in entries[:limit]]

    def get_snapshots(self) -> List[Dict[str, Any]]:
        """Returns metadata for all available catalog snapshots."""
        with self._lock:
            return [
                {
                    "snapshot_id": s["snapshot_id"],
                    "tag": s["tag"],
                    "timestamp": s["timestamp"],
                    "serial": s["serial"],
                    "member_count": s["member_count"],
                    "catalog_origin": s["catalog_origin"],
                }
                for s in self._snapshots.values()
            ]

    def export_audit_log_json(self, limit: int = 1000) -> str:
        """Exports audit trail as formatted JSON document."""
        entries = self.get_entries(limit=limit, reverse=False)
        return json.dumps(
            {
                "exported_at": time.time(),
                "total_entries": len(entries),
                "integrity_valid": self.verify_integrity()[0],
                "entries": entries,
            },
            indent=2,
        )

    def get_stats(self) -> Dict[str, Any]:
        """Returns statistics on audit log buffer and snapshot storage."""
        with self._lock:
            valid, broken_idx = self.verify_integrity()
            return {
                "total_entries_recorded": self._next_id - 1,
                "buffered_entries": len(self._entries),
                "snapshot_count": len(self._snapshots),
                "last_hash": self._last_hash,
                "integrity_valid": valid,
                "broken_index": broken_idx,
            }

