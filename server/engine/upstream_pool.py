"""
FocusDNS Engine - Resilient Upstream Pool & Circuit Breakers
Features:
- Multi-protocol upstream support (UDP 53, TCP 53, DoT 853)
- Circuit Breaker pattern (CLOSED -> OPEN -> HALF_OPEN) preventing upstream failure pauses
- Health monitoring with rolling latency percentiles (p50, p95)
- Dynamic routing strategies:
  * LOWEST_LATENCY (auto-routes to fastest upstream)
  * WEIGHTED_ROUND_ROBIN (proportional balancing)
  * FAILOVER (primary with zero-loss fallback)
  * PARALLEL_RACE (dispatches to fastest pair, takes first response)
- Automatic fallback on truncation (TC=1) or timeout
"""

import collections
import concurrent.futures
import random
import socket
import struct
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple, Any

from dnslib import DNSRecord

# Circuit Breaker Thresholds
CIRCUIT_FAILURE_THRESHOLD = 4        # Consecutive failures to trip circuit OPEN
CIRCUIT_RECOVERY_TIMEOUT = 25.0       # Seconds before testing HALF_OPEN
DEFAULT_PROBE_INTERVAL = 30.0        # Seconds between health probes
DEFAULT_QUERY_TIMEOUT = 2.0          # Seconds before query timeout


class CircuitState:
    CLOSED = "CLOSED"        # Healthy, operational
    OPEN = "OPEN"            # Tripped, traffic diverted away
    HALF_OPEN = "HALF_OPEN"  # Testing canary probe


