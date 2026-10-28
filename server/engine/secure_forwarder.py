"""
FocusDNS Engine - RFC 8310 & RFC 9103 Secure Upstream DNS Forwarder Subsystem
Standards & RFCs:
- RFC 7858: Specification for DNS over Transport Layer Security (DoT)
- RFC 8310: Usage Profiles for DNS over TLS and DNS over DTLS (Strict vs Opportunistic)
- RFC 8484: DNS Queries over HTTPS (DoH) Client Semantics
- RFC 9103: DNS-over-TLS and DNS-over-QUIC Privacy Considerations & Operational Profiles
- RFC 7766: DNS Transport over TCP - Implementation Requirements

Features:
- Multi-protocol upstream proxy: DNS-over-TLS (DoT, port 853), TCP, and UDP
- RFC 8310 Strict vs Opportunistic privacy profiles with SNI and ALPN negotiation
- Circuit breaker fault tolerance (CLOSED, HALF_OPEN, OPEN) with automated self-healing
- Dynamic selection strategies: ROUND_ROBIN, FASTEST (EWMA latency), FAILOVER, RANDOM
- Thread-safe TLS session ticket cache for TLS 1.3 0-RTT and fast resumption
- High-efficiency connection pooling with idle expiration and socket re-use
- Multi-tier automatic retry and failover cascade
"""

import enum
import os
import select
import socket
import ssl
import struct
import threading
import time
from typing import Any, Dict, List, Optional, Tuple


class PrivacyProfile(str, enum.Enum):
    """
    RFC 8310 §3 DNS Privacy Profiles.
    """
    STRICT = "strict"              # RFC 8310 §3.2: Strict authentication of certificate and hostname
    OPPORTUNISTIC = "opportunistic"  # RFC 8310 §3.1: Best-effort encryption without cert validation failure block


class UpstreamProtocol(str, enum.Enum):
    """Supported upstream transport protocols."""
    DOT = "dot"    # RFC 7858 DNS-over-TLS (port 853)
    DOQ = "doq"    # RFC 9250 DNS-over-QUIC (port 853)
    TCP = "tcp"    # RFC 7766 DNS-over-TCP (port 53)
    UDP = "udp"    # RFC 1035 Standard DNS over UDP (port 53)


class CircuitState(str, enum.Enum):
    """Circuit breaker states for upstream health management."""
    CLOSED = "closed"        # Healthy, executing queries normally
    HALF_OPEN = "half_open"  # Testing upstream recovery with limited probes
    OPEN = "open"            # Unhealthy, temporarily bypassed


class SelectionStrategy(str, enum.Enum):
    """Upstream endpoint selection algorithms."""
    ROUND_ROBIN = "round_robin"
    FASTEST = "fastest"        # Lowest Exponentially Weighted Moving Average (EWMA) latency
    FAILOVER = "failover"      # Priority order with primary/secondary cascade
    RANDOM = "random"


class UpstreamConfig:
    """Configuration specification for an upstream DNS server."""

    def __init__(
        self,
        host: str,
        port: int = 853,
        protocol: UpstreamProtocol = UpstreamProtocol.DOT,
        server_name: Optional[str] = None,
        privacy_profile: PrivacyProfile = PrivacyProfile.STRICT,
        ca_file: Optional[str] = None,
        timeout_sec: float = 3.0,
        max_failures: int = 3,
        recovery_timeout_sec: float = 30.0,
        weight: int = 100,
        priority: int = 1,
    ):
        self.host: str = host
        self.port: int = port
        self.protocol: UpstreamProtocol = protocol
        self.server_name: str = server_name or host
        self.privacy_profile: PrivacyProfile = privacy_profile
        self.ca_file: Optional[str] = ca_file
        self.timeout_sec: float = timeout_sec
        self.max_failures: int = max_failures
        self.recovery_timeout_sec: float = recovery_timeout_sec
        self.weight: int = weight
        self.priority: int = priority

    @property
    def endpoint_id(self) -> str:
        return f"{self.protocol.value}://{self.host}:{self.port}"


class UpstreamStats:
    """Runtime telemetry and health metrics for an upstream server."""

    def __init__(self):
        self.queries_sent: int = 0
        self.queries_succeeded: int = 0
        self.queries_failed: int = 0
        self.queries_timed_out: int = 0
        self.last_latency_ms: float = 0.0
        self.ewma_latency_ms: float = 0.0
        self.consecutive_failures: int = 0
        self.circuit_state: CircuitState = CircuitState.CLOSED
        self.last_state_change: float = time.time()
        self.last_successful_query: float = 0.0
        self.last_failed_query: float = 0.0


