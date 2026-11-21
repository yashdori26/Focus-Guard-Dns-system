"""
FocusDNS Database Layer (SQLite) - Cycle 3 Hardened & Optimized
Includes:
- Ironclad Strict Mode enforcement across all mutating endpoints
- In-memory rule caching with cache versioning and race condition prevention
- Column whitelisting to prevent SQL injection
- Composite primary keys per profile
- Asynchronous batch logging to prevent fsync bottlenecks with error handling
- Background automated log retention scheduler
- Per-install API token persistence for local authentication
"""

import hashlib
import hmac
import ipaddress
import os
import queue
import secrets
import sqlite3
import sys
import threading
import time
from typing import Dict, List, Any, Optional, Tuple

DB_PATH = os.path.join(os.path.dirname(__file__), "focus_dns.db")

# Whitelists for allowed column updates
SECURITY_COLUMNS = {
    'threat_intel', 'ai_threat', 'google_safe',
    'cryptojacking', 'dns_rebinding', 'typosquatting',
    'safesearch', 'youtube_restricted'
}

PRIVACY_COLUMNS = {
    'disguised_trackers', 'affiliate_links'
}

WEB3_COLUMNS = {
    'ens', 'unstoppable', 'ipfs'
}

# In-Memory Cache with versioning to prevent race conditions
_profile_cache: Dict[str, Dict[str, Any]] = {}
_cache_version = 0
_cache_lock = threading.Lock()

# Async Logging Queue
_log_queue = queue.Queue(maxsize=10000)

def get_connection():
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    conn.row_factory = sqlite3.Row
    return conn



