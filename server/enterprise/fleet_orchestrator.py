"""
FocusDNS Enterprise Fleet Orchestrator & Cross-Device Gateway
Coordinates multi-device state synchronization (Android mobile app, desktop daemons,
browser extensions), cryptographic pairing token verification, remote session dispatching,
and accountability partner emergency signoff.
"""

import asyncio
import json
import time
import hmac
import hashlib
import secrets
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, field, asdict

@dataclass
class FleetDeviceNode:
    device_id: str
    user_id: str
    device_name: str
    platform: str  # 'android', 'chrome_extension', 'windows', 'macos', 'linux'
    client_version: str
    last_heartbeat_timestamp: float
    is_online: bool = True
    battery_percentage: Optional[int] = None
    is_charging: Optional[bool] = None
    active_mode: str = 'unrestricted'  # 'focus', 'break', 'unrestricted'
    is_strict_lock_active: bool = False
    strict_locked_until: Optional[float] = None
    session_remaining_seconds: int = 0
    distractions_blocked_today: int = 0
    minutes_reclaimed_today: int = 0
    websocket_client: Optional[object] = field(default=None, repr=False)

@dataclass
class EmergencyUnlockRequest:
    request_id: str
    user_id: str
    device_id: str
    reason: str
    partner_email: str
    requested_at: float
    status: str = 'pending'  # 'pending', 'approved', 'rejected', 'expired'
    approved_at: Optional[float] = None
    approval_token: Optional[str] = None

