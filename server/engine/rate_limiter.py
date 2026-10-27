"""
FocusDNS Engine - Response Rate Limiting (RRL) & Anti-Amplification Shield
Standards & Mechanics:
- Standard DNS Response Rate Limiting (RRL) for authoritative and recursive resolvers
- Token Bucket per Client IP & Subnet (/24 IPv4, /48 IPv6)
- SLIP Mitigation: Sends truncated responses (TC=1) for 1-in-N dropped queries to force TCP validation
- Pseudo-Random Subdomain (PRSD / Water Torture) NXDOMAIN Flood Protection
"""

import ipaddress
import threading
import time
from typing import Dict, Optional, Tuple, Any

# Default RRL Parameters
DEFAULT_CLIENT_QPS = 50.0            # Max queries per second per single IP
DEFAULT_CLIENT_BURST = 100.0         # Burst allowance
DEFAULT_SUBNET_QPS = 200.0           # Max queries per second per /24 or /48 subnet
DEFAULT_SUBNET_BURST = 400.0         # Subnet burst allowance
DEFAULT_SLIP_RATIO = 2               # 1 in every N dropped responses receives TC=1
DEFAULT_NXDOMAIN_CEILING_QPS = 20.0  # Max NXDOMAINs per second before dampening


class TokenBucket:
    """Thread-safe token bucket rate limiter."""

    __slots__ = ("rate", "burst", "tokens", "last_update")

    def __init__(self, rate: float, burst: float):
        self.rate = rate
        self.burst = burst
        self.tokens = burst
        self.last_update = time.time()

    def consume(self, amount: float = 1.0, now: Optional[float] = None) -> bool:
        t = time.time() if now is None else now
        elapsed = t - self.last_update
        self.last_update = t

        # Refill tokens
        self.tokens = min(self.burst, self.tokens + (elapsed * self.rate))

        if self.tokens >= amount:
            self.tokens -= amount
            return True
        return False


class RateLimitAction:
    """Result of rate limit check."""

    PASS = "PASS"          # Allowed to proceed
    DROP = "DROP"          # Silently discarded (amplification defense)
    SLIP_TC = "SLIP_TC"    # Respond with TC=1 to force TCP handshake verification


class DNSRateLimiter:
    """
    High-performance DNS Response Rate Limiter.
    Defends FocusDNS against DNS reflection attacks, DDoS amplification,
    and cache-poisoning Water Torture attacks.
    """

    def __init__(
        self,
        client_qps: float = DEFAULT_CLIENT_QPS,
        client_burst: float = DEFAULT_CLIENT_BURST,
        subnet_qps: float = DEFAULT_SUBNET_QPS,
        subnet_burst: float = DEFAULT_SUBNET_BURST,
        slip_ratio: int = DEFAULT_SLIP_RATIO,
        nxdomain_qps: float = DEFAULT_NXDOMAIN_CEILING_QPS,
        max_buckets: int = 50000,
    ):
        self.client_qps = client_qps
        self.client_burst = client_burst
        self.subnet_qps = subnet_qps
        self.subnet_burst = subnet_burst
        self.slip_ratio = slip_ratio
        self.nxdomain_qps = nxdomain_qps
        self.max_buckets = max_buckets

        # IP -> TokenBucket
        self._client_buckets: Dict[str, TokenBucket] = {}
        # Subnet -> TokenBucket
        self._subnet_buckets: Dict[str, TokenBucket] = {}
        # Apex -> TokenBucket (NXDOMAIN dampener)
        self._nxdomain_buckets: Dict[str, TokenBucket] = {}

        # Slip counter per client
        self._slip_counters: Dict[str, int] = {}

        self._lock = threading.Lock()

        # Telemetry
        self._total_checked = 0
        self._total_allowed = 0
        self._total_dropped = 0
        self._total_slipped_tc = 0

    @staticmethod
    def get_subnet_key(ip_str: str) -> str:
        """Computes /24 for IPv4 or /48 for IPv6 to aggregate nearby addresses."""
        try:
            ip_obj = ipaddress.ip_address(ip_str)
            if ip_obj.version == 4:
                return ".".join(ip_str.split(".")[:3]) + ".0/24"
            else:
                return ":".join(ip_str.split(":")[:3]) + "::/48"
        except ValueError:
            return "unknown-subnet"

    def check_query_rate(self, client_ip: str) -> str:
        """
        Evaluates incoming query from client IP.
        Returns RateLimitAction (PASS, DROP, or SLIP_TC).
        """
        now = time.time()
        subnet_key = self.get_subnet_key(client_ip)

        with self._lock:
            self._total_checked += 1

            # Evict if capacity exceeded
            if len(self._client_buckets) > self.max_buckets:
                self._client_buckets.clear()
                self._subnet_buckets.clear()

            # 1. Check Subnet bucket
            if subnet_key not in self._subnet_buckets:
                self._subnet_buckets[subnet_key] = TokenBucket(self.subnet_qps, self.subnet_burst)
            subnet_allowed = self._subnet_buckets[subnet_key].consume(1.0, now)

            # 2. Check Client IP bucket
            if client_ip not in self._client_buckets:
                self._client_buckets[client_ip] = TokenBucket(self.client_qps, self.client_burst)
            client_allowed = self._client_buckets[client_ip].consume(1.0, now)

            if subnet_allowed and client_allowed:
                self._total_allowed += 1
                return RateLimitAction.PASS

            # Rate limit exceeded -> Apply SLIP policy
            self._slip_counters[client_ip] = self._slip_counters.get(client_ip, 0) + 1
            counter = self._slip_counters[client_ip]

            if counter % self.slip_ratio == 0:
                self._total_slipped_tc += 1
                return RateLimitAction.SLIP_TC
            else:
                self._total_dropped += 1
                return RateLimitAction.DROP

    def check_nxdomain_rate(self, apex_domain: str) -> bool:
        """
        Protects against Pseudo-Random Subdomain (PRSD) Water Torture attacks.
        Returns True if NXDOMAIN response is permitted, False if throttled.
        """
        clean = apex_domain.strip().lower().rstrip(".")
        now = time.time()

        with self._lock:
            if clean not in self._nxdomain_buckets:
                if len(self._nxdomain_buckets) > 10000:
                    self._nxdomain_buckets.clear()
                self._nxdomain_buckets[clean] = TokenBucket(self.nxdomain_qps, self.nxdomain_qps * 2)
            return self._nxdomain_buckets[clean].consume(1.0, now)

    def get_stats(self) -> Dict[str, Any]:
        """Returns real-time rate limiter telemetry."""
        with self._lock:
            return {
                "total_checked": self._total_checked,
                "total_allowed": self._total_allowed,
                "total_dropped": self._total_dropped,
                "total_slipped_tc": self._total_slipped_tc,
                "total_slipped": self._total_slipped_tc,
                "active_client_buckets": len(self._client_buckets),
                "tracked_ips": len(self._client_buckets),
                "active_subnet_buckets": len(self._subnet_buckets),
                "active_nxdomain_buckets": len(self._nxdomain_buckets),
            }

    def reset(self):
        """Resets all token buckets and counters."""
        with self._lock:
            self._client_buckets.clear()
            self._subnet_buckets.clear()
            self._nxdomain_buckets.clear()
            self._slip_counters.clear()
            self._total_checked = 0
            self._total_allowed = 0
            self._total_dropped = 0
            self._total_slipped_tc = 0