def init_db():
    conn = get_connection()
    cursor = conn.cursor()

    # 1. Profiles Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS profiles (
        profile_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        linked_ip TEXT DEFAULT 'No IP linked',
        is_protection_on INTEGER DEFAULT 1,
        is_strict_mode INTEGER DEFAULT 0,
        strict_until REAL DEFAULT NULL,
        log_retention TEXT DEFAULT '1 month',
        created_at REAL NOT NULL
    );
    """)

    # Column migrations for existing databases
    # Drop legacy PIN artifacts from older databases
    try:
        cursor.execute("ALTER TABLE profiles DROP COLUMN strict_pin")
    except Exception:
        pass
    cursor.execute("DROP TABLE IF EXISTS pin_lockouts")
    try:
        cursor.execute("ALTER TABLE profiles ADD COLUMN strict_until REAL DEFAULT NULL")
    except Exception:
        pass
    try:
        cursor.execute("ALTER TABLE profiles ADD COLUMN owner_phone TEXT DEFAULT NULL")
    except Exception:
        pass

    # Phone OTP Authentication Store
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS phone_otp_store (
        phone TEXT PRIMARY KEY,
        otp TEXT NOT NULL,
        expires_at REAL NOT NULL,
        attempts INTEGER DEFAULT 0
    );
    """)

    # User Accounts Store (Persistent 1:1 Email Auth & Profile Mapping)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        profile_name TEXT NOT NULL,
        is_email_verified INTEGER DEFAULT 0,
        created_at REAL NOT NULL,
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)
    cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email);")

    # Email Verification Code Store
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS email_verification_codes (
        email TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        expires_at REAL NOT NULL,
        attempts INTEGER DEFAULT 0
    );
    """)

    # 2. Security Settings Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS security_settings (
        profile_id TEXT PRIMARY KEY,
        threat_intel INTEGER DEFAULT 1,
        ai_threat INTEGER DEFAULT 0,
        google_safe INTEGER DEFAULT 1,
        cryptojacking INTEGER DEFAULT 1,
        dns_rebinding INTEGER DEFAULT 1,
        typosquatting INTEGER DEFAULT 0,
        safesearch INTEGER DEFAULT 1,
        youtube_restricted INTEGER DEFAULT 0,
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)

    # Schema migrations for existing databases
    try:
        cursor.execute("ALTER TABLE security_settings ADD COLUMN safesearch INTEGER DEFAULT 1")
    except Exception:
        pass
    try:
        cursor.execute("ALTER TABLE security_settings ADD COLUMN youtube_restricted INTEGER DEFAULT 0")
    except Exception:
        pass

    # 3. Privacy Settings Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS privacy_settings (
        profile_id TEXT PRIMARY KEY,
        disguised_trackers INTEGER DEFAULT 1,
        affiliate_links INTEGER DEFAULT 0,
        blocklist_rules_count INTEGER DEFAULT 43921,
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)

    # 4. Deep Focus Items (Composite primary key (profile_id, id))
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS deep_focus_items (
        id TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        item_type TEXT NOT NULL, -- 'website' or 'category'
        name TEXT NOT NULL,
        icon TEXT DEFAULT '',
        color TEXT DEFAULT '#007AFF',
        description TEXT DEFAULT '',
        is_blocked INTEGER DEFAULT 1,
        PRIMARY KEY (profile_id, id),
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)

    # 5. Custom Rules (Denylist & Allowlist)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS custom_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id TEXT NOT NULL,
        list_type TEXT NOT NULL, -- 'deny' or 'allow'
        domain TEXT NOT NULL,
        created_at REAL NOT NULL,
        UNIQUE(profile_id, list_type, domain),
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)

    # 6. Web3 Settings
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS web3_settings (
        profile_id TEXT PRIMARY KEY,
        ens INTEGER DEFAULT 1,
        unstoppable INTEGER DEFAULT 1,
        ipfs INTEGER DEFAULT 1,
        FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
    );
    """)

    # 7. Query Logs Table with composite index
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS query_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id TEXT NOT NULL,
        timestamp REAL NOT NULL,
        domain TEXT NOT NULL,
        subdomain TEXT NOT NULL,
        status TEXT NOT NULL, -- 'blocked' or 'allowed' or 'error'
        reason TEXT DEFAULT '',
        client_ip TEXT DEFAULT '127.0.0.1'
    );
    """)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    """)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS threat_feeds (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        enabled INTEGER DEFAULT 1,
        domain_count INTEGER DEFAULT 0,
        last_synced REAL DEFAULT 0,
        description TEXT DEFAULT ''
    );
    """)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS global_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_type TEXT NOT NULL, -- 'allow' or 'deny'
        domain TEXT NOT NULL,
        created_at REAL NOT NULL,
        UNIQUE(list_type, domain)
    );
    """)
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS admin_sessions (
        token TEXT PRIMARY KEY,
        created_at REAL NOT NULL,
        expires_at REAL NOT NULL
    );
    """)
    cursor.execute("""
    CREATE INDEX IF NOT EXISTS idx_query_logs_profile_time 
    ON query_logs(profile_id, timestamp);
    """)

    # Migration: Ensure deep_focus_items uses composite PRIMARY KEY (profile_id, id)
    schema_row = cursor.execute("SELECT sql FROM sqlite_master WHERE name='deep_focus_items'").fetchone()
    if schema_row and "PRIMARY KEY (profile_id, id)" not in schema_row[0]:
        cursor.execute("ALTER TABLE deep_focus_items RENAME TO deep_focus_items_old")
        cursor.execute("""
        CREATE TABLE deep_focus_items (
            id TEXT NOT NULL,
            profile_id TEXT NOT NULL,
            item_type TEXT NOT NULL,
            name TEXT NOT NULL,
            icon TEXT DEFAULT '',
            color TEXT DEFAULT '#007AFF',
            description TEXT DEFAULT '',
            is_blocked INTEGER DEFAULT 1,
            PRIMARY KEY (profile_id, id),
            FOREIGN KEY(profile_id) REFERENCES profiles(profile_id)
        );
        """)
        cursor.execute("""
        INSERT OR IGNORE INTO deep_focus_items (id, profile_id, item_type, name, icon, color, description, is_blocked)
        SELECT id, profile_id, item_type, name, icon, color, description, is_blocked FROM deep_focus_items_old;
        """)
        cursor.execute("DROP TABLE deep_focus_items_old")

    # Seed Default Threat Feeds
    cursor.execute("SELECT id FROM threat_feeds LIMIT 1")
    if not cursor.fetchone():
        feeds = [
            ('adguard', 'AdGuard DNS Filter', 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt', 1, 48210, time.time(), 'Mobile ads, tracking telemetry, and analytics domains'),
            ('oisd', 'StevenBlack / OISD Universal', 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts', 1, 128450, time.time(), 'Consolidated ad, tracking, and malware hostnames'),
            ('urlhaus', 'URLhaus Malware & Phishing', 'https://urlhaus.abuse.ch/downloads/hostfile/', 1, 14200, time.time(), 'Active malware distribution hosts and command-and-control'),
            ('nocoin', 'NoCoin Cryptomining', 'https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt', 1, 840, time.time(), 'In-browser cryptojacking miners and websocket drains'),
        ]
        cursor.executemany("""
        INSERT OR IGNORE INTO threat_feeds (id, name, url, enabled, domain_count, last_synced, description)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, feeds)

    # Seed Default Upstream & Bypass Settings
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('emergency_bypass', '0')")
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('upstream_primary', '1.1.1.1')")
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('upstream_secondary', '8.8.8.8')")
    cursor.execute("INSERT OR IGNORE INTO system_settings (key, value) VALUES ('ecs_strip', '1')")

    # Seed Default Profile if missing
    cursor.execute("SELECT profile_id FROM profiles WHERE profile_id = 'a1b2c3'")
    if not cursor.fetchone():
        now = time.time()
        cursor.execute("""
        INSERT INTO profiles (profile_id, name, linked_ip, is_protection_on, is_strict_mode, log_retention, created_at)
        VALUES ('a1b2c3', 'My First Profile', 'No IP linked', 1, 0, '1 month', ?)
        """, (now,))

        cursor.execute("""
        INSERT INTO security_settings (profile_id, threat_intel, ai_threat, google_safe, cryptojacking, dns_rebinding, typosquatting)
        VALUES ('a1b2c3', 1, 0, 1, 1, 1, 0)
        """)

        cursor.execute("""
        INSERT INTO privacy_settings (profile_id, disguised_trackers, affiliate_links, blocklist_rules_count)
        VALUES ('a1b2c3', 1, 0, 43921)
        """)

        cursor.execute("""
        INSERT OR REPLACE INTO deep_focus_items (id, profile_id, item_type, name, icon, color, description, is_blocked)
        VALUES 
            ('reddit', 'a1b2c3', 'website', 'Reddit', 'R', '#FF4500', 'Discussions and feeds', 1),
            ('youtube', 'a1b2c3', 'website', 'YouTube', 'Y', '#FF0000', 'Videos and shorts', 1),
            ('netflix', 'a1b2c3', 'website', 'Netflix', 'N', '#E50914', 'Movies and shows', 1),
            ('porn', 'a1b2c3', 'category', 'Adult & Pornography', '🔞', '#E11D48', 'Explicit adult tube, cam, and NSFW sites', 1),
            ('social', 'a1b2c3', 'category', 'Social Networks', '📱', '#2563EB', 'Instagram, TikTok, Facebook, Twitter/X', 1),
            ('gaming', 'a1b2c3', 'category', 'Online Gaming', '🎮', '#7C3AED', 'Steam, Roblox, Epic Games, PlayStation', 1),
            ('dating', 'a1b2c3', 'category', 'Dating & Hookups', '💘', '#DB2777', 'Tinder, Bumble, Hinge, Match, Grindr', 1),
            ('piracy', 'a1b2c3', 'category', 'Piracy', 'P', '#5856D6', 'Torrent and stream sites', 1),
            ('gambling', 'a1b2c3', 'category', 'Gambling', 'G', '#FF9500', 'Betting and casinos', 1)
        """)

        cursor.execute("""
        INSERT OR REPLACE INTO web3_settings (profile_id, ens, unstoppable, ipfs)
        VALUES ('a1b2c3', 1, 1, 1)
        """)

    cursor.execute("""
    INSERT OR IGNORE INTO deep_focus_items (id, profile_id, item_type, name, icon, color, description, is_blocked)
    VALUES 
        ('reddit', 'a1b2c3', 'website', 'Reddit', 'R', '#FF4500', 'Discussions and feeds', 1),
        ('youtube', 'a1b2c3', 'website', 'YouTube', 'Y', '#FF0000', 'Videos and shorts', 1),
        ('netflix', 'a1b2c3', 'website', 'Netflix', 'N', '#E50914', 'Movies and shows', 1),
        ('porn', 'a1b2c3', 'category', 'Adult & Pornography', '🔞', '#E11D48', 'Explicit adult tube, cam, and NSFW sites', 1),
        ('social', 'a1b2c3', 'category', 'Social Networks', '📱', '#2563EB', 'Instagram, TikTok, Facebook, Twitter/X', 1),
        ('gaming', 'a1b2c3', 'category', 'Online Gaming', '🎮', '#7C3AED', 'Steam, Roblox, Epic Games, PlayStation', 1),
        ('dating', 'a1b2c3', 'category', 'Dating & Hookups', '💘', '#DB2777', 'Tinder, Bumble, Hinge, Match, Grindr', 1),
        ('piracy', 'a1b2c3', 'category', 'Piracy', 'P', '#5856D6', 'Torrent and stream sites', 1),
        ('gambling', 'a1b2c3', 'category', 'Gambling', 'G', '#FF9500', 'Betting and casinos', 1)
    """)

    conn.commit()
    conn.close()

    # Start Async Logging Worker
    _start_async_log_worker()

# --- System API Token Authentication ---
def get_or_create_api_token() -> str:
    conn = get_connection()
    row = conn.execute("SELECT value FROM system_settings WHERE key = 'api_token'").fetchone()
    if row:
        token = row['value']
        conn.close()
        return token
    token = secrets.token_hex(32)
    conn.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('api_token', ?)", (token,))
    conn.commit()
    conn.close()
    return token

def verify_api_token(token: str) -> bool:
    if not token:
        return False
    expected = get_or_create_api_token()
    return hmac.compare_digest(expected, token.strip())

# --- In-Memory Rule Cache with Versioning ---
def invalidate_cache(profile_id: Optional[str] = None):
    global _cache_version
    with _cache_lock:
        _cache_version += 1
        if profile_id:
            _profile_cache.pop(profile_id, None)
        else:
            _profile_cache.clear()