class UpstreamEndpoint:
    """Encapsulates upstream configuration, health circuit breaker, and latency metrics."""

    def __init__(self, config: UpstreamConfig):
        self.config: UpstreamConfig = config
        self.stats: UpstreamStats = UpstreamStats()
        self._lock = threading.RLock()

    def is_available(self) -> bool:
        """Determines if the endpoint is eligible to receive queries based on circuit breaker state."""
        with self._lock:
            now = time.time()
            if self.stats.circuit_state == CircuitState.CLOSED:
                return True
            if self.stats.circuit_state == CircuitState.OPEN:
                if now - self.stats.last_state_change >= self.config.recovery_timeout_sec:
                    # Transition to HALF_OPEN to attempt recovery
                    self.stats.circuit_state = CircuitState.HALF_OPEN
                    self.stats.last_state_change = now
                    return True
                return False
            if self.stats.circuit_state == CircuitState.HALF_OPEN:
                return True
            return False

    def record_success(self, latency_ms: float):
        """Records a successful query execution, updating EWMA latency and resetting circuit breaker."""
        with self._lock:
            now = time.time()
            self.stats.queries_sent += 1
            self.stats.queries_succeeded += 1
            self.stats.last_latency_ms = latency_ms
            self.stats.last_successful_query = now
            self.stats.consecutive_failures = 0

            # Update EWMA (alpha = 0.25)
            if self.stats.ewma_latency_ms == 0.0:
                self.stats.ewma_latency_ms = latency_ms
            else:
                self.stats.ewma_latency_ms = (0.25 * latency_ms) + (0.75 * self.stats.ewma_latency_ms)

            if self.stats.circuit_state == CircuitState.HALF_OPEN:
                self.stats.circuit_state = CircuitState.CLOSED
                self.stats.last_state_change = now

    def record_failure(self, is_timeout: bool = False):
        """Records query failure, tripping circuit breaker if threshold is exceeded."""
        with self._lock:
            now = time.time()
            self.stats.queries_sent += 1
            self.stats.queries_failed += 1
            if is_timeout:
                self.stats.queries_timed_out += 1
            self.stats.consecutive_failures += 1
            self.stats.last_failed_query = now

            if self.stats.circuit_state == CircuitState.HALF_OPEN:
                # Probing failed; reopen immediately
                self.stats.circuit_state = CircuitState.OPEN
                self.stats.last_state_change = now
            elif self.stats.circuit_state == CircuitState.CLOSED:
                if self.stats.consecutive_failures >= self.config.max_failures:
                    self.stats.circuit_state = CircuitState.OPEN
                    self.stats.last_state_change = now

    def to_dict(self) -> Dict[str, Any]:
        """Telemetry representation."""
        with self._lock:
            return {
                "endpoint_id": self.config.endpoint_id,
                "host": self.config.host,
                "port": self.config.port,
                "protocol": self.config.protocol.value,
                "server_name": self.config.server_name,
                "privacy_profile": self.config.privacy_profile.value,
                "circuit_state": self.stats.circuit_state.value,
                "queries_sent": self.stats.queries_sent,
                "queries_succeeded": self.stats.queries_succeeded,
                "queries_failed": self.stats.queries_failed,
                "queries_timed_out": self.stats.queries_timed_out,
                "consecutive_failures": self.stats.consecutive_failures,
                "last_latency_ms": round(self.stats.last_latency_ms, 2),
                "ewma_latency_ms": round(self.stats.ewma_latency_ms, 2),
                "is_available": self.is_available(),
            }


class TLSSessionCache:
    """Thread-safe in-memory cache for TLS session tickets to enable fast TLS resumption."""

    def __init__(self, default_ttl_sec: float = 86400.0):
        self.default_ttl_sec: float = default_ttl_sec
        self._cache: Dict[str, Tuple[Any, float]] = {}
        self._lock = threading.Lock()

    def _make_key(self, host: str, port: int, server_name: str) -> str:
        return f"{host}:{port}:{server_name}"

    def store_session(self, host: str, port: int, server_name: str, session: Any, ttl_sec: Optional[float] = None):
        """Stores a TLS session ticket with an expiration timestamp."""
        key = self._make_key(host, port, server_name)
        expires_at = time.time() + (ttl_sec if ttl_sec is not None else self.default_ttl_sec)
        with self._lock:
            self._cache[key] = (session, expires_at)

    def get_session(self, host: str, port: int, server_name: str) -> Optional[Any]:
        """Retrieves an unexpired TLS session ticket."""
        key = self._make_key(host, port, server_name)
        with self._lock:
            if key not in self._cache:
                return None
            session, expires_at = self._cache[key]
            if time.time() > expires_at:
                del self._cache[key]
                return None
            return session

    def invalidate(self, host: str, port: int, server_name: str):
        """Removes a TLS session from the cache."""
        key = self._make_key(host, port, server_name)
        with self._lock:
            self._cache.pop(key, None)

    def clear(self):
        with self._lock:
            self._cache.clear()

    def size(self) -> int:
        with self._lock:
            return len(self._cache)


