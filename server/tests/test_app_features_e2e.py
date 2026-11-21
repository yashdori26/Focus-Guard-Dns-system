"""E2E audit: replays the exact HTTP calls the Flutter app makes, then checks real DNS behaviour."""
import json, urllib.request, urllib.error, sys, os

B = "http://127.0.0.1:8080"
PID = None
results = []

def call(method, path, body=None, token=None):
    h = {"Content-Type": "application/json"}
    if token: h["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(B + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try: return e.code, json.loads(e.read() or b"{}")
        except Exception: return e.code, {}

def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  -> {detail}" if detail else ""))

_, t = call("GET", "/api/auth/token"); T = t["token"]
def new_profile(name):
    st, d = call("POST", "/api/profiles", {"name": name}, T)
    p = d.get("profile") or d
    return p.get("profile_id")
PID = new_profile("E2E-Audit")          # throwaway profile: never touches the real one
STRICT_PID = new_profile("E2E-Strict")  # strict-mode lock is only ever applied to this one
print("throwaway profiles:", PID, STRICT_PID)
def resolve(domain, qtype="A"):
    _, r = call("POST", "/api/query/resolve", {"domain": domain, "type": qtype, "profile_id": PID}, T)
    return r

def hit(r, text): return text.lower() in (r.get("reason") or "").lower()
def set_sec(f, v): return call("PATCH", "/api/security", {"profile_id": PID, "feature": f, "value": v}, T)
def set_priv(f, v): return call("PATCH", "/api/privacy", {"profile_id": PID, "feature": f, "value": v}, T)

# make sure we start from a clean, non-strict state

print("\n=== ALLOWLIST / DENYLIST (what the app SHOULD send; server side) ===")
call("DELETE", f"/api/denylist/blocked-test.example?profile_id={PID}", None, T)
st, _ = call("POST", "/api/denylist", {"profile_id": PID, "domain": "blocked-test.example"}, T)
r = resolve("blocked-test.example")
check("Denylist add -> domain is actually blocked", r.get("status") == "blocked", r.get("reason", ""))
r = resolve("sub.blocked-test.example")
check("Denylist blocks subdomains too", r.get("status") == "blocked", r.get("reason", ""))
st, _ = call("DELETE", f"/api/denylist/blocked-test.example?profile_id={PID}", None, T)
r = resolve("blocked-test.example")
check("Denylist remove -> rule no longer applied", not hit(r, "Denylist"), r.get("reason",""))

call("POST", "/api/denylist", {"profile_id": PID, "domain": "tracker-x.example"}, T)
call("POST", "/api/allowlist", {"profile_id": PID, "domain": "tracker-x.example"}, T)
r = resolve("tracker-x.example")
check("Allowlist overrides denylist", hit(r, "Allowlist"), r.get("reason",""))
call("DELETE", f"/api/allowlist/tracker-x.example?profile_id={PID}", None, T)
call("DELETE", f"/api/denylist/tracker-x.example?profile_id={PID}", None, T)

print("\n=== SECURITY toggles: does flipping them change real DNS answers? ===")
def toggle_effect(feature, domain, tag, qtype="A"):
    set_sec(feature, True); on = resolve(domain, qtype)
    set_sec(feature, False); off = resolve(domain, qtype)
    set_sec(feature, True)
    check(f"Security '{feature}': ON applies '{tag}', OFF does not ({domain})", hit(on, tag) and not hit(off, tag), f"ON={on.get('reason')} | OFF={off.get('reason')}")

# new profiles ship with YouTube in Deep Focus; remove it so it doesn't mask the YouTube-restricted test
call("DELETE", f"/api/deep-focus/youtube?profile_id={PID}", None, T)
toggle_effect("threat_intel", "malware-test.com", "Threat Intelligence")
toggle_effect("cryptojacking", "coinhive.com", "Cryptojacking")
toggle_effect("ai_threat", "xkqjzvwpbtmnrslqd.com", "DGA")
toggle_effect("typosquatting", "paypa1-login.com", "Typosquatting")
toggle_effect("safesearch", "www.google.com", "Google SafeSearch")
toggle_effect("safesearch", "www.bing.com", "Bing Strict")
set_sec("youtube_restricted", True); set_sec("safesearch", False)
on = resolve("www.youtube.com")
set_sec("youtube_restricted", False)
off = resolve("www.youtube.com")
check("Security 'youtube_restricted': ON rewrites YouTube, OFF does not", hit(on, "YouTube Restricted") and not hit(off, "YouTube Restricted"), f"ON={on.get('reason')} | OFF={off.get('reason')}")
set_sec("safesearch", True)

# toggles with no visible enforcement in the resolver
import re as _re
_src = open(os.path.join(os.path.dirname(__file__), "..", "resolver.py")).read()
check("Security 'google_safe' is read by the resolver (has any effect)", "google_safe" in _src, "toggle is stored but resolver never reads it" if "google_safe" not in _src else "")
check("Security 'dns_rebinding' is read by the resolver", "dns_rebinding" in _src)

print("\n=== PRIVACY toggles ===")
set_priv("disguised_trackers", True); on = resolve("doubleclick.net")
set_priv("disguised_trackers", False); off = resolve("doubleclick.net"); set_priv("disguised_trackers", True)
check("Privacy 'disguised_trackers': ON blocks trackers, OFF does not", hit(on, "Tracker") and not hit(off, "Tracker"), f"ON={on.get('reason')} | OFF={off.get('reason')}")
check("Privacy 'affiliate_links' is read by the resolver (has any effect)", "affiliate_links" in _src, "toggle is stored but resolver never reads it" if "affiliate_links" not in _src else "")

check("Web3 toggles (ens/unstoppable/ipfs) are read by the resolver", any(k in _src for k in ("web3", "get_web3_settings")), "toggles are stored but resolver never reads them" if not any(k in _src for k in ("web3", "get_web3_settings")) else "")

print("\n=== SETTINGS tab: the exact verbs the app uses ===")
st, _ = call("POST", "/api/settings", {"profile_id": PID, "profile_name": "Audit Name"}, T)
check("Profile name save (app uses POST /api/settings)", st == 200, f"HTTP {st}")
_, g = call("GET", f"/api/settings?profile_id={PID}", None, T)
check("Profile name actually persisted", g.get("profile_name") == "Audit Name", f"server has: {g.get('profile_name')}")
st, _ = call("POST", "/api/settings", {"profile_id": PID, "log_retention": "1 week"}, T)
_, g = call("GET", f"/api/settings?profile_id={PID}", None, T)
check("Log retention save + persisted", st == 200 and g.get("log_retention") == "1 week", f"HTTP {st}, server has: {g.get('log_retention')}")
st, _ = call("POST", "/api/settings", {"profile_id": PID, "web3_feature": "ens", "web3_value": False}, T)
_, g = call("GET", f"/api/settings?profile_id={PID}", None, T)
check("Web3 toggle save + persisted", st == 200 and g.get("web3", {}).get("ens") is False, f"HTTP {st}, server has: {g.get('web3')}")
# the same via PATCH (what the server actually implements)
st2, _ = call("PATCH", "/api/settings", {"profile_id": PID, "profile_name": "My First Profile", "log_retention": "1 month", "web3_feature": "ens", "web3_value": True}, T)
check("(reference) PATCH /api/settings works on the server", st2 == 200, f"HTTP {st2}")

print("\n=== LOGS ===")
resolve("logs-test-one.example")
_, lg = call("GET", f"/api/logs?profile_id={PID}&q=logs-test-one", None, T)
import time; time.sleep(1.5)
_, lg = call("GET", f"/api/logs?profile_id={PID}&q=logs-test-one", None, T)
check("Server logs search finds the query", lg.get("count", 0) >= 1, f"count={lg.get('count')}")

print("\n=== STRICT MODE barrier on lists ===")
call("POST", "/api/denylist", {"profile_id": STRICT_PID, "domain": "keepme.example"}, T)
call("POST", "/api/profile/strict-mode", {"profile_id": STRICT_PID, "is_strict": True, "duration_minutes": 5}, T)
st, _ = call("POST", "/api/allowlist", {"profile_id": STRICT_PID, "domain": "evade.example"}, T)
check("Strict: adding to allowlist is refused (403)", st == 403, f"HTTP {st}")
st, _ = call("DELETE", f"/api/denylist/keepme.example?profile_id={STRICT_PID}", None, T)
check("Strict: removing denylist entry is refused (403)", st == 403, f"HTTP {st}")
st, _ = call("PATCH","/api/security",{"profile_id":STRICT_PID,"feature":"threat_intel","value":False},T)
check("Strict: disabling a security toggle is refused (403)", st == 403, f"HTTP {st}")
st, _ = call("PATCH","/api/privacy",{"profile_id":STRICT_PID,"feature":"disguised_trackers","value":False},T)
check("Strict: disabling a privacy toggle is refused (403)", st == 403, f"HTTP {st}")


import sqlite3, os
dbp = os.path.join(os.path.dirname(__file__), "..", "focus_dns.db")
try:
    c = sqlite3.connect(dbp)
    for pid in (PID, STRICT_PID):
        for t in [r[0] for r in c.execute("select name from sqlite_master where type='table'")]:
            cols = [x[1] for x in c.execute(f"pragma table_info({t})")]
            if "profile_id" in cols: c.execute(f"delete from {t} where profile_id=?", (pid,))
    c.commit(); c.close()
except Exception as e:
    print("cleanup note:", e)
fails = [r for r in results if not r[1]]
print(f"\n{len(results)-len(fails)}/{len(results)} passed, {len(fails)} failed")
sys.exit(1 if fails else 0)