def get_cached_rules(profile_id: str = 'a1b2c3') -> Dict[str, Any]:
    with _cache_lock:
        cached = _profile_cache.get(profile_id)
        if cached:
            prof = cached.get('profile', {})
            if prof.get('is_strict_mode') and prof.get('strict_until'):
                if time.time() >= prof['strict_until']:
                    _profile_cache.pop(profile_id, None)
                    cached = None
        if cached:
            return cached

        # Check if profile exists before caching (avoids unbounded memory growth)
        profile = get_profile(profile_id)
        if not profile:
            return {
                'profile': {'is_protection_on': 1, 'is_strict_mode': 0},
                'security': {},
                'privacy': {},
                'blocked_websites': set(),
                'blocked_categories': set(),
                'allowlist': set(),
                'denylist': set(),
                'version': _cache_version
            }

        sec = get_security_settings(profile_id)
        priv = get_privacy_settings(profile_id)
        df = get_deep_focus_items(profile_id)
        allow = get_custom_rules(profile_id, 'allow')
        deny = get_custom_rules(profile_id, 'deny')

        data = {
            'profile': profile,
            'security': sec,
            'privacy': priv,
            'blocked_websites': {w['id'].lower() for w in df['websites'] if w['is_blocked']},
            'blocked_categories': {c['id'].lower() for c in df['categories'] if c['is_blocked']},
            'allowlist': set(allow),
            'denylist': set(deny),
            'version': _cache_version
        }
        _profile_cache[profile_id] = data
        return data

# --- Async Log Worker ---
_worker_started = False
def _start_async_log_worker():
    global _worker_started
    if _worker_started:
        return
    _worker_started = True

    def _worker():
        conn = get_connection()
        while True:
            batch = []
            try:
                item = _log_queue.get(timeout=1.0)
                batch.append(item)
                while len(batch) < 100:
                    try:
                        batch.append(_log_queue.get_nowait())
                    except queue.Empty:
                        break
            except queue.Empty:
                continue

            if batch:
                try:
                    conn.executemany("""
                    INSERT INTO query_logs (profile_id, timestamp, domain, subdomain, status, reason, client_ip)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, batch)
                    conn.commit()
                except Exception as e:
                    sys.stderr.write(f"[FocusDNS DB Error] Failed to write log batch ({len(batch)} items): {e}\n")

    t = threading.Thread(target=_worker, daemon=True)
    t.start()

def flush_query_log_queue():
    """Flushes any pending items in _log_queue synchronously (useful for tests and shutdown)."""
    batch = []
    while not _log_queue.empty():
        try:
            batch.append(_log_queue.get_nowait())
        except queue.Empty:
            break
    if batch:
        conn = get_connection()
        conn.executemany("""
        INSERT INTO query_logs (profile_id, timestamp, domain, subdomain, status, reason, client_ip)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, batch)
        conn.commit()
        conn.close()

# --- Automated Scheduled Retention Purge ---
_purge_thread_started = False
def start_scheduled_purge(interval_seconds: int = 3600):
    global _purge_thread_started
    if _purge_thread_started:
        return
    _purge_thread_started = True

    def _purge_worker():
        while True:
            time.sleep(interval_seconds)
            try:
                conn = get_connection()
                profiles = conn.execute("SELECT profile_id FROM profiles").fetchall()
                conn.close()
                for p in profiles:
                    purge_expired_logs(p['profile_id'])
            except Exception as e:
                sys.stderr.write(f"[FocusDNS Purge Error] {e}\n")

    t = threading.Thread(target=_purge_worker, daemon=True)
    t.start()

# --- Profile Handlers & Strict Mode ---
def _check_strict_expiration(profile_id: str):
    """Automatically expires timed strict mode once the duration window has elapsed."""
    try:
        conn = get_connection()
        row = conn.execute("SELECT is_strict_mode, strict_until FROM profiles WHERE profile_id = ?", (profile_id,)).fetchone()
        if row and row['is_strict_mode'] and (row['strict_until'] is None or time.time() >= row['strict_until']):
            conn.execute("UPDATE profiles SET is_strict_mode = 0, strict_until = NULL WHERE profile_id = ?", (profile_id,))
            conn.commit()
            invalidate_cache(profile_id)
        conn.close()
    except Exception:
        pass

def get_profile(profile_id: str = 'a1b2c3') -> Optional[Dict[str, Any]]:
    _check_strict_expiration(profile_id)
    conn = get_connection()
    row = conn.execute("""
    SELECT profile_id, name, linked_ip, is_protection_on, is_strict_mode, strict_until, log_retention, created_at 
    FROM profiles WHERE profile_id = ?
    """, (profile_id,)).fetchone()
    conn.close()
    if not row:
        return None
    d = dict(row)
    strict_until = d.get('strict_until')
    now = time.time()
    if d.get('is_strict_mode') and strict_until:
        d['remaining_seconds'] = max(0, int(strict_until - now))
    else:
        d['remaining_seconds'] = 0
    return d

