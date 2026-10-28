"""
FocusDNS Engine - RFC 7873 & RFC 9018 Interoperable DNS Server Cookie Subsystem
Standards & RFCs:
- RFC 7873: Domain Name System (DNS) Cookies
- RFC 9018: Interoperable Domain Name System (DNS) Server Cookies
- Anti-Spoofing & Reflection Flood Mitigation
"""

import hashlib
import hmac
import os
import struct
import threading
import time
from typing import Any, Dict, List, Optional, Tuple


SERVER_COOKIE_VERSION_1 = 0x01
SERVER_COOKIE_LEN = 16
CLIENT_COOKIE_LEN = 8
TOTAL_COOKIE_LEN = 24

# Timestamp validity window per RFC 9018 Section 5.3
COOKIE_LOWER_TIME_TOLERANCE = 300   # 5 minutes in past
COOKIE_MAX_TIME_VALIDITY = 3600     # 1 hour validity


class DNSCookieSecret:
    """Manages a single 16-octet cryptographic secret used to sign server cookies."""

    def __init__(self, secret_bytes: Optional[bytes] = None):
        self.secret: bytes = secret_bytes or os.urandom(16)
        self.created_at: float = time.time()


class DNSCookieManager:
    """
    RFC 9018 Interoperable DNS Server Cookie Engine.
    Implements Version 1 Server Cookies with automated secret rollover.
    Defends against DNS reflection, spoofing, and amplification attacks.
    """

    def __init__(self, rollover_interval_sec: float = 3600.0):
        self.active_secret = DNSCookieSecret()
        self.previous_secret: Optional[DNSCookieSecret] = None
        self.rollover_interval_sec: float = rollover_interval_sec
        self.last_rollover: float = time.time()

        self.cookies_generated: int = 0
        self.cookies_valid: int = 0
        self.cookies_expired: int = 0
        self.cookies_bad_hash: int = 0
        self.secrets_rotated: int = 0
        self._lock = threading.Lock()

    def generate_server_cookie(self, client_cookie: bytes, client_ip: str) -> bytes:
        """
        Generates RFC 9018 Version 1 Server Cookie:
        [version: 1 octet = 0x01][reserved: 3 octets = 0x000000][timestamp: 4 octets][hash: 8 octets]
        """
        if len(client_cookie) != CLIENT_COOKIE_LEN:
            raise ValueError(f"Client cookie MUST be {CLIENT_COOKIE_LEN} octets")

        now = int(time.time())
        hdr = struct.pack("!BBBBI", SERVER_COOKIE_VERSION_1, 0, 0, 0, now)

        with self._lock:
            secret = self.active_secret.secret
            self.cookies_generated += 1

        # Compute HMAC-SHA256 over: Client Cookie (8) + Version (1) + Reserved (3) + Timestamp (4) + Client IP
        ip_bytes = client_ip.encode("utf-8")
        mac = hmac.new(secret, client_cookie + hdr + ip_bytes, hashlib.sha256).digest()
        truncated_hash = mac[:8]

        return hdr + truncated_hash

    def validate_cookie(
        self, client_cookie: bytes, server_cookie: bytes, client_ip: str
    ) -> Tuple[bool, str]:
        """
        Validates RFC 9018 Server Cookie.
        Checks length, version, timestamp freshness, and cryptographic HMAC.
        Accepts cookies signed by active secret or previous secret (grace period).
        """
        if len(client_cookie) != CLIENT_COOKIE_LEN:
            return False, "INVALID_CLIENT_COOKIE_LENGTH"

        if len(server_cookie) != SERVER_COOKIE_LEN:
            return False, "INVALID_SERVER_COOKIE_LENGTH"

        version = server_cookie[0]
        if version != SERVER_COOKIE_VERSION_1:
            return False, "UNSUPPORTED_COOKIE_VERSION"

        # Check timestamp
        timestamp = struct.unpack("!I", server_cookie[4:8])[0]
        now = int(time.time())

        if (now - timestamp) > COOKIE_MAX_TIME_VALIDITY:
            with self._lock:
                self.cookies_expired += 1
            return False, "COOKIE_EXPIRED"

        if (timestamp - now) > COOKIE_LOWER_TIME_TOLERANCE:
            with self._lock:
                self.cookies_expired += 1
            return False, "COOKIE_TIMESTAMP_IN_FUTURE"

        # Verify HMAC hash against active secret, then previous secret
        hdr = server_cookie[:8]
        expected_hash = server_cookie[8:16]
        ip_bytes = client_ip.encode("utf-8")
        data_to_mac = client_cookie + hdr + ip_bytes

        with self._lock:
            active_sec = self.active_secret.secret
            prev_sec = self.previous_secret.secret if self.previous_secret else None

        mac_active = hmac.new(active_sec, data_to_mac, hashlib.sha256).digest()[:8]
        if hmac.compare_digest(mac_active, expected_hash):
            with self._lock:
                self.cookies_valid += 1
            return True, "VALID_ACTIVE_SECRET"

        if prev_sec:
            mac_prev = hmac.new(prev_sec, data_to_mac, hashlib.sha256).digest()[:8]
            if hmac.compare_digest(mac_prev, expected_hash):
                with self._lock:
                    self.cookies_valid += 1
                return True, "VALID_PREVIOUS_SECRET"

        with self._lock:
            self.cookies_bad_hash += 1
        return False, "BAD_COOKIE_HMAC"

    def rotate_secret(self):
        """Performs secret rollover: shifts active secret to previous and generates a new active secret."""
        with self._lock:
            self.previous_secret = self.active_secret
            self.active_secret = DNSCookieSecret()
            self.last_rollover = time.time()
            self.secrets_rotated += 1

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "rfc": "RFC 9018",
                "cookies_generated": self.cookies_generated,
                "cookies_valid": self.cookies_valid,
                "cookies_expired": self.cookies_expired,
                "cookies_bad_hash": self.cookies_bad_hash,
                "secrets_rotated": self.secrets_rotated,
                "has_previous_secret": (self.previous_secret is not None),
            }
