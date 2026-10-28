"""
FocusDNS Page-Wise REST API Router & DoH Service - Hardened
Includes:
- Mandatory API token authentication (Authorization: Bearer <token> or X-Api-Key)
- Strict Mode enforcement across ALL mutating routes (timer-only; no PIN)
- Rejection of non-JSON content types (415 Unsupported Media Type for simple requests)
- Strict type checking on boolean configuration toggles
- Settings log_retention barrier under Strict Mode
- Real DoH (RFC 8484) wire-format service with 4KB cap and Cache-Control TTLs
- Restricted CORS origin validation protecting local daemon from browser attacks
"""

import base64
import json
import os
import threading
import time
import urllib.parse
import uuid
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler
from typing import Dict, Any, Optional, Tuple

from dnslib import DNSRecord

from . import db
from . import resolver
from .engine.mdm_server import (
    get_fleet_manager,
    PolicyLockMode,
    SplitTunnelPolicyMode,
    MdmPolicyProfile,
)
from .engine.attestation_validator import AttestationValidator
from .engine.private_dns_server import PrivateDnsServerManager
from .engine.oem_telemetry_collector import OemTelemetryCollector
from .engine.dpc_provisioning_server import DpcProvisioningServer
from .engine.kiosk_policy_manager import KioskPolicyManager, KioskProfile
from .engine.managed_config_distributor import ManagedConfigDistributor, TenantAppConfig

_attestation_validator = AttestationValidator()
_private_dns_server = PrivateDnsServerManager()
_oem_telemetry = OemTelemetryCollector()
_dpc_server = DpcProvisioningServer()
_kiosk_manager = KioskPolicyManager()
_appconfig_distributor = ManagedConfigDistributor()