class FleetOrchestrator:
    """Master fleet orchestrator coordinating cross-device state and anti-tamper locks."""

    def __init__(self, secret_key: str = "focus_dns_master_secret_2026"):
        self.secret_key = secret_key.encode('utf-8')
        # user_id -> Dict[device_id, FleetDeviceNode]
        self._user_fleets: Dict[str, Dict[str, FleetDeviceNode]] = {}
        # request_id -> EmergencyUnlockRequest
        self._emergency_requests: Dict[str, EmergencyUnlockRequest] = {}
        # user_id -> accountability partner email
        self._user_partners: Dict[str, str] = {}
        # active pairing codes: code -> (user_id, expiry_timestamp)
        self._pairing_codes: Dict[str, tuple[str, float]] = {}

    # =========================================================================
    # 1. DEVICE REGISTRATION & PAIRING CRYPTOGRAPHY
    # =========================================================================

    def generate_pairing_code(self, user_id: str, lifetime_seconds: int = 300) -> str:
        """Generates a secure 6-digit or alpha pairing code for browser extensions."""
        code = f"{secrets.randbelow(900000) + 100000}"
        self._pairing_codes[code] = (user_id, time.time() + lifetime_seconds)
        return code

    def verify_pairing_code(self, code: str) -> Optional[str]:
        """Validates pairing code and returns associated user_id if valid."""
        self._clean_expired_pairing_codes()
        if code in self._pairing_codes:
            user_id, expiry = self._pairing_codes.pop(code)
            if time.time() <= expiry:
                return user_id
        return None

    def create_device_signature(self, user_id: str, device_id: str, timestamp: int) -> str:
        """Creates an HMAC-SHA256 signature for authenticating device sync messages."""
        msg = f"{user_id}:{device_id}:{timestamp}".encode('utf-8')
        return hmac.new(self.secret_key, msg, hashlib.sha256).hexdigest()

    def verify_device_signature(self, user_id: str, device_id: str, timestamp: int, signature: str) -> bool:
        """Verifies device signature against master secret."""
        if abs(time.time() - timestamp) > 300:  # 5 min replay window
            return False
        expected = self.create_device_signature(user_id, device_id, timestamp)
        return hmac.compare_digest(expected, signature)

    def register_or_update_device(
        self,
        user_id: str,
        device_id: str,
        device_name: str,
        platform: str,
        client_version: str = "2.0.0",
        websocket_client: Optional[object] = None
    ) -> FleetDeviceNode:
        """Registers a new fleet node or updates connection state."""
        if user_id not in self._user_fleets:
            self._user_fleets[user_id] = {}

        now = time.time()
        if device_id in self._user_fleets[user_id]:
            node = self._user_fleets[user_id][device_id]
            node.device_name = device_name
            node.platform = platform
            node.client_version = client_version
            node.last_heartbeat_timestamp = now
            node.is_online = True
            if websocket_client is not None:
                node.websocket_client = websocket_client
        else:
            node = FleetDeviceNode(
                device_id=device_id,
                user_id=user_id,
                device_name=device_name,
                platform=platform,
                client_version=client_version,
                last_heartbeat_timestamp=now,
                is_online=True,
                websocket_client=websocket_client
            )
            self._user_fleets[user_id][device_id] = node

        return node

    def record_heartbeat(
        self,
        user_id: str,
        device_id: str,
        battery: Optional[int] = None,
        is_charging: Optional[bool] = None,
        distractions_blocked: int = 0,
        minutes_reclaimed: int = 0,
        is_strict_lock: bool = False
    ) -> bool:
        """Records telemetry pulse from device."""
        if user_id in self._user_fleets and device_id in self._user_fleets[user_id]:
            node = self._user_fleets[user_id][device_id]
            node.last_heartbeat_timestamp = time.time()
            node.is_online = True
            if battery is not None:
                node.battery_percentage = battery
            if is_charging is not None:
                node.is_charging = is_charging
            node.distractions_blocked_today = distractions_blocked
            node.minutes_reclaimed_today = minutes_reclaimed
            node.is_strict_lock_active = is_strict_lock
            return True
        return False

    def mark_device_offline(self, user_id: str, device_id: str):
        if user_id in self._user_fleets and device_id in self._user_fleets[user_id]:
            node = self._user_fleets[user_id][device_id]
            node.is_online = False
            node.websocket_client = None

    def get_fleet_nodes(self, user_id: str) -> List[dict]:
        """Returns all fleet device nodes for a given user."""
        if user_id not in self._user_fleets:
            return []
        nodes = []
        now = time.time()
        for node in self._user_fleets[user_id].values():
            # Mark offline if no heartbeat in 45 seconds
            if now - node.last_heartbeat_timestamp > 45:
                node.is_online = False
            data = asdict(node)
            data.pop('websocket_client', None)
            nodes.append(data)
        return nodes

    # =========================================================================
    # 2. CROSS-DEVICE SESSION DISPATCHING & LOCK PROPAGATION
    # =========================================================================

    async def broadcast_focus_session_to_fleet(
        self,
        user_id: str,
        origin_device_id: str,
        duration_minutes: int,
        is_strict: bool = True
    ) -> int:
        """Pushes strict focus lock or focus session to all devices in the user's fleet."""
        if user_id not in self._user_fleets:
            return 0

        target_until = time.time() + (duration_minutes * 60) if is_strict else None
        broadcast_payload = json.dumps({
            "type": "TRIGGER_FOCUS_LOCK" if is_strict else "TRIGGER_FOCUS_SESSION",
            "durationMinutes": duration_minutes,
            "isStrict": is_strict,
            "strictLockedUntil": target_until * 1000 if target_until else None,
            "originDeviceId": origin_device_id,
            "timestamp": int(time.time() * 1000)
        })

        dispatched_count = 0
        for dev_id, node in self._user_fleets[user_id].items():
            node.current_mode = 'focus'
            node.is_strict_lock_active = is_strict
            node.strict_locked_until = target_until
            node.session_remaining_seconds = duration_minutes * 60

            # Push to connected WebSocket
            if node.is_online and node.websocket_client:
                try:
                    if hasattr(node.websocket_client, 'send_text'):
                        await node.websocket_client.send_text(broadcast_payload)
                        dispatched_count += 1
                except Exception:
                    node.is_online = False

        return dispatched_count

    async def broadcast_break_session_to_fleet(
        self,
        user_id: str,
        duration_minutes: int = 5
    ) -> int:
        """Transitions entire fleet to mindful break mode."""
        if user_id not in self._user_fleets:
            return 0

        payload = json.dumps({
            "type": "TRIGGER_BREAK",
            "breakDurationMinutes": duration_minutes,
            "timestamp": int(time.time() * 1000)
        })

        dispatched = 0
        for node in self._user_fleets[user_id].values():
            node.current_mode = 'break'
            if node.is_online and node.websocket_client:
                try:
                    if hasattr(node.websocket_client, 'send_text'):
                        await node.websocket_client.send_text(payload)
                        dispatched += 1
                except Exception:
                    node.is_online = False
        return dispatched

    # =========================================================================
    # 3. ACCOUNTABILITY PARTNER EMERGENCY VAULT
    # =========================================================================

    def register_accountability_partner(self, user_id: str, partner_email: str):
        self._user_partners[user_id] = partner_email.lower().strip()

    def get_accountability_partner(self, user_id: str) -> Optional[str]:
        return self._user_partners.get(user_id)

    def create_emergency_unlock_request(
        self,
        user_id: str,
        device_id: str,
        reason: str
    ) -> EmergencyUnlockRequest:
        """Creates a pending unlock request awaiting partner approval."""
        partner = self._user_partners.get(user_id, "partner@focusdns.app")
        request_id = f"req_{secrets.token_hex(8)}"
        req = EmergencyUnlockRequest(
            request_id=request_id,
            user_id=user_id,
            device_id=device_id,
            reason=reason,
            partner_email=partner,
            requested_at=time.time(),
            status='pending'
        )
        self._emergency_requests[request_id] = req
        return req

    def get_pending_emergency_requests(self, partner_email: str) -> List[dict]:
        """Returns all pending unlock requests assigned to a partner."""
        email_clean = partner_email.lower().strip()
        results = []
        for req in self._emergency_requests.values():
            if req.partner_email == email_clean and req.status == 'pending':
                results.append(asdict(req))
        return results

    async def approve_emergency_unlock(
        self,
        request_id: str,
        partner_email: str,
        partner_pin: str
    ) -> bool:
        """Approves emergency request and releases strict lock across all fleet devices."""
        if request_id not in self._emergency_requests:
            return False

        req = self._emergency_requests[request_id]
        if req.partner_email != partner_email.lower().strip():
            return False

        # In production, check partner PIN or cryptographic signature
        req.status = 'approved'
        req.approved_at = time.time()
        req.approval_token = secrets.token_hex(16)

        # Broadcast release across fleet
        await self._broadcast_emergency_release(req.user_id)
        return True

    async def _broadcast_emergency_release(self, user_id: str):
        if user_id not in self._user_fleets:
            return

        payload = json.dumps({
            "type": "EMERGENCY_OVERRIDE_APPROVED",
            "message": "Accountability partner granted emergency unlock.",
            "timestamp": int(time.time() * 1000)
        })

        for node in self._user_fleets[user_id].values():
            node.is_strict_lock_active = False
            node.strict_locked_until = None
            node.current_mode = 'unrestricted'
            if node.is_online and node.websocket_client:
                try:
                    if hasattr(node.websocket_client, 'send_text'):
                        await node.websocket_client.send_text(payload)
                except Exception:
                    pass

    # =========================================================================
    # 4. INTERNAL UTILITIES
    # =========================================================================

    def _clean_expired_pairing_codes(self):
        now = time.time()
        expired = [c for c, (_, exp) in self._pairing_codes.items() if now > exp]
        for c in expired:
            del self._pairing_codes[c]
