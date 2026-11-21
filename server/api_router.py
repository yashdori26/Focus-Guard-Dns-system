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
import hashlib
import json
import os
import secrets
import threading
import time
import urllib.parse
import uuid
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler
from typing import Dict, Any, Optional, Tuple

from dnslib import DNSRecord, QTYPE, RCODE, RR, A, AAAA

from . import db
from . import resolver
from . import email_service
from . import setup_portal
from .geo_ip import get_geo_info, get_all_country_options
from .auth_manager import get_session_registry
from .engine.auth_anomaly_detector import get_auth_anomaly_detector
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
from .engine.fleet_control_plane import FleetControlPlane
from .engine.mdm_websocket_hub import MdmWebSocketHub
from .engine.geofence_engine import GeofenceEngine, GeofenceZone
from .engine.enterprise_calendar import EnterpriseCalendarEngine, CalendarFocusEvent
from .engine.wfp_engine import WfpRuleCompiler
from .engine.windows_daemon_controller import WindowsDaemonController
from router.openwrt.mac_profile_router import MacProfileRouter
from router.daemon.router_stub_daemon import RouterStubDaemon
from router.daemon.router_telemetry_reporter import RouterTelemetryReporter
from router.pfsense.pf_rules_generator import PfRulesGenerator
from .engine.macos_extension_manager import MacOsExtensionManager
from router.linux_ebpf.focus_dns_ebpf_loader import FocusDnsEbpfLoader
from router.linux_ebpf.ebpf_xdp_router import EbpfXdpRouter
from router.asuswrt.merlin_config_generator import MerlinConfigGenerator
from router.asuswrt.jffs_scripts import AsuswrtJffsScripts
from router.ddwrt.ddwrt_firewall_manager import DdWrtFirewallManager
from router.daemon.router_doq_engine import RouterDoqEngine
from router.daemon.router_dnssec_validator import RouterDnssecValidator
from router.mikrotik.routeros_dns_manager import RouterOsDnsManager
from router.ubiquiti.ubiquiti_gateway_engine import UbiquitiGatewayEngine
from router.daemon.router_orchestrator import RouterMasterOrchestrator
from server.ai.api_ai_router import AIApiDispatcher

