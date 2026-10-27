"""
FocusDNS Backend Automated Integration Tests - Cycle 4 Hardened
Tests:
- All 10 page-wise REST API endpoints with mandatory API token authentication
- Strict Mode enforcement across ALL mutating routes (security, privacy, rules, focus items)
- Negative security tests:
  * 401 Unauthorized on missing/invalid token
  * 415 Unsupported Media Type on non-JSON content type (cross-site simple request defense)
  * 404 Not Found on unknown profile_id
- RFC 1035 UDP DNS Resolution across query types (A, AAAA, MX, TXT, NXDOMAIN)
- RFC 8484 DNS-over-HTTPS (DoH) via GET and POST wire-format
"""

import base64
import json
import os
import socket
import sys
import time
import urllib.request
import urllib.error

# Ensure dnslib is available
SERVER_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VENV_PKGS = os.path.join(SERVER_DIR, "venv/lib/python3.14/site-packages")
if os.path.exists(VENV_PKGS) and VENV_PKGS not in sys.path:
    sys.path.insert(0, VENV_PKGS)
if SERVER_DIR not in sys.path:
    sys.path.insert(0, SERVER_DIR)

from dnslib import DNSRecord, QTYPE, RCODE

BASE_URL = "http://127.0.0.1:8080"
TOKEN = ""

def req_raw(method, path, data=None, headers=None):
    h = {'Content-Type': 'application/json', **(headers or {})}
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
            try:
                parsed = json.loads(content.decode('utf-8'))
            except Exception:
                parsed = content
            return resp.status, parsed
    except urllib.error.HTTPError as e:
        content = e.read()
        try:
            parsed = json.loads(content.decode('utf-8'))
        except Exception:
            parsed = content
        return e.code, parsed

def get(path, auth=True):
    h = {'X-Api-Key': TOKEN} if (auth and TOKEN) else {}
    st, b = req_raw('GET', path, headers=h)
    return b

def post(path, data, auth=True):
    h = {}
    if auth and TOKEN:
        h['X-Api-Key'] = TOKEN
    return req_raw('POST', path, data=data, headers=h)

def patch(path, data, auth=True):
    h = {}
    if auth and TOKEN:
        h['X-Api-Key'] = TOKEN
    return req_raw('PATCH', path, data=data, headers=h)

def delete(path, auth=True):
    h = {}
    if auth and TOKEN:
        h['X-Api-Key'] = TOKEN
    return req_raw('DELETE', path, headers=h)

def test_dns_udp(domain: str, qtype: str = 'A') -> DNSRecord:
    """Sends a real RFC 1035 UDP query to 127.0.0.1:5354 and returns the parsed DNSRecord."""
    req = DNSRecord.question(domain, qtype)
    packet = req.pack()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3.0)
    sock.sendto(packet, ('127.0.0.1', 5354))
    data, _ = sock.recvfrom(4096)
    return DNSRecord.parse(data)

def test_doh_post(domain: str, qtype: str = 'A', profile_id: str = 'a1b2c3', token: str = '') -> DNSRecord:
    """Sends an RFC 8484 DoH POST wire-format query to http://127.0.0.1:8080/dns-query."""
    req = DNSRecord.question(domain, qtype)
    req_bytes = req.pack()

    tok = token if token != '' else TOKEN
    h = {'Content-Type': 'application/dns-message', 'Accept': 'application/dns-message'}
    if tok:
        h['X-Api-Key'] = tok

    http_req = urllib.request.Request(
        f"{BASE_URL}/dns-query?profile_id={profile_id}",
        data=req_bytes,
        headers=h,
        method='POST'
    )
    with urllib.request.urlopen(http_req) as resp:
        assert resp.headers.get('Content-Type') == 'application/dns-message'
        resp_bytes = resp.read()
        return DNSRecord.parse(resp_bytes)