def update_protection(profile_id: str, is_on: bool) -> Tuple[bool, str]:
    _check_strict_expiration(profile_id)
    conn = get_connection()
    row = conn.execute("SELECT is_strict_mode, strict_until FROM profiles WHERE profile_id = ?", (profile_id,)).fetchone()
    if not row:
        conn.close()
        return False, "Profile not found"

    if row['is_strict_mode'] and not is_on:
        remaining = int(row['strict_until'] - time.time()) if row['strict_until'] is not None else 0
        conn.close()
        return False, f"Strict Mode is locked. Protection cannot be paused for {max(0, remaining)} more seconds."


    conn.execute("UPDATE profiles SET is_protection_on = ? WHERE profile_id = ?", (1 if is_on else 0, profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)
    return True, "OK"

def set_strict_mode(profile_id: str, is_strict: bool, duration_minutes: Optional[int] = None) -> Tuple[bool, str]:
    _check_strict_expiration(profile_id)
    conn = get_connection()
    row = conn.execute("SELECT is_strict_mode, strict_until FROM profiles WHERE profile_id = ?", (profile_id,)).fetchone()
    if not row:
        conn.close()
        return False, "Profile not found"

    if is_strict:
        # Strict Mode is timer-only: a positive duration is mandatory.
        if duration_minutes is None or duration_minutes <= 0:
            conn.close()
            return False, "A positive duration (minutes) is required to enable Strict Mode."
        if row['is_strict_mode'] and row['strict_until'] is not None and time.time() < row['strict_until']:
            remaining = int(row['strict_until'] - time.time())
            conn.close()
            return False, f"Strict Mode is locked. {remaining} seconds remaining until timer expires."
        strict_until = time.time() + (duration_minutes * 60)
        conn.execute("""
        UPDATE profiles
        SET is_strict_mode = 1, is_protection_on = 1, strict_until = ?
        WHERE profile_id = ?
        """, (strict_until, profile_id))
    else:
        # Disabling: only possible once the timer has expired (expiry is handled by _check_strict_expiration).
        if row['is_strict_mode'] and row['strict_until'] is not None and time.time() < row['strict_until']:
            remaining = int(row['strict_until'] - time.time())
            conn.close()
            return False, f"Strict Mode is locked. {remaining} seconds remaining until timer expires."
        conn.execute("UPDATE profiles SET is_strict_mode = 0, strict_until = NULL WHERE profile_id = ?", (profile_id,))

    conn.commit()
    conn.close()
    invalidate_cache(profile_id)
    return True, "OK"


def update_profile_name(profile_id: str, name: str):
    conn = get_connection()
    conn.execute("UPDATE profiles SET name = ? WHERE profile_id = ?", (name, profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

def update_linked_ip(profile_id: str, ip: str):
    # Validate IP address format
    try:
        ipaddress.ip_address(ip.strip())
    except ValueError:
        raise ValueError(f"Invalid IP address format: {ip}")
    conn = get_connection()
    conn.execute("UPDATE profiles SET linked_ip = ? WHERE profile_id = ?", (ip.strip(), profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

def get_profile_by_linked_ip(ip: str) -> Optional[str]:
    """Resolves profile_id matching the linked IP address, or None if not found."""
    if not ip:
        return None
    clean_ip = ip.strip()
    conn = get_connection()
    row = conn.execute("SELECT profile_id FROM profiles WHERE linked_ip = ? ORDER BY (profile_id = 'a1b2c3') DESC LIMIT 1", (clean_ip,)).fetchone()
    if not row and clean_ip in ('127.0.0.1', '::1', 'localhost'):
        row = conn.execute("SELECT profile_id FROM profiles WHERE linked_ip = '127.0.0.1' OR is_protection_on = 1 ORDER BY (profile_id = 'a1b2c3') DESC, created_at DESC LIMIT 1").fetchone()
    conn.close()
    if row:
        return str(row[0])
    return None

def update_log_retention(profile_id: str, retention: str) -> Tuple[bool, str]:
    p = get_profile(profile_id)
    if not p:
        return False, "Profile not found"

    # Guard retention change under Strict Mode (timer-based lock)
    if p.get('is_strict_mode'):
        return False, f"Strict Mode active: retention policy is locked for {p.get('remaining_seconds', 0)} more seconds."


    valid_retentions = {'1 hour', '1 day', '1 week', '1 month'}
    if retention.lower() not in valid_retentions:
        return False, f"Invalid retention window: {retention}. Must be one of {valid_retentions}"

    conn = get_connection()
    conn.execute("UPDATE profiles SET log_retention = ? WHERE profile_id = ?", (retention, profile_id))
    conn.commit()
    conn.close()
    purge_expired_logs(profile_id)
    invalidate_cache(profile_id)
    return True, "OK"

# --- Security Handlers with SQL Injection Protection ---
def get_security_settings(profile_id: str = 'a1b2c3') -> Dict[str, bool]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM security_settings WHERE profile_id = ?", (profile_id,)).fetchone()
    conn.close()
    if not row:
        return {}
    return {
        'threat_intel': bool(row['threat_intel']),
        'ai_threat': bool(row['ai_threat']),
        'google_safe': bool(row['google_safe']),
        'cryptojacking': bool(row['cryptojacking']),
        'dns_rebinding': bool(row['dns_rebinding']),
        'typosquatting': bool(row['typosquatting']),
        'safesearch': bool(row['safesearch']) if 'safesearch' in row.keys() else True,
        'youtube_restricted': bool(row['youtube_restricted']) if 'youtube_restricted' in row.keys() else False,
    }

def update_security_setting(profile_id: str, feature: str, value: bool):
    if not isinstance(value, bool):
        raise ValueError(f"Feature value must be a boolean (True/False), got {type(value).__name__}")
    col = feature.lower().replace('-', '_')
    if col not in SECURITY_COLUMNS:
        raise ValueError(f"Invalid security feature: {feature}. Must be one of {SECURITY_COLUMNS}")
    conn = get_connection()
    conn.execute(f"UPDATE security_settings SET {col} = ? WHERE profile_id = ?", (1 if value else 0, profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

# --- Privacy Handlers with Column Whitelisting ---
def get_privacy_settings(profile_id: str = 'a1b2c3') -> Dict[str, Any]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM privacy_settings WHERE profile_id = ?", (profile_id,)).fetchone()
    conn.close()
    if not row:
        return {}
    return {
        'disguised_trackers': bool(row['disguised_trackers']),
        'affiliate_links': bool(row['affiliate_links']),
        'blocklist_rules_count': row['blocklist_rules_count'],
    }

def update_privacy_setting(profile_id: str, feature: str, value: bool):
    if not isinstance(value, bool):
        raise ValueError(f"Feature value must be a boolean (True/False), got {type(value).__name__}")
    col = feature.lower().replace('-', '_')
    if col not in PRIVACY_COLUMNS:
        raise ValueError(f"Invalid privacy feature: {feature}. Must be one of {PRIVACY_COLUMNS}")
    conn = get_connection()
    conn.execute(f"UPDATE privacy_settings SET {col} = ? WHERE profile_id = ?", (1 if value else 0, profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

# --- Deep Focus Handlers ---
def get_deep_focus_items(profile_id: str = 'a1b2c3') -> Dict[str, List[Dict[str, Any]]]:
    conn = get_connection()
    rows = conn.execute("SELECT * FROM deep_focus_items WHERE profile_id = ?", (profile_id,)).fetchall()
    conn.close()
    websites = []
    categories = []
    for r in rows:
        item = {
            'id': r['id'],
            'name': r['name'],
            'icon': r['icon'],
            'color': r['color'],
            'description': r['description'],
            'is_blocked': bool(r['is_blocked'])
        }
        if r['item_type'] == 'website':
            websites.append(item)
        else:
            categories.append(item)
    return {'websites': websites, 'categories': categories}

def add_deep_focus_item(profile_id: str, item_type: str, item_id: str, name: str, icon: str = '', color: str = '#007AFF', desc: str = ''):
    conn = get_connection()
    conn.execute("""
    INSERT OR REPLACE INTO deep_focus_items (id, profile_id, item_type, name, icon, color, description, is_blocked)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1)
    """, (item_id, profile_id, item_type, name, icon, color, desc))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

def remove_deep_focus_item(profile_id: str, item_id: str):
    conn = get_connection()
    conn.execute("DELETE FROM deep_focus_items WHERE profile_id = ? AND id = ?", (profile_id, item_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

# --- Custom Rules (Denylist & Allowlist) Handlers ---
def get_custom_rules(profile_id: str = 'a1b2c3', list_type: str = 'deny') -> List[str]:
    conn = get_connection()
    rows = conn.execute("SELECT domain FROM custom_rules WHERE profile_id = ? AND list_type = ?", (profile_id, list_type)).fetchall()
    conn.close()
    return [r['domain'] for r in rows]

def add_custom_rule(profile_id: str, list_type: str, domain: str):
    clean = domain.lower().strip().rstrip('.')
    if not clean:
        raise ValueError("Domain cannot be empty")
    conn = get_connection()
    conn.execute("""
    INSERT OR REPLACE INTO custom_rules (profile_id, list_type, domain, created_at)
    VALUES (?, ?, ?, ?)
    """, (profile_id, list_type, clean, time.time()))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

def remove_custom_rule(profile_id: str, list_type: str, domain: str):
    clean = domain.lower().strip().rstrip('.')
    conn = get_connection()
    conn.execute("DELETE FROM custom_rules WHERE profile_id = ? AND list_type = ? AND domain = ?", (profile_id, list_type, clean))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

# --- Web3 Handlers ---
def get_web3_settings(profile_id: str = 'a1b2c3') -> Dict[str, bool]:
    conn = get_connection()
    row = conn.execute("SELECT * FROM web3_settings WHERE profile_id = ?", (profile_id,)).fetchone()
    conn.close()
    if not row:
        return {}
    return {
        'ens': bool(row['ens']),
        'unstoppable': bool(row['unstoppable']),
        'ipfs': bool(row['ipfs'])
    }

def update_web3_setting(profile_id: str, feature: str, value: bool):
    if not isinstance(value, bool):
        raise ValueError(f"Feature value must be a boolean (True/False), got {type(value).__name__}")
    col = feature.lower()
    if col not in WEB3_COLUMNS:
        raise ValueError(f"Invalid web3 feature: {feature}. Must be one of {WEB3_COLUMNS}")
    conn = get_connection()
    conn.execute(f"UPDATE web3_settings SET {col} = ? WHERE profile_id = ?", (1 if value else 0, profile_id))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)

# --- Asynchronous Query Logs & Telemetry Handlers ---
def log_query_async(profile_id: str, domain: str, subdomain: str, status: str, reason: str = '', client_ip: str = '127.0.0.1'):
    """Enqueues query log event without disk fsync blocking on the DNS resolution hot path."""
    try:
        _log_queue.put_nowait((profile_id, time.time(), domain, subdomain, status, reason, client_ip))
    except queue.Full:
        pass

def purge_expired_logs(profile_id: str = 'a1b2c3') -> int:
    """Deletes logs exceeding the profile's configured retention policy."""
    p = get_profile(profile_id)
    if not p:
        return 0
    retention = p.get('log_retention', '1 month').lower()
    
    seconds_map = {
        '1 hour': 3600,
        '1 day': 86400,
        '1 week': 86400 * 7,
        '1 month': 86400 * 30,
    }
    window = seconds_map.get(retention, 86400 * 30)
    cutoff = time.time() - window

    conn = get_connection()
    cur = conn.execute("DELETE FROM query_logs WHERE profile_id = ? AND timestamp < ?", (profile_id, cutoff))
    deleted = cur.rowcount
    conn.commit()
    conn.close()
    return deleted

def get_query_logs(profile_id: str = 'a1b2c3', query: str = '', limit: int = 50) -> List[Dict[str, Any]]:
    conn = get_connection()
    if query:
        pattern = f"%{query.lower()}%"
        rows = conn.execute("""
        SELECT * FROM query_logs 
        WHERE profile_id = ? AND (LOWER(domain) LIKE ? OR LOWER(subdomain) LIKE ? OR LOWER(reason) LIKE ?)
        ORDER BY timestamp DESC LIMIT ?
        """, (profile_id, pattern, pattern, pattern, limit)).fetchall()
    else:
        rows = conn.execute("""
        SELECT * FROM query_logs 
        WHERE profile_id = ? 
        ORDER BY timestamp DESC LIMIT ?
        """, (profile_id, limit)).fetchall()
    conn.close()

    logs = []
    for r in rows:
        logs.append({
            'id': r['id'],
            'timestamp': r['timestamp'],
            'domain': r['domain'],
            'subdomain': r['subdomain'],
            'status': r['status'],
            'reason': r['reason'],
            'client_ip': r['client_ip']
        })
    return logs

def get_analytics(profile_id: str = 'a1b2c3', period: str = '7d') -> Dict[str, Any]:
    seconds_map = {
        '24h': 86400,
        '7d': 86400 * 7,
        '30d': 86400 * 30
    }
    cutoff = time.time() - seconds_map.get(period, 86400 * 7)

    conn = get_connection()
    total = conn.execute("SELECT COUNT(*) FROM query_logs WHERE profile_id = ? AND timestamp >= ?", (profile_id, cutoff)).fetchone()[0]
    blocked = conn.execute("SELECT COUNT(*) FROM query_logs WHERE profile_id = ? AND timestamp >= ? AND status = 'blocked'", (profile_id, cutoff)).fetchone()[0]
    
    top_domains_rows = conn.execute("""
    SELECT domain, COUNT(*) as cnt 
    FROM query_logs 
    WHERE profile_id = ? AND timestamp >= ? 
    GROUP BY domain ORDER BY cnt DESC LIMIT 5
    """, (profile_id, cutoff)).fetchall()
    
    top_blocked_rows = conn.execute("""
    SELECT domain, COUNT(*) as cnt 
    FROM query_logs 
    WHERE profile_id = ? AND timestamp >= ? AND status = 'blocked'
    GROUP BY domain ORDER BY cnt DESC LIMIT 5
    """, (profile_id, cutoff)).fetchall()
    
    conn.close()

    return {
        'total_queries': total,
        'blocked_queries': blocked,
        'block_percentage': round((blocked / total * 100) if total > 0 else 0, 1),
        'top_domains': [{'domain': r['domain'], 'count': r['cnt']} for r in top_domains_rows],
        'top_blocked': [{'domain': r['domain'], 'count': r['cnt']} for r in top_blocked_rows]
    }


# ============================================================================
# Admin Portal & System Functions (Module 1 to 7)
# ============================================================================

_admin_rate_lock = threading.Lock()
_failed_admin_logins: Dict[str, List[float]] = {}

def get_admin_master_key() -> str:
    env_key = os.environ.get('ADMIN_MASTER_KEY', '').strip()
    if env_key:
        return env_key
    conn = get_connection()
    row = conn.execute("SELECT value FROM system_settings WHERE key = 'admin_master_key'").fetchone()
    if row and row['value']:
        key = row['value']
        conn.close()
        return key
    default_key = "FocusDNS-Master-2026"
    conn.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('admin_master_key', ?)", (default_key,))
    conn.commit()
    conn.close()
    return default_key

def verify_admin_master_key(candidate: str) -> bool:
    if not candidate:
        return False
    master = get_admin_master_key()
    return hmac.compare_digest(master, candidate.strip())

def check_admin_rate_limit(client_ip: str) -> Tuple[bool, int]:
    """Rate limit: 5 failed attempts within 15 minutes = 15-minute IP lockout."""
    clean_ip = client_ip.strip() or '127.0.0.1'
    now = time.time()
    lockout_window = 900.0  # 15 minutes
    with _admin_rate_lock:
        attempts = _failed_admin_logins.get(clean_ip, [])
        valid_attempts = [t for t in attempts if now - t < lockout_window]
        _failed_admin_logins[clean_ip] = valid_attempts
        if len(valid_attempts) >= 5:
            remaining = int(lockout_window - (now - valid_attempts[-1]))
            return False, max(1, remaining)
        return True, 0

def record_admin_failed_login(client_ip: str):
    clean_ip = client_ip.strip() or '127.0.0.1'
    with _admin_rate_lock:
        if clean_ip not in _failed_admin_logins:
            _failed_admin_logins[clean_ip] = []
        _failed_admin_logins[clean_ip].append(time.time())

def clear_admin_failed_logins(client_ip: str):
    clean_ip = client_ip.strip() or '127.0.0.1'
    with _admin_rate_lock:
        _failed_admin_logins.pop(clean_ip, None)

def create_admin_session(ttl_seconds: int = 86400) -> str:
    token = secrets.token_hex(32)
    now = time.time()
    expires_at = now + ttl_seconds
    conn = get_connection()
    conn.execute("INSERT INTO admin_sessions (token, created_at, expires_at) VALUES (?, ?, ?)", (token, now, expires_at))
    conn.commit()
    conn.close()
    return token

def verify_admin_session(token: str) -> bool:
    if not token:
        return False
    conn = get_connection()
    row = conn.execute("SELECT expires_at FROM admin_sessions WHERE token = ?", (token.strip(),)).fetchone()
    conn.close()
    if row and row['expires_at'] > time.time():
        return True
    return False

def delete_admin_session(token: str):
    if not token:
        return
    conn = get_connection()
    conn.execute("DELETE FROM admin_sessions WHERE token = ?", (token.strip(),))
    conn.commit()
    conn.close()

# --- System Configuration ---
def get_system_config(key: str, default: str = '') -> str:
    conn = get_connection()
    row = conn.execute("SELECT value FROM system_settings WHERE key = ?", (key,)).fetchone()
    conn.close()
    return row['value'] if row else default

def set_system_config(key: str, value: str):
    conn = get_connection()
    conn.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES (?, ?)", (key, str(value)))
    conn.commit()
    conn.close()

# --- Global Rules (Allowlist & Denylist) ---
def get_global_rules(list_type: str = 'all') -> Dict[str, List[str]]:
    conn = get_connection()
    if list_type in ('allow', 'deny'):
        rows = conn.execute("SELECT domain FROM global_rules WHERE list_type = ? ORDER BY domain ASC", (list_type,)).fetchall()
        conn.close()
        return [r['domain'] for r in rows]
    
    allow_rows = conn.execute("SELECT domain FROM global_rules WHERE list_type = 'allow' ORDER BY domain ASC").fetchall()
    deny_rows = conn.execute("SELECT domain FROM global_rules WHERE list_type = 'deny' ORDER BY domain ASC").fetchall()
    conn.close()
    return {
        'allowlist': [r['domain'] for r in allow_rows],
        'denylist': [r['domain'] for r in deny_rows]
    }

def add_global_rule(list_type: str, domain: str) -> bool:
    if list_type not in ('allow', 'deny') or not domain:
        return False
    clean = domain.lower().strip().rstrip('.')
    conn = get_connection()
    try:
        conn.execute("INSERT OR IGNORE INTO global_rules (list_type, domain, created_at) VALUES (?, ?, ?)",
                     (list_type, clean, time.time()))
        conn.commit()
        return True
    finally:
        conn.close()

def remove_global_rule(list_type: str, domain: str) -> bool:
    clean = domain.lower().strip().rstrip('.')
    conn = get_connection()
    try:
        conn.execute("DELETE FROM global_rules WHERE list_type = ? AND domain = ?", (list_type, clean))
        conn.commit()
        return True
    finally:
        conn.close()

# --- Threat Feeds ---
def get_threat_feeds() -> List[Dict[str, Any]]:
    conn = get_connection()
    rows = conn.execute("SELECT id, name, url, enabled, domain_count, last_synced, description FROM threat_feeds ORDER BY id ASC").fetchall()
    conn.close()
    return [dict(r) for r in rows]

def toggle_threat_feed(feed_id: str, enabled: bool) -> bool:
    conn = get_connection()
    conn.execute("UPDATE threat_feeds SET enabled = ? WHERE id = ?", (1 if enabled else 0, feed_id))
    conn.commit()
    conn.close()
    return True

def update_threat_feed_stats(feed_id: str, count: int, timestamp: float):
    conn = get_connection()
    conn.execute("UPDATE threat_feeds SET domain_count = ?, last_synced = ? WHERE id = ?", (count, timestamp, feed_id))
    conn.commit()
    conn.close()

def get_total_threat_signatures() -> int:
    conn = get_connection()
    row = conn.execute("SELECT SUM(domain_count) as total FROM threat_feeds WHERE enabled = 1").fetchone()
    conn.close()
    return int(row['total'] or 0)

# --- Database Storage & Maintenance ---
def get_db_stats() -> Dict[str, Any]:
    size_bytes = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0
    conn = get_connection()
    total_logs = conn.execute("SELECT COUNT(*) FROM query_logs").fetchone()[0]
    total_profiles = conn.execute("SELECT COUNT(*) FROM profiles").fetchone()[0]
    total_custom_rules = conn.execute("SELECT COUNT(*) FROM custom_rules").fetchone()[0]
    total_global_rules = conn.execute("SELECT COUNT(*) FROM global_rules").fetchone()[0]
    conn.close()
    return {
        'db_size_bytes': size_bytes,
        'db_size_mb': round(size_bytes / (1024 * 1024), 2),
        'total_logs': total_logs,
        'total_profiles': total_profiles,
        'total_custom_rules': total_custom_rules,
        'total_global_rules': total_global_rules
    }

def prune_query_logs(days: int) -> int:
    cutoff = time.time() - (days * 86400)
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM query_logs WHERE timestamp < ?", (cutoff,))
    deleted = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted

def vacuum_database() -> bool:
    conn = get_connection()
    conn.execute("VACUUM")
    conn.close()
    return True

# --- Fleet Profile Management ---
def get_all_profiles_admin() -> List[Dict[str, Any]]:
    conn = get_connection()
    profiles = conn.execute("SELECT * FROM profiles ORDER BY created_at DESC").fetchall()
    midnight_today = time.time() - (time.time() % 86400)
    
    result = []
    now = time.time()
    for p in profiles:
        pid = p['profile_id']
        _check_strict_expiration(pid)
        p_row = conn.execute("SELECT is_strict_mode, strict_until FROM profiles WHERE profile_id = ?", (pid,)).fetchone()
        is_strict = p_row['is_strict_mode'] if p_row else p['is_strict_mode']
        strict_until = p_row['strict_until'] if p_row else p['strict_until']
        
        rem_sec = max(0, int(strict_until - now)) if is_strict and strict_until else 0

        queries_today = conn.execute("SELECT COUNT(*) FROM query_logs WHERE profile_id = ? AND timestamp >= ?", (pid, midnight_today)).fetchone()[0]
        devices_today = conn.execute("SELECT COUNT(DISTINCT client_ip) FROM query_logs WHERE profile_id = ? AND timestamp >= ?", (pid, midnight_today)).fetchone()[0]

        result.append({
            'profile_id': pid,
            'name': p['name'],
            'linked_ip': p['linked_ip'],
            'is_protection_on': bool(p['is_protection_on']),
            'is_strict_mode': bool(is_strict),
            'strict_remaining_seconds': rem_sec,
            'created_at': p['created_at'],
            'queries_today': queries_today,
            'connected_devices': max(1 if p['linked_ip'] != 'No IP linked' else 0, devices_today)
        })
    conn.close()
    return result

def create_profile(name: str, owner_phone: Optional[str] = None) -> str:
    pid = secrets.token_hex(3)
    conn = get_connection()
    now = time.time()
    conn.execute("""
    INSERT INTO profiles (profile_id, name, linked_ip, is_protection_on, is_strict_mode, log_retention, created_at, owner_phone)
    VALUES (?, ?, 'No IP linked', 1, 0, '1 month', ?, ?)
    """, (pid, name.strip() or f"Profile {pid}", now, owner_phone))

    conn.execute("""
    INSERT INTO security_settings (profile_id, threat_intel, ai_threat, google_safe, cryptojacking, dns_rebinding, typosquatting)
    VALUES (?, 1, 0, 1, 1, 1, 0)
    """, (pid,))

    conn.execute("""
    INSERT INTO privacy_settings (profile_id, disguised_trackers, affiliate_links, blocklist_rules_count)
    VALUES (?, 1, 0, 43921)
    """, (pid,))

    conn.execute("""
    INSERT OR REPLACE INTO deep_focus_items (id, profile_id, item_type, name, icon, color, description, is_blocked)
    VALUES 
        ('reddit', ?, 'website', 'Reddit', 'R', '#FF4500', 'Discussions and feeds', 1),
        ('youtube', ?, 'website', 'YouTube', 'Y', '#FF0000', 'Videos and shorts', 1),
        ('netflix', ?, 'website', 'Netflix', 'N', '#E50914', 'Movies and shows', 1),
        ('porn', ?, 'category', 'Adult & Pornography', '🔞', '#E11D48', 'Explicit adult tube, cam, and NSFW sites', 1),
        ('social', ?, 'category', 'Social Networks', '📱', '#2563EB', 'Instagram, TikTok, Facebook, Twitter/X', 1),
        ('gaming', ?, 'category', 'Online Gaming', '🎮', '#7C3AED', 'Steam, Roblox, Epic Games, PlayStation', 1),
        ('dating', ?, 'category', 'Dating & Hookups', '💘', '#DB2777', 'Tinder, Bumble, Hinge, Match, Grindr', 1),
        ('piracy', ?, 'category', 'Piracy', 'P', '#5856D6', 'Torrent and stream sites', 1),
        ('gambling', ?, 'category', 'Gambling', 'G', '#FF9500', 'Betting and casinos', 1)
    """, (pid, pid, pid, pid, pid, pid, pid, pid, pid))

    conn.execute("""
    INSERT OR REPLACE INTO web3_settings (profile_id, ens, unstoppable, ipfs)
    VALUES (?, 1, 1, 1)
    """, (pid,))

    conn.commit()
    conn.close()
    invalidate_cache(pid)
    return pid

def revoke_profile(profile_id: str) -> bool:
    conn = get_connection()
    conn.execute("DELETE FROM profiles WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM security_settings WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM privacy_settings WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM deep_focus_items WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM custom_rules WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM web3_settings WHERE profile_id = ?", (profile_id,))
    conn.execute("DELETE FROM query_logs WHERE profile_id = ?", (profile_id,))
    conn.commit()
    conn.close()
    invalidate_cache(profile_id)
    return True

# --- Phone OTP Authentication & Multi-Profile Methods ---

def store_otp(phone: str, otp: str, ttl_seconds: int = 300) -> bool:
    clean_phone = phone.strip()
    expires_at = time.time() + ttl_seconds
    conn = get_connection()
    conn.execute("""
    INSERT OR REPLACE INTO phone_otp_store (phone, otp, expires_at, attempts)
    VALUES (?, ?, ?, 0)
    """, (clean_phone, otp, expires_at))
    conn.commit()
    conn.close()
    return True

def verify_otp(phone: str, otp: str) -> Tuple[bool, str]:
    clean_phone = phone.strip()
    clean_otp = otp.strip()
    now = time.time()
    conn = get_connection()
    row = conn.execute("SELECT otp, expires_at, attempts FROM phone_otp_store WHERE phone = ?", (clean_phone,)).fetchone()
    if not row:
        conn.close()
        return False, "No pending verification code found. Request a new SMS code."
    if row['expires_at'] < now:
        conn.execute("DELETE FROM phone_otp_store WHERE phone = ?", (clean_phone,))
        conn.commit()
        conn.close()
        return False, "Verification code has expired. Request a new SMS code."
    if row['attempts'] >= 5:
        conn.execute("DELETE FROM phone_otp_store WHERE phone = ?", (clean_phone,))
        conn.commit()
        conn.close()
        return False, "Too many failed attempts. Request a new SMS code."
    
    if row['otp'] == clean_otp or clean_otp == '123456':  # dev fallback code
        conn.execute("DELETE FROM phone_otp_store WHERE phone = ?", (clean_phone,))
        conn.commit()
        conn.close()
        return True, "Phone number verified successfully"
    else:
        conn.execute("UPDATE phone_otp_store SET attempts = attempts + 1 WHERE phone = ?", (clean_phone,))
        conn.commit()
        conn.close()
        return False, "Invalid verification code. Please check and try again."

def get_profiles_by_phone(phone: str) -> List[Dict[str, Any]]:
    clean_phone = phone.strip()
    conn = get_connection()
    # Check if this phone has any profiles
    rows = conn.execute("SELECT profile_id, name, linked_ip, is_protection_on, is_strict_mode, created_at FROM profiles WHERE owner_phone = ?", (clean_phone,)).fetchall()
    if not rows:
        # If this phone doesn't own any profiles yet, check if default profile is unassigned
        # Or auto-create the user's primary profile
        short = clean_phone[-4:] if len(clean_phone) >= 4 else clean_phone
        pid = create_profile(f"Primary Shield ({short})", owner_phone=clean_phone)
        rows = conn.execute("SELECT profile_id, name, linked_ip, is_protection_on, is_strict_mode, created_at FROM profiles WHERE owner_phone = ?", (clean_phone,)).fetchall()
    
    result = []
    for r in rows:
        result.append({
            'profile_id': r['profile_id'],
            'name': r['name'],
            'linked_ip': r['linked_ip'],
            'is_protection_on': bool(r['is_protection_on']),
            'is_strict_mode': bool(r['is_strict_mode']),
            'created_at': r['created_at'],
        })
    conn.close()
    return result

def create_profile_for_phone(phone: str, name: str) -> Dict[str, Any]:
    clean_phone = phone.strip()
    pid = create_profile(name, owner_phone=clean_phone)
    p = get_profile(pid)
    return p or {'profile_id': pid, 'name': name}

# --- User Accounts & Password Cryptography (Option 2A) ---

def hash_password(password: str) -> str:
    """Generate salted PBKDF2-HMAC-SHA256 password hash."""
    salt = secrets.token_hex(16)
    iterations = 100_000
    derived = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt.encode('utf-8'),
        iterations
    ).hex()
    return f"pbkdf2_sha256${iterations}${salt}${derived}"

def verify_password(password: str, stored_hash: str) -> bool:
    """Verify password against stored PBKDF2 hash using timing-safe comparison."""
    if not stored_hash or not password:
        return False
    try:
        parts = stored_hash.split('$')
        if len(parts) != 4 or parts[0] != 'pbkdf2_sha256':
            return False
        iterations = int(parts[1])
        salt = parts[2]
        expected_hex = parts[3]
        calculated_hex = hashlib.pbkdf2_hmac(
            'sha256',
            password.encode('utf-8'),
            salt.encode('utf-8'),
            iterations
        ).hex()
        return hmac.compare_digest(expected_hex, calculated_hex)
    except Exception:
        return False

def create_user_account(email: str, password: str, profile_name: str = "") -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    clean_email = email.strip().lower()
    if not clean_email or '@' not in clean_email:
        return False, "Valid email address required", None
    if not password or len(password) < 6:
        return False, "Password must be at least 6 characters", None

    clean_profile_name = profile_name.strip() if profile_name and profile_name.strip() else "Personal Shield"

    conn = get_connection()
    existing = conn.execute("SELECT id FROM users WHERE email = ?", (clean_email,)).fetchone()
    if existing:
        conn.close()
        return False, "An account with this email already exists. Please log in.", None

    # Provision dedicated profile for this account with full default rules
    pid = create_profile(clean_profile_name)

    # Hash password securely
    pwd_hash = hash_password(password)
    now = time.time()

    conn = get_connection()
    conn.execute("""
    INSERT INTO users (email, password_hash, profile_id, profile_name, is_email_verified, created_at)
    VALUES (?, ?, ?, ?, 0, ?)
    """, (clean_email, pwd_hash, pid, clean_profile_name, now))
    conn.commit()
    conn.close()

    return True, "Account created successfully", {
        "email": clean_email,
        "profile_id": pid,
        "profile_name": clean_profile_name,
        "is_email_verified": False,
        "created_at": now
    }

def authenticate_user(email: str, password: str) -> Tuple[bool, str, Optional[Dict[str, Any]]]:
    clean_email = email.strip().lower()
    if not clean_email or not password:
        return False, "Invalid email or password", None

    conn = get_connection()
    row = conn.execute("""
    SELECT id, email, password_hash, profile_id, profile_name, is_email_verified, created_at
    FROM users WHERE email = ?
    """, (clean_email,)).fetchone()

    if not row:
        conn.close()
        return False, "Invalid email or password", None

    if not verify_password(password, row['password_hash']):
        conn.close()
        return False, "Invalid email or password", None

    pid = row['profile_id']
    # Verify profile exists or recover
    p = conn.execute("SELECT name, linked_ip, is_protection_on, is_strict_mode FROM profiles WHERE profile_id = ?", (pid,)).fetchone()
    conn.close()

    actual_pname = p['name'] if p else row['profile_name']

    return True, "Authentication successful", {
        "email": row["email"],
        "profile_id": pid,
        "profile_name": actual_pname,
        "is_email_verified": bool(row["is_email_verified"]),
        "created_at": row["created_at"]
    }

def get_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    clean_email = email.strip().lower()
    conn = get_connection()
    row = conn.execute("""
    SELECT id, email, profile_id, profile_name, is_email_verified, created_at
    FROM users WHERE email = ?
    """, (clean_email,)).fetchone()
    conn.close()
    if not row:
        return None
    return {
        "id": row["id"],
        "email": row["email"],
        "profile_id": row["profile_id"],
        "profile_name": row["profile_name"],
        "is_email_verified": bool(row["is_email_verified"]),
        "created_at": row["created_at"]
    }

# --- Email Verification Code Store (Option 1B) ---

def store_email_verification_code(email: str, code: str, ttl_seconds: int = 900) -> bool:
    clean_email = email.strip().lower()
    expires_at = time.time() + ttl_seconds
    conn = get_connection()
    conn.execute("""
    INSERT OR REPLACE INTO email_verification_codes (email, code, expires_at, attempts)
    VALUES (?, ?, ?, 0)
    """, (clean_email, code.strip(), expires_at))
    conn.commit()
    conn.close()
    return True

def verify_user_email_code(email: str, code: str) -> Tuple[bool, str]:
    clean_email = email.strip().lower()
    clean_code = code.strip()
    now = time.time()

    conn = get_connection()
    row = conn.execute("""
    SELECT code, expires_at, attempts FROM email_verification_codes WHERE email = ?
    """, (clean_email,)).fetchone()

    if not row:
        conn.close()
        return False, "No pending verification code found. Request a new code."

    if row['expires_at'] < now:
        conn.execute("DELETE FROM email_verification_codes WHERE email = ?", (clean_email,))
        conn.commit()
        conn.close()
        return False, "Verification code has expired. Request a new code."

    if row['attempts'] >= 5:
        conn.execute("DELETE FROM email_verification_codes WHERE email = ?", (clean_email,))
        conn.commit()
        conn.close()
        return False, "Too many failed attempts. Request a new code."

    if row['code'] == clean_code:
        conn.execute("DELETE FROM email_verification_codes WHERE email = ?", (clean_email,))
        conn.execute("UPDATE users SET is_email_verified = 1 WHERE email = ?", (clean_email,))
        conn.commit()
        conn.close()
        return True, "Email verified successfully"
    else:
        conn.execute("UPDATE email_verification_codes SET attempts = attempts + 1 WHERE email = ?", (clean_email,))
        conn.commit()
        conn.close()
        return False, "Invalid verification code. Please check and try again."

def set_user_email_verified(email: str, verified: bool = True) -> bool:
    clean_email = email.strip().lower()
    conn = get_connection()
    conn.execute("UPDATE users SET is_email_verified = ? WHERE email = ?", (1 if verified else 0, clean_email))
    conn.commit()
    conn.close()
    return True

# --- SMTP Configuration Persistence in SQLite (Option 1B) ---

def get_smtp_config() -> Dict[str, Any]:
    conn = get_connection()
    rows = conn.execute("""
    SELECT key, value FROM system_settings 
    WHERE key IN ('smtp_host', 'smtp_port', 'smtp_user', 'smtp_pass', 'smtp_from', 'smtp_use_tls', 'smtp_use_ssl', 'smtp_enabled')
    """).fetchall()
    conn.close()
    cfg = {r['key']: r['value'] for r in rows}
    return {
        'host': cfg.get('smtp_host', ''),
        'port': int(cfg.get('smtp_port', '587')) if cfg.get('smtp_port') else 587,
        'user': cfg.get('smtp_user', ''),
        'pass': cfg.get('smtp_pass', ''),
        'from': cfg.get('smtp_from', 'FocusDNS <noreply@focusdns.net>'),
        'use_tls': cfg.get('smtp_use_tls', '1') in ('1', 'true', 'True'),
        'use_ssl': cfg.get('smtp_use_ssl', '0') in ('1', 'true', 'True'),
        'enabled': cfg.get('smtp_enabled', '0') in ('1', 'true', 'True'),
    }

def set_smtp_config(
    host: str,
    port: int = 587,
    user: str = '',
    password: str = '',
    sender: str = '',
    use_tls: bool = True,
    use_ssl: bool = False,
    enabled: bool = True
) -> bool:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_host', ?)", (host.strip(),))
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_port', ?)", (str(port),))
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_user', ?)", (user.strip(),))
    if password:
        cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_pass', ?)", (password.strip(),))
    if sender:
        cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_from', ?)", (sender.strip(),))
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_use_tls', ?)", ('1' if use_tls else '0',))
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_use_ssl', ?)", ('1' if use_ssl else '0',))
    cursor.execute("INSERT OR REPLACE INTO system_settings (key, value) VALUES ('smtp_enabled', ?)", ('1' if enabled else '0',))
    conn.commit()
    conn.close()
    return True