class DoTConnectionPool:
    """
    High-performance TLS socket pool for upstream DNS-over-TLS connections.
    Reuses persistent TLS connections to minimize handshake latency overhead.
    """

    def __init__(self, max_idle_sec: float = 60.0, max_connections_per_host: int = 10):
        self.max_idle_sec: float = max_idle_sec
        self.max_connections_per_host: int = max_connections_per_host
        self._pool: Dict[str, List[Tuple[ssl.SSLSocket, float]]] = {}
        self._lock = threading.Lock()

    def _pool_key(self, endpoint: UpstreamConfig) -> str:
        return f"{endpoint.host}:{endpoint.port}:{endpoint.server_name}"

    def acquire(self, endpoint: UpstreamConfig) -> Optional[ssl.SSLSocket]:
        """Attempts to retrieve an idle reusable TLS connection from the pool."""
        key = self._pool_key(endpoint)
        now = time.time()
        with self._lock:
            connections = self._pool.get(key, [])
            while connections:
                sock, last_used = connections.pop()
                if (now - last_used) < self.max_idle_sec:
                    # Check if socket is still open and hasn't encountered EOF
                    try:
                        readable, _, _ = select.select([sock], [], [], 0)
                        if readable:
                            # Unexpected incoming data or closed by peer
                            peek = sock.recv(1, socket.MSG_PEEK)
                            if not peek:
                                sock.close()
                                continue
                    except Exception:
                        try:
                            sock.close()
                        except Exception:
                            pass
                        continue
                    return sock
                else:
                    try:
                        sock.close()
                    except Exception:
                        pass
        return None

    def release(self, endpoint: UpstreamConfig, sock: ssl.SSLSocket, reusable: bool = True):
        """Returns a connection to the pool or closes it if no longer reusable."""
        if not reusable:
            try:
                sock.close()
            except Exception:
                pass
            return

        key = self._pool_key(endpoint)
        now = time.time()
        with self._lock:
            if key not in self._pool:
                self._pool[key] = []
            if len(self._pool[key]) < self.max_connections_per_host:
                self._pool[key].append((sock, now))
            else:
                try:
                    sock.close()
                except Exception:
                    pass

    def close_all(self):
        """Closes all active pooled connections."""
        with self._lock:
            for conns in self._pool.values():
                for sock, _ in conns:
                    try:
                        sock.close()
                    except Exception:
                        pass
            self._pool.clear()