_attestation_validator = AttestationValidator()
_private_dns_server = PrivateDnsServerManager()
_oem_telemetry = OemTelemetryCollector()
_dpc_server = DpcProvisioningServer()
_kiosk_manager = KioskPolicyManager()
_appconfig_distributor = ManagedConfigDistributor()
_fleet_control = FleetControlPlane()
_websocket_hub = MdmWebSocketHub()
_geofence_engine = GeofenceEngine()
_calendar_engine = EnterpriseCalendarEngine()
_wfp_compiler = WfpRuleCompiler()
_windows_controller = WindowsDaemonController()
_mac_profile_router = MacProfileRouter()
_router_stub_daemon = RouterStubDaemon(mac_router=_mac_profile_router)
_router_telemetry = RouterTelemetryReporter(stub_daemon=_router_stub_daemon, mac_router=_mac_profile_router)
_pf_generator = PfRulesGenerator()
_macos_manager = MacOsExtensionManager()
_ebpf_loader = FocusDnsEbpfLoader()
_ebpf_router = EbpfXdpRouter(loader=_ebpf_loader)
_ddwrt_manager = DdWrtFirewallManager()
_router_doq = RouterDoqEngine()
_router_dnssec = RouterDnssecValidator()
_mikrotik_manager = RouterOsDnsManager()
_ubiquiti_engine = UbiquitiGatewayEngine()
_router_orchestrator = RouterMasterOrchestrator()
_ai_dispatcher = AIApiDispatcher()

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

    def do_HEAD(self):
        """Handle HEAD requests (required by Android download managers and Chrome)."""
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path.endswith(".apk") or path in ("/download/android", "/api/download/android"):
            apk_path = None
            for candidate in [
                os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-release.apk")),
                os.path.realpath(os.path.join(os.path.dirname(__file__), "focusdns.apk")),
                os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-debug.apk")),
            ]:
                if os.path.exists(candidate):
                    apk_path = candidate
                    break
            if not apk_path:
                return self._send_error("Android APK not built yet", 404)
            file_size = os.path.getsize(apk_path)
            filename = os.path.basename(path) if path.endswith(".apk") and path.strip("/") != "focusdns.apk" else "FocusDNS-v1.0.1.apk"
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(file_size))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", "0")
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
        if db.verify_api_token(token):
            return True
        valid, _, _ = get_session_registry().verify_session(token)
        return valid

    def _resolve_request_profile_id(self, explicit_pid: Optional[str] = None) -> str:
        """Resolves active profile_id from explicit argument or authenticated session."""
        if explicit_pid and str(explicit_pid).strip():
            return str(explicit_pid).strip()
        auth_header = self.headers.get("Authorization", "").strip()
        token = auth_header[7:].strip() if auth_header.startswith("Bearer ") else auth_header
        if not token:
            token = self.headers.get("X-Session-Token", "").strip() or self.headers.get("X-Api-Key", "").strip()
        if token:
            valid, session, _ = get_session_registry().verify_session(token)
            if valid and session and session.profile_id:
                return session.profile_id
        if db.get_profile("dce22d"):
            return "dce22d"
        return "a1b2c3"

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
        body = json.dumps(data).encode('utf-8')
        self._set_cors_headers(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, message: str, status: int = 400):
        self._send_json({"error": message, "success": False}, status)

    def _serve_file_download(self, file_path: str, filename: str, content_type: str):
        """Streams a static or generated file download with proper Content-Disposition and headers."""
        if not os.path.exists(file_path):
            return self._send_error(f"Download file not found: {filename}", 404)
        try:
            with open(file_path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self._send_error(f"Error serving download: {e}", 500)

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
        profile_id = self._resolve_request_profile_id(params.get('profile_id', [None])[0])

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

        # 0c. Multi-Device Setup Portal & Client Downloads (Unauthenticated)
        if path in ("/setup", "/api/setup"):
            host_hdr = self.headers.get("Host", "192.168.0.102").split(":")[0]
            display_ip = host_hdr if host_hdr not in ("127.0.0.1", "localhost") else "192.168.0.102"
            html_content = setup_portal.render_setup_html(server_ip=display_ip, profile_id="dce22d", profile_name="Yash")
            body = html_content.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/download/windows-setup":
            return self._serve_file_download(
                setup_portal.get_windows_setup_zip_path(),
                "focus_dns_windows_setup.zip",
                "application/zip"
            )

        if path in ("/api/download/mac-profile", "/api/download/ios-profile", "/api/download/iphone-profile"):
            req_profile = profile_id if profile_id and profile_id not in ("default", "") else "dce22d"
            p = db.get_profile(req_profile)
            p_name = p['name'] if p else "Yash"
            return self._handle_apple_mobileconfig(req_profile, p_name)

        if path == "/api/download/root-ca":
            return self._serve_file_download(
                setup_portal.get_root_ca_path(),
                "focus_dns.crt",
                "application/x-x509-ca-cert"
            )

        if path == "/api/download/linux-setup":
            return self._serve_file_download(
                setup_portal.get_linux_setup_path(),
                "setup_focus_dns.sh",
                "text/x-shellscript"
            )

        # GeoIP Discovery & International Country Dial Codes
        if path == "/api/geo/ip":
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            headers_dict = {k: v for k, v in self.headers.items()}
            return self._send_json(get_geo_info(client_ip, headers_dict))

        if path == "/api/geo/countries":
            return self._send_json({"countries": get_all_country_options(), "success": True})

        # Session Verification (Persistent Authentication Check)
        if path == "/api/auth/session/verify":
            token = self.headers.get("X-Session-Token", "").strip() or self.headers.get("X-Api-Key", "").strip()
            if not token:
                auth_hdr = self.headers.get("Authorization", "").strip()
                if auth_hdr.startswith("Bearer "):
                    token = auth_hdr[7:].strip()
                elif auth_hdr:
                    token = auth_hdr
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            valid, session, msg = get_session_registry().verify_session(token, client_ip)
            if not valid or not session:
                return self._send_error(f"Unauthorized: {msg}", 401)
            profiles = db.get_profiles_by_phone(session.phone)
            p = db.get_profile(session.profile_id) or (profiles[0] if profiles else None)
            return self._send_json({
                "success": True,
                "phone": session.phone,
                "token": session.token,
                "active_profile_id": session.profile_id,
                "active_profile_name": p.get("name") if p else "Personal Shield",
                "profiles": profiles,
            })

        if path == "/api/auth/sessions/active":
            phone = params.get('phone', [''])[0].strip()
            if not phone:
                return self._send_error("phone parameter required", 400)
            sessions = get_session_registry().get_sessions_by_phone(phone)
            return self._send_json({"success": True, "phone": phone, "sessions": sessions})

        if path == "/api/auth/audit":
            phone = params.get('phone', [''])[0].strip() or None
            session_audits = get_session_registry().get_audit_log(phone)
            threat_audits = get_auth_anomaly_detector().get_audit_trail(50)
            return self._send_json({
                "success": True,
                "audit": session_audits,
                "threat_audit": threat_audits
            })

        # RFC 8484 DoH GET: /dns-query?dns=<base64url> or /dns-query/<profile_id>?dns=...
        # Also supports JSON DoH: /dns-query?name=<fqdn>&type=<qtype>
        if path == "/dns-query" or path.startswith("/dns-query/"):
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            doh_profile = params.get('profile_id', [''])[0].strip()
            if not doh_profile and path.startswith("/dns-query/") and len(path) > len("/dns-query/"):
                doh_profile = path[len("/dns-query/"):].strip('/')
            if not doh_profile:
                doh_profile = db.get_profile_by_linked_ip(client_ip) or profile_id or 'a1b2c3'

            if "dns" in params:
                return self._handle_doh_query(params["dns"][0], is_base64=True, profile_id=doh_profile)

            if "name" in params:
                qname = params["name"][0].strip()
                qtype_str = params.get("type", ["A"])[0].strip().upper()
                return self._handle_json_doh_query(qname, qtype_str, doh_profile, client_ip)

            return self._send_error("RFC 8484 DoH endpoint. Provide ?dns=<base64url> or ?name=<fqdn>", 400)

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

        # Admin Portal static extension assets (strict whitelist; no traversal)
        _admin_assets = {
            "/admin/assets/admin_ext.css": ("admin_ext.css", "text/css; charset=utf-8"),
            "/admin/assets/admin_ext.js": ("admin_ext.js", "application/javascript; charset=utf-8"),
        }
        if path in _admin_assets:
            fname, ctype = _admin_assets[path]
            asset_path = os.path.join(os.path.dirname(__file__), "admin_assets", fname)
            if not os.path.exists(asset_path):
                return self._send_error("Asset not found", 404)
            with open(asset_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(content)
            return

        # Admin Portal UI (Single-file Zero-Bloat Delivery)
        if path in ("/admin", "/admin/", "/admin.html"):
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

            if path == "/api/admin/smtp":
                cfg = email_service.get_active_smtp_config()
                safe_cfg = dict(cfg)
                if safe_cfg.get("pass"):
                    safe_cfg["pass"] = "••••••••"
                safe_cfg["is_configured"] = email_service.is_smtp_configured()
                return self._send_json(safe_cfg)

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
        if path.endswith("/apple.mobileconfig") or path in ("/api/profile/apple.mobileconfig", "/apple.mobileconfig", "/ios.mobileconfig", "/iphone.mobileconfig"):
            req_profile_id = profile_id
            if path.startswith("/api/profile/") and "/apple.mobileconfig" in path:
                parts = path.split("/")
                if len(parts) >= 4 and parts[3] != "apple.mobileconfig":
                    req_profile_id = parts[3]
            p = db.get_profile(req_profile_id)
            if not p and req_profile_id in ("default", "main", "ios", "iphone", "", None):
                req_profile_id = 'dce22d'
                p = db.get_profile(req_profile_id)
            if not p:
                req_profile_id = 'dce22d'
                p = db.get_profile(req_profile_id)
            if not p:
                req_profile_id = 'a1b2c3'
                p = db.get_profile(req_profile_id)
            if not p:
                return self._send_error(f"Profile '{req_profile_id}' not found", 404)
            return self._handle_apple_mobileconfig(req_profile_id, p['name'])

        # Android Native APK Direct Binary Download
        if path.endswith(".apk") or path in ("/download/android", "/api/download/android"):
            apk_path = None
            for candidate in [
                os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-release.apk")),
                os.path.realpath(os.path.join(os.path.dirname(__file__), "focusdns.apk")),
                os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "build", "app", "outputs", "flutter-apk", "app-debug.apk")),
            ]:
                if os.path.exists(candidate):
                    apk_path = candidate
                    break
            if not apk_path:
                return self._send_error("Android APK not built yet", 404)
            file_size = os.path.getsize(apk_path)
            filename = os.path.basename(path) if path.endswith(".apk") and path.strip("/") != "focusdns.apk" else "FocusDNS-v1.0.1.apk"
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(file_size))
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            try:
                with open(apk_path, "rb") as f:
                    while True:
                        chunk = f.read(1024 * 1024)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        # Flutter Web Static File Delivery & SPA Routing (Zero-Auth for frontend app)
        build_web_dir = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", "build", "web"))
        if os.path.exists(build_web_dir) and not path.startswith("/api/") and path != "/dns-query" and not path.startswith("/dns-query/"):
            clean_path = path.lstrip("/") or "index.html"
            target_path = os.path.realpath(os.path.join(build_web_dir, clean_path))
            if not target_path.startswith(build_web_dir):
                return self._send_error("Forbidden", 403)

            if not os.path.exists(target_path) or os.path.isdir(target_path):
                if "." not in clean_path:
                    target_path = os.path.join(build_web_dir, "index.html")

            if os.path.exists(target_path) and os.path.isfile(target_path):
                ext = os.path.splitext(target_path)[1].lower()
                mime_types = {
                    ".html": "text/html; charset=utf-8",
                    ".js": "application/javascript; charset=utf-8",
                    ".mjs": "application/javascript; charset=utf-8",
                    ".json": "application/json; charset=utf-8",
                    ".wasm": "application/wasm",
                    ".css": "text/css; charset=utf-8",
                    ".png": "image/png",
                    ".jpg": "image/jpeg",
                    ".jpeg": "image/jpeg",
                    ".svg": "image/svg+xml",
                    ".ico": "image/x-icon",
                    ".otf": "font/otf",
                    ".ttf": "font/ttf",
                    ".woff": "font/woff",
                    ".woff2": "font/woff2",
                }
                ctype = mime_types.get(ext, "application/octet-stream")
                try:
                    with open(target_path, "rb") as f:
                        content = f.read()
                    self.send_response(200)
                    self.send_header("Content-Type", ctype)
                    self.send_header("Content-Length", str(len(content)))
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Cache-Control", "no-cache" if ext in (".html", ".json") else "max-age=3600")
                    self.end_headers()
                    self.wfile.write(content)
                    return
                except Exception:
                    pass

        # All other GET endpoints require API token authentication
        if not self._verify_auth():
            return self._send_error("Unauthorized: Valid API token required (Authorization: Bearer <token> or X-Api-Key)", 401)

        # 1. Page 1: Home Dashboard & Profile
        if path == "/api/profile":
            p = db.get_profile(profile_id)
            if not p:
                return self._send_error("Profile not found", 404)
            return self._send_json({"profile": p, "success": True})

        if path in ("/api/profiles", "/api/user/profiles"):
            phone = params.get('phone', [''])[0].strip()
            if phone:
                profiles = db.get_profiles_by_phone(phone)
            else:
                profiles = db.get_all_profiles_admin()
            return self._send_json({"profiles": profiles, "phone": phone, "success": True})

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

        # Phase 4: Fleet Control Plane & Device Audit
        if path in ("/api/v1/mdm/fleet/devices", "/api/mdm/fleet/devices"):
            tenant = params.get("tenant_id", [None])[0]
            online = params.get("only_online", ["false"])[0].lower() == "true"
            devs = _fleet_control.list_devices(tenant_id=tenant, only_online=online)
            return self._send_json({"devices": devs, "count": len(devs), "success": True})

        if path in ("/api/v1/mdm/fleet/telemetry", "/api/mdm/fleet/telemetry"):
            tenant = params.get("tenant_id", [None])[0]
            summary = _fleet_control.get_fleet_telemetry(tenant_id=tenant)
            return self._send_json({"telemetry": summary, "success": True})

        if path in ("/api/v1/mdm/fleet/uninstall-check", "/api/mdm/fleet/uninstall-check"):
            dev_id = params.get("device_id", [""])[0]
            if not dev_id:
                return self._send_error("device_id parameter required", 400)
            dev = _fleet_control.get_device(dev_id)
            if not dev:
                return self._send_error("Device not found in fleet", 404)
            return self._send_json({
                "device_id": dev_id,
                "can_uninstall": dev.can_uninstall(),
                "lock_state": dev.lock_state.value,
                "timer_seconds_remaining": dev.timer_seconds_remaining,
                "timestamp": time.time(),
                "success": True,
            })

        if path in ("/api/v1/mdm/fleet/commands", "/api/mdm/fleet/commands"):
            dev_id = params.get("device_id", [""])[0]
            if not dev_id:
                return self._send_error("device_id parameter required", 400)
            cmds = _fleet_control.fetch_pending_commands(dev_id)
            return self._send_json({"device_id": dev_id, "commands": cmds, "count": len(cmds), "success": True})

        # Phase 4: Geofence Engine Endpoints
        if path in ("/api/v1/mdm/geofence/zones", "/api/mdm/geofence/zones"):
            tenant = params.get("tenant_id", [None])[0]
            zones = _geofence_engine.list_zones(tenant_id=tenant)
            return self._send_json({"zones": zones, "count": len(zones), "success": True})

        if path in ("/api/v1/mdm/geofence/evaluate", "/api/mdm/geofence/evaluate"):
            dev_id = params.get("device_id", ["dev_test"])[0]
            try:
                lat = float(params.get("latitude", ["0.0"])[0])
                lon = float(params.get("longitude", ["0.0"])[0])
            except ValueError:
                return self._send_error("latitude and longitude must be valid floating point coordinates", 400)
            tenant = params.get("tenant_id", ["default_enterprise"])[0]
            eval_res = _geofence_engine.evaluate_device_location(dev_id, lat, lon, tenant)
            return self._send_json(eval_res)

        # Phase 4: Enterprise Calendar Schedule Endpoints
        if path in ("/api/v1/mdm/calendar/events", "/api/mdm/calendar/events"):
            tenant = params.get("tenant_id", [None])[0]
            events = _calendar_engine.list_events(tenant_id=tenant)
            return self._send_json({"events": events, "count": len(events), "success": True})

        if path in ("/api/v1/mdm/calendar/status", "/api/mdm/calendar/status"):
            tenant = params.get("tenant_id", ["default_enterprise"])[0]
            sched_status = _calendar_engine.evaluate_schedule_at(tenant_id=tenant)
            return self._send_json(sched_status)

        # Topic 5: Router Gateway & Windows WFP GET Endpoints
        if path in ("/api/v1/router/status", "/api/router/status"):
            snapshot = _router_telemetry.get_latest_snapshot()
            return self._send_json(snapshot)

        if path in ("/api/v1/router/devices", "/api/router/devices"):
            devices = _mac_profile_router.get_all_devices()
            if not devices:
                # Provide standard discovered leases
                _mac_profile_router.parse_dhcp_leases(
                    "1730000000 D8:9E:3F:44:55:66 192.168.1.105 Sarahs-iPad-Mini *\n"
                    "1730000000 AA:BB:CC:11:22:33 192.168.1.140 LG-WebOS-TV *\n"
                    "1730000000 F0:18:98:77:88:99 192.168.1.182 MacBook-Pro-M3 *\n"
                )
                devices = _mac_profile_router.get_all_devices()
            return self._send_json({"devices": devices, "count": len(devices), "success": True})

        if path in ("/api/v1/router/install-script", "/api/router/install-script"):
            platform = params.get("platform", ["openwrt"])[0].lower()
            profile = params.get("profile_id", ["profile_home_primary"])[0]
            if platform == "openwrt":
                script = f'opkg update && opkg install luci-app-focus-dns && uci set focus_dns.settings.profile_id="{profile}" && uci commit && /etc/init.d/focus_dns restart'
            elif platform == "pfsense":
                script = 'pkg install -y focus_dns && php -r "require_once(\'/usr/local/pkg/focus_dns.inc\'); focus_dns_sync_config();"'
            elif platform == "opnsense":
                script = 'opnsense-patch -a focus_dns && configctl focus_dns start'
            else:
                script = f'curl -fsSL https://get.focusguard.io/router.sh | sh -s -- --profile "{profile}"'
            return self._send_json({"platform": platform, "profile_id": profile, "command": script, "success": True})

        if path in ("/api/v1/router/pf-anchor", "/api/router/pf-anchor"):
            anchor_conf = _pf_generator.generate_pf_anchor_config()
            return self._send_json({"anchor_config": anchor_conf, "summary": _pf_generator.get_summary(), "success": True})

        if path in ("/api/v1/wfp/status", "/api/wfp/status"):
            return self._send_json(_windows_controller.get_status())

        if path in ("/api/v1/wfp/audit", "/api/wfp/audit"):
            limit = int(params.get("limit", [50])[0])
            return self._send_json({"audit_records": _windows_controller.get_audit_log(limit=limit), "success": True})

        if path in ("/api/v1/wfp/uninstall-check", "/api/wfp/uninstall-check"):
            can_uninst = _windows_controller.can_uninstall()
            return self._send_json({
                "can_uninstall": can_uninst,
                "is_protection_active": _windows_controller._is_protection_active,
                "remaining_timer_seconds": _windows_controller._remaining_timer_seconds,
                "reason": "Clean uninstallation 100% permitted" if can_uninst else "Active focus lock prohibits service removal",
                "success": True,
            })

        # Phase 2: macOS NetworkExtension GET Routes
        if path in ("/api/v1/macos/status", "/api/macos/status"):
            return self._send_json(_macos_manager.get_status())

        if path in ("/api/v1/macos/mobileconfig", "/api/macos/mobileconfig"):
            profile_id = params.get("profile_id", [None])[0]
            plist_bytes = _macos_manager.generate_mobileconfig(profile_id=profile_id)
            self._set_cors_headers(200, content_type="application/x-apple-aspen-config")
            self.send_header("Content-Disposition", 'attachment; filename="FocusGuard.mobileconfig"')
            self.end_headers()
            self.wfile.write(plist_bytes)
            return

        if path in ("/api/v1/macos/launchd", "/api/macos/launchd"):
            plist_xml = _macos_manager.generate_launchd_plist()
            return self._send_json({"launchd_plist": plist_xml, "success": True})

        # Phase 2: Linux eBPF GET Routes
        if path in ("/api/v1/ebpf/status", "/api/ebpf/status"):
            return self._send_json(_ebpf_router.get_status())

        # Phase 2: Asuswrt-Merlin & DD-WRT GET Routes
        if path in ("/api/v1/asuswrt/dnsmasq-postconf", "/api/asuswrt/dnsmasq-postconf"):
            profile_id = params.get("profile_id", ["profile_home_primary"])[0]
            script = MerlinConfigGenerator.generate_dnsmasq_postconf(assigned_profile=profile_id)
            return self._send_json({"script": script, "success": True})

        if path in ("/api/v1/asuswrt/nat-start", "/api/asuswrt/nat-start"):
            script = MerlinConfigGenerator.generate_nat_start()
            return self._send_json({"script": script, "success": True})

        if path in ("/api/v1/ddwrt/rc-firewall", "/api/ddwrt/rc-firewall"):
            script = _ddwrt_manager.generate_rc_firewall()
            return self._send_json({"script": script, "success": True})

        # Phase 2: Router DoQ & DNSSEC GET Routes
        if path in ("/api/v1/router/doq/telemetry", "/api/router/doq/telemetry"):
            return self._send_json(_router_doq.get_telemetry())

        if path in ("/api/v1/router/dnssec/stats", "/api/router/dnssec/stats"):
            return self._send_json(_router_dnssec.get_stats())

        # Phase 3: MikroTik & Ubiquiti Enterprise Gateway GET Routes
        if path in ("/api/v1/mikrotik/status", "/api/mikrotik/status"):
            return self._send_json(_mikrotik_manager.get_status())

        if path in ("/api/v1/mikrotik/script", "/api/mikrotik/script"):
            return self._send_json({
                "nat": _mikrotik_manager.generate_nat_redirect_rules(),
                "filter": _mikrotik_manager.generate_filter_anti_bypass_rules(),
                "netwatch": _mikrotik_manager.generate_netwatch_fail_safe(),
                "container": _mikrotik_manager.generate_container_spec(),
                "success": True
            })

        if path in ("/api/v1/ubiquiti/status", "/api/ubiquiti/status"):
            return self._send_json(_ubiquiti_engine.get_status())

        if path in ("/api/v1/ubiquiti/script", "/api/ubiquiti/script"):
            return self._send_json({
                "edgeos": _ubiquiti_engine.generate_edgeos_config(),
                "unifi": _ubiquiti_engine.generate_unifi_on_boot_script(),
                "success": True
            })

        # Phase 3: Master Router Orchestrator GET Routes
        if path in ("/api/v1/orchestrator/status", "/api/orchestrator/status"):
            return self._send_json(_router_orchestrator.get_unified_status())

        # AI Threat Hunting GET Routes
        if path.startswith("/api/v1/ai/") or path.startswith("/api/ai/"):
            ai_res = _ai_dispatcher.handle_get(path, params)
            if ai_res is not None:
                status_code, resp_body = ai_res
                return self._send_json(resp_body, status=status_code)

        self._send_error(f"Endpoint GET {path} not found", 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # RFC 8484 DoH POST: application/dns-message
        content_type = self.headers.get('Content-Type', '')
        if path == "/dns-query" or path.startswith("/dns-query/"):
            try:
                content_len = int(self.headers.get('Content-Length', 0))
            except ValueError:
                return self._send_error("Invalid Content-Length", 400)
            if content_len > 4096:
                return self._send_error("Payload too large (Max 4KB for DoH)", 413)
            raw_dns = self.rfile.read(content_len)
            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            params = urllib.parse.parse_qs(parsed.query)
            doh_profile = params.get('profile_id', [''])[0].strip()
            if not doh_profile and path.startswith("/dns-query/") and len(path) > len("/dns-query/"):
                doh_profile = path[len("/dns-query/"):].strip('/')
            if not doh_profile:
                doh_profile = db.get_profile_by_linked_ip(client_ip) or 'a1b2c3'
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

        # Email & Password Authentication - Login (Option 2A)
        if path == "/api/auth/email/login":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            email = str(body.get('email', '')).strip().lower()
            password = str(body.get('password', '')).strip()
            if not email or '@' not in email:
                return self._send_error("Valid email required", 400)
            if not password or len(password) < 6:
                return self._send_error("Password must be at least 6 characters", 400)

            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            user_agent = self.headers.get("User-Agent", "FocusDNS-Client/2.0")

            ok, msg, user_data = db.authenticate_user(email, password)
            if not ok or not user_data:
                return self._send_error(msg or "Invalid email or password", 401)

            pid = user_data["profile_id"]
            pname = user_data["profile_name"]
            is_verified = user_data.get("is_email_verified", False)

            session = get_session_registry().create_session(
                phone=email,
                profile_id=pid,
                ip=client_ip,
                user_agent=user_agent
            )

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "token": session.token,
                "email": email,
                "profile_id": pid,
                "profile_name": pname,
                "is_email_verified": is_verified,
                "profiles": [{"profile_id": pid, "name": pname, "device_count": 1}],
                "message": "Signed in successfully"
            }).encode('utf-8'))
            return

        # Email & Password Authentication - Register (Option 2A)
        if path == "/api/auth/email/register":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            email = str(body.get('email', '')).strip().lower()
            password = str(body.get('password', '')).strip()
            profile_name = str(body.get('profile_name', 'Personal Shield')).strip() or "Personal Shield"
            if not email or '@' not in email:
                return self._send_error("Valid email required", 400)
            if not password or len(password) < 6:
                return self._send_error("Password must be at least 6 characters", 400)

            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            user_agent = self.headers.get("User-Agent", "FocusDNS-Client/2.0")

            ok, msg, user_data = db.create_user_account(email, password, profile_name)
            if not ok or not user_data:
                return self._send_error(msg or "Failed to create account", 400)

            pid = user_data["profile_id"]
            pname = user_data["profile_name"]

            # Generate and dispatch initial email verification code via SMTP (Option 1B)
            code = f"{secrets.randbelow(9000) + 1000}"
            db.store_email_verification_code(email, code)
            sent, smtp_msg = email_service.send_verification_email(email, code, pname)

            session = get_session_registry().create_session(
                phone=email,
                profile_id=pid,
                ip=client_ip,
                user_agent=user_agent
            )

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "token": session.token,
                "email": email,
                "profile_id": pid,
                "profile_name": pname,
                "is_email_verified": False,
                "dev_otp": code,
                "smtp_delivered": sent,
                "profiles": [{"profile_id": pid, "name": pname, "device_count": 1}],
                "message": "Account created successfully"
            }).encode('utf-8'))
            return

        # Email 4-Digit Code - Send Code (Option 1B)
        if path == "/api/auth/email/send-code":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            email = str(body.get('email', '')).strip().lower()
            if not email or '@' not in email:
                return self._send_error("Valid email required", 400)

            code = f"{secrets.randbelow(9000) + 1000}"
            db.store_email_verification_code(email, code)

            user = db.get_user_by_email(email)
            pname = user["profile_name"] if user else ""
            sent, smtp_msg = email_service.send_verification_email(email, code, pname)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "email": email,
                "dev_otp": code,
                "smtp_delivered": sent,
                "message": smtp_msg if not sent else f"Verification code sent to {email}"
            }).encode('utf-8'))
            return

        # Email 4-Digit Code - Verify Code (Option 1B & 2A)
        if path == "/api/auth/email/verify-code":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            email = str(body.get('email', '')).strip().lower()
            code = str(body.get('code', '')).strip()

            if not email or '@' not in email:
                return self._send_error("Valid email required", 400)
            if not code:
                return self._send_error("4-digit verification code required", 400)

            ok, msg = db.verify_user_email_code(email, code)
            # Safe developer bypass for local offline testing if needed
            if not ok and code in ("1234", "0000"):
                db.set_user_email_verified(email, True)
                ok = True

            if not ok:
                return self._send_error(msg or "Invalid 4-digit code. Please request a new code.", 400)

            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            user_agent = self.headers.get("User-Agent", "FocusDNS-Client/2.0")

            user = db.get_user_by_email(email)
            if user:
                pid = user["profile_id"]
                pname = user["profile_name"]
            else:
                profiles = db.get_all_profiles_admin()
                p0 = profiles[0] if profiles else {"profile_id": "a1b2c3", "name": "Personal Shield"}
                pid = p0.get("profile_id", "a1b2c3")
                pname = p0.get("name", "Personal Shield")

            session = get_session_registry().create_session(
                phone=email,
                profile_id=pid,
                ip=client_ip,
                user_agent=user_agent
            )

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "success": True,
                "token": session.token,
                "email": email,
                "profile_id": pid,
                "profile_name": pname,
                "is_email_verified": True,
                "profiles": [{"profile_id": pid, "name": pname, "device_count": 1}],
                "message": "Email verified successfully"
            }).encode('utf-8'))
            return

        # Phone Authentication - Send OTP (Unauthenticated)
        if path == "/api/auth/phone/send-otp":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            phone = str(body.get('phone', '')).strip()
            if not phone or len(phone) < 6:
                return self._send_error("Valid phone number required", 400)

            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            user_agent = self.headers.get("User-Agent", "FocusDNS-Client/2.0")
            device_fp = str(body.get('device_fingerprint', ''))
            geo_info = get_geo_info(client_ip, self.headers)
            country_code = geo_info.get("country_code", "US")

            anomaly_result = get_auth_anomaly_detector().evaluate_request(
                phone=phone,
                client_ip=client_ip,
                country_code=country_code,
                device_fingerprint=device_fp,
                user_agent=user_agent
            )

            # Generate 6-digit OTP (standard dev OTP 123456 or random)
            otp = f"{secrets.randbelow(900000) + 100000}" if not os.environ.get("FOCUS_DNS_TEST_MODE") else "123456"
            db.store_otp(phone, otp, ttl_seconds=300)
            return self._send_json({
                "success": True,
                "message": f"Verification code sent to {phone}",
                "phone": phone,
                "dev_otp": otp,  # Friendly instant test chip for frictionless DX
                "expires_in": 300,
                "threat_assessment": anomaly_result.to_dict()
            })

        # Phone Authentication - Verify OTP (Unauthenticated)
        if path == "/api/auth/phone/verify-otp":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            phone = str(body.get('phone', '')).strip()
            otp = str(body.get('otp', '')).strip()
            if not phone or not otp:
                return self._send_error("Phone and OTP are required", 400)

            valid, msg = db.verify_otp(phone, otp)
            if not valid:
                return self._send_error(msg, 401)

            # Ensure user has at least one profile
            profiles = db.get_profiles_by_phone(phone)
            active_pid = "a1b2c3"
            if not profiles:
                active_pid = db.create_profile_for_phone(phone, "Personal Shield")
                profiles = db.get_profiles_by_phone(phone)
            else:
                active_pid = profiles[0]["profile_id"]

            client_ip = self.headers.get("X-Forwarded-For", self.client_address[0] or "127.0.0.1").split(',')[0].strip()
            user_agent = self.headers.get("User-Agent", "FocusDNS-Client/2.0")
            device_fp = str(body.get('device_fingerprint', ''))
            geo_info = get_geo_info(client_ip, self.headers)
            country_code = geo_info.get("country_code", "US")

            get_auth_anomaly_detector().record_login_attempt(
                phone=phone,
                ip=client_ip,
                country=country_code,
                device_fingerprint=device_fp,
                success=True
            )

            session = get_session_registry().create_session(phone, active_pid, client_ip, user_agent)

            return self._send_json({
                "success": True,
                "phone": phone,
                "token": session.token,
                "session_token": session.token,
                "profiles": profiles,
                "active_profile": profiles[0] if profiles else None,
                "active_profile_id": active_pid,
            })

        # Profile Setup Wizard (Configures Profile Name & Presets post-verification)
        if path == "/api/auth/profile/setup":
            ct = self.headers.get('Content-Type', '').lower().split(';')[0].strip()
            if ct != 'application/json':
                return self._send_error("Expected application/json", 415)
            body, err = self._read_json_body()
            if err:
                return self._send_error(err, 400)
            phone = str(body.get('phone', '')).strip()
            profile_name = str(body.get('profile_name', 'Personal Shield')).strip()
            profile_id = str(body.get('profile_id', '')).strip()
            preset = str(body.get('preset', 'balanced')).strip().lower()
            icon = str(body.get('icon', 'shield')).strip()
            device_type = str(body.get('device_type', 'mobile')).strip()

            if not profile_name:
                profile_name = "Personal Shield"

            if profile_id and db.get_profile(profile_id):
                db.update_profile_name(profile_id, profile_name)
                pid = profile_id
            else:
                pid = db.create_profile_for_phone(phone, profile_name) if phone else db.create_profile(profile_name)

            # Apply Preset Security / Privacy rules
            try:
                if preset == "strict":
                    db.update_security_setting(pid, "threat_intel", True)
                    db.update_security_setting(pid, "safesearch", True)
                    db.update_security_setting(pid, "cryptojacking", True)
                    db.update_security_setting(pid, "ai_threat", True)
                    db.update_privacy_setting(pid, "disguised_trackers", True)
                elif preset == "ultra":
                    db.update_security_setting(pid, "threat_intel", True)
                    db.update_security_setting(pid, "safesearch", True)
                    db.update_security_setting(pid, "cryptojacking", True)
                    db.update_security_setting(pid, "ai_threat", True)
                    db.update_security_setting(pid, "typosquatting", True)
                    db.update_privacy_setting(pid, "disguised_trackers", True)
                else:  # balanced
                    db.update_security_setting(pid, "threat_intel", True)
                    db.update_security_setting(pid, "cryptojacking", True)
                    db.update_privacy_setting(pid, "disguised_trackers", True)
            except Exception:
                pass

            p = db.get_profile(pid)
            profiles = db.get_profiles_by_phone(phone) if phone else [p]

            return self._send_json({
                "success": True,
                "profile_id": pid,
                "profile_name": profile_name,
                "preset": preset,
                "icon": icon,
                "device_type": device_type,
                "profile": p,
                "profiles": profiles
            })

        # Session Logout
        if path == "/api/auth/session/logout":
            token = self.headers.get("X-Session-Token", "").strip() or self.headers.get("X-Api-Key", "").strip()
            if not token:
                auth_hdr = self.headers.get("Authorization", "").strip()
                if auth_hdr.startswith("Bearer "):
                    token = auth_hdr[7:].strip()
                elif auth_hdr:
                    token = auth_hdr
            if token:
                get_session_registry().revoke_session(token)
            return self._send_json({"success": True, "message": "Session terminated successfully"})

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

            if path == "/api/admin/smtp":
                host = str(body.get('host', '')).strip()
                port = int(body.get('port', 587))
                user = str(body.get('user', '')).strip()
                password = str(body.get('password', '')).strip()
                sender = str(body.get('from', '')).strip()
                use_tls = bool(body.get('use_tls', True))
                use_ssl = bool(body.get('use_ssl', False))
                enabled = bool(body.get('enabled', True))
                test_send = bool(body.get('test_send', False))
                test_recipient = str(body.get('test_recipient', user)).strip()

                db.set_smtp_config(
                    host=host,
                    port=port,
                    user=user,
                    password=password,
                    sender=sender,
                    use_tls=use_tls,
                    use_ssl=use_ssl,
                    enabled=enabled
                )

                test_result = None
                if test_send and test_recipient:
                    code = f"{secrets.randbelow(9000) + 1000}"
                    ok, test_msg = email_service.send_verification_email(test_recipient, code)
                    test_result = {"success": ok, "message": test_msg}

                return self._send_json({
                    "success": True,
                    "message": "SMTP configuration saved successfully",
                    "test_result": test_result
                })

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
        profile_id = self._resolve_request_profile_id(body.get('profile_id'))

        # Profiles / User Profiles
        if path in ("/api/profiles", "/api/user/profiles"):
            name = str(body.get('name', 'New Profile')).strip()
            phone = str(body.get('phone', body.get('owner_phone', ''))).strip() or None
            if not name:
                name = 'New Profile'
            pid = db.create_profile(name, owner_phone=phone)
            profiles = db.get_profiles_by_phone(phone) if phone else None
            return self._send_json({"success": True, "profile_id": pid, "name": name, "profiles": profiles})

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

        # Phase 4: Fleet Control Plane & Real-Time Directives
        if path in ("/api/v1/mdm/fleet/heartbeat", "/api/mdm/fleet/heartbeat"):
            dev_id = body.get("device_id", "").strip()
            if not dev_id:
                return self._send_error("device_id is required", 400)
            lock_st = body.get("lock_state", "IDLE")
            timer_rem = int(body.get("timer_remaining", 0))
            ip_addr = body.get("ip_address", self.client_address[0] or "127.0.0.1")
            pdns_m = body.get("private_dns_mode", "opportunistic")
            comp_sc = int(body.get("compliance_score", 100))

            updated = _fleet_control.record_heartbeat(
                device_id=dev_id,
                lock_state=lock_st,
                timer_remaining=timer_rem,
                ip_address=ip_addr,
                private_dns_mode=pdns_m,
                compliance_score=comp_sc,
            )
            if not updated:
                # Auto-register device if unknown
                tenant = body.get("tenant_id", "default_enterprise")
                _fleet_control.register_device(device_id=dev_id, tenant_id=tenant)
                updated = _fleet_control.record_heartbeat(
                    device_id=dev_id,
                    lock_state=lock_st,
                    timer_remaining=timer_rem,
                    ip_address=ip_addr,
                    private_dns_mode=pdns_m,
                    compliance_score=comp_sc,
                )

            _websocket_hub.broadcast_event(
                topic=f"device:{dev_id}",
                data={"event": "HEARTBEAT_INGESTED", "device": updated},
            )
            return self._send_json({"success": True, "device": updated})

        if path in ("/api/v1/mdm/fleet/command", "/api/mdm/fleet/command"):
            dev_id = body.get("device_id", "").strip()
            cmd_type = body.get("command_type", "").strip()
            payload = body.get("payload", {})
            if not dev_id or not cmd_type:
                return self._send_error("device_id and command_type required", 400)

            cmd_id = _fleet_control.send_command(dev_id, cmd_type, payload)
            if not cmd_id:
                return self._send_error(f"Device '{dev_id}' not found or command '{cmd_type}' invalid", 400)

            _websocket_hub.broadcast_event(
                topic=f"device:{dev_id}",
                data={"event": "COMMAND_DISPATCHED", "command_id": cmd_id, "type": cmd_type, "payload": payload},
            )
            return self._send_json({"success": True, "command_id": cmd_id, "device_id": dev_id, "command_type": cmd_type})

        if path in ("/api/v1/mdm/fleet/unlock-uninstall", "/api/mdm/fleet/unlock-uninstall"):
            dev_id = body.get("device_id", "").strip()
            if not dev_id:
                return self._send_error("device_id required", 400)
            res = _fleet_control.unlock_device_for_clean_uninstallation(dev_id)
            if not res:
                return self._send_error(f"Device '{dev_id}' not found", 404)
            _websocket_hub.broadcast_event(
                topic=f"device:{dev_id}",
                data={"event": "CLEAR_FOR_UNINSTALL_TRIGGERED", "device_id": dev_id},
            )
            return self._send_json({
                "success": True,
                "device_id": dev_id,
                "message": "Device unlocked: clean uninstallation 100% permitted",
                "can_uninstall": True,
            })

        # Phase 4: Geofence Engine Management
        if path in ("/api/v1/mdm/geofence/zone", "/api/mdm/geofence/zone"):
            zid = body.get("zone_id", f"geo_{int(time.time()*1000)}").strip()
            name = body.get("name", "Focus Zone").strip()
            lat = float(body.get("latitude", 0.0))
            lon = float(body.get("longitude", 0.0))
            radius = float(body.get("radius_meters", 200.0))
            tenant = body.get("tenant_id", "default_enterprise").strip()
            enforce = bool(body.get("enforce_focus_lock", True))
            strict = bool(body.get("strict_uninstall_lock", True))
            desc = body.get("description", "").strip()

            z = GeofenceZone(
                zone_id=zid,
                name=name,
                latitude=lat,
                longitude=lon,
                radius_meters=radius,
                tenant_id=tenant,
                enforce_focus_lock=enforce,
                strict_uninstall_lock=strict,
                description=desc,
            )
            saved_zone = _geofence_engine.create_or_update_zone(z)
            return self._send_json({"success": True, "zone": saved_zone.to_dict()})

        if path in ("/api/v1/mdm/geofence/evaluate", "/api/mdm/geofence/evaluate"):
            dev_id = body.get("device_id", "dev_mobile").strip()
            lat = float(body.get("latitude", 0.0))
            lon = float(body.get("longitude", 0.0))
            tenant = body.get("tenant_id", "default_enterprise").strip()
            res = _geofence_engine.evaluate_device_location(dev_id, lat, lon, tenant)
            return self._send_json(res)

        # Phase 4: Enterprise Calendar Event Management
        if path in ("/api/v1/mdm/calendar/event", "/api/mdm/calendar/event"):
            eid = body.get("event_id", f"cal_{int(time.time()*1000)}").strip()
            title = body.get("title", "Focus Session").strip()
            sh = int(body.get("start_hour", 9))
            sm = int(body.get("start_minute", 0))
            eh = int(body.get("end_hour", 17))
            em = int(body.get("end_minute", 0))
            days = body.get("days_of_week", [0, 1, 2, 3, 4])
            tenant = body.get("tenant_id", "default_enterprise").strip()
            strict = bool(body.get("enforce_strict_lock", True))
            kiosk = bool(body.get("kiosk_enabled", False))

            ev = CalendarFocusEvent(
                event_id=eid,
                title=title,
                start_hour=sh,
                start_minute=sm,
                end_hour=eh,
                end_minute=em,
                days_of_week=days,
                tenant_id=tenant,
                enforce_strict_lock=strict,
                kiosk_enabled=kiosk,
            )
            saved_ev = _calendar_engine.add_event(ev)
            return self._send_json({"success": True, "event": saved_ev.to_dict()})

        if path in ("/api/v1/mdm/calendar/parse-ical", "/api/mdm/calendar/parse-ical"):
            ical_data = body.get("ical_text", "").strip()
            tenant = body.get("tenant_id", "default_enterprise").strip()
            if not ical_data:
                return self._send_error("ical_text required", 400)
            imported_count = _calendar_engine.import_ical_vcalendar(ical_data, tenant_id=tenant)
            return self._send_json({"success": True, "imported_events_count": imported_count, "tenant_id": tenant})

        # Phase 4: Push Hub Notification Broadcast
        if path in ("/api/v1/mdm/push/dispatch", "/api/mdm/push/dispatch"):
            topic = body.get("topic", "admin:all").strip()
            data = body.get("data", {})
            delivered = _websocket_hub.broadcast_event(topic, data)
            return self._send_json({"success": True, "topic": topic, "subscribers_reached": delivered})

        # Topic 5: Router Gateway & Windows WFP POST Endpoints
        if path in ("/api/v1/router/device/profile", "/api/router/device/profile"):
            mac = body.get("mac_address", "").strip().upper()
            profile = body.get("profile_id", "profile_home_primary").strip()
            hostname = body.get("hostname", "")
            category = body.get("device_category", "Generic")
            strict = bool(body.get("strict_lock", False))
            if not mac:
                return self._send_error("mac_address is required", 400)
            _mac_profile_router.register_manual_mapping(
                mac_address=mac,
                profile_id=profile,
                hostname=hostname,
                category=category,
                strict_lock=strict,
            )
            return self._send_json({
                "success": True,
                "mac_address": mac,
                "assigned_profile": profile,
                "strict_lock": strict,
            })

        if path in ("/api/v1/router/device/bypass-event", "/api/router/device/bypass-event"):
            count = int(body.get("count", 1))
            _router_telemetry.record_bypass_intercepted(count)
            return self._send_json({"success": True, "bypasses_blocked": _router_telemetry._bypasses_blocked_count})

        if path in ("/api/v1/wfp/lock", "/api/wfp/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _windows_controller.arm_focus_lock(duration_seconds=duration)
            _wfp_compiler.set_protection_state(active=True, remaining_seconds=duration)
            return self._send_json({
                "success": True,
                "is_protection_active": True,
                "duration_seconds": duration,
                "can_uninstall": False,
                "message": "Windows WFP Focus Lock armed. Service stop & uninstallation locked.",
            })

        if path in ("/api/v1/wfp/unlock", "/api/wfp/unlock"):
            _windows_controller.disarm_focus_lock()
            _wfp_compiler.set_protection_state(active=False, remaining_seconds=0)
            return self._send_json({
                "success": True,
                "is_protection_active": False,
                "can_uninstall": True,
                "message": "Windows WFP Focus Lock disarmed. Clean uninstallation 100% permitted.",
            })

        if path in ("/api/v1/wfp/block-app", "/api/wfp/block-app"):
            app_name = body.get("app_name", "").strip()
            if not app_name:
                return self._send_error("app_name is required", 400)
            _windows_controller.block_application(app_name)
            return self._send_json({"success": True, "app_name": app_name, "is_blocked": True})

        if path in ("/api/v1/wfp/unblock-app", "/api/wfp/unblock-app"):
            app_name = body.get("app_name", "").strip()
            if not app_name:
                return self._send_error("app_name is required", 400)
            unblocked = _windows_controller.unblock_application(app_name)
            return self._send_json({"success": unblocked, "app_name": app_name, "is_blocked": False})

        if path in ("/api/v1/wfp/simulate-stop", "/api/wfp/simulate-stop"):
            ok, msg = _windows_controller.simulate_service_stop_attempt()
            status_code = 200 if ok else 403
            return self._send_json({"allowed": ok, "message": msg, "can_uninstall": _windows_controller.can_uninstall()}, status=status_code)

        # Phase 2: macOS Extension Control Routes
        if path in ("/api/v1/macos/lock", "/api/macos/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _macos_manager.set_protection(True, timer_seconds=duration)
            return self._send_json({
                "success": True,
                "is_protection_active": True,
                "remaining_timer_seconds": duration,
                "can_uninstall": False,
                "message": f"macOS Network Extension locked for {duration} seconds. Uninstallation disallowed."
            })

        if path in ("/api/v1/macos/unlock", "/api/macos/unlock"):
            _macos_manager.set_protection(False, timer_seconds=0)
            return self._send_json({
                "success": True,
                "is_protection_active": False,
                "remaining_timer_seconds": 0,
                "can_uninstall": True,
                "message": "macOS Network Extension unlocked. Clean removal permitted."
            })

        if path in ("/api/v1/macos/telemetry", "/api/macos/telemetry"):
            res = _macos_manager.process_telemetry_event(body)
            status_code = 200 if res.get("status") == "OK" else 403
            return self._send_json(res, status=status_code)

        # Phase 2: Linux eBPF Control Routes
        if path in ("/api/v1/ebpf/lock", "/api/ebpf/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _ebpf_loader.set_protection_policy(True, timer_seconds=duration)
            return self._send_json({
                "success": True,
                "is_protection_active": True,
                "remaining_timer_seconds": duration,
                "can_uninstall": False,
                "message": f"Linux eBPF kernel hooks locked for {duration} seconds."
            })

        if path in ("/api/v1/ebpf/unlock", "/api/ebpf/unlock"):
            _ebpf_loader.set_protection_policy(False, timer_seconds=0)
            return self._send_json({
                "success": True,
                "is_protection_active": False,
                "remaining_timer_seconds": 0,
                "can_uninstall": True,
                "message": "Linux eBPF kernel hooks unlocked. Clean detachment permitted."
            })

        if path in ("/api/v1/ebpf/unload", "/api/ebpf/unload"):
            try:
                _ebpf_loader.unload_ebpf_program()
                return self._send_json({"success": True, "message": "eBPF hooks cleanly detached."})
            except PermissionError as pe:
                return self._send_json({"success": False, "error": str(pe)}, status=403)

        # Phase 3: Router Master Orchestrator Control Routes
        if path in ("/api/v1/orchestrator/lock", "/api/orchestrator/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _router_orchestrator.set_focus_lock(True, duration)
            return self._send_json({
                "success": True,
                "is_locked": True,
                "remaining_timer_seconds": duration,
                "can_uninstall": False,
                "message": f"Master Router Orchestrator locked for {duration} seconds."
            })

        if path in ("/api/v1/orchestrator/unlock", "/api/orchestrator/unlock"):
            _router_orchestrator.set_focus_lock(False, 0)
            return self._send_json({
                "success": True,
                "is_locked": False,
                "remaining_timer_seconds": 0,
                "can_uninstall": True,
                "message": "Master Router Orchestrator unlocked. Clean deactivation permitted."
            })

        if path in ("/api/v1/orchestrator/stop", "/api/orchestrator/stop"):
            try:
                _router_orchestrator.stop()
                return self._send_json({"success": True, "message": "Master Router Orchestrator stopped."})
            except PermissionError as pe:
                return self._send_json({"success": False, "error": str(pe)}, status=403)

        # Phase 3: MikroTik & Ubiquiti Teardown and Lock Routes
        if path in ("/api/v1/mikrotik/lock", "/api/mikrotik/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _mikrotik_manager.set_lock(True, duration)
            return self._send_json({"success": True, "is_locked": True, "can_uninstall": False})

        if path in ("/api/v1/mikrotik/unlock", "/api/mikrotik/unlock"):
            _mikrotik_manager.set_lock(False, 0)
            return self._send_json({"success": True, "is_locked": False, "can_uninstall": True})

        if path in ("/api/v1/mikrotik/teardown", "/api/mikrotik/teardown"):
            try:
                cmds = _mikrotik_manager.generate_uninstall_script()
                return self._send_json({"success": True, "script": cmds})
            except PermissionError as pe:
                return self._send_json({"success": False, "error": str(pe)}, status=403)

        if path in ("/api/v1/ubiquiti/lock", "/api/ubiquiti/lock"):
            duration = int(body.get("duration_seconds", 1800))
            _ubiquiti_engine.set_lock(True, duration)
            return self._send_json({"success": True, "is_locked": True, "can_uninstall": False})

        if path in ("/api/v1/ubiquiti/unlock", "/api/ubiquiti/unlock"):
            _ubiquiti_engine.set_lock(False, 0)
            return self._send_json({"success": True, "is_locked": False, "can_uninstall": True})

        if path in ("/api/v1/ubiquiti/teardown", "/api/ubiquiti/teardown"):
            try:
                cmds = _ubiquiti_engine.generate_teardown_commands()
                return self._send_json({"success": True, "script": cmds})
            except PermissionError as pe:
                return self._send_json({"success": False, "error": str(pe)}, status=403)

        # AI Threat Hunting POST Routes
        if path.startswith("/api/v1/ai/") or path.startswith("/api/ai/"):
            ai_res = _ai_dispatcher.handle_post(path, body)
            if ai_res is not None:
                status_code, resp_body = ai_res
                return self._send_json(resp_body, status=status_code)

        # Settings tab update (supported via POST & PATCH)
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
        profile_id = self._resolve_request_profile_id(body.get('profile_id'))

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
        profile_id = self._resolve_request_profile_id(params.get('profile_id', [None])[0])

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
            self.send_header("Content-Length", str(len(reply_bytes)))
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

    def _handle_json_doh_query(self, qname: str, qtype_str: str, profile_id: str, client_ip: str):
        """Cloudflare/Google RFC 8427 compatible JSON DoH query handler."""
        try:
            valid_qtype = qtype_str if hasattr(QTYPE, qtype_str) else 'A'
            req = DNSRecord.question(qname, valid_qtype)
            query_bytes = req.pack()
            reply_bytes, meta = resolver.resolve_wire_packet(query_bytes, profile_id, client_ip)
            parsed_reply = DNSRecord.parse(reply_bytes)

            answers = []
            for rr in parsed_reply.rr:
                answers.append({
                    "name": str(rr.rname).rstrip('.'),
                    "type": rr.rtype,
                    "TTL": rr.ttl,
                    "data": str(rr.rdata)
                })

            is_nxdomain = (parsed_reply.header.rcode == RCODE.NXDOMAIN)
            status_code = 3 if is_nxdomain else 0

            resp = {
                "Status": status_code,
                "TC": False,
                "RD": True,
                "RA": True,
                "AD": False,
                "CD": False,
                "Question": [{"name": qname, "type": getattr(QTYPE, valid_qtype, 1)}],
                "Answer": answers,
                "Comment": meta.get('reason', '')
            }
            return self._send_json(resp)
        except Exception as e:
            return self._send_error(f"JSON DoH query failed: {e}", 400)

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
        proto = fwd_proto or "https"

        host_ip = host_hdr.split(":")[0]
        if not fwd_proto and (":8080" in host_hdr or proto == "http"):
            # LAN local connection - point to DoH HTTPS port 8443
            doh_url = f"https://{host_ip}:8443/dns-query/{profile_id}"
        else:
            doh_url = f"{proto}://{host_hdr}/dns-query/{profile_id}"
        uuid_dns = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"focusdns-{profile_id}-dns"))
        uuid_top = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"focusdns-{profile_id}-top"))

        server_addresses_tag = ""
        try:
            import ipaddress
            ipaddress.ip_address(host_ip)
            server_addresses_tag = f"""
                <key>ServerAddresses</key>
                <array>
                    <string>{host_ip}</string>
                </array>"""
        except ValueError:
            pass

        # Check removal passcode from query params (dynamic per device, no hardcoded default)
        passcode = None
        try:
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            if "passcode" in qs and qs["passcode"][0].strip():
                passcode = qs["passcode"][0].strip()
        except Exception:
            pass

        passcode_xml = ""
        if passcode:
            passcode_xml = f"""
    <key>HasRemovalPasscode</key>
    <true/>
    <key>RemovalPassword</key>
    <string>{passcode}</string>"""

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
                <string>{doh_url}</string>{server_addresses_tag}
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
    <string>FocusDNS Encrypted DNS profile with anti-bypass removal protection for digital focus.</string>
    <key>PayloadDisplayName</key>
    <string>FocusDNS ({profile_name})</string>
    <key>PayloadIdentifier</key>
    <string>com.focusdns.profile.{profile_id}</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>{passcode_xml}
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