class FocusDNSApiHandler(BaseHTTPRequestHandler):

    def _set_cors_headers(self, status: int = 200, content_type: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        origin = self.headers.get("Origin", "")
        # Protect local API: Only allow localhost, loopback, or app schemes
        allowed_origin = None
        if origin:
            if (origin.startswith("http://localhost:") or
                origin.startswith("http://127.0.0.1:") or
                origin in ("http://localhost", "http://127.0.0.1", "tauri://localhost", "capacitor://localhost")):
                allowed_origin = origin
        else:
            # Native desktop/mobile apps, curl, etc.
            allowed_origin = "*"

        if allowed_origin:
            self.send_header("Access-Control-Allow-Origin", allowed_origin)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Api-Key, X-Admin-Key, X-Requested-With")
            self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Cache-Control", "no-cache")

    def do_OPTIONS(self):
        self._set_cors_headers(204)
        self.end_headers()

    def _verify_auth(self) -> bool:
        """Validates API token strictly from X-Api-Key or Authorization header."""
        token = self.headers.get("X-Api-Key", "").strip()
        if not token:
            auth_header = self.headers.get("Authorization", "").strip()
            if auth_header.startswith("Bearer "):
                token = auth_header[7:].strip()
            elif auth_header:
                token = auth_header.strip()
        if not token:
            return False
        return db.verify_api_token(token)

    def _verify_admin_auth(self) -> bool:
        """
        Validates admin access via:
        1. Cookie: admin_session=<token>
        2. Header: X-Admin-Key: <token_or_master_key>
        3. Header: Authorization: Bearer <token_or_master_key>
        """
        cookie_header = self.headers.get("Cookie", "")
        if cookie_header:
            c = SimpleCookie()
            try:
                c.load(cookie_header)
                if "admin_session" in c:
                    token = c["admin_session"].value.strip()
                    if db.verify_admin_session(token):
                        return True
            except Exception:
                pass

        admin_key = self.headers.get("X-Admin-Key", "").strip()
        if admin_key:
            if db.verify_admin_session(admin_key) or db.verify_admin_master_key(admin_key):
                return True

        auth = self.headers.get("Authorization", "").strip()
        if auth:
            token = auth[7:].strip() if auth.startswith("Bearer ") else auth
            if db.verify_admin_session(token) or db.verify_admin_master_key(token):
                return True

        return False

    def _read_json_body(self, max_bytes: int = 1048576) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        """Reads and validates JSON body up to 1MB."""
        try:
            content_len = int(self.headers.get('Content-Length', 0))
        except ValueError:
            return None, "Invalid Content-Length"

        if content_len > max_bytes:
            return None, "Payload too large (Max 1MB)"
        if content_len == 0:
            return {}, None

        raw = self.rfile.read(content_len)
        try:
            return json.loads(raw.decode('utf-8')), None
        except Exception:
            return None, "Malformed JSON syntax"

    def _send_json(self, data: Any, status: int = 200):
        self._set_cors_headers(status)
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def _send_error(self, message: str, status: int = 400):
        self._send_json({"error": message, "success": False}, status)

    def _check_strict_mode_barrier(self, profile_id: str) -> Tuple[bool, str]:
        """Returns (is_allowed, error_message). Uses cache for fast lookup.

        Timer-only strict mode: locked while strict_until is in the future.
        Once expired (or if strict is on with no end time, a legacy/invalid
        state) strict mode is cleared and the action is allowed.
        """
        cache = db.get_cached_rules(profile_id)
        profile = cache.get('profile', {})
        if not profile.get('is_strict_mode'):
            return True, "OK"
        until = profile.get('strict_until')
        now = time.time()
        if until and now < until:
            rem = max(1, int(until - now))
            return False, f"Strict Mode is locked until timer expires ({rem} seconds remaining)."
        db._check_strict_expiration(profile_id)
        return True, "OK"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)
        profile_id = params.get('profile_id', ['a1b2c3'])[0]

        # 0. Healthcheck (Unauthenticated)
        if path in ("/health", "/api/health"):
            return self._send_json({
                "status": "healthy",
                "service": "FocusDNS Hardened Backend",
                "doh_rfc8484": True,
                "timestamp": time.time()
            })

        # 0b. Public/Client IP Echo Discovery (Unauthenticated)
        if path in ("/api/ip", "/api/setup/my-ip"):
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            return self._send_json({
                "ip": client_ip,
                "success": True,
                "timestamp": time.time()
            })

        # RFC 8484 DoH GET: /dns-query?dns=<base64url> or /dns-query/<profile_id>?dns=...
        if (path == "/dns-query" or path.startswith("/dns-query/")) and "dns" in params:
            doh_profile = profile_id
            if path.startswith("/dns-query/") and len(path) > len("/dns-query/"):
                doh_profile = path[len("/dns-query/"):].strip('/')
            if not self._verify_auth():
                return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)
            return self._handle_doh_query(params["dns"][0], is_base64=True, profile_id=doh_profile)

        # Standard Prometheus Metrics Exposition Endpoint (/metrics)
        if path == "/metrics":
            from .engine import get_prometheus_exporter
            metrics_payload = get_prometheus_exporter().export_metrics_text().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(metrics_payload)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(metrics_payload)
            return

        # Local bootstrap endpoint: only accessible from loopback without hostile Origin
        if path == "/api/auth/token":
            origin = self.headers.get("Origin", "")
            if origin and not (origin.startswith("http://localhost:") or origin.startswith("http://127.0.0.1:") or origin in ("http://localhost", "http://127.0.0.1")):
                return self._send_error("Forbidden: Hostile cross-origin token request", 403)
            if self.client_address[0] not in ("127.0.0.1", "::1", "localhost"):
                return self._send_error("Forbidden: Local access only", 403)
            return self._send_json({"token": db.get_or_create_api_token(), "success": True})

        # Admin Portal UI (Single-file Zero-Bloat Delivery)
        if path in ("/admin", "/admin/"):
            admin_html_path = os.path.join(os.path.dirname(__file__), "admin.html")
            if not os.path.exists(admin_html_path):
                return self._send_error("Admin portal UI file not found", 404)
            with open(admin_html_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(content)
            return

        # Admin Auth Status Check
        if path == "/api/admin/auth/check":
            return self._send_json({"authenticated": self._verify_admin_auth(), "success": True})

        # Protected Administrative GET Routes
        if path.startswith("/api/admin/"):
            if not self._verify_admin_auth():
                return self._send_error("Unauthorized: Admin credentials or master key required", 401)

            if path == "/api/admin/metrics":
                return self._send_json(resolver.get_server_metrics())

            if path == "/api/admin/feeds":
                return self._send_json({
                    "feeds": db.get_threat_feeds(),
                    "total_signatures": db.get_total_threat_signatures(),
                    "success": True
                })

            if path == "/api/admin/upstream":
                return self._send_json({
                    "primary": resolver._upstream_primary,
                    "secondary": resolver._upstream_secondary,
                    "ecs_strip": resolver._ecs_strip,
                    "success": True
                })

            if path == "/api/admin/global-rules":
                return self._send_json({"rules": db.get_global_rules('all'), "success": True})

            if path == "/api/admin/profiles":
                return self._send_json({"profiles": db.get_all_profiles_admin(), "success": True})

            if path == "/api/admin/maintenance":
                return self._send_json({"stats": db.get_db_stats(), "success": True})

            if path == "/api/admin/backup":
                if not os.path.exists(db.DB_PATH):
                    return self._send_error("Database file not found", 404)
                with open(db.DB_PATH, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", 'attachment; filename="focus_dns_backup.db"')
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

            if path == "/api/admin/stream":
                anonymize = params.get('anonymize', ['false'])[0].lower() == 'true'
                return self._handle_admin_sse_stream(anonymize=anonymize)

            return self._send_error(f"Endpoint GET {path} not found", 404)

        # Apple iOS / macOS .mobileconfig Profile Download (NextDNS Parity)
        if path.endswith("/apple.mobileconfig") or path == "/api/profile/apple.mobileconfig":
            req_profile_id = profile_id
            if path.startswith("/api/profile/") and "/apple.mobileconfig" in path:
                parts = path.split("/")
                if len(parts) >= 4 and parts[3] != "apple.mobileconfig":
                    req_profile_id = parts[3]
            p = db.get_profile(req_profile_id)
            if not p:
                return self._send_error(f"Profile '{req_profile_id}' not found", 404)
            return self._handle_apple_mobileconfig(req_profile_id, p['name'])

        # All other GET endpoints require API token authentication
        if not self._verify_auth():
            return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)

        # 1. Page 1: Home Dashboard & Profile
        if path == "/api/profile":
            p = db.get_profile(profile_id)
            if not p:
                return self._send_error("Profile not found", 404)
            return self._send_json({"profile": p, "success": True})

        if path == "/api/profiles":
            profiles = db.get_all_profiles_admin()
            return self._send_json({"profiles": profiles, "success": True})

        if path == "/api/analytics/summary":
            analytics = db.get_analytics(profile_id, '7d')
            return self._send_json(analytics)

        # 2. Page 2: Setup Tab
        if path == "/api/setup":
            p = db.get_profile(profile_id)
            if not p:
                return self._send_error("Profile not found", 404)
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            linked_ip = p.get('linked_ip', 'No IP linked')
            host_hdr = self.headers.get("Host", "127.0.0.1:8080")
            proto = self.headers.get("X-Forwarded-Proto", "https" if ":443" in host_hdr or ("." in host_hdr and not host_hdr.startswith("127.") and not host_hdr.startswith("10.") and not host_hdr.startswith("192.168.")) else "http")
            doh_endpoint = f"{proto}://{host_hdr}/dns-query?profile_id={profile_id}"
            apple_url = f"{proto}://{host_hdr}/api/profile/{profile_id}/apple.mobileconfig"
            return self._send_json({
                "profile_id": profile_id,
                "name": p['name'],
                "linked_ip": linked_ip,
                "client_ip": client_ip,
                "is_matched": (linked_ip == client_ip and linked_ip != 'No IP linked'),
                "ipv4_endpoints": ['45.90.28.140', '45.90.30.140'],
                "ipv6_endpoints": [f'2a07:a8c0::{profile_id}', f'2a07:a8c1::{profile_id}'],
                "doh_endpoint": doh_endpoint,
                "dot_endpoint": f"{profile_id}.dns.local",
                "apple_mobileconfig_url": apple_url,
                "success": True
            })

        # 3. Page 3: Security Tab
        if path == "/api/security":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            sec = db.get_security_settings(profile_id)
            return self._send_json({"security": sec, "success": True})

        # 4. Page 4: Privacy Tab
        if path == "/api/privacy":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            priv = db.get_privacy_settings(profile_id)
            return self._send_json({"privacy": priv, "success": True})

        # 5. Page 5: Deep Focus Tab
        if path == "/api/deep-focus":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            items = db.get_deep_focus_items(profile_id)
            for app in items.get('apps', []):
                app_id = app.get('id') or app.get('name', '').lower()
                app['packages'] = sorted(list(resolver.APP_PACKAGES.get(app_id, [])))
            return self._send_json(items)

        # Android package mapping for Accessibility App Blocker
        if path == "/api/app-packages":
            return self._send_json({
                "packages": {k: sorted(list(v)) for k, v in resolver.APP_PACKAGES.items()},
                "success": True
            })

        # 6. Page 6: Denylist Tab
        if path == "/api/denylist":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            rules = db.get_custom_rules(profile_id, 'deny')
            return self._send_json({"denylist": rules, "count": len(rules)})

        # 7. Page 7: Allowlist Tab
        if path == "/api/allowlist":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            rules = db.get_custom_rules(profile_id, 'allow')
            return self._send_json({"allowlist": rules, "count": len(rules)})

        # 8. Page 8: Analytics Tab
        if path == "/api/analytics":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            period = params.get('period', ['7d'])[0]
            if period not in ('24h', '7d', '30d'):
                period = '7d'
            data = db.get_analytics(profile_id, period)
            return self._send_json(data)

        # 9. Page 9: Query Logs Tab
        if path == "/api/logs":
            if not db.get_profile(profile_id):
                return self._send_error("Profile not found", 404)
            search_query = params.get('q', [''])[0]
            try:
                limit = min(max(int(params.get('limit', [50])[0]), 1), 500)
            except ValueError:
                limit = 50
            logs = db.get_query_logs(profile_id, search_query, limit)
            return self._send_json({"logs": logs, "count": len(logs)})

        # 9b. Live SSE Stream of Logs
        if path == "/api/logs/stream":
            return self._handle_sse_stream()

        # 10. Page 10: Settings Tab
        if path == "/api/settings":
            p = db.get_profile(profile_id)
            if not p:
                return self._send_error("Profile not found", 404)
            w3 = db.get_web3_settings(profile_id)
            return self._send_json({
                "profile_name": p['name'],
                "log_retention": p['log_retention'],
                "is_strict_mode": bool(p['is_strict_mode']),
                "strict_until": p.get('strict_until'),
                "remaining_seconds": p.get('remaining_seconds', 0),
                "web3": w3
            })

        # 11. MDM & Anti-Bypass Device Administration Endpoints
        if path in ("/api/v1/mdm/devices", "/api/mdm/devices"):
            fm = get_fleet_manager()
            devices = [d.to_dict() for d in fm.list_devices()]
            return self._send_json({"devices": devices, "total": len(devices)})

        if path in ("/api/v1/mdm/telemetry", "/api/mdm/telemetry"):
            fm = get_fleet_manager()
            return self._send_json(fm.get_fleet_telemetry())

        if path in ("/api/v1/mdm/policy", "/api/mdm/policy"):
            fm = get_fleet_manager()
            pid = params.get("profile_id", ["default"])[0]
            pol = fm.get_policy(pid)
            if not pol:
                return self._send_error("MDM Policy profile not found", 404)
            return self._send_json(pol.to_dict())

        if path in ("/api/v1/mdm/check-uninstall", "/api/mdm/check-uninstall"):
            fm = get_fleet_manager()
            dev_id = params.get("device_id", [""])[0]
            if not dev_id:
                return self._send_error("device_id query parameter required", 400)
            can_uninstall, reason = fm.evaluate_uninstall_permission(dev_id)
            return self._send_json({
                "device_id": dev_id,
                "can_uninstall": can_uninstall,
                "reason": reason,
                "timestamp": time.time(),
            })

        if path in ("/api/v1/mdm/audit", "/api/mdm/audit"):
            fm = get_fleet_manager()
            try:
                limit = min(max(int(params.get("limit", [50])[0]), 1), 500)
            except ValueError:
                limit = 50
            return self._send_json({"audit_log": fm.get_audit_log(limit)})

        if path in ("/api/v1/mdm/attestation/device", "/api/mdm/attestation/device"):
            dev_id = params.get("device_id", [""])[0]
            if not dev_id:
                return self._send_error("device_id parameter required", 400)
            data = _attestation_validator.get_device_attestation(dev_id)
            if not data:
                return self._send_error("Device attestation not found", 404)
            return self._send_json(data)

        if path in ("/api/v1/mdm/private-dns/history", "/api/mdm/private-dns/history"):
            dev_id = params.get("device_id", [None])[0]
            return self._send_json({
                "history": _private_dns_server.get_audit_history(dev_id),
                "summary": _private_dns_server.get_fleet_compliance_summary(),
            })

        if path in ("/api/v1/mdm/telemetry/device-risk", "/api/mdm/telemetry/device-risk"):
            dev_id = params.get("device_id", [""])[0]
            if not dev_id:
                return self._send_error("device_id parameter required", 400)
            return self._send_json(_oem_telemetry.calculate_device_risk_score(dev_id))

        if path in ("/api/v1/mdm/telemetry/fleet-summary", "/api/mdm/telemetry/fleet-summary"):
            return self._send_json(_oem_telemetry.get_fleet_security_summary())

        # Phase 3: Android Enterprise Zero-Touch QR Payload
        if path in ("/api/v1/mdm/dpc/qr-payload", "/api/mdm/dpc/qr-payload"):
            tok_id = params.get("token_id", ["tok_default_enterprise_provisioning"])[0]
            strict = params.get("strict", ["false"])[0].lower() == "true"
            qr_bundle = _dpc_server.generate_zero_touch_qr_payload(tok_id, enforce_strict_uninstall_lock=strict)
            return self._send_json({"token_id": tok_id, "provisioning_bundle": qr_bundle, "success": True})

        # Phase 3: LockTask Kiosk Profiles
        if path in ("/api/v1/mdm/kiosk/profiles", "/api/mdm/kiosk/profiles"):
            return self._send_json({
                "profiles": _kiosk_manager.list_profiles(),
                "summary": _kiosk_manager.get_fleet_kiosk_summary(),
            })

        # Phase 3: LockTask Kiosk Directive Evaluation
        if path in ("/api/v1/mdm/kiosk/evaluate", "/api/mdm/kiosk/evaluate"):
            dev_id = params.get("device_id", [""])[0]
            focus = params.get("focus_active", ["false"])[0].lower() == "true"
            if not dev_id:
                return self._send_error("device_id required", 400)
            return self._send_json(_kiosk_manager.evaluate_kiosk_directive(dev_id, focus))

        # Phase 3: Managed Configurations (AppConfig)
        if path in ("/api/v1/mdm/appconfig", "/api/mdm/appconfig"):
            tenant = params.get("tenant_id", ["default_enterprise"])[0]
            bundle = _appconfig_distributor.get_appconfig_bundle(tenant)
            intune = _appconfig_distributor.generate_intune_sync_payload(tenant)
            return self._send_json({
                "tenant_id": tenant,
                "appconfig": bundle,
                "intune_payload": intune,
                "success": True,
            })

        self._send_error(f"Endpoint GET {path} not found", 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # RFC 8484 DoH POST: application/dns-message
        content_type = self.headers.get('Content-Type', '')
        if (path == "/dns-query" or path.startswith("/dns-query/")) and "application/dns-message" in content_type:
            try:
                content_len = int(self.headers.get('Content-Length', 0))
            except ValueError:
                return self._send_error("Invalid Content-Length", 400)
            if content_len > 4096:
                return self._send_error("Payload too large (Max 4KB for DoH)", 413)
            raw_dns = self.rfile.read(content_len)
            params = urllib.parse.parse_qs(parsed.query)
            doh_profile = params.get('profile_id', ['a1b2c3'])[0]
            if path.startswith("/dns-query/") and len(path) > len("/dns-query/"):
                doh_profile = path[len("/dns-query/"):].strip('/')
            if not self._verify_auth():
                return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)
            return self._handle_doh_query(raw_dns, is_base64=False, profile_id=doh_profile)

        # Admin Login & Logout Authentication Endpoints
        if path == "/api/admin/auth/login":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            allowed, retry_after = db.check_admin_rate_limit(client_ip)
            if not allowed:
                return self._send_json({
                    "error": f"Too many failed login attempts. IP temporarily locked out for {retry_after} more seconds.",
                    "retry_after": retry_after,
                    "success": False
                }, 429)

            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            master_key = body.get("master_key", "").strip()
            if not db.verify_admin_master_key(master_key):
                db.record_admin_failed_login(client_ip)
                return self._send_error("Invalid Master Admin Key", 401)

            db.clear_admin_failed_logins(client_ip)
            session_token = db.create_admin_session()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Set-Cookie", f"admin_session={session_token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "token": session_token,
                "message": "Authenticated as FocusDNS Operator"
            }).encode('utf-8'))
            return

        if path == "/api/admin/auth/logout":
            cookie_header = self.headers.get("Cookie", "")
            if cookie_header:
                c = SimpleCookie()
                try:
                    c.load(cookie_header)
                    if "admin_session" in c:
                        db.delete_admin_session(c["admin_session"].value.strip())
                except Exception:
                    pass
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Set-Cookie", "admin_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "message": "Logged out"}).encode('utf-8'))
            return

        # Protected Administrative POST Routes
        if path.startswith("/api/admin/"):
            if not self._verify_admin_auth():
                return self._send_error("Unauthorized: Admin credentials or master key required", 401)

            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)

            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)

            if path == "/api/admin/feeds/sync":
                resolver.sync_threat_feeds_background()
                return self._send_json({"success": True, "message": "Threat feed sync initiated in background"})

            if path == "/api/admin/feeds/toggle":
                feed_id = body.get("feed_id", "")
                enabled = bool(body.get("enabled", True))
                if not feed_id:
                    return self._send_error("feed_id is required", 400)
                db.toggle_threat_feed(feed_id, enabled)
                resolver.reload_global_rules()
                return self._send_json({"success": True, "feed_id": feed_id, "enabled": enabled})

            if path == "/api/admin/upstream":
                primary = body.get("primary", "")
                secondary = body.get("secondary", "")
                ecs_strip = body.get("ecs_strip", True)
                resolver.set_upstreams(primary, secondary, ecs_strip)
                return self._send_json({
                    "success": True,
                    "primary": resolver._upstream_primary,
                    "secondary": resolver._upstream_secondary,
                    "ecs_strip": resolver._ecs_strip
                })

            if path == "/api/admin/upstream/benchmark":
                results = resolver.benchmark_upstreams()
                return self._send_json({"results": results, "success": True})

            if path == "/api/admin/emergency-bypass":
                enabled = body.get("enabled")
                if enabled is None:
                    enabled = not resolver._global_emergency_bypass
                resolver.set_emergency_bypass(enabled)
                return self._send_json({
                    "success": True,
                    "emergency_bypass": resolver._global_emergency_bypass,
                    "message": "Global Emergency Safe Bypass toggled"
                })

            if path == "/api/admin/global-rules":
                list_type = body.get("list_type", "allow")
                domain = body.get("domain", "").strip()
                if not domain:
                    return self._send_error("domain is required", 400)
                db.add_global_rule(list_type, domain)
                resolver.reload_global_rules()
                return self._send_json({"success": True, "list_type": list_type, "domain": domain})

            if path == "/api/admin/profiles":
                name = body.get("name", "New Profile").strip()
                pid = db.create_profile(name)
                return self._send_json({"success": True, "profile_id": pid, "name": name})

            if path == "/api/admin/maintenance/prune":
                try:
                    days = int(body.get("days", 30))
                except (ValueError, TypeError):
                    days = 30
                deleted = db.prune_query_logs(days)
                return self._send_json({"success": True, "deleted_logs": deleted, "pruned_days": days})

            if path == "/api/admin/maintenance/vacuum":
                db.vacuum_database()
                return self._send_json({"success": True, "stats": db.get_db_stats()})

            return self._send_error(f"Endpoint POST {path} not found", 404)

        # All other POST endpoints require API token authentication
        if not self._verify_auth():
            return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)

        # Reject simple cross-site requests (Content-Type must be application/json)
        ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
        if ct != 'application/json':
            return self._send_error(f"Unsupported Media Type: Expected application/json, got '{self.headers.get('Content-Type', '')}'", 415)

        body, err = self._read_json_body()
        if err:
            return self._send_error(err, 400)
        profile_id = body.get('profile_id', 'a1b2c3')

        # Profiles
        if path == "/api/profiles":
            name = str(body.get('name', 'New Profile')).strip()
            if not name:
                name = 'New Profile'
            pid = db.create_profile(name)
            return self._send_json({"success": True, "profile_id": pid, "name": name})

        # Toggle Protection
        if path == "/api/profile/toggle-protection":
            is_on = body.get('is_on')
            if not isinstance(is_on, bool):
                return self._send_error("is_on must be a boolean", 400)
            success, msg = db.update_protection(profile_id, is_on)
            if not success:
                return self._send_error(msg, 403)
            return self._send_json({"success": True, "is_protection_on": is_on})

        # Strict Mode
        if path == "/api/profile/strict-mode":
            is_strict = body.get('is_strict')
            if not isinstance(is_strict, bool):
                return self._send_error("is_strict must be a boolean", 400)
            duration_minutes = body.get('duration_minutes', body.get('durationMinutes'))
            if duration_minutes is not None:
                try:
                    duration_minutes = int(duration_minutes)
                except ValueError:
                    duration_minutes = None
            success, msg = db.set_strict_mode(profile_id, is_strict, duration_minutes=duration_minutes)
            if not success:
                return self._send_error(msg, 403)
            p = db.get_profile(profile_id)
            return self._send_json({
                "success": True,
                "is_strict_mode": is_strict,
                "strict_until": p.get('strict_until') if p else None,
                "remaining_seconds": p.get('remaining_seconds', 0) if p else 0
            })

        # Setup - Link IP
        if path == "/api/setup/link-ip":
            ip = body.get('ip')
            if not ip or not str(ip).strip():
                ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            else:
                ip = str(ip).strip()
            try:
                db.update_linked_ip(profile_id, ip)
            except ValueError as e:
                return self._send_error(str(e), 400)
            return self._send_json({"success": True, "linked_ip": ip, "profile_id": profile_id})

        # Deep Focus - Add Item
        if path == "/api/deep-focus":
            item_type = body.get('type', 'website')
            item_id = body.get('id', body.get('name', '').lower())
            name = body.get('name', '').strip()
            if not name:
                return self._send_error("Name required", 400)
            db.add_deep_focus_item(profile_id, item_type, item_id, name,
                                   body.get('icon', ''), body.get('color', '#007AFF'),
                                   body.get('description', ''))
            return self._send_json({"success": True, "added": name})

        # Denylist - Add Domain
        if path == "/api/denylist":
            domain = body.get('domain', '').strip()
            if not domain:
                return self._send_error("Domain required", 400)
            try:
                db.add_custom_rule(profile_id, 'deny', domain)
            except ValueError as e:
                return self._send_error(str(e), 400)
            return self._send_json({"success": True, "domain": domain})

        # Allowlist - Add Domain (Must check Strict Mode barrier if active)
        if path == "/api/allowlist":
            allowed, msg = self._check_strict_mode_barrier(profile_id)
            if not allowed:
                return self._send_error(f"Strict Mode active: Cannot modify allowlist while Strict Mode timer is active ({msg})", 403)
            domain = body.get('domain', '').strip()
            if not domain:
                return self._send_error("Domain required", 400)
            try:
                db.add_custom_rule(profile_id, 'allow', domain)
            except ValueError as e:
                return self._send_error(str(e), 400)
            return self._send_json({"success": True, "domain": domain})

        # Real-Time Query Simulator
        if path in ("/api/query/resolve", "/dns-query"):
            domain = body.get('domain', body.get('name', ''))
            qtype = body.get('type', 'A')
            if not domain:
                return self._send_error("Domain parameter required", 400)
            result = resolver.resolve_domain(domain, profile_id, qtype, self.client_address[0])
            return self._send_json(result)

        # MDM Device Enrollment
        if path in ("/api/v1/mdm/enroll", "/api/mdm/enroll"):
            dev_id = body.get("device_id", "").strip()
            if not dev_id:
                return self._send_error("device_id required", 400)
            dev_name = body.get("device_name", f"Device-{dev_id[:6]}").strip()
            platform = body.get("platform", "Android").strip()
            os_version = body.get("os_version", "14").strip()
            pid = body.get("profile_id", "default").strip()
            device_owner = bool(body.get("device_owner", False))
            admin_active = bool(body.get("admin_active", False))
            fm = get_fleet_manager()
            rec = fm.enroll_device(
                device_id=dev_id,
                device_name=dev_name,
                platform=platform,
                os_version=os_version,
                profile_id=pid,
                device_owner=device_owner,
                admin_active=admin_active,
            )
            return self._send_json({"enrolled": True, "device": rec.to_dict()})

        # MDM Device Telemetry Ingestion
        if path in ("/api/v1/mdm/telemetry", "/api/mdm/telemetry"):
            dev_id = body.get("device_id", "").strip()
            if not dev_id:
                return self._send_error("device_id required", 400)
            telemetry = body.get("telemetry", body)
            fm = get_fleet_manager()
            fm.process_telemetry(dev_id, telemetry)
            dev = fm.get_device(dev_id)
            return self._send_json({
                "success": True,
                "device_id": dev_id,
                "can_uninstall": dev.can_uninstall if dev else True,
            })

        # MDM Policy Update
        if path in ("/api/v1/mdm/policy", "/api/mdm/policy"):
            pid = body.get("profile_id", "default").strip()
            name = body.get("name", "Standard Protection Policy").strip()
            raw_mode = body.get("lock_mode", PolicyLockMode.CONDITIONAL_ON_PROTECTION.value)
            try:
                lock_mode = PolicyLockMode(raw_mode)
            except ValueError:
                lock_mode = PolicyLockMode.CONDITIONAL_ON_PROTECTION
            raw_st_mode = body.get("split_tunnel_mode", SplitTunnelPolicyMode.DISALLOW_LIST.value)
            try:
                st_mode = SplitTunnelPolicyMode(raw_st_mode)
            except ValueError:
                st_mode = SplitTunnelPolicyMode.DISALLOW_LIST
            exempt_packages = body.get("exempt_packages", [])
            disallow_safe_boot = bool(body.get("disallow_safe_boot", True))
            disallow_vpn_config = bool(body.get("disallow_vpn_config", True))
            camera_disabled = bool(body.get("camera_disabled", False))
            fm = get_fleet_manager()
            pol = MdmPolicyProfile(
                profile_id=pid,
                name=name,
                lock_mode=lock_mode,
                split_tunnel_mode=st_mode,
                exempt_packages=exempt_packages,
                disallow_safe_boot=disallow_safe_boot,
                disallow_vpn_config=disallow_vpn_config,
                camera_disabled=camera_disabled,
            )
            fm.set_policy(pol)
            return self._send_json({"success": True, "policy": pol.to_dict()})

        # MDM Attestation Nonce Request
        if path in ("/api/v1/mdm/attestation/nonce", "/api/mdm/attestation/nonce"):
            device_id = body.get("device_id", "").strip()
            purpose = body.get("purpose", "attestation").strip()
            if not device_id:
                return self._send_error("device_id required in request body", 400)
            nonce = _attestation_validator.generate_nonce(device_id, purpose=purpose)
            return self._send_json({"device_id": device_id, "nonce": nonce, "ttl_seconds": 300, "success": True})

        # MDM Hardware Attestation Signature Verification
        if path in ("/api/v1/mdm/attestation/verify", "/api/mdm/attestation/verify"):
            device_id = body.get("device_id", "").strip()
            payload = body.get("payload", "").strip()
            nonce = body.get("nonce", "").strip()
            sig = body.get("signature_base64", "").strip()
            ts = int(body.get("timestamp_ms", 0))
            if not (device_id and payload and nonce and sig and ts):
                return self._send_error("device_id, payload, nonce, signature_base64, and timestamp_ms required", 400)
            res = _attestation_validator.verify_assertion(device_id, payload, nonce, sig, ts)
            return self._send_json(res.to_dict(), status=200 if res.is_valid else 403)

        # MDM Private DNS Evaluation
        if path in ("/api/v1/mdm/private-dns/evaluate", "/api/mdm/private-dns/evaluate"):
            device_id = body.get("device_id", "").strip()
            mode = body.get("mode", "off").strip()
            specifier = body.get("hostname_specifier", "").strip()
            if not device_id:
                return self._send_error("device_id required", 400)
            eval_res = _private_dns_server.evaluate_device_dns(device_id, mode, specifier)
            return self._send_json(eval_res)

        # MDM Multi-OEM Telemetry Event Ingestion
        if path in ("/api/v1/mdm/telemetry/oem-event", "/api/mdm/telemetry/oem-event"):
            ev_id = body.get("event_id", f"ev_{int(time.time()*1000)}")
            device_id = body.get("device_id", "").strip()
            oem = body.get("oem_vendor", "UNKNOWN").strip()
            ev_type = body.get("event_type", "UNKNOWN").strip()
            pkg = body.get("package_name", "").strip()
            wtitle = body.get("window_title", "").strip()
            details = body.get("details", {})
            if not device_id:
                return self._send_error("device_id required", 400)
            recorded = _oem_telemetry.record_event(
                event_id=ev_id,
                device_id=device_id,
                oem_vendor=oem,
                event_type=ev_type,
                package_name=pkg,
                window_title=wtitle,
                details=details,
            )
            return self._send_json({"success": True, "event": recorded})

        # DPC Enrollment Token Generation
        if path in ("/api/v1/mdm/dpc/token", "/api/mdm/dpc/token"):
            tenant = body.get("tenant_id", "default_enterprise").strip()
            name = body.get("name", "Provisioning Token").strip()
            max_uses = int(body.get("max_uses", 1))
            ttl = int(body.get("ttl_seconds", 86400))
            pol_id = body.get("policy_id", "default").strip()
            hw_id = body.get("bound_hardware_id")
            token = _dpc_server.create_enrollment_token(
                tenant_id=tenant,
                name=name,
                max_uses=max_uses,
                ttl_seconds=ttl,
                policy_id=pol_id,
                bound_hardware_id=hw_id,
            )
            return self._send_json({"success": True, "token": token.to_dict()})

        # DPC Device Enrollment
        if path in ("/api/v1/mdm/dpc/enroll", "/api/mdm/dpc/enroll"):
            device_id = body.get("device_id", "").strip()
            token_id = body.get("token_id", "").strip()
            hardware_id = body.get("hardware_id")
            device_model = body.get("device_model", "Android Device").strip()
            os_version = body.get("os_version", "Android 14").strip()
            if not device_id or not token_id:
                return self._send_error("device_id and token_id are required", 400)
            res = _dpc_server.process_enrollment(
                device_id=device_id,
                token_id=token_id,
                hardware_id=hardware_id,
                device_model=device_model,
                os_version=os_version,
            )
            return self._send_json(res, status=200 if res.get("success") else 400)

        # Kiosk Profile Management
        if path in ("/api/v1/mdm/kiosk/profile", "/api/mdm/kiosk/profile"):
            prof_id = body.get("profile_id", f"prof_{int(time.time()*1000)}").strip()
            p_name = body.get("name", "Focus Kiosk").strip()
            primary = body.get("primary_app", "com.focusdns.app").strip()
            allowed = body.get("allowed_packages")
            k_prof = KioskProfile(
                profile_id=prof_id,
                name=p_name,
                primary_app=primary,
                allowed_packages=allowed,
                allow_system_info=body.get("allow_system_info", True),
                allow_keyguard=body.get("allow_keyguard", True),
                allow_notifications=body.get("allow_notifications", False),
                enforce_on_focus=body.get("enforce_on_focus", True),
            )
            saved = _kiosk_manager.save_profile(k_prof)
            return self._send_json({"success": True, "profile": saved.to_dict()})

        # Managed Configurations AppConfig
        if path in ("/api/v1/mdm/appconfig", "/api/mdm/appconfig"):
            tenant = body.get("tenant_id", "default_enterprise").strip()
            name = body.get("name", "Enterprise Profile").strip()
            s_url = body.get("server_url", "https://dns.focusguard.internal").strip()
            e_tok = body.get("enrollment_token", "").strip()
            strict = body.get("enforce_strict_uninstall_lock", False)
            wl_pkgs = body.get("whitelisted_packages", [])
            kiosk_en = body.get("kiosk_enabled", False)
            dot_h = body.get("approved_dot_host", "dns.focusguard.internal").strip()
            app_cfg = TenantAppConfig(
                tenant_id=tenant,
                name=name,
                server_url=s_url,
                enrollment_token=e_tok,
                enforce_strict_uninstall_lock=strict,
                whitelisted_packages=wl_pkgs,
                kiosk_enabled=kiosk_en,
                approved_dot_host=dot_h,
            )
            saved_cfg = _appconfig_distributor.set_tenant_config(app_cfg)
            return self._send_json({"success": True, "appconfig": saved_cfg.to_dict()})

        self._send_error(f"Endpoint POST {path} not found", 404)

    def do_PATCH(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # All PATCH endpoints require API token authentication
        if not self._verify_auth():
            return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)

        # Reject simple cross-site requests (Content-Type must be application/json)
        ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
        if ct != 'application/json':
            return self._send_error(f"Unsupported Media Type: Expected application/json, got '{self.headers.get('Content-Type', '')}'", 415)

        body, err = self._read_json_body()
        if err:
            return self._send_error(err, 400)
        profile_id = body.get('profile_id', 'a1b2c3')

        # Security setting patch
        if path == "/api/security":
            feature = body.get('feature')
            value = body.get('value')
            if feature is None or value is None:
                return self._send_error("Missing feature or value", 400)
            if not isinstance(value, bool):
                return self._send_error("Value must be a strict boolean (true/false)", 400)
            if value is False:
                allowed, msg = self._check_strict_mode_barrier(profile_id)
                if not allowed:
                    return self._send_error(f"Strict Mode active: Cannot disable security features while Strict Mode timer is active ({msg})", 403)
            try:
                db.update_security_setting(profile_id, feature, value)
            except ValueError as e:
                return self._send_error(str(e), 400)
            return self._send_json({"success": True, "feature": feature, "value": value})

        # Privacy setting patch
        if path == "/api/privacy":
            feature = body.get('feature')
            value = body.get('value')
            if feature is None or value is None:
                return self._send_error("Missing feature or value", 400)
            if not isinstance(value, bool):
                return self._send_error("Value must be a strict boolean (true/false)", 400)
            if value is False:
                allowed, msg = self._check_strict_mode_barrier(profile_id)
                if not allowed:
                    return self._send_error(f"Strict Mode active: Cannot disable privacy features while Strict Mode timer is active ({msg})", 403)
            try:
                db.update_privacy_setting(profile_id, feature, value)
            except ValueError as e:
                return self._send_error(str(e), 400)
            return self._send_json({"success": True, "feature": feature, "value": value})

        # Settings tab patch
        if path == "/api/settings":
            if 'profile_name' in body:
                db.update_profile_name(profile_id, str(body['profile_name']).strip())
            if 'log_retention' in body:
                success, msg = db.update_log_retention(profile_id, str(body['log_retention']))
                if not success:
                    return self._send_error(msg, 403)
            if 'web3_feature' in body and 'web3_value' in body:
                w3_val = body['web3_value']
                if not isinstance(w3_val, bool):
                    return self._send_error("web3_value must be a strict boolean", 400)
                if w3_val is False:
                    allowed, msg = self._check_strict_mode_barrier(profile_id)
                    if not allowed:
                        return self._send_error(f"Strict Mode active: Cannot disable Web3 features while Strict Mode timer is active ({msg})", 403)
                try:
                    db.update_web3_setting(profile_id, body['web3_feature'], w3_val)
                except ValueError as e:
                    return self._send_error(str(e), 400)
            return self._send_json({"success": True})

        self._send_error(f"Endpoint PATCH {path} not found", 404)

    def do_DELETE(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)
        profile_id = params.get('profile_id', ['a1b2c3'])[0]

        # Protected Administrative DELETE Routes
        if path.startswith("/api/admin/"):
            if not self._verify_admin_auth():
                return self._send_error("Unauthorized: Admin credentials or master key required", 401)

            if path.startswith("/api/admin/global-rules/"):
                parts = path[len("/api/admin/global-rules/"):].split('/', 1)
                if len(parts) != 2:
                    return self._send_error("Invalid route format: expected /api/admin/global-rules/{list_type}/{domain}", 400)
                list_type = parts[0]
                domain = urllib.parse.unquote(parts[1])
                db.remove_global_rule(list_type, domain)
                resolver.reload_global_rules()
                return self._send_json({"success": True, "removed": domain, "list_type": list_type})

            if path.startswith("/api/admin/profiles/"):
                pid = path[len("/api/admin/profiles/"):].strip('/')
                if not pid:
                    return self._send_error("profile_id is required", 400)
                db.revoke_profile(pid)
                return self._send_json({"success": True, "revoked": pid})

            return self._send_error(f"Endpoint DELETE {path} not found", 404)

        # All other DELETE endpoints require API token authentication
        if not self._verify_auth():
            return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)

        # Deep Focus delete: /api/deep-focus/{id}
        if path.startswith("/api/deep-focus/"):
            allowed, msg = self._check_strict_mode_barrier(profile_id)
            if not allowed:
                return self._send_error(f"Strict Mode active: Cannot remove blocked items while Strict Mode timer is active ({msg})", 403)
            item_id = urllib.parse.unquote(path[len("/api/deep-focus/"):])
            db.remove_deep_focus_item(profile_id, item_id)
            return self._send_json({"success": True, "removed": item_id})

        # Denylist delete: /api/denylist/{domain}
        if path.startswith("/api/denylist/"):
            allowed, msg = self._check_strict_mode_barrier(profile_id)
            if not allowed:
                return self._send_error(f"Strict Mode active: Cannot remove denylist entries while Strict Mode timer is active ({msg})", 403)
            domain = urllib.parse.unquote(path[len("/api/denylist/"):])
            db.remove_custom_rule(profile_id, 'deny', domain)
            return self._send_json({"success": True, "removed": domain})

        # Allowlist delete: /api/allowlist/{domain}
        if path.startswith("/api/allowlist/"):
            domain = urllib.parse.unquote(path[len("/api/allowlist/"):])
            db.remove_custom_rule(profile_id, 'allow', domain)
            return self._send_json({"success": True, "removed": domain})

        self._send_error(f"Endpoint DELETE {path} not found", 404)

    def _handle_doh_query(self, raw_input, is_base64: bool = False, profile_id: str = 'a1b2c3'):
        """RFC 8484 DNS-over-HTTPS wire-format handler."""
        try:
            if is_base64:
                padded = raw_input + '=' * (-len(raw_input) % 4)
                query_bytes = base64.urlsafe_b64decode(padded)
            else:
                query_bytes = raw_input

            if len(query_bytes) > 4096:
                return self._send_error("DNS message payload too large (Max 4KB)", 413)

            reply_bytes, meta = resolver.resolve_wire_packet(query_bytes, profile_id, self.client_address[0])

            # Calculate min TTL for Cache-Control
            ttl = 60
            try:
                rec = DNSRecord.parse(reply_bytes)
                ttls = [rr.ttl for rr in rec.rr if rr.ttl > 0]
                if ttls:
                    ttl = max(5, min(ttls))
            except Exception:
                pass

            self.send_response(200)
            self.send_header("Content-Type", "application/dns-message")
            self.send_header("Cache-Control", f"max-age={ttl}")
            origin = self.headers.get("Origin", "")
            if origin:
                self.send_header("Access-Control-Allow-Origin", origin)
            else:
                self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(reply_bytes)
        except Exception as e:
            self._send_error(f"DoH processing failed: {e}", 400)

    def _handle_sse_stream(self):
        """Server-Sent Events endpoint for real-time query log streaming."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        event_queue = []
        cond = threading.Condition()

        def on_event(ev):
            with cond:
                event_queue.append(ev)
                cond.notify()

        resolver.subscribe_logs(on_event)
        try:
            while True:
                with cond:
                    while not event_queue:
                        cond.wait(timeout=15.0)
                        if not event_queue:
                            self.wfile.write(b": keep-alive\n\n")
                            self.wfile.flush()
                    batch = list(event_queue)
                    event_queue.clear()

                for ev in batch:
                    msg = f"data: {json.dumps(ev)}\n\n"
                    self.wfile.write(msg.encode('utf-8'))
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            resolver.unsubscribe_logs(on_event)

    def _handle_admin_sse_stream(self, anonymize: bool = False):
        """Server-Sent Events endpoint for real-time live telescope query log streaming with optional IP anonymization."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        event_queue = []
        cond = threading.Condition()

        def on_event(ev):
            with cond:
                copied = dict(ev)
                if anonymize and 'client_ip' in copied:
                    ip = copied['client_ip']
                    if '.' in ip:
                        parts = ip.split('.')
                        copied['client_ip'] = f"{parts[0]}.{parts[1]}.{parts[2]}.***" if len(parts) == 4 else ip
                    elif ':' in ip:
                        copied['client_ip'] = ip.split(':')[0] + '::***'
                event_queue.append(copied)
                cond.notify()

        resolver.subscribe_logs(on_event)
        try:
            while True:
                with cond:
                    while not event_queue:
                        cond.wait(timeout=15.0)
                        if not event_queue:
                            self.wfile.write(b": keep-alive\n\n")
                            self.wfile.flush()
                    batch = list(event_queue)
                    event_queue.clear()

                for ev in batch:
                    msg = f"data: {json.dumps(ev)}\n\n"
                    self.wfile.write(msg.encode('utf-8'))
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            resolver.unsubscribe_logs(on_event)

    def _handle_apple_mobileconfig(self, profile_id: str, profile_name: str):
        """Generates native Apple Encrypted DNS .mobileconfig profile for zero-app iOS/macOS enrollment."""
        host_hdr = self.headers.get("Host", "127.0.0.1:8080")
        fwd_proto = self.headers.get("X-Forwarded-Proto", "")
        if fwd_proto:
            proto = fwd_proto
        elif ":443" in host_hdr or ("." in host_hdr and not host_hdr.startswith("127.") and not host_hdr.startswith("10.") and not host_hdr.startswith("192.168.")):
            proto = "https"
        else:
            proto = "http"

        doh_url = f"{proto}://{host_hdr}/dns-query?profile_id={profile_id}"
        uuid_dns = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"focusdns-{profile_id}-dns"))
        uuid_top = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"focusdns-{profile_id}-top"))

        xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>DNSSettings</key>
            <dict>
                <key>DNSProtocol</key>
                <string>HTTPS</string>
                <key>ServerURL</key>
                <string>{doh_url}</string>
            </dict>
            <key>PayloadDescription</key>
            <string>Configures Apple device to use FocusDNS Encrypted DNS over HTTPS.</string>
            <key>PayloadDisplayName</key>
            <string>FocusDNS DoH ({profile_name})</string>
            <key>PayloadIdentifier</key>
            <string>com.focusdns.profile.{profile_id}.dns</string>
            <key>PayloadType</key>
            <string>com.apple.dnsSettings.managed</string>
            <key>PayloadUUID</key>
            <string>{uuid_dns}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>FocusDNS Encrypted DNS profile for tamper-proof digital focus and threat protection.</string>
    <key>PayloadDisplayName</key>
    <string>FocusDNS ({profile_name})</string>
    <key>PayloadIdentifier</key>
    <string>com.focusdns.profile.{profile_id}</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>{uuid_top}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>"""
        content = xml.encode('utf-8')
        self.send_response(200)
        self.send_header("Content-Type", "application/x-apple-aspen-config; charset=utf-8")
        self.send_header("Content-Disposition", f'attachment; filename="focusdns-{profile_id}.mobileconfig"')
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(content)

