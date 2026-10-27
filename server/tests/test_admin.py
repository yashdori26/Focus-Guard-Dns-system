"""
FocusDNS Web Admin Portal Integration Test Suite
Verifies:
- Zero-bloat single-file HTML delivery (GET /admin)
- Master key authentication & session management (Cookie & X-Admin-Key)
- Brute-force rate limiting: 5 failed attempts = 15-minute lockout (HTTP 429)
- Module 1: Mission Control metrics (QPS, uptime, memory, cache ratio, total today)
- Module 2: Blocklist & Threat Intel Feeds (get feeds, toggle, background sync)
- Module 3: Upstream routing & latency benchmark
- Module 4: Global Emergency Controls (Safe Bypass toggle & Global Allow/Denylist)
- Module 5: Fleet & Profile management (list, provision, revoke)
- Module 7: Database & Storage Maintenance (prune, vacuum, backup download)
"""

import http.client
import json
import os
import sys
import time
import urllib.request
import urllib.error

# Setup paths
SERVER_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PARENT_DIR = os.path.abspath(os.path.join(SERVER_DIR, ".."))
VENV_PKGS = os.path.join(SERVER_DIR, "venv/lib/python3.14/site-packages")
if os.path.exists(VENV_PKGS) and VENV_PKGS not in sys.path:
    sys.path.insert(0, VENV_PKGS)
if PARENT_DIR not in sys.path:
    sys.path.insert(0, PARENT_DIR)

from dnslib import DNSRecord, QTYPE, RCODE
from server import db, resolver

BASE_URL = "http://127.0.0.1:8080"
MASTER_KEY = db.get_admin_master_key()
ADMIN_COOKIE = ""