def test_doh_get(domain: str, qtype: str = 'A', profile_id: str = 'a1b2c3', token: str = '') -> DNSRecord:
    """Sends an RFC 8484 DoH GET base64url query to http://127.0.0.1:8080/dns-query?dns=..."""
    req = DNSRecord.question(domain, qtype)
    req_b64 = base64.urlsafe_b64encode(req.pack()).decode('ascii').rstrip('=')

    tok = token if token != '' else TOKEN
    h = {'Accept': 'application/dns-message'}
    if tok:
        h['X-Api-Key'] = tok

    http_req = urllib.request.Request(
        f"{BASE_URL}/dns-query?dns={req_b64}&profile_id={profile_id}",
        headers=h
    )
    with urllib.request.urlopen(http_req) as resp:
        assert resp.headers.get('Content-Type') == 'application/dns-message'
        resp_bytes = resp.read()
        return DNSRecord.parse(resp_bytes)

def run_tests():
    global TOKEN
    print("=" * 60)
    print("🚀 Running FocusDNS End-to-End Hardened Verification Suite")
    print("=" * 60)

    # Ensure profile strict mode is clear before starting
    try:
        import db
        conn = db.get_connection()
        conn.execute("UPDATE profiles SET is_strict_mode = 0, strict_until = NULL WHERE profile_id = 'a1b2c3'")
        conn.commit()
        conn.close()
        db.invalidate_cache('a1b2c3')
    except Exception:
        pass

    # 1. Healthcheck (Unauthenticated)
    res = get("/health", auth=False)
    assert res['status'] == 'healthy', "Health check failed"
    assert res.get('doh_rfc8484') is True, "DoH RFC 8484 should be active"
    print("✅ 1. Healthcheck endpoint verified (DoH RFC 8484 enabled)")

    # 2. Negative Security Tests:
    # A. Unauthenticated request without token -> MUST return 401 Unauthorized
    st, err = req_raw('GET', '/api/profile')
    assert st == 401, f"Expected 401 Unauthorized without token, got {st}"
    print("✅ 2a. Negative test passed: Missing API token returns HTTP 401 Unauthorized")

    # B. Non-JSON Content-Type (e.g. text/plain simple request) -> MUST return 415 Unsupported Media Type
    st, err = req_raw('POST', '/api/denylist', data='domain=malicious.com', headers={'Content-Type': 'text/plain'})
    assert st == 401 or st == 415, f"Expected 401 or 415, got {st}"
    print("✅ 2b. Negative test passed: Simple cross-site text/plain requests rejected")

    # Obtain Local Bootstrap Token
    st, tok_res = req_raw('GET', '/api/auth/token')
    assert st == 200 and 'token' in tok_res, "Failed to retrieve local auth token"
    TOKEN = tok_res['token']
    print(f"✅ 2c. Bootstrap API token retrieved ({TOKEN[:8]}...)")

    # C. Authenticated request with non-JSON Content-Type -> MUST return 415
    st, err = req_raw('POST', '/api/denylist', data='domain=malicious.com', headers={'Content-Type': 'text/plain', 'X-Api-Key': TOKEN})
    assert st == 415, f"Expected 415 Unsupported Media Type, got {st}"
    print("✅ 2d. Negative test passed: Authenticated text/plain POST rejected with HTTP 415")

    # D. Removed PIN endpoint must be gone
    st, _ = post("/api/profile/verify-pin", {"pin": "1234"})
    assert st == 404, f"Expected 404 on removed verify-pin endpoint, got {st}"
    print("✅ 2e. Negative test passed: /api/profile/verify-pin no longer exists")

    # E. Unknown profile_id check -> MUST return 404
    st, not_found_res = req_raw('GET', '/api/profile?profile_id=unknown999', headers={'X-Api-Key': TOKEN})
    assert st == 404, f"Expected 404 on unknown profile_id, got {st}"
    print("✅ 2f. Negative test passed: Unknown profile_id returns HTTP 404 Not Found")

    # 3. Page 1: Home Dashboard & Timed Strict Mode Barrier
    res = get("/api/profile")
    assert 'profile' in res
    print("✅ 3. Page 1 [GET /api/profile] verified")

    # Enable timed Strict Mode (a stray 'pin' key must be ignored)
    status, res = post("/api/profile/strict-mode", {"is_strict": True, "duration_minutes": 30, "pin": "1234"})
    assert status == 200 and res['is_strict_mode'] is True
    # Unlocking before expiry must fail (PIN key ignored)
    status, _ = post("/api/profile/strict-mode", {"is_strict": False, "pin": "1234"})
    assert status == 403, f"Expected 403 unlocking before expiry, got {status}"
    # Re-enabling with a new duration while locked must also fail (no shortening/overwrite)
    status, _ = post("/api/profile/strict-mode", {"is_strict": True, "duration_minutes": 1})
    assert status == 403, f"Expected 403 overwriting active timer, got {status}"
    print("✅ 3. Page 1 [POST /api/profile/strict-mode] timed Strict Mode enabled")

    # Strict Mode Barrier Checks:
    # A. Attempt to turn OFF protection during timer -> 403
    status, _ = post("/api/profile/toggle-protection", {"is_on": False})
    assert status == 403, f"Expected 403, got {status}"

    # B. Attempt to disable security setting during timer -> 403
    status, _ = patch("/api/security", {"feature": "threat_intel", "value": False})
    assert status == 403, f"Expected 403, got {status}"

    # C. Attempt to disable privacy setting during timer -> 403
    status, _ = patch("/api/privacy", {"feature": "disguised_trackers", "value": False})
    assert status == 403, f"Expected 403, got {status}"

    # D. Attempt to add to allowlist during timer -> 403
    status, _ = post("/api/allowlist", {"domain": "bypass-filter.com"})
    assert status == 403, f"Expected 403, got {status}"

    # E. Attempt to remove from denylist during timer -> 403
    status, _ = delete("/api/denylist/bad-tracker.com")
    assert status == 403, f"Expected 403, got {status}"

    # F. Attempt to remove from deep focus during timer -> 403
    status, _ = delete("/api/deep-focus/reddit")
    assert status == 403, f"Expected 403, got {status}"

    # G. Attempt to change log retention during timer -> 403
    status, _ = patch("/api/settings", {"log_retention": "1 hour"})
    assert status == 403, f"Expected 403, got {status}"
    print("✅ 3. Strict Mode Ironclad Barrier verified across all 7 mutating routes (HTTP 403)")

    # Simulate timer expiration, then Strict Mode is released
    import db
    conn = db.get_connection()
    conn.execute("UPDATE profiles SET strict_until = ? WHERE profile_id = 'a1b2c3'", (time.time() - 2,))
    conn.commit()
    conn.close()
    db.invalidate_cache('a1b2c3')
    status, res = post("/api/profile/strict-mode", {"is_strict": False})
    assert status == 200 and res['is_strict_mode'] is False
    print("✅ 3. Strict Mode released after timer expiry")

    # 4. Page 2: Setup Tab & IP Discovery
    ip_res = get("/api/ip", auth=False)
    assert ip_res.get('success') is True and 'ip' in ip_res
    print("✅ 4a. IP echo discovery endpoint [/api/ip] verified:", ip_res['ip'])

    res = get("/api/setup")
    assert res['profile_id'] == 'a1b2c3'
    assert 'client_ip' in res and 'doh_endpoint' in res and 'dot_endpoint' in res
    assert len(res['ipv4_endpoints']) >= 2 and len(res['ipv6_endpoints']) >= 2

    status, res = post("/api/setup/link-ip", {"ip": "198.51.100.42"})
    assert status == 200 and res['linked_ip'] == "198.51.100.42"

    # Auto-link client IP without passing explicit IP
    status, res = post("/api/setup/link-ip", {})
    assert status == 200 and res['linked_ip'] in ("127.0.0.1", ip_res['ip'])
    print("✅ 4b. Page 2 [Setup Tab GET & dynamic link-ip] verified")

    # 5. Page 3: Security Tab
    res = get("/api/security")
    assert 'threat_intel' in res['security']
    status, _ = patch("/api/security", {"feature": "ai_threat", "value": True})
    assert status == 200
    res_updated = get("/api/security")
    assert res_updated['security']['ai_threat'] is True
    patch("/api/security", {"feature": "ai_threat", "value": False})
    print("✅ 5. Page 3 [Security Tab GET/PATCH] verified")

    # 6. Page 4: Privacy Tab
    res = get("/api/privacy")
    assert 'disguised_trackers' in res['privacy']
    status, _ = patch("/api/privacy", {"feature": "affiliate_links", "value": True})
    assert status == 200
    patch("/api/privacy", {"feature": "affiliate_links", "value": False})
    print("✅ 6. Page 4 [Privacy Tab GET/PATCH] verified")

    # 7. Page 5: Deep Focus Tab
    status, _ = post("/api/deep-focus", {"type": "website", "id": "testapp", "name": "TestApp", "icon": "T", "color": "#00FF00"})
    assert status == 200
    res = get("/api/deep-focus")
    assert any(w['name'] == 'TestApp' for w in res['websites'])
    status, _ = delete("/api/deep-focus/testapp")
    assert status == 200
    res_after = get("/api/deep-focus")
    assert not any(w['name'] == 'TestApp' for w in res_after['websites'])
    print("✅ 7. Page 5 [Deep Focus Tab GET/POST/DELETE] verified")

    # 8. Page 6: Denylist Tab
    status, _ = post("/api/denylist", {"domain": "bad-tracker.com"})
    assert status == 200
    res = get("/api/denylist")
    assert "bad-tracker.com" in res['denylist']
    status, _ = delete("/api/denylist/bad-tracker.com")
    assert status == 200
    print("✅ 8. Page 6 [Denylist Tab GET/POST/DELETE] verified")

    # 9. Page 7: Allowlist Tab
    status, _ = post("/api/allowlist", {"domain": "my-special-site.org"})
    assert status == 200
    res = get("/api/allowlist")
    assert "my-special-site.org" in res['allowlist']
    status, _ = delete("/api/allowlist/my-special-site.org")
    assert status == 200
    print("✅ 9. Page 7 [Allowlist Tab GET/POST/DELETE] verified")

    # 10. Page 8: Analytics Tab
    res = get("/api/analytics?period=7d")
    assert 'total_queries' in res and 'blocked_queries' in res
    print("✅ 10. Page 8 [Analytics Tab GET] verified")

    # 11. Page 9: Logs Tab
    res = get("/api/logs?limit=5")
    assert 'logs' in res
    print("✅ 11. Page 9 [Logs Tab GET] verified")

    # 12. Page 10: Settings Tab
    res = get("/api/settings")
    assert 'profile_name' in res
    status, _ = patch("/api/settings", {"profile_name": "My Master Focus Profile", "log_retention": "1 week"})
    assert status == 200
    res_up = get("/api/settings")
    assert res_up['profile_name'] == "My Master Focus Profile"
    patch("/api/settings", {"profile_name": "My First Profile", "log_retention": "1 month"})
    print("✅ 12. Page 10 [Settings Tab GET/PATCH] verified")

    # 13. Simulator API (POST /api/query/resolve)
    _, res_reddit = post("/api/query/resolve", {"domain": "reddit.com"})
    assert res_reddit['status'] == 'blocked' and res_reddit['rcode'] == 'NXDOMAIN'
    print("✅ 13. Simulator API [reddit.com -> NXDOMAIN BLOCKED] verified")

    _, res_google = post("/api/query/resolve", {"domain": "google.com"})
    assert res_google['status'] == 'allowed' and res_google['rcode'] == 'NOERROR' and res_google['ip'] != '0.0.0.0'
    print(f"✅ 13. Simulator API [google.com -> {res_google['ip']} NOERROR ALLOWED] verified")

    # 14. Live RFC 1035 UDP DNS Server (UDP Port 5354)
    rec_blocked = test_dns_udp("reddit.com", "A")
    assert rec_blocked.header.rcode == RCODE.NXDOMAIN, f"Expected NXDOMAIN, got {rec_blocked.header.rcode}"
    assert len(rec_blocked.rr) == 0, "NXDOMAIN should have 0 answers"
    print("✅ 14. Live RFC 1035 UDP DNS Server [reddit.com -> NXDOMAIN RCODE 3] verified")

    rec_allowed = test_dns_udp("google.com", "A")
    assert rec_allowed.header.rcode == RCODE.NOERROR, f"Expected NOERROR, got {rec_allowed.header.rcode}"
    assert len(rec_allowed.rr) > 0, "Allowed domain should return answers"
    print(f"✅ 14. Live RFC 1035 UDP DNS Server [google.com -> {rec_allowed.rr[0].rdata} NOERROR] verified")

    # 15. Live RFC 1035 Multi-Type DNS Lookups (AAAA, MX, Nonexistent NXDOMAIN)
    rec_aaaa = test_dns_udp("google.com", "AAAA")
    assert rec_aaaa.header.rcode == RCODE.NOERROR and len(rec_aaaa.rr) > 0
    print(f"✅ 15. Live UDP DNS Multi-Type [google.com AAAA -> {rec_aaaa.rr[0].rdata} NOERROR] verified")

    rec_mx = test_dns_udp("gmail.com", "MX")
    assert rec_mx.header.rcode == RCODE.NOERROR and len(rec_mx.rr) > 0
    print(f"✅ 15. Live UDP DNS Multi-Type [gmail.com MX -> {len(rec_mx.rr)} records NOERROR] verified")

    rec_nx = test_dns_udp("this-does-not-exist-zzqq-test-focusdns.com", "A")
    assert rec_nx.header.rcode == RCODE.NXDOMAIN
    print("✅ 15. Live UDP Nonexistent Domain [NXDOMAIN RCODE 3, not SERVFAIL] verified")

    # 16. Live RFC 8484 DNS-over-HTTPS (DoH) via GET & POST
    doh_blocked = test_doh_post("reddit.com", "A")
    assert doh_blocked.header.rcode == RCODE.NXDOMAIN, "DoH POST should return NXDOMAIN"
    print("✅ 16. Live RFC 8484 DoH POST wire-format [reddit.com -> NXDOMAIN] verified")

    doh_allowed_get = test_doh_get("google.com", "A")
    assert doh_allowed_get.header.rcode == RCODE.NOERROR, "DoH GET should return NOERROR"
    assert len(doh_allowed_get.rr) > 0, "DoH GET should return RR answers"
    print(f"✅ 16. Live RFC 8484 DoH GET base64url [google.com -> {doh_allowed_get.rr[0].rdata} NOERROR] verified")

    doh_txt = test_doh_post("google.com", "TXT")
    assert doh_txt.header.rcode == RCODE.NOERROR and len(doh_txt.rr) > 0
    print(f"✅ 16. Live RFC 8484 DoH Wire Multi-Type [google.com TXT -> {len(doh_txt.rr)} records] verified")

    # 17. Authenticated & Multi-Profile DoH
    doh_auth = test_doh_post("google.com", "A", profile_id="a1b2c3", token=TOKEN)
    assert doh_auth.header.rcode == RCODE.NOERROR and len(doh_auth.rr) > 0
    print("✅ 17. DoH Multi-Profile & Token Authentication [?profile_id=a1b2c3 + X-Api-Key] verified")

    # Negative test: DoH with missing token -> 401 Unauthorized
    req = DNSRecord.question("google.com", "A")
    st, _ = req_raw('POST', '/dns-query?profile_id=a1b2c3', data=req.pack(), headers={'Content-Type': 'application/dns-message'})
    assert st == 401, f"Expected 401 Unauthorized on missing DoH token, got {st}"
    print("✅ 17. Negative test passed: DoH rejects missing API token with HTTP 401")

    # Negative test: DoH with invalid token -> 401 Unauthorized
    st, _ = req_raw('POST', '/dns-query?profile_id=a1b2c3', data=req.pack(), headers={'Content-Type': 'application/dns-message', 'X-Api-Key': 'invalid_token'})
    assert st == 401, f"Expected 401 Unauthorized on invalid DoH token, got {st}"
    print("✅ 17. Negative test passed: DoH rejects invalid API token with HTTP 401")

    # Negative test: DoH with token in query param -> MUST return 401 (query string tokens forbidden)
    st, doh_qp_body = req_raw('POST', f'/dns-query?profile_id=a1b2c3&token={TOKEN}', data=req.pack(), headers={'Content-Type': 'application/dns-message'})
    assert st == 401, f"Expected 401 Unauthorized with query string token, got {st}"
    print("✅ 17. Negative test passed: DoH rejects ?token=<token> in URL (header-only auth enforced)")

    # 18. App Package Mapping Endpoint (GET /api/app-packages)
    res_pkg = get("/api/app-packages")
    assert res_pkg.get("success") is True, "Expected success: True from /api/app-packages"
    packages = res_pkg.get("packages", {})
    assert "com.reddit.frontpage" in packages.get("reddit", []), "Reddit package must be present"
    assert "com.google.android.youtube" in packages.get("youtube", []), "YouTube package must be present"
    print("✅ 18. GET /api/app-packages verified: Android package mappings returned for Accessibility Blocker")

    # 19. Timed Strict Mode (Mutation Lock, & Auto-Expiration)
    st_timed, res_timed = post("/api/profile/strict-mode", {"is_strict": True, "duration_minutes": 15})
    assert st_timed == 200, f"Expected 200 on timed strict mode, got {st_timed}"
    assert res_timed.get("is_strict_mode") is True
    assert res_timed.get("strict_until") is not None
    assert res_timed.get("remaining_seconds", 0) > 0

    # Mutations must be locked during timer
    st_mut, _ = post("/api/profile/toggle-protection", {"is_on": False})
    assert st_mut == 403, f"Expected 403 during active timed strict mode, got {st_mut}"
    st_dis, _ = post("/api/profile/strict-mode", {"is_strict": False})
    assert st_dis == 403, f"Expected 403 when trying to disable active timed strict mode, got {st_dis}"

    # Simulate timer expiration by setting strict_until to the past
    conn = db.get_connection()
    conn.execute("UPDATE profiles SET strict_until = ? WHERE profile_id = 'a1b2c3'", (time.time() - 2,))
    conn.commit()
    conn.close()
    db.invalidate_cache('a1b2c3')

    # Now verify expiration auto-clears strict mode
    prof_exp = get("/api/profile")
    assert prof_exp['profile']['is_strict_mode'] == 0, "Strict Mode must auto-expire when strict_until passes"
    assert prof_exp['profile']['strict_until'] is None
    assert prof_exp['profile']['remaining_seconds'] == 0

    # Mutations are now permitted
    st_mut_ok, _ = post("/api/profile/toggle-protection", {"is_on": True})
    assert st_mut_ok == 200, f"Expected 200 after expiration, got {st_mut_ok}"
    print("✅ 19. Timed Strict Mode verified: activation, mutation lock, and auto-expiration")

    print("\n" + "=" * 60)
    print("🎉 ALL 19 TEST SUITES PASSED FLAWLESSLY WITH AUTH & PROTOCOLS!")
    print("=" * 60)

if __name__ == '__main__':
    run_tests()
