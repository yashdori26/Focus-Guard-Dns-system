"""
Comprehensive Account & Settings Audit for FocusDNS
Tests:
1. HTTP Login for yashdori26@gmail.com with YashDori
2. Session Token & Profile Binding Verification (Profile ID dce22d, Profile Name Yash, is_email_verified True)
3. Reading all Profile, Security, Privacy, and Deep Focus settings via REST API
4. Testing mutations (toggling settings, adding/removing custom rules)
5. Zero-Leak DNS query resolution verification for profile dce22d across all categories and apps
"""

import json
import urllib.request
import urllib.error
import sys

BASE_URL = "http://127.0.0.1:8080"
EMAIL = "yashdori26@gmail.com"
PASSWORD = "YashDori"

def post_json(path, data, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{BASE_URL}{path}", data=json.dumps(data).encode("utf-8"), headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))

def get_json(path, token=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{BASE_URL}{path}", headers=headers)
    with urllib.request.urlopen(req) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))

def patch_json(path, data, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{BASE_URL}{path}", data=json.dumps(data).encode("utf-8"), headers=headers, method="PATCH")
    with urllib.request.urlopen(req) as resp:
        return resp.status, json.loads(resp.read().decode("utf-8"))

def main():
    print("============================================================")
    print("   FOCUS-DNS ACCOUNT & SETTINGS AUDIT FOR YASH")
    print("============================================================")
    
    # 1. Login
    print("\n[Step 1] Logging into account via POST /api/auth/email/login...")
    status, login_res = post_json("/api/auth/email/login", {"email": EMAIL, "password": PASSWORD})
    assert status == 200, f"Login failed: status {status}"
    assert login_res["success"], "Login success flag is false"
    assert login_res["email"] == EMAIL, f"Email mismatch: {login_res['email']}"
    assert login_res["profile_name"] == "Yash", f"Profile name mismatch: {login_res['profile_name']}"
    assert login_res["is_email_verified"] is True, f"Email verified mismatch: {login_res['is_email_verified']}"
    
    token = login_res["token"]
    pid = login_res["profile_id"]
    print(f"  ✓ Login successful!")
    print(f"  ✓ Active Profile Name: {login_res['profile_name']}")
    print(f"  ✓ Active Profile ID:   {pid}")
    print(f"  ✓ Email Verified:      {login_res['is_email_verified']}")
    print(f"  ✓ Session Token:       {token[:20]}...")

    # 2. Check Profile Dashboard (/api/profile)
    print("\n[Step 2] Auditing Profile Dashboard via GET /api/profile...")
    status, prof_res = get_json("/api/profile", token=token)
    assert status == 200 and prof_res["success"]
    p = prof_res["profile"]
    print(f"  ✓ Profile Name:        {p['name']}")
    print(f"  ✓ Protection Active:   {bool(p['is_protection_on'])}")
    print(f"  ✓ Strict Mode:         {bool(p['is_strict_mode'])}")
    print(f"  ✓ Log Retention:       {p['log_retention']}")

    # 3. Check Security Settings (/api/security)
    print("\n[Step 3] Auditing Security Settings via GET /api/security...")
    status, sec_res = get_json("/api/security", token=token)
    assert status == 200 and sec_res["success"]
    sec = sec_res["security"]
    for k, v in sec.items():
        print(f"  ✓ {k:22}: {v}")
    assert sec["safesearch"] is True, "SafeSearch should be True"
    assert sec["threat_intel"] is True, "Threat Intel should be True"

    # 4. Check Privacy Settings (/api/privacy)
    print("\n[Step 4] Auditing Privacy Settings via GET /api/privacy...")
    status, priv_res = get_json("/api/privacy", token=token)
    assert status == 200 and priv_res["success"]
    priv = priv_res["privacy"]
    for k, v in priv.items():
        print(f"  ✓ {k:22}: {v}")
    assert priv["disguised_trackers"] is True

    # 5. Check Deep Focus Items (/api/deep-focus)
    print("\n[Step 5] Auditing Deep Focus Categories & Apps via GET /api/deep-focus...")
    status, df_res = get_json("/api/deep-focus", token=token)
    assert status == 200
    websites = df_res.get("websites", [])
    categories = df_res.get("categories", [])
    print("  ✓ Blocked Websites / Apps:")
    for w in websites:
        state = "BLOCKED" if w.get("is_blocked") else "UNBLOCKED"
        print(f"    - {w.get('name', w.get('id')):15}: {state}")
    print("  ✓ Blocked Categories:")
    for c in categories:
        state = "BLOCKED" if c.get("is_blocked") else "UNBLOCKED"
        print(f"    - {c.get('name', c.get('id')):25}: {state}")

    # 6. Test Settings Mutation & Persistence
    print("\n[Step 6] Testing Security Settings Mutation & Invalidation...")
    # Toggle SafeSearch and AI Threat
    patch_json("/api/security", {"feature": "ai_threat", "value": True, "profile_id": pid}, token=token)
    _, sec_check = get_json("/api/security", token=token)
    assert sec_check["security"]["ai_threat"] is True, "ai_threat mutation failed"
    print("  ✓ AI Threat toggle to True: Verified persisted")
    # Restore AI Threat
    patch_json("/api/security", {"feature": "ai_threat", "value": False, "profile_id": pid}, token=token)
    _, sec_check = get_json("/api/security", token=token)
    assert sec_check["security"]["ai_threat"] is False
    print("  ✓ AI Threat toggle back to False: Verified persisted")

    # 7. Test Custom Rules (Denylist & Allowlist)
    print("\n[Step 7] Testing Custom Denylist / Allowlist Mutations...")
    test_domain = "audit-custom-block.test"
    post_json("/api/denylist", {"domain": test_domain, "profile_id": pid}, token=token)
    _, dl_res = get_json("/api/denylist", token=token)
    assert test_domain in dl_res["denylist"], f"Domain {test_domain} not found in denylist"
    print(f"  ✓ Added '{test_domain}' to Denylist: Verified listed")

    # Remove test domain
    del_req = urllib.request.Request(
        f"{BASE_URL}/api/denylist/{test_domain}?profile_id={pid}",
        headers={"Authorization": f"Bearer {token}"},
        method="DELETE"
    )
    with urllib.request.urlopen(del_req) as resp:
        assert resp.status == 200
    _, dl_res = get_json("/api/denylist", token=token)
    assert test_domain not in dl_res["denylist"]
    print(f"  ✓ Removed '{test_domain}' from Denylist: Verified clean")

    # 8. Live DNS Filter Queries for Profile dce22d
    print("\n[Step 8] Live DNS Queries on Profile dce22d (Zero-Leak Audit)...")
    test_domains = [
        ("pornhub.com", "Mainstream Adult", True),
        ("xvideos.com", "Mainstream Adult", True),
        ("desihub.net", "Regional Adult (DesiHub)", True),
        ("desipapa.com", "Regional Adult (DesiPapa)", True),
        ("antarvasna.com", "Regional Adult (Antarvasna)", True),
        ("auntysex.com", "Compound Word Adult", True),
        ("chutland.com", "Regional Adult Slang", True),
        ("tiranga.games", "Colour Trading / Gambling", True),
        ("bdggame.com", "Colour Trading / Gambling", True),
        ("91club.com", "Colour Trading / Gambling", True),
        ("bet365.com", "Mainstream Betting", True),
        ("thepiratebay.org", "Piracy / Torrents", True),
        ("1337x.to", "Piracy / Torrents", True),
        ("youtube.com", "Blocked App: YouTube", True),
        ("m.youtube.com", "Blocked App: YouTube Mobile", True),
        ("reddit.com", "Blocked App: Reddit", True),
        ("netflix.com", "Blocked App: Netflix", True),
        ("wikipedia.org", "Clean Encyclopedia", False),
        ("github.com", "Clean Developer Platform", False),
    ]

    all_passed = True
    for d, cat, should_block in test_domains:
        url = f"{BASE_URL}/dns-query/{pid}?name={d}&type=A"
        req = urllib.request.Request(url, headers={"Accept": "application/dns-json"})
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            rcode = data.get("Status")
            is_blocked = (rcode == 3) # NXDOMAIN
            expected_str = "BLOCKED" if should_block else "ALLOWED"
            actual_str = "BLOCKED" if is_blocked else "ALLOWED"
            ok = (is_blocked == should_block)
            status_icon = "✓" if ok else "✗"
            print(f"  {status_icon} [{cat:28}] {d:22}: {actual_str} (RCODE {rcode})")
            if not ok:
                all_passed = False

    print("\n============================================================")
    if all_passed:
        print("🎉 ALL CHECKS & SETTINGS AUDIT PASSED WITH 100% SUCCESS!")
    else:
        print("❌ SOME CHECKS FAILED!")
        sys.exit(1)
    print("============================================================")

if __name__ == "__main__":
    main()
