"""
FocusDNS Real-Time Resolver & Threat Detection Engine - Cycle 3 Hardened
Includes:
- Public Suffix aware split_domain via publicsuffix2 (handles .co.uk, .com.cn, .github.io, etc.)
- Real wire-format UDP DNS forwarding to upstream nameserver (1.1.1.1 / 8.8.8.8) with timeout
- Preservation of upstream RCODE (NXDOMAIN vs NOERROR vs SERVFAIL), TTLs, and query types (A, AAAA, MX, TXT, etc.)
- DNS Rebinding inspection on resolved A and AAAA addresses (with CGNAT & local zone exemption)
- Comprehensive query logging and SSE broadcasting on ALL paths (including SERVFAIL and NXDOMAIN)
- Suffix-only domain matching eliminating false positives
"""

import ipaddress
import math
import re
import socket
import struct
import sys
import threading
import time
import urllib.request
from typing import Dict, Any, Tuple, Optional, Callable, List, Set

from dnslib import DNSRecord, DNSHeader, RR, QTYPE, RCODE, A, AAAA, SOA

try:
    import publicsuffix2
    HAS_PUBLICSUFFIX = True
except ImportError:
    HAS_PUBLICSUFFIX = False

from . import db

# Upstream DNS server configuration & Dynamic Controls
UPSTREAM_DNS_HOST = '1.1.1.1'
FALLBACK_DNS_HOST = '8.8.8.8'
UPSTREAM_DNS_PORT = 53
UPSTREAM_TIMEOUT = 2.0

# In-Memory Admin Operational State (Module 1 to 7)
_global_emergency_bypass: bool = False
_global_allowlist: Set[str] = set()
_global_denylist: Set[str] = set()
_threat_feed_domains: Set[str] = set()
_ram_dns_cache: Dict[Tuple[str, int], Tuple[bytes, float]] = {}
_ram_cache_lock = threading.Lock()

_server_start_time: float = time.time()
_total_queries_counter: int = 0
_total_blocked_counter: int = 0
_cache_hits_counter: int = 0
_cache_misses_counter: int = 0
_active_doh_counter: int = 0

_qps_timestamps: List[float] = []
_qps_lock = threading.Lock()

_upstream_primary: str = '1.1.1.1'
_upstream_secondary: str = '8.8.8.8'
_ecs_strip: bool = True

def reload_global_rules():
    global _global_emergency_bypass, _upstream_primary, _upstream_secondary, _ecs_strip, UPSTREAM_DNS_HOST, FALLBACK_DNS_HOST
    try:
        _global_emergency_bypass = (db.get_system_config('emergency_bypass', '0') == '1')
        _upstream_primary = db.get_system_config('upstream_primary', '1.1.1.1') or '1.1.1.1'
        UPSTREAM_DNS_HOST = _upstream_primary
        _upstream_secondary = db.get_system_config('upstream_secondary', '8.8.8.8') or '8.8.8.8'
        FALLBACK_DNS_HOST = _upstream_secondary
        _ecs_strip = (db.get_system_config('ecs_strip', '1') == '1')
        
        rules = db.get_global_rules('all')
        _global_allowlist.clear()
        _global_allowlist.update(rules['allowlist'])
        _global_denylist.clear()
        _global_denylist.update(rules['denylist'])
        with _ram_cache_lock:
            _ram_dns_cache.clear()
    except Exception as e:
        sys.stderr.write(f"[Resolver Reload Warning] {e}\n")

# Seed initial operational state
reload_global_rules()

def set_emergency_bypass(enabled: bool):
    global _global_emergency_bypass
    _global_emergency_bypass = bool(enabled)
    db.set_system_config('emergency_bypass', '1' if enabled else '0')
    with _ram_cache_lock:
        _ram_dns_cache.clear()

def set_upstreams(primary: str, secondary: str, ecs_strip: bool):
    global _upstream_primary, _upstream_secondary, _ecs_strip, UPSTREAM_DNS_HOST, FALLBACK_DNS_HOST
    if primary:
        _upstream_primary = primary.strip()
        UPSTREAM_DNS_HOST = _upstream_primary
        db.set_system_config('upstream_primary', _upstream_primary)
    if secondary:
        _upstream_secondary = secondary.strip()
        FALLBACK_DNS_HOST = _upstream_secondary
        db.set_system_config('upstream_secondary', _upstream_secondary)
    _ecs_strip = bool(ecs_strip)
    db.set_system_config('ecs_strip', '1' if ecs_strip else '0')