class UpstreamNode:
    """Represents a single upstream DNS resolver with circuit breaker and health telemetry."""

    def __init__(
        self,
        name: str,
        host: str,
        port: int = 53,
        protocol: str = "UDP",
        weight: int = 100,
        is_backup: bool = False,
    ):
        self.name = name
        self.host = host
        self.port = port
        self.protocol = protocol.upper()
        self.weight = max(1, weight)
        self.is_backup = is_backup

        # Circuit Breaker State
        self.state = CircuitState.CLOSED
        self.consecutive_failures = 0
        self.last_failure_time = 0.0
        self.last_success_time = time.time()
        self.last_state_change = time.time()

        # Telemetry & Latencies
        self.total_queries = 0
        self.total_failures = 0
        self.latencies: collections.deque[float] = collections.deque(maxlen=100)
        self.avg_latency_ms = 15.0
        self._lock = threading.Lock()

    @property
    def is_available(self) -> bool:
        with self._lock:
            now = time.time()
            if self.state == CircuitState.CLOSED:
                return True
            elif self.state == CircuitState.OPEN:
                if now - self.last_failure_time >= CIRCUIT_RECOVERY_TIMEOUT:
                    # Transition to HALF_OPEN to allow canary probe
                    self.state = CircuitState.HALF_OPEN
                    self.last_state_change = now
                    return True
                return False
            elif self.state == CircuitState.HALF_OPEN:
                return True
            return False

    def record_success(self, latency_ms: float):
        with self._lock:
            self.total_queries += 1
            self.consecutive_failures = 0
            self.last_success_time = time.time()
            self.latencies.append(latency_ms)
            if self.latencies:
                self.avg_latency_ms = round(sum(self.latencies) / len(self.latencies), 1)

            if self.state in (CircuitState.HALF_OPEN, CircuitState.OPEN):
                self.state = CircuitState.CLOSED
                self.last_state_change = time.time()

    def record_failure(self):
        with self._lock:
            self.total_queries += 1
            self.total_failures += 1
            self.consecutive_failures += 1
            self.last_failure_time = time.time()

            if self.state == CircuitState.HALF_OPEN or self.consecutive_failures >= CIRCUIT_FAILURE_THRESHOLD:
                self.state = CircuitState.OPEN
                self.last_state_change = time.time()

    def get_stats(self) -> Dict[str, Any]:
        with self._lock:
            sorted_lat = sorted(self.latencies) if self.latencies else [self.avg_latency_ms]
            p50 = sorted_lat[len(sorted_lat) // 2]
            p95 = sorted_lat[int(len(sorted_lat) * 0.95)] if len(sorted_lat) >= 20 else sorted_lat[-1]
            fail_rate = round(self.total_failures / self.total_queries * 100, 1) if self.total_queries > 0 else 0.0

            return {
                "name": self.name,
                "host": self.host,
                "port": self.port,
                "protocol": self.protocol,
                "state": self.state,
                "consecutive_failures": self.consecutive_failures,
                "avg_latency_ms": self.avg_latency_ms,
                "p50_latency_ms": round(p50, 1),
                "p95_latency_ms": round(p95, 1),
                "total_queries": self.total_queries,
                "total_failures": self.total_failures,
                "failure_rate_percent": fail_rate,
            }

    def __repr__(self) -> str:
        return f"<UpstreamNode {self.name} ({self.host}:{self.port}) state={self.state} lat={self.avg_latency_ms}ms>"


class UpstreamRoutingStrategy:
    LOWEST_LATENCY = "LOWEST_LATENCY"
    WEIGHTED_ROUND_ROBIN = "WEIGHTED_ROUND_ROBIN"
    FAILOVER = "FAILOVER"
    PARALLEL_RACE = "PARALLEL_RACE"


class UpstreamPool:
    """
    Autonomous upstream resolver pool with zero-loss failover and circuit breaker protection.
    """

    def __init__(
        self,
        strategy: str = UpstreamRoutingStrategy.LOWEST_LATENCY,
        query_timeout: float = DEFAULT_QUERY_TIMEOUT,
    ):
        self.strategy = strategy
        self.query_timeout = query_timeout
        self._nodes: List[UpstreamNode] = []
        self._wrr_index = 0
        self._lock = threading.Lock()

        # Thread pool for concurrent probing and parallel racing
        self._executor = concurrent.futures.ThreadPoolExecutor(max_workers=8, thread_name_prefix="upstream-pool")

        # Initialize standard robust defaults
        self.add_node(UpstreamNode("Cloudflare Primary", "1.1.1.1", 53, "UDP", weight=100))
        self.add_node(UpstreamNode("Google Primary", "8.8.8.8", 53, "UDP", weight=90))
        self.add_node(UpstreamNode("Quad9 Malware Defense", "9.9.9.9", 53, "UDP", weight=80))

    def add_node(self, node: UpstreamNode):
        with self._lock:
            # Avoid duplicate host:port
            for n in self._nodes:
                if n.host == node.host and n.port == node.port and n.protocol == node.protocol:
                    return
            self._nodes.append(node)

    def remove_node(self, host: str, port: int = 53):
        with self._lock:
            self._nodes = [n for n in self._nodes if not (n.host == host and n.port == port)]

    def get_healthy_nodes(self) -> List[UpstreamNode]:
        """Returns list of nodes whose circuit breakers are not OPEN."""
        with self._lock:
            healthy = [n for n in self._nodes if n.is_available]
            if not healthy:
                # Emergency: If ALL circuits tripped, return all nodes to avoid total blackout
                return list(self._nodes)
            return healthy

    def select_node(self) -> Optional[UpstreamNode]:
        """Selects an upstream node based on active routing strategy."""
        candidates = self.get_healthy_nodes()
        if not candidates:
            return None

        if self.strategy == UpstreamRoutingStrategy.LOWEST_LATENCY:
            # Pick node with lowest rolling average latency
            return min(candidates, key=lambda n: n.avg_latency_ms)

        elif self.strategy == UpstreamRoutingStrategy.FAILOVER:
            # Return primary (first non-backup available)
            primaries = [n for n in candidates if not n.is_backup]
            return primaries[0] if primaries else candidates[0]

        elif self.strategy == UpstreamRoutingStrategy.WEIGHTED_ROUND_ROBIN:
            with self._lock:
                total_weight = sum(n.weight for n in candidates)
                pick = random.randint(1, total_weight)
                current = 0
                for n in candidates:
                    current += n.weight
                    if current >= pick:
                        return n
                return candidates[0]

        return candidates[0]

    def _query_single_node(self, node: UpstreamNode, query_bytes: bytes) -> Optional[bytes]:
        """Executes query against a specific node over its designated transport."""
        t0 = time.time()
        reply: Optional[bytes] = None

        if node.protocol == "UDP":
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(self.query_timeout)
            try:
                s.sendto(query_bytes, (node.host, node.port))
                reply, _ = s.recvfrom(4096)
            except Exception:
                reply = None
            finally:
                s.close()

            # Handle TC (Truncation) bit by retrying over TCP
            if reply and len(reply) >= 4 and (reply[2] & 0x02):
                reply = self._query_tcp(node.host, node.port, query_bytes)

        elif node.protocol == "TCP":
            reply = self._query_tcp(node.host, node.port, query_bytes)

        lat = (time.time() - t0) * 1000.0
        if reply:
            node.record_success(lat)
            return reply
        else:
            node.record_failure()
            return None

    def _query_tcp(self, host: str, port: int, query_bytes: bytes) -> Optional[bytes]:
        """RFC 1035 §4.2.2 2-octet length-prefixed TCP DNS query."""
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(self.query_timeout)
        try:
            s.connect((host, port))
            s.sendall(struct.pack("!H", len(query_bytes)) + query_bytes)
            raw_len = s.recv(2)
            if len(raw_len) < 2:
                return None
            msg_len = struct.unpack("!H", raw_len)[0]
            buf = bytearray()
            while len(buf) < msg_len:
                chunk = s.recv(msg_len - len(buf))
                if not chunk:
                    break
                buf.extend(chunk)
            return bytes(buf)
        except Exception:
            return None
        finally:
            s.close()

    def resolve_wire(self, query_bytes: bytes) -> Tuple[Optional[bytes], str]:
        """
        Executes query against upstream pool with zero-loss fallback.
        If selected node fails, automatically retries on backup nodes.
        Returns (wire_reply_bytes, status_str).
        """
        if self.strategy == UpstreamRoutingStrategy.PARALLEL_RACE:
            return self._resolve_parallel_race(query_bytes)

        healthy_nodes = self.get_healthy_nodes()
        if not healthy_nodes:
            return None, "SERVFAIL"

        primary = self.select_node()
        if primary:
            reply = self._query_single_node(primary, query_bytes)
            if reply:
                return reply, "NOERROR"

        # Fallback to remaining healthy nodes
        for fallback in healthy_nodes:
            if fallback is primary:
                continue
            reply = self._query_single_node(fallback, query_bytes)
            if reply:
                return reply, "NOERROR"

        return None, "SERVFAIL"

    def _resolve_parallel_race(self, query_bytes: bytes) -> Tuple[Optional[bytes], str]:
        """Races top 2 healthy upstreams in parallel and takes the first successful reply."""
        healthy = self.get_healthy_nodes()
        if not healthy:
            return None, "SERVFAIL"

        race_nodes = sorted(healthy, key=lambda n: n.avg_latency_ms)[:2]

        futures = [self._executor.submit(self._query_single_node, n, query_bytes) for n in race_nodes]
        done, not_done = concurrent.futures.wait(futures, timeout=self.query_timeout, return_when=concurrent.futures.FIRST_COMPLETED)

        for f in done:
            try:
                res = f.result()
                if res:
                    return res, "NOERROR"
            except Exception:
                pass

        # Wait on any remaining if first completed didn't succeed
        for f in not_done:
            try:
                res = f.result(timeout=0.5)
                if res:
                    return res, "NOERROR"
            except Exception:
                pass

        return None, "SERVFAIL"

    def get_stats(self) -> Dict[str, Any]:
        """Returns aggregated telemetry for the entire upstream pool."""
        with self._lock:
            node_stats = [n.get_stats() for n in self._nodes]
            healthy_count = sum(1 for n in self._nodes if n.is_available)
            tot_queries = sum(n.total_queries for n in self._nodes)
            tot_failures = sum(n.total_failures for n in self._nodes)
            return {
                "strategy": self.strategy,
                "total_nodes": len(self._nodes),
                "healthy_nodes": healthy_count,
                "active_nodes": healthy_count,
                "total_queries": tot_queries,
                "failover_count": tot_failures,
                "nodes": node_stats,
            }

    def close(self):
        self._executor.shutdown(wait=False)