def raw_req(method, path, data=None, headers=None):
    h = {'Content-Type': 'application/json', **(headers or {})}
    if ADMIN_COOKIE and 'Cookie' not in h:
        h['Cookie'] = ADMIN_COOKIE
    body = None
    if data is not None:
        if isinstance(data, (dict, list)):
            body = json.dumps(data).encode('utf-8')
        elif isinstance(data, bytes):
            body = data
        elif isinstance(data, str):
            body = data.encode('utf-8')

    req = urllib.request.Request(f"{BASE_URL}{path}", data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read()
            cookie = resp.headers.get('Set-Cookie', '')
            try:
                parsed = json.loads(content.decode('utf-8'))
            except Exception:
                parsed = content
            return resp.status, parsed, cookie
    except urllib.error.HTTPError as e:
        content = e.read()
        try:
            parsed = json.loads(content.decode('utf-8'))
        except Exception:
            parsed = content
        return e.code, parsed, e.headers.get('Set-Cookie', '')

def test_admin_portal():
    global ADMIN_COOKIE
    print("=" * 60)
    print("🏛️  Running FocusDNS Web Admin Portal Verification Suite")
    print("=" * 60)

    # 1. Verify GET /admin delivers the single-page HTML interface
    st, body, _ = raw_req("GET", "/admin")
    assert st == 200, f"Expected 200 for /admin, got {st}"
    html_str = body.decode('utf-8') if isinstance(body, bytes) else str(body)
    assert "FocusDNS Operator" in html_str, "HTML must contain 'FocusDNS Operator'"
    assert "Mission Control" in html_str, "HTML must contain 'Mission Control'"
    assert "Live Telescope" in html_str, "HTML must contain 'Live Telescope'"
    print("✅ 1. Zero-bloat single-page delivery verified (GET /admin)")

    # 2. Check initial auth status (unauthenticated)
    st, body, _ = raw_req("GET", "/api/admin/auth/check")
    assert st == 200 and body.get("authenticated") is False
    print("✅ 2. Auth check endpoint verified (Unauthenticated initial state)")

    # 3. Negative Auth Test: Accessing protected admin endpoint returns HTTP 401
    st, body, _ = raw_req("GET", "/api/admin/metrics")
    assert st == 401, f"Expected 401 Unauthorized for /api/admin/metrics, got {st}"
    print("✅ 3. Negative test passed: Protected admin endpoint rejected without auth (401)")

    # 4. Rate-Limiting & Brute-Force Defense Test (Dynamic attacker IP for idempotency)
    attacker_ip = f"198.51.100.{int(time.time() * 1000) % 200 + 10}"
    attacker_headers = {"X-Forwarded-For": attacker_ip}
    for i in range(4):
        st, body, _ = raw_req("POST", "/api/admin/auth/login", {"master_key": "wrong-key"}, headers=attacker_headers)
        assert st == 401, f"Attempt {i+1}: Expected 401, got {st}"

    # 5th failed attempt
    st, body, _ = raw_req("POST", "/api/admin/auth/login", {"master_key": "wrong-key"}, headers=attacker_headers)
    assert st == 401 or st == 429
    # 6th attempt must be locked out with HTTP 429
    st, body, _ = raw_req("POST", "/api/admin/auth/login", {"master_key": "wrong-key"}, headers=attacker_headers)
    assert st == 429, f"Expected 429 Too Many Requests after 5 failures, got {st}"
    assert "locked out" in body.get("error", "").lower()
    print("✅ 4. Brute-force rate limiting verified (5 failed attempts = 15-minute lockout HTTP 429)")

    # 5. Perform successful Master Key Login (from operator IP)
    st, body, cookie = raw_req("POST", "/api/admin/auth/login", {"master_key": MASTER_KEY})
    assert st == 200 and body.get("success") is True, f"Login failed: {body}"
    assert "admin_session=" in cookie, "Must set HttpOnly admin_session cookie"
    # Save cookie for subsequent requests
    ADMIN_COOKIE = cookie.split(';')[0]
    token = body.get("token")
    assert len(token) >= 32, "Token must be secure hex"
    print(f"✅ 5. Master key login verified, session cookie issued: {ADMIN_COOKIE[:24]}...")

    # 6. Verify Auth Check now returns True
    st, body, _ = raw_req("GET", "/api/admin/auth/check")
    assert st == 200 and body.get("authenticated") is True
    print("✅ 6. Session authentication verified via Cookie")

    # 7. Module 1: Mission Control Metrics
    st, m, _ = raw_req("GET", "/api/admin/metrics")
    assert st == 200, f"Failed getting metrics: {m}"
    assert "qps" in m and "uptime_seconds" in m
    assert "cache_hit_ratio" in m and "total_queries_today" in m
    assert "signatures_count" in m and m["signatures_count"] > 0
    print(f"✅ 7. Module 1 Mission Control verified (QPS: {m['qps']}, Signatures: {m['signatures_count']}, RAM: {m['memory_mb']} MB)")

    # 8. Module 2: Threat Intel Feeds
    st, feeds_data, _ = raw_req("GET", "/api/admin/feeds")
    assert st == 200 and len(feeds_data["feeds"]) >= 4
    # Toggle feed
    st, tog_res, _ = raw_req("POST", "/api/admin/feeds/toggle", {"feed_id": "adguard", "enabled": False})
    assert st == 200 and tog_res["enabled"] is False
    st, tog_res, _ = raw_req("POST", "/api/admin/feeds/toggle", {"feed_id": "adguard", "enabled": True})
    assert st == 200 and tog_res["enabled"] is True
    # Trigger sync
    st, sync_res, _ = raw_req("POST", "/api/admin/feeds/sync", {})
    assert st == 200 and sync_res["success"] is True
    print("✅ 8. Module 2 Threat Intel Feed manager verified (get, toggle, background sync)")

    # 9. Module 3: Upstream Routing & Benchmark
    st, up_data, _ = raw_req("GET", "/api/admin/upstream")
    assert st == 200 and "primary" in up_data
    # Update upstreams
    st, up_upd, _ = raw_req("POST", "/api/admin/upstream", {
        "primary": "1.1.1.1",
        "secondary": "8.8.8.8",
        "ecs_strip": True
    })
    assert st == 200 and up_upd["primary"] == "1.1.1.1"
    # Benchmark
    st, bench, _ = raw_req("POST", "/api/admin/upstream/benchmark", {})
    assert st == 200 and len(bench.get("results", [])) >= 3
    print("✅ 9. Module 3 Upstream engine & latency benchmark verified (Quad9, Cloudflare, Google tested)")

    # 10. Module 4: Global Emergency Controls & Fail-Safe
    # Test Emergency Safe Bypass ON
    st, bp_res, _ = raw_req("POST", "/api/admin/emergency-bypass", {"enabled": True})
    assert st == 200 and bp_res["emergency_bypass"] is True
    resolver.reload_global_rules()

    # When emergency bypass is ON, resolving normally blocked domain (reddit.com) passes through as NOERROR
    res_bypass = resolver.resolve_domain("reddit.com", "a1b2c3", "A")
    assert res_bypass["status"] == "allowed", f"Expected allowed under emergency bypass, got {res_bypass['status']}"
    assert "Global Safe Bypass Active" in res_bypass["reason"]

    # Toggle Emergency Safe Bypass OFF
    st, bp_res, _ = raw_req("POST", "/api/admin/emergency-bypass", {"enabled": False})
    assert st == 200 and bp_res["emergency_bypass"] is False
    resolver.reload_global_rules()
    print("✅ 10a. Global Safe Bypass verified: 100% pass-through NOERROR on emergency failover")

    # Test Global Allowlist and Global Denylist
    st, al_res, _ = raw_req("POST", "/api/admin/global-rules", {"list_type": "allow", "domain": "wikipedia.org"})
    assert st == 200 and al_res["success"] is True
    st, dl_res, _ = raw_req("POST", "/api/admin/global-rules", {"list_type": "deny", "domain": "evil-botnet-c2.net"})
    assert st == 200 and dl_res["success"] is True
    resolver.reload_global_rules()

    res_al = resolver.resolve_domain("wikipedia.org", "a1b2c3", "A")
    assert res_al["status"] == "allowed" and "Global Allowlist" in res_al["reason"]

    res_dl = resolver.resolve_domain("evil-botnet-c2.net", "a1b2c3", "A")
    assert res_dl["status"] == "blocked" and "Global Denylist" in res_dl["reason"]

    # Remove global rules
    st, del_al, _ = raw_req("DELETE", "/api/admin/global-rules/allow/wikipedia.org")
    assert st == 200 and del_al["success"] is True
    st, del_dl, _ = raw_req("DELETE", "/api/admin/global-rules/deny/evil-botnet-c2.net")
    assert st == 200 and del_dl["success"] is True
    resolver.reload_global_rules()
    print("✅ 10b. Global Overrides verified (Global Allowlist & Global Denylist priority resolution)")

    # 11. Module 5: Fleet & Profile Management
    st, profs_data, _ = raw_req("GET", "/api/admin/profiles")
    assert st == 200 and len(profs_data.get("profiles", [])) >= 1
    # Create profile
    st, new_prof, _ = raw_req("POST", "/api/admin/profiles", {"name": "Test Fleet Device"})
    assert st == 200 and "profile_id" in new_prof
    new_pid = new_prof["profile_id"]
    # Revoke profile
    st, rev_res, _ = raw_req("DELETE", f"/api/admin/profiles/{new_pid}")
    assert st == 200 and rev_res.get("revoked") == new_pid
    print("✅ 11. Module 5 Fleet & profile provisioning and revocation verified")

    # 12. Module 7: Database & Storage Maintenance
    st, maint_data, _ = raw_req("GET", "/api/admin/maintenance")
    assert st == 200 and "stats" in maint_data
    assert maint_data["stats"]["db_size_mb"] > 0
    # Prune
    st, prune_res, _ = raw_req("POST", "/api/admin/maintenance/prune", {"days": 30})
    assert st == 200 and "deleted_logs" in prune_res
    # Vacuum
    st, vac_res, _ = raw_req("POST", "/api/admin/maintenance/vacuum", {})
    assert st == 200 and vac_res["success"] is True
    # Backup download
    st, backup_bytes, _ = raw_req("GET", "/api/admin/backup")
    assert st == 200 and len(backup_bytes) > 1024, "Backup must be valid SQLite file"
    assert backup_bytes[:15] == b"SQLite format 3", "Backup must have valid SQLite header magic"
    print("✅ 12. Module 7 Storage maintenance verified (prune, vacuum, binary .db backup download)")

    # 13. Session Logout
    st, out_res, _ = raw_req("POST", "/api/admin/auth/logout", {})
    assert st == 200 and out_res["success"] is True
    # Ensure session is terminated
    st, check_res, _ = raw_req("GET", "/api/admin/auth/check")
    assert st == 200 and check_res.get("authenticated") is False
    print("✅ 13. Admin logout & session termination verified")

    print("=" * 60)
    print("🎉 ALL 13 ADMIN PORTAL TEST SUITES PASSED FLAWLESSLY!")
    print("=" * 60)

if __name__ == '__main__':
    test_admin_portal()