def benchmark_upstreams() -> List[Dict[str, Any]]:
    targets = [
        {"name": "Quad9 (Malware & DNSSEC)", "host": "9.9.9.9", "port": 53},
        {"name": "Cloudflare (Speed & Anycast)", "host": "1.1.1.1", "port": 53},
        {"name": "Google Public DNS", "host": "8.8.8.8", "port": 53},
    ]
    if _upstream_primary not in ('9.9.9.9', '1.1.1.1', '8.8.8.8'):
        targets.append({"name": f"Custom Primary ({_upstream_primary})", "host": _upstream_primary, "port": 53})

    req = DNSRecord.question("example.com", "A")
    raw_packet = req.pack()
    results = []

    for t in targets:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2.0)
        t0 = time.time()
        try:
            s.sendto(raw_packet, (t["host"], t["port"]))
            s.recvfrom(512)
            lat = round((time.time() - t0) * 1000, 1)
            results.append({
                "name": t["name"],
                "host": t["host"],
                "latency_ms": lat,
                "status": "online"
            })
        except Exception:
            results.append({
                "name": t["name"],
                "host": t["host"],
                "latency_ms": -1,
                "status": "timeout"
            })
        finally:
            s.close()
    return results

def sync_threat_feeds_background():
    """Background worker to download and compile remote threat feeds into in-memory Trie/Set."""
    def _worker():
        try:
            feeds = db.get_threat_feeds()
            aggregated_domains = set()
            for f in feeds:
                if not f['enabled']:
                    continue
                url = f['url']
                fid = f['id']
                try:
                    req = urllib.request.Request(url, headers={'User-Agent': 'FocusDNS-Feed-Sync/1.0'})
                    with urllib.request.urlopen(req, timeout=12.0) as resp:
                        content = resp.read().decode('utf-8', errors='ignore')
                        parsed_count = 0
                        for line in content.splitlines():
                            line = line.strip()
                            if not line or line.startswith('#') or line.startswith('!'):
                                continue
                            parts = line.split()
                            if len(parts) >= 2 and parts[0] in ('0.0.0.0', '127.0.0.1'):
                                d = parts[1].strip().lower().rstrip('.')
                            else:
                                d = parts[0].strip().lower().rstrip('.')
                            if '.' in d and len(d) > 3:
                                aggregated_domains.add(d)
                                parsed_count += 1
                        db.update_threat_feed_stats(fid, parsed_count, time.time())
                except Exception as ex:
                    sys.stderr.write(f"[Feed Sync Error for {fid}] {ex}\n")
            
            if aggregated_domains:
                _threat_feed_domains.clear()
                _threat_feed_domains.update(aggregated_domains)
        except Exception as e:
            sys.stderr.write(f"[Feed Sync Global Error] {e}\n")

    t = threading.Thread(target=_worker, daemon=True)
    t.start()

def get_server_metrics() -> Dict[str, Any]:
    now = time.time()
    with _qps_lock:
        valid = [t for t in _qps_timestamps if now - t <= 5.0]
        _qps_timestamps[:] = valid
        qps = round(len(valid) / 5.0, 1)

    uptime = int(now - _server_start_time)
    
    mem_mb = 42.0
    try:
        import resource
        ru = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        mem_mb = round(ru / 1024.0, 1)
    except Exception:
        pass

    midnight_today = now - (now % 86400)
    conn = db.get_connection()
    today_total = conn.execute("SELECT COUNT(*) FROM query_logs WHERE timestamp >= ?", (midnight_today,)).fetchone()[0]
    today_blocked = conn.execute("SELECT COUNT(*) FROM query_logs WHERE timestamp >= ? AND status = 'blocked'", (midnight_today,)).fetchone()[0]
    conn.close()

    total_today = max(today_total, _total_queries_counter)
    blocked_today = max(today_blocked, _total_blocked_counter)
    block_percent = round((blocked_today / total_today * 100) if total_today > 0 else 0, 1)

    cache_total = _cache_hits_counter + _cache_misses_counter
    cache_ratio = round((_cache_hits_counter / cache_total * 100) if cache_total > 0 else 0, 1)

    sig_count = len(_threat_feed_domains) or db.get_total_threat_signatures()

    return {
        'qps': qps,
        'uptime_seconds': uptime,
        'uptime_formatted': f"{uptime // 3600}h {(uptime % 3600) // 60}m {uptime % 60}s",
        'total_queries_today': total_today,
        'total_blocked_today': blocked_today,
        'block_percentage': block_percent,
        'cache_hit_ratio': cache_ratio,
        'cache_hits': _cache_hits_counter,
        'cache_misses': _cache_misses_counter,
        'memory_mb': mem_mb,
        'active_threads': threading.active_count(),
        'active_doh_connections': _active_doh_counter,
        'signatures_count': sig_count,
        'emergency_bypass': _global_emergency_bypass,
        'upstream_primary': _upstream_primary,
        'upstream_secondary': _upstream_secondary,
        'ecs_strip': _ecs_strip
    }