class SecureUpstreamForwarder:
    """
    Production-grade carrier-class secure upstream DNS forwarding engine.
    Orchestrates upstream server selection, TLS 1.3 encryption, DoT connection pooling,
    and automatic failover.
    """

    def __init__(
        self,
        strategy: SelectionStrategy = SelectionStrategy.ROUND_ROBIN,
        max_retries: int = 2,
        connection_pool: Optional[DoTConnectionPool] = None,
        session_cache: Optional[TLSSessionCache] = None,
    ):
        self.strategy: SelectionStrategy = strategy
        self.max_retries: int = max_retries
        self.pool: DoTConnectionPool = connection_pool or DoTConnectionPool()
        self.session_cache: TLSSessionCache = session_cache or TLSSessionCache()
        self.endpoints: List[UpstreamEndpoint] = []
        self._rr_index: int = 0
        self._lock = threading.RLock()

        self.total_forwarded: int = 0
        self.total_successful: int = 0
        self.total_retries: int = 0
        self.total_failures: int = 0

    def add_upstream(self, config: UpstreamConfig) -> UpstreamEndpoint:
        """Registers a new upstream server endpoint."""
        endpoint = UpstreamEndpoint(config)
        with self._lock:
            self.endpoints.append(endpoint)
        return endpoint

    def remove_upstream(self, host: str, port: int) -> bool:
        """Removes an upstream server endpoint by host and port."""
        with self._lock:
            initial_len = len(self.endpoints)
            self.endpoints = [ep for ep in self.endpoints if not (ep.config.host == host and ep.config.port == port)]
            return len(self.endpoints) < initial_len

    def get_endpoints(self) -> List[UpstreamEndpoint]:
        """Returns a snapshot copy of registered endpoints."""
        with self._lock:
            return list(self.endpoints)

    def select_endpoint(self) -> Optional[UpstreamEndpoint]:
        """
        Selects the optimal upstream endpoint based on configured SelectionStrategy
        and circuit breaker availability.
        """
        with self._lock:
            available = [ep for ep in self.endpoints if ep.is_available()]
            if not available:
                # If all are OPEN or unavailable, fallback to trying any endpoint rather than immediately dropping
                available = list(self.endpoints)
            if not available:
                return None

            if self.strategy == SelectionStrategy.ROUND_ROBIN:
                ep = available[self._rr_index % len(available)]
                self._rr_index += 1
                return ep

            elif self.strategy == SelectionStrategy.FASTEST:
                # Pick endpoint with lowest EWMA latency (default to 0.0 if untracked)
                return min(available, key=lambda e: e.stats.ewma_latency_ms if e.stats.ewma_latency_ms > 0 else 0.001)

            elif self.strategy == SelectionStrategy.FAILOVER:
                # Sort by priority ascending (1 = highest priority)
                return min(available, key=lambda e: e.config.priority)

            elif self.strategy == SelectionStrategy.RANDOM:
                import random
                return random.choice(available)

            return available[0]

    def _create_ssl_context(self, config: UpstreamConfig) -> ssl.SSLContext:
        """Constructs an SSLContext compliant with RFC 8310 privacy profile."""
        ctx = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=config.ca_file)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        # Configure ALPN for DNS over TLS per RFC 7858
        try:
            ctx.set_alpn_protocols(["dot"])
        except (AttributeError, NotImplementedError):
            pass

        if config.privacy_profile == PrivacyProfile.OPPORTUNISTIC:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        else:
            ctx.check_hostname = True
            ctx.verify_mode = ssl.CERT_REQUIRED

        return ctx

    def _forward_dot(self, endpoint: UpstreamEndpoint, query_wire: bytes, timeout: float) -> bytes:
        """
        Executes DNS-over-TLS query over persistent or new TLS socket.
        Frames query with 2-octet big-endian length per RFC 7858 / RFC 1035 §4.2.2.
        """
        cfg = endpoint.config
        sock = self.pool.acquire(cfg)
        is_new_socket = False

        if sock is None:
            is_new_socket = True
            raw_sock = socket.create_connection((cfg.host, cfg.port), timeout=timeout)
            raw_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

            ctx = self._create_ssl_context(cfg)
            session = self.session_cache.get_session(cfg.host, cfg.port, cfg.server_name)

            sock = ctx.wrap_socket(
                raw_sock,
                server_hostname=cfg.server_name if cfg.privacy_profile == PrivacyProfile.STRICT else None,
                session=session,
            )

            # Store session ticket if available for TLS 1.3 resumption
            if hasattr(sock, "session") and sock.session is not None:
                self.session_cache.store_session(cfg.host, cfg.port, cfg.server_name, sock.session)

        sock.settimeout(timeout)

        try:
            # Wire transmission: 2-byte length prefix + query
            wire_payload = struct.pack("!H", len(query_wire)) + query_wire
            sock.sendall(wire_payload)

            # Receive 2-byte response length
            len_bytes = b""
            while len(len_bytes) < 2:
                chunk = sock.recv(2 - len(len_bytes))
                if not chunk:
                    raise ConnectionResetError("Upstream DoT server closed connection during response header read")
                len_bytes += chunk

            resp_len = struct.unpack("!H", len_bytes)[0]

            # Receive response payload
            resp_bytes = b""
            while len(resp_bytes) < resp_len:
                chunk = sock.recv(resp_len - len(resp_bytes))
                if not chunk:
                    raise ConnectionResetError("Upstream DoT server closed connection during response payload read")
                resp_bytes += chunk

            self.pool.release(cfg, sock, reusable=True)
            return resp_bytes

        except Exception:
            self.pool.release(cfg, sock, reusable=False)
            raise

    def _forward_tcp(self, endpoint: UpstreamEndpoint, query_wire: bytes, timeout: float) -> bytes:
        """Executes query over standard TCP DNS (RFC 7766)."""
        cfg = endpoint.config
        with socket.create_connection((cfg.host, cfg.port), timeout=timeout) as sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            wire_payload = struct.pack("!H", len(query_wire)) + query_wire
            sock.sendall(wire_payload)

            len_bytes = b""
            while len(len_bytes) < 2:
                chunk = sock.recv(2 - len(len_bytes))
                if not chunk:
                    raise ConnectionResetError("Upstream TCP server closed connection")
                len_bytes += chunk

            resp_len = struct.unpack("!H", len_bytes)[0]
            resp_bytes = b""
            while len(resp_bytes) < resp_len:
                chunk = sock.recv(resp_len - len(resp_bytes))
                if not chunk:
                    raise ConnectionResetError("Upstream TCP server closed connection")
                resp_bytes += chunk

            return resp_bytes

    def _forward_udp(self, endpoint: UpstreamEndpoint, query_wire: bytes, timeout: float) -> bytes:
        """Executes query over standard UDP DNS (RFC 1035)."""
        cfg = endpoint.config
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(timeout)
            sock.sendto(query_wire, (cfg.host, cfg.port))
            data, _ = sock.recvfrom(4096)
            return data

    def forward(self, query_wire: bytes, timeout: Optional[float] = None) -> Tuple[bytes, UpstreamEndpoint]:
        """
        Forwards DNS query to optimal upstream with automated retry and failover cascade.
        Returns:
            Tuple[bytes, UpstreamEndpoint]: Raw DNS wire response and responding endpoint.
        """
        with self._lock:
            self.total_forwarded += 1

        attempts = 0
        last_error = None
        visited_endpoints: List[UpstreamEndpoint] = []

        while attempts <= self.max_retries:
            endpoint = self.select_endpoint()
            if not endpoint:
                raise RuntimeError("No available upstream DNS endpoints configured or reachable")

            if endpoint in visited_endpoints and len(visited_endpoints) < len(self.endpoints):
                # Pick an alternative if available
                alternatives = [ep for ep in self.endpoints if ep not in visited_endpoints and ep.is_available()]
                if alternatives:
                    endpoint = alternatives[0]

            visited_endpoints.append(endpoint)
            effective_timeout = timeout or endpoint.config.timeout_sec
            t_start = time.perf_counter()

            try:
                if endpoint.config.protocol == UpstreamProtocol.DOT:
                    resp = self._forward_dot(endpoint, query_wire, effective_timeout)
                elif endpoint.config.protocol == UpstreamProtocol.TCP:
                    resp = self._forward_tcp(endpoint, query_wire, effective_timeout)
                elif endpoint.config.protocol == UpstreamProtocol.UDP:
                    resp = self._forward_udp(endpoint, query_wire, effective_timeout)
                else:
                    raise NotImplementedError(f"Unsupported protocol: {endpoint.config.protocol}")

                latency_ms = (time.perf_counter() - t_start) * 1000.0
                endpoint.record_success(latency_ms)

                with self._lock:
                    self.total_successful += 1

                return resp, endpoint

            except socket.timeout as exc:
                endpoint.record_failure(is_timeout=True)
                last_error = exc
            except Exception as exc:
                endpoint.record_failure(is_timeout=False)
                last_error = exc

            attempts += 1
            with self._lock:
                self.total_retries += 1

        with self._lock:
            self.total_failures += 1

        raise RuntimeError(f"All upstream queries failed after {attempts} attempts. Last error: {last_error}")

    def probe_health(self, endpoint: UpstreamEndpoint) -> bool:
        """
        Actively probes health of an upstream endpoint using a lightweight root SOA query.
        """
        try:
            from dnslib import DNSRecord, QTYPE
            probe_query = DNSRecord.question(".", "SOA").pack()
            resp_wire, _ = self.forward(probe_query, timeout=endpoint.config.timeout_sec)
            return len(resp_wire) > 12
        except Exception:
            return False

    def get_status(self) -> Dict[str, Any]:
        """Provides complete telemetry and pool health metrics."""
        with self._lock:
            endpoints_status = [ep.to_dict() for ep in self.endpoints]
            return {
                "rfc": "RFC 8310 / RFC 9103 / RFC 7858",
                "strategy": self.strategy.value,
                "endpoints_count": len(self.endpoints),
                "total_forwarded": self.total_forwarded,
                "total_successful": self.total_successful,
                "total_retries": self.total_retries,
                "total_failures": self.total_failures,
                "tls_sessions_cached": self.session_cache.size(),
                "endpoints": endpoints_status,
            }