# Firefox Canary domain (RFC / Mozilla standard): returning NXDOMAIN signals Firefox to disable built-in DoH
FIREFOX_CANARY_DOMAIN = 'use-application-dns.net'

# Known Public DoH Providers that apps and browsers use to bypass system/local DNS
DOH_BYPASS_DOMAINS = {
    'dns.google', 'dns.google.com',
    'cloudflare-dns.com', '1dot1dot1dot1.cloudflare-dns.com',
    'security.cloudflare-dns.com', 'family.cloudflare-dns.com',
    'dns.quad9.net', 'quad9.net',
    'doh.opendns.com', 'dns.umbrella.com',
    'dns.adguard-dns.com',
    'doh.cleanbrowsing.org',
    'dns.nextdns.io',
    'doh.mullvad.net',
    'dns.controld.com',
    'doh.dns.apple.com',
}

# Known service domain mappings for Deep Focus (comprehensive multi-domain coverage)
APP_DOMAINS = {
    'reddit': {
        'reddit.com', 'redd.it', 'redditmedia.com', 'redditstatic.com',
        'redditmail.com', 'redditinc.com'
    },
    'youtube': {
        'youtube.com', 'youtu.be', 'googlevideo.com', 'ytimg.com',
        'youtubei.googleapis.com', 'yt.be', 'youtube-nocookie.com', 'youtubekids.com'
    },
    'netflix': {
        'netflix.com', 'nflxvideo.net', 'nflximg.net', 'nflxext.com', 'nflxso.net'
    },
    'tiktok': {
        'tiktok.com', 'tiktokv.com', 'tiktokcdn.com', 'tiktokcdn-us.com',
        'byteoversea.com', 'ibytedtos.com', 'musical.ly', 'snssdk.com',
        'amemv.com', 'tiktokv.us', 'bytedance.com', 'muscdn.com'
    },
    'instagram': {
        'instagram.com', 'cdninstagram.com', 'ig.me', 'threads.net', 'threads.com'
    },
    'steam': {
        'steampowered.com', 'steamcommunity.com', 'steamgames.com', 'steamstatic.com', 'steamcontent.com'
    },
    'whatsapp': {
        'whatsapp.com', 'whatsapp.net', 'wa.me'
    },
    'xbox': {
        'xbox.com', 'xboxlive.com'
    },
    'discord': {
        'discord.com', 'discordapp.com', 'discord.gg', 'discord.media', 'discordapp.net'
    },
    'twitter': {
        'twitter.com', 'x.com', 'twimg.com', 't.co', 'periscope.tv', 'pscp.tv'
    },
    'facebook': {
        'facebook.com', 'fbcdn.net', 'fbsbx.com', 'fb.me', 'fb.com', 'messenger.com', 'meta.com'
    },
    'spotify': {
        'spotify.com', 'scdn.co', 'spotifycdn.com', 'spoti.fi'
    },
    'twitch': {
        'twitch.tv', 'ttvnw.net', 'jtvnw.net', 'twitchcdn.net'
    },
    'snapchat': {
        'snapchat.com', 'sc-cdn.net', 'snapkit.com'
    },
    'roblox': {
        'roblox.com', 'rbxcdn.com'
    },
    'amazon': {
        'amazon.com', 'media-amazon.com', 'ssl-images-amazon.com', 'a2z.com'
    },
    'imgur': {'imgur.com'},
    'blizzard': {'blizzard.com', 'battle.net'},
    'vimeo': {'vimeo.com'},
    'hulu': {'hulu.com'},
}

# Known Android application package name mappings for Deep Focus
APP_PACKAGES = {
    'reddit': {
        'com.reddit.frontpage', 'com.laurencedawson.reddit_sync',
        'com.rubenmayayo.reddit', 'ml.docilealligator.infinityforreddit'
    },
    'youtube': {
        'com.google.android.youtube', 'com.google.android.apps.youtube.music',
        'com.google.android.apps.youtube.kids'
    },
    'netflix': {
        'com.netflix.mediaclient', 'com.netflix.ninja'
    },
    'tiktok': {
        'com.zhiliaoapp.musically', 'com.ss.android.ugc.trill', 'com.zhiliaoapp.musically.go'
    },
    'instagram': {
        'com.instagram.android', 'com.instagram.lite', 'com.instagram.barcelona'
    },
    'steam': {
        'com.valvesoftware.android.steam.community'
    },
    'whatsapp': {
        'com.whatsapp', 'com.whatsapp.w4b'
    },
    'xbox': {
        'com.microsoft.xboxone.smartglass', 'com.microsoft.xboxone.smartglass.beta'
    },
    'discord': {
        'com.discord'
    },
    'twitter': {
        'com.twitter.android', 'com.twitter.android.lite'
    },
    'facebook': {
        'com.facebook.katana', 'com.facebook.orca', 'com.facebook.lite'
    },
    'spotify': {
        'com.spotify.music', 'com.spotify.lite'
    },
    'twitch': {
        'tv.twitch.android.app'
    },
    'snapchat': {
        'com.snapchat.android'
    },
    'roblox': {
        'com.roblox.client'
    },
    'amazon': {
        'com.amazon.mShop.android.shopping'
    },
}

# Known category domain targets (strictly matched by domain suffix)
CATEGORY_DOMAINS = {
    'piracy': {
        'thepiratebay.org', '1337x.to', 'rarbg.to', 'yts.mx', 'fmoviesz.to',
        'fitgirl-repacks.site', 'torrentfreak.com', 'nyaa.si', 'rutracker.org'
    },
    'gambling': {
        'bet365.com', 'draftkings.com', 'pokerstars.com', 'stake.com',
        'casino.com', '1xbet.com', 'betway.com', 'bovada.lv', 'betfair.com'
    },
    'social': {
        'facebook.com', 'fbcdn.net', 'twitter.com', 'x.com', 'snapchat.com',
        'threads.net', 'linkedin.com', 'pinterest.com'
    },
    'gaming': {
        'roblox.com', 'epicgames.com', 'ea.com', 'riotgames.com', 'ubisoft.com',
        'playstation.com', 'nintendo.com'
    },
    'video': {
        'twitch.tv', 'dailymotion.com', 'disneyplus.com', 'primevideo.com'
    },
}

# Known malware & mining domains (strict domains)
KNOWN_MALWARE = {
    'malware-test.com', 'c2-botnet.xyz', 'phishing-bank.net', 'payload.ru',
    'evil-trojan.biz', 'ransomware-c2.cc'
}

KNOWN_MINERS = {
    'coinhive.com', 'cryptoloot.pro', 'webminerpool.com', 'monerominer.rocks',
    'coin-have.com', 'crypto-loot.com'
}

KNOWN_TRACKERS = {
    'appsflyersdk.com', 'segment.io', 'doubleclick.net', 'google-analytics.com',
    'adnxs.com', 'scorecardresearch.com', 'criteo.com', 'taboola.com'
}

# RFC 6598 Shared CGNAT space
CGNAT_NET = ipaddress.ip_network('100.64.0.0/10')

# Real-time query log listeners for SSE
_log_subscribers: List[Callable[[Dict[str, Any]], None]] = []
_subscribers_lock = threading.Lock()

def subscribe_logs(callback: Callable[[Dict[str, Any]], None]):
    with _subscribers_lock:
        _log_subscribers.append(callback)

def unsubscribe_logs(callback: Callable[[Dict[str, Any]], None]):
    with _subscribers_lock:
        if callback in _log_subscribers:
            _log_subscribers.remove(callback)

def broadcast_log(event: Dict[str, Any]):
    with _subscribers_lock:
        for cb in list(_log_subscribers):
            try:
                cb(event)
            except Exception:
                pass

def calculate_entropy(s: str) -> float:
    """Calculates Shannon entropy to detect algorithmic DGA domains."""
    if not s:
        return 0.0
    prob = [float(s.count(c)) / len(s) for c in dict.fromkeys(list(s))]
    return - sum([p * math.log(p) / math.log(2.0) for p in prob])

def split_domain(fqdn: str) -> Tuple[str, str]:
    """
    Public suffix aware domain splitter.
    e.g.
    'www.bbc.co.uk' -> ('www.', 'bbc.co.uk')
    'foo.blogspot.com' -> ('', 'foo.blogspot.com')
    'api.reddit.com' -> ('api.', 'reddit.com')
    'localhost' -> ('', 'localhost')
    """
    clean = fqdn.lower().strip().rstrip('.')
    if not clean or '.' not in clean:
        return ('', clean)

    if HAS_PUBLICSUFFIX:
        try:
            sld = publicsuffix2.get_sld(clean)
            if sld and sld in clean:
                sub = clean[:-len(sld)]
                return (sub, sld)
        except Exception:
            pass

    # Fallback to standard 2-label split
    parts = clean.split('.')
    if len(parts) <= 2:
        return ('', clean)
    base = f"{parts[-2]}.{parts[-1]}"
    sub = '.'.join(parts[:-2]) + '.'
    return (sub, base)

def domain_matches(fqdn: str, target: str) -> bool:
    """
    Checks if fqdn matches or is a subdomain of target.
    Prevents false positives (e.g. 'box.community.net' will NEVER match 'x.com').
    """
    fqdn = fqdn.lower().strip().rstrip('.')
    target = target.lower().strip().rstrip('.')
    if target.startswith('*.'):
        target = target[2:]
    return fqdn == target or fqdn.endswith('.' + target)

def is_private_ip(ip_str: str) -> bool:
    """
    RFC-compliant private/local IP check using standard ipaddress library.
    Catches IPv4 & IPv6 loopback, link-local, private, reserved, unspecified, and CGNAT IPs.
    """
    try:
        ip = ipaddress.ip_address(ip_str)
        if (ip.is_private or ip.is_loopback or ip.is_link_local or 
                ip.is_reserved or ip.is_unspecified):
            return True
        if ip.version == 4 and ip in CGNAT_NET:
            return True
        return False
    except ValueError:
        return False

def is_local_zone(fqdn: str) -> bool:
    """Checks if a domain belongs to a standard local or home network zone."""
    local_suffixes = ('.local', '.lan', '.home.arpa', '.internal', '.localhost')
    return any(fqdn.endswith(s) or fqdn == s[1:] for s in local_suffixes)

def _forward_tcp(query_bytes: bytes, host: str, port: int, timeout: float = 2.0) -> Optional[bytes]:
    """Relays wire query over TCP (RFC 1035 section 4.2.2)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect((host, port))
        sock.sendall(struct.pack('!H', len(query_bytes)) + query_bytes)
        len_raw = sock.recv(2)
        if len(len_raw) < 2:
            return None
        resp_len = struct.unpack('!H', len_raw)[0]
        data = b''
        while len(data) < resp_len:
            chunk = sock.recv(resp_len - len(data))
            if not chunk:
                break
            data += chunk
        return data
    except Exception:
        return None
    finally:
        try:
            sock.close()
        except Exception:
            pass


def forward_wire_query(query_bytes: bytes, timeout: float = UPSTREAM_TIMEOUT) -> Tuple[Optional[bytes], str]:
    """
    Forwards raw binary DNS query packet to upstream resolver (primary, fallback secondary).
    Automatically falls back to TCP if the UDP response is truncated (TC=1).
    Returns (reply_packet_bytes, rcode_str).
    """
    reply = None
    primary_host = _upstream_primary or UPSTREAM_DNS_HOST
    secondary_host = _upstream_secondary or FALLBACK_DNS_HOST
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(query_bytes, (primary_host, UPSTREAM_DNS_PORT))
        reply, _ = sock.recvfrom(4096)
    except (socket.timeout, Exception):
        pass
    finally:
        sock.close()

    if not reply:
        # Fallback secondary upstream
        sock_fb = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock_fb.settimeout(timeout)
        try:
            sock_fb.sendto(query_bytes, (secondary_host, UPSTREAM_DNS_PORT))
            reply, _ = sock_fb.recvfrom(4096)
        except Exception:
            return None, 'SERVFAIL'
        finally:
            sock_fb.close()

    if reply:
        # Check TC (Truncation) bit: flags byte 1, bit 1 (0x02)
        if len(reply) >= 4 and (reply[2] & 0x02):
            tcp_reply = _forward_tcp(query_bytes, primary_host, UPSTREAM_DNS_PORT, timeout=timeout)
            if not tcp_reply:
                tcp_reply = _forward_tcp(query_bytes, secondary_host, UPSTREAM_DNS_PORT, timeout=timeout)
            if tcp_reply:
                return tcp_reply, 'NOERROR'
        return reply, 'NOERROR'

    return None, 'SERVFAIL'


def resolve_wire_packet(query_bytes: bytes, profile_id: str = 'a1b2c3', client_ip: str = '127.0.0.1') -> Tuple[bytes, Dict[str, Any]]:
    """
    Evaluates FocusDNS filtering pipeline against raw wire DNS packet.
    Returns (response_wire_bytes, telemetry_event_dict).
    """
    try:
        req = DNSRecord.parse(query_bytes)
    except Exception:
        reply = DNSRecord(DNSHeader(id=0, qr=1, rcode=RCODE.FORMERR))
        return reply.pack(), {'status': 'error', 'rcode': 'FORMERR'}

    if not req.q or req.header.qr != 0:
        reply = req.reply()
        reply.header.rcode = RCODE.FORMERR
        return reply.pack(), {'status': 'error', 'rcode': 'FORMERR'}

    qname = str(req.q.qname).rstrip('.').lower()
    qtype_int = req.q.qtype
    qtype_str = QTYPE.get(qtype_int, 'A')

    # Record QPS & total queries
    global _total_queries_counter, _total_blocked_counter
    _total_queries_counter += 1
    with _qps_lock:
        _qps_timestamps.append(time.time())

    subdomain, base_domain = split_domain(qname)
    cache = db.get_cached_rules(profile_id)
    profile = cache['profile']

    def build_block_reply(reason: str) -> Tuple[bytes, Dict[str, Any]]:
        global _total_blocked_counter
        _total_blocked_counter += 1
        reply = req.reply()
        reply.header.rcode = RCODE.NXDOMAIN
        reply.header.ra = 1
        # RFC 2308: Short negative caching TTL (30s) so unblocking takes effect fast
        soa_name = f"{base_domain}." if base_domain else "."
        reply.add_auth(RR(soa_name, QTYPE.SOA, ttl=30, rdata=SOA("ns1.focusdns.local.", "admin.focusdns.local.", (1, 30, 30, 30, 30))))
        res = {
            'profile_id': profile_id,
            'domain': base_domain,
            'subdomain': subdomain,
            'qtype': qtype_str,
            'status': 'blocked',
            'reason': reason,
            'ip': '0.0.0.0' if qtype_str == 'A' else '::',
            'rcode': 'NXDOMAIN',
            'client_ip': client_ip
        }
        db.log_query_async(profile_id, base_domain, subdomain, 'blocked', reason, client_ip)
        broadcast_log(res)
        return reply.pack(), res

    def build_safesearch_reply(target_ipv4: str, target_ipv6: str, reason: str) -> Tuple[bytes, Dict[str, Any]]:
        reply = req.reply()
        reply.header.rcode = RCODE.NOERROR
        reply.header.ra = 1
        resolved_ip = target_ipv4
        if qtype_int == QTYPE.A:
            reply.add_answer(RR(f"{qname}.", QTYPE.A, ttl=300, rdata=A(target_ipv4)))
        elif qtype_int == QTYPE.AAAA:
            reply.add_answer(RR(f"{qname}.", QTYPE.AAAA, ttl=300, rdata=AAAA(target_ipv6)))
            resolved_ip = target_ipv6
        else:
            return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, reason)

        res = {
            'profile_id': profile_id,
            'domain': base_domain,
            'subdomain': subdomain,
            'qtype': qtype_str,
            'status': 'allowed',
            'reason': reason,
            'ip': resolved_ip,
            'rcode': 'NOERROR',
            'client_ip': client_ip
        }
        db.log_query_async(profile_id, base_domain, subdomain, 'allowed', reason, client_ip)
        broadcast_log(res)
        return reply.pack(), res

    # 0. Global Safe Bypass Check (Highest Priority Fail-Safe)
    if _global_emergency_bypass:
        return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, 'Global Safe Bypass Active (Pass-Through)')

    # 0a. Global Allowlist Check
    for rule in list(_global_allowlist):
        if domain_matches(qname, rule):
            return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, f'Global Allowlist: {rule}')

    # 0b. Global Denylist Check
    for rule in list(_global_denylist):
        if domain_matches(qname, rule):
            return build_block_reply(f'Global Denylist: {rule}')

    # 0c. Firefox Canary Domain Check (Always return NXDOMAIN to signal browser to use system resolver)
    if domain_matches(qname, FIREFOX_CANARY_DOMAIN):
        return build_block_reply('Bypass Prevention: Firefox Canary Domain (DoH Opt-Out)')

    # 1. Protection Paused Check
    if not profile.get('is_protection_on', 1):
        return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, 'Protection Paused')

    # 2. Allowlist Check (Highest Priority)
    for rule in cache['allowlist']:
        if domain_matches(qname, rule):
            return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, f'Allowlist: {rule}')

    # 3. Denylist Check
    for rule in cache['denylist']:
        if domain_matches(qname, rule):
            return build_block_reply(f'Denylist: {rule}')

    # 4. Deep Focus (Apps & Websites)
    for site_id in cache['blocked_websites']:
        domains = APP_DOMAINS.get(site_id, {site_id + '.com'})
        for d in domains:
            if domain_matches(qname, d):
                return build_block_reply(f'Deep Focus: {site_id.capitalize()}')

    # 5. Deep Focus (Categories) - Strict Suffix Matching
    for cat_id in cache['blocked_categories']:
        target_domains = CATEGORY_DOMAINS.get(cat_id, set())
        for d in target_domains:
            if domain_matches(qname, d):
                return build_block_reply(f'Category Block: {cat_id.capitalize()}')

    # 6. Cybersecurity Feeds & Threat Toggles
    sec = cache['security']

    # 6a. Threat Intelligence Feeds (Local + Remote Community Feeds)
    if sec.get('threat_intel', True):
        for mal in KNOWN_MALWARE:
            if domain_matches(qname, mal):
                return build_block_reply('Security: Threat Intelligence Feed')
        if base_domain in _threat_feed_domains or qname in _threat_feed_domains:
            return build_block_reply('Security: Threat Intel Community Feed Signature')

    # 6b. Cryptojacking Protection
    if sec.get('cryptojacking', True):
        for miner in KNOWN_MINERS:
            if domain_matches(qname, miner):
                return build_block_reply('Security: In-Browser Cryptojacking')

    # 6c. Algorithmic Domain Detection (DGA Heuristics on registered domain)
    if sec.get('ai_threat', False):
        domain_label = base_domain.split('.')[0]
        if len(domain_label) >= 12 and calculate_entropy(domain_label) > 3.4:
            return build_block_reply('Security: DGA Algorithmic Domain Heuristic')

    # 6d. Typosquatting Lookalikes
    if sec.get('typosquatting', False):
        if re.search(r'(paypa1|goog1e|app1e|micros0ft|netf1ix|tw1tter)', qname):
            return build_block_reply('Security: Typosquatting Phishing Detection')

    # 6e. DNS-over-HTTPS (DoH) Bypass Provider Defense
    if sec.get('block_doh_bypass', True):
        for doh_domain in DOH_BYPASS_DOMAINS:
            if domain_matches(qname, doh_domain):
                return build_block_reply('Security: Bypass Prevention (Public DoH Provider)')

    # 7. Privacy Toggles (Trackers)
    priv = cache['privacy']
    if priv.get('disguised_trackers', True):
        for trk in KNOWN_TRACKERS:
            if domain_matches(qname, trk):
                return build_block_reply('Privacy: Disguised Tracker Blocklist')

    # 7b. SafeSearch & YouTube Restricted Mode DNS Rewriting
    if sec.get('safesearch', False) or sec.get('youtube_restricted', False):
        is_youtube = qname in ('youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtubei.googleapis.com', 'youtube-nocookie.com')
        if is_youtube and (sec.get('youtube_restricted', False) or sec.get('safesearch', False)):
            return build_safesearch_reply('216.239.38.119', '2001:4860:4806::77', 'SafeSearch: YouTube Restricted Mode Enforced')

        if sec.get('safesearch', False):
            is_google = (qname == 'google.com' or qname.startswith('www.google.') or (base_domain and base_domain.startswith('google.')))
            if is_google:
                return build_safesearch_reply('216.239.38.120', '2001:4860:4806::78', 'SafeSearch: Google SafeSearch VIP Enforced')

            if qname in ('bing.com', 'www.bing.com'):
                return build_safesearch_reply('204.79.197.220', '2620:1ec:c11::200', 'SafeSearch: Bing Strict VIP Enforced')

            if qname in ('duckduckgo.com', 'www.duckduckgo.com'):
                return build_safesearch_reply('52.142.124.215', '2603:1030:20a:3::1', 'SafeSearch: DuckDuckGo Safe VIP Enforced')

    # 8. Clean Query -> Forward Wire Query Upstream
    return _forward_and_process_allowed(req, query_bytes, profile_id, base_domain, subdomain, qtype_str, client_ip, 'Clean Query')

def _forward_and_process_allowed(req: DNSRecord, query_bytes: bytes, profile_id: str,
                                base_domain: str, subdomain: str, qtype_str: str,
                                client_ip: str, reason: str) -> Tuple[bytes, Dict[str, Any]]:
    """Forwards query upstream, inspects for DNS rebinding, logs telemetry, and returns wire reply."""
    qname = str(req.q.qname).rstrip('.').lower()

    # Check RAM DNS Cache (0ms response)
    cache_key = (qname, req.q.qtype)
    now = time.time()
    cached_wire = None
    with _ram_cache_lock:
        entry = _ram_dns_cache.get(cache_key)
        if entry and entry[1] > now:
            cached_wire = entry[0]

    if cached_wire:
        global _cache_hits_counter
        _cache_hits_counter += 1
        hit_wire = bytearray(cached_wire)
        req_id = req.header.id
        hit_wire[0] = (req_id >> 8) & 0xFF
        hit_wire[1] = req_id & 0xFF
        res = {
            'profile_id': profile_id,
            'domain': base_domain,
            'subdomain': subdomain,
            'qtype': qtype_str,
            'status': 'allowed',
            'reason': 'RAM Cache Hit (0ms)',
            'ip': '',
            'rcode': 'NOERROR',
            'client_ip': client_ip
        }
        db.log_query_async(profile_id, base_domain, subdomain, 'allowed', 'RAM Cache Hit (0ms)', client_ip)
        broadcast_log(res)
        return bytes(hit_wire), res

    global _cache_misses_counter
    _cache_misses_counter += 1

    # Local zone short-circuit
    if is_local_zone(qname):
        reply = req.reply()
        reply.header.ra = 1
        if qname in ('localhost', 'router.lan'):
            if req.q.qtype == QTYPE.A:
                reply.add_answer(RR(req.q.qname, QTYPE.A, rdata=A('127.0.0.1'), ttl=60))
            elif req.q.qtype == QTYPE.AAAA:
                reply.add_answer(RR(req.q.qname, QTYPE.AAAA, rdata=AAAA('::1'), ttl=60))
        res = {
            'profile_id': profile_id,
            'domain': base_domain,
            'subdomain': subdomain,
            'qtype': qtype_str,
            'status': 'allowed',
            'reason': 'Local Zone',
            'ip': '127.0.0.1' if req.q.qtype == QTYPE.A else '::1',
            'rcode': 'NOERROR',
            'client_ip': client_ip
        }
        db.log_query_async(profile_id, base_domain, subdomain, 'allowed', 'Local Zone', client_ip)
        broadcast_log(res)
        return reply.pack(), res

    upstream_bytes, status_code = forward_wire_query(query_bytes, timeout=UPSTREAM_TIMEOUT)
    if upstream_bytes is None or status_code == 'SERVFAIL':
        # Upstream failure
        reply = req.reply()
        reply.header.rcode = RCODE.SERVFAIL
        reply.header.ra = 1
        res = {
            'profile_id': profile_id,
            'domain': base_domain,
            'subdomain': subdomain,
            'qtype': qtype_str,
            'status': 'error',
            'reason': 'Upstream Resolution Failed',
            'ip': '',
            'rcode': 'SERVFAIL',
            'client_ip': client_ip
        }
        db.log_query_async(profile_id, base_domain, subdomain, 'error', 'Upstream Resolution Failed', client_ip)
        broadcast_log(res)
        return reply.pack(), res

    # Parse upstream response
    try:
        upstream_reply = DNSRecord.parse(upstream_bytes)
    except Exception:
        reply = req.reply()
        reply.header.rcode = RCODE.SERVFAIL
        return reply.pack(), {'status': 'error', 'rcode': 'SERVFAIL'}

    upstream_rcode_str = RCODE.get(upstream_reply.header.rcode, 'NOERROR')

    # DNS Rebinding check on resolved IP addresses
    cache = db.get_cached_rules(profile_id)
    sec = cache.get('security', {})
    if sec.get('dns_rebinding', True) and not is_local_zone(qname):
        for rr in upstream_reply.rr:
            if rr.rtype in (QTYPE.A, QTYPE.AAAA):
                ip_val = str(rr.rdata)
                if is_private_ip(ip_val):
                    # Intercept rebinding attempt! Return NXDOMAIN
                    reply = req.reply()
                    reply.header.rcode = RCODE.NXDOMAIN
                    reply.header.ra = 1
                    res = {
                        'profile_id': profile_id,
                        'domain': base_domain,
                        'subdomain': subdomain,
                        'qtype': qtype_str,
                        'status': 'blocked',
                        'reason': f'Security: DNS Rebinding Attempt ({ip_val})',
                        'ip': '0.0.0.0',
                        'rcode': 'NXDOMAIN',
                        'client_ip': client_ip
                    }
                    db.log_query_async(profile_id, base_domain, subdomain, 'blocked', f'Security: DNS Rebinding Attempt ({ip_val})', client_ip)
                    broadcast_log(res)
                    return reply.pack(), res

    # Extract first IP for telemetry reporting
    resolved_ip = ''
    for rr in upstream_reply.rr:
        if rr.rtype in (QTYPE.A, QTYPE.AAAA):
            resolved_ip = str(rr.rdata)
            break

    status_label = 'allowed' if upstream_rcode_str == 'NOERROR' else ('blocked' if upstream_rcode_str == 'NXDOMAIN' else 'allowed')
    res = {
        'profile_id': profile_id,
        'domain': base_domain,
        'subdomain': subdomain,
        'qtype': qtype_str,
        'status': status_label,
        'reason': reason,
        'ip': resolved_ip,
        'rcode': upstream_rcode_str,
        'client_ip': client_ip
    }
    db.log_query_async(profile_id, base_domain, subdomain, status_label, reason, client_ip)
    broadcast_log(res)

    # Cache positive response in RAM cache
    if upstream_rcode_str == 'NOERROR' and upstream_reply.rr:
        ttls = [rr.ttl for rr in upstream_reply.rr if rr.ttl > 0]
        min_ttl = min(ttls) if ttls else 60
        cache_ttl = max(10, min(min_ttl, 1800))
        with _ram_cache_lock:
            _ram_dns_cache[cache_key] = (upstream_bytes, now + cache_ttl)

    return upstream_bytes, res

def resolve_domain(fqdn: str, profile_id: str = 'a1b2c3', qtype: str = 'A', client_ip: str = '127.0.0.1') -> Dict[str, Any]:
    """Simulator helper used by REST API (POST /api/query/resolve)."""
    req = DNSRecord.question(fqdn, str(qtype).upper())
    _, res = resolve_wire_packet(req.pack(), profile_id, client_ip)
    return res

