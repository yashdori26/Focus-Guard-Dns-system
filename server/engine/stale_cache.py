"""
FocusDNS RFC 8767 Stale-While-Revalidate Caching Engine
======================================================
Implements RFC 8767: Serving Stale Data to Improve DNS Resiliency and Latency.

Core Behavior:
1. Fresh Hits (now <= fresh_until): Serves cached DNS wire records in 0ms with
   remaining standard TTL.
2. Stale Hits (fresh_until < now <= stale_until): Instantly serves stale DNS
   record in 0ms with a synthesized short TTL (RFC 8767 Sec 4), while asynchronously
   triggering a background revalidation query.
3. In-Flight De-Duplication: If multiple clients request an expired domain simultaneously,
   only ONE upstream revalidation is dispatched, eliminating upstream dogpiling.
4. TTL Clamping: Enforces configurable lower (min_ttl) and upper (max_ttl) bounds.
5. Thread-Safe Concurrent LRU: High-speed lock-striped storage with automatic eviction.
"""

from __future__ import annotations

import collections
import concurrent.futures
import threading
import time
from typing import Any, Callable, Dict, List, Optional, Set, Tuple


class CacheState:
    FRESH = "FRESH"
    STALE = "STALE"
    EXPIRED = "EXPIRED"


class CacheEntry:
    """Represents a cached DNS wire response with RFC 8767 freshness bounds."""
    __slots__ = (
        'key', 'wire_bytes', 'rcode', 'resolved_ip', 'created_at',
        'ttl', 'fresh_until', 'stale_until', 'hit_count', 'last_accessed'
    )

    def __init__(
        self,
        key: Tuple[str, int],
        wire_bytes: bytes,
        rcode: int,
        resolved_ip: str,
        ttl: int,
        stale_window: int = 86400
    ):
        now = time.time()
        self.key = key
        self.wire_bytes = wire_bytes
        self.rcode = rcode
        self.resolved_ip = resolved_ip
        self.created_at = now
        self.ttl = ttl
        self.fresh_until = now + ttl
        self.stale_until = now + ttl + stale_window
        self.hit_count = 0
        self.last_accessed = now

    def get_state(self, now: float) -> str:
        """Determines the current RFC 8767 state of this entry."""
        if now <= self.fresh_until:
            return CacheState.FRESH
        elif now <= self.stale_until:
            return CacheState.STALE
        return CacheState.EXPIRED

    def remaining_fresh_ttl(self, now: float) -> int:
        """Returns remaining seconds of true freshness."""
        return max(1, int(self.fresh_until - now))

    def touch(self, now: float):
        self.hit_count += 1
        self.last_accessed = now


class StaleCacheEngine:
    """
    High-performance RFC 8767 Stale-While-Revalidate DNS cache.
    Eliminates cold resolution pauses for users by serving stale data
    while asynchronously updating in the background.
    """

    def __init__(
        self,
        max_entries: int = 50000,
        min_ttl: int = 15,
        max_ttl: int = 86400,
        stale_window: int = 86400,
        stale_window_seconds: Optional[int] = None,
        worker_threads: int = 4,
        revalidation_fetcher: Optional[Callable] = None,
    ):
        self.max_entries: int = max_entries
        self.min_ttl: int = min_ttl
        self.max_ttl: int = max_ttl
        self.stale_window: int = stale_window_seconds if stale_window_seconds is not None else stale_window
        self.revalidation_fetcher = revalidation_fetcher

        # Thread-safe ordered storage (LRU)
        self._entries: collections.OrderedDict[Tuple[str, int], CacheEntry] = collections.OrderedDict()
        self._lock = threading.Lock()

        # In-flight revalidation deduplication
        self._inflight_revalidations: Set[Tuple[str, int]] = set()
        self._inflight_lock = threading.Lock()

        # Background worker pool for RFC 8767 revalidation
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=worker_threads,
            thread_name_prefix="dns-revalidate"
        )

        # Performance Telemetry
        self._fresh_hits: int = 0
        self._stale_hits: int = 0
        self._misses: int = 0

        self._revalidations_dispatched: int = 0
        self._revalidations_succeeded: int = 0
        self._evictions: int = 0

    def clamp_ttl(self, original_ttl: int) -> int:
        """Enforces security bounds: prevents 0s TTL attacks and bounds ceiling."""
        if original_ttl < self.min_ttl:
            return self.min_ttl
        if original_ttl > self.max_ttl:
            return self.max_ttl
        return original_ttl

    def put(
        self,
        qname: str,
        qtype: int,
        wire_bytes: bytes,
        rcode: int = 0,
        resolved_ip: str = "",
        ttl: int = 300,
        original_ttl: Optional[int] = None
    ) -> CacheEntry:
        """Stores a fresh DNS response in the cache."""
        effective_ttl = original_ttl if original_ttl is not None else ttl
        clamped_ttl = self.clamp_ttl(effective_ttl)
        key = (qname.strip().lower().rstrip('.'), qtype)
        entry = CacheEntry(
            key=key,
            wire_bytes=wire_bytes,
            rcode=rcode,
            resolved_ip=resolved_ip,
            ttl=clamped_ttl,
            stale_window=self.stale_window
        )

        with self._lock:
            if key in self._entries:
                self._entries.move_to_end(key)
            self._entries[key] = entry

            # Enforce capacity via LRU eviction
            while len(self._entries) > self.max_entries:
                self._entries.popitem(last=False)
                self._evictions += 1

        return entry

    def get(
        self,
        qname: str,
        qtype: int,
        revalidation_callback: Optional[Callable] = None
    ) -> Tuple[Optional[bytes], str, int]:
        """
        Retrieves a record from the cache.
        Returns (wire_bytes, status_description, effective_ttl).
        - If FRESH: returns wire bytes directly with true remaining TTL.
        - If STALE: returns wire bytes immediately with synthetic RFC 8767 short TTL (10s),
          and dispatches background revalidation via revalidation_callback.
        - If EXPIRED or MISS: returns (None, CacheState.EXPIRED, 0).
        """
        key = (qname.strip().lower().rstrip('.'), qtype)
        now = time.time()
        entry: Optional[CacheEntry] = None

        with self._lock:
            entry = self._entries.get(key)
            if entry:
                self._entries.move_to_end(key)

        if not entry:
            self._misses += 1
            return None, CacheState.EXPIRED, 0

        state = entry.get_state(now)
        entry.touch(now)

        if state == CacheState.FRESH:
            self._fresh_hits += 1
            rem_ttl = entry.remaining_fresh_ttl(now)
            return entry.wire_bytes, CacheState.FRESH, rem_ttl

        elif state == CacheState.STALE:
            self._stale_hits += 1
            # Synthesize short RFC 8767 TTL for stale serving (e.g. 10s)
            stale_ttl = min(10, self.min_ttl)

            # Trigger background revalidation if callback provided and not already in-flight
            cb = revalidation_callback or self.revalidation_fetcher
            if cb:
                self._dispatch_background_revalidation(qname, qtype, cb)

            return entry.wire_bytes, CacheState.STALE, stale_ttl

        else:
            # Fully expired past stale window
            with self._lock:
                if key in self._entries:
                    del self._entries[key]
                    self._evictions += 1
            self._misses += 1
            return None, CacheState.EXPIRED, 0

    def _dispatch_background_revalidation(
        self,
        qname: str,
        qtype: int,
        callback: Callable
    ):
        """Dispatches an asynchronous upstream probe with deduplication."""
        key = (qname.strip().lower().rstrip('.'), qtype)

        with self._inflight_lock:
            if key in self._inflight_revalidations:
                # Already in-flight! Avoid duplicate upstream probe.
                return
            self._inflight_revalidations.add(key)

        self._revalidations_dispatched += 1

        def _task():
            try:
                res = callback(qname, qtype)
                if res:
                    if isinstance(res, (bytes, bytearray)):
                        self.put(qname, qtype, bytes(res), ttl=300)
                        self._revalidations_succeeded += 1
                    elif isinstance(res, (tuple, list)) and res[0]:
                        wire_bytes = bytes(res[0])
                        rcode = res[1] if len(res) > 1 else 0
                        ip = res[2] if len(res) > 2 else ""
                        ttl = res[3] if len(res) > 3 else 300
                        self.put(qname, qtype, wire_bytes, rcode=rcode, resolved_ip=ip, ttl=ttl)
                        self._revalidations_succeeded += 1
            except Exception:
                pass
            finally:
                with self._inflight_lock:
                    self._inflight_revalidations.discard(key)


        self._executor.submit(_task)


    def invalidate(self, qname: Optional[str] = None):
        """Invalidates entries matching domain, or clears all if qname is None."""
        with self._lock:
            if qname is None:
                self._entries.clear()
            else:
                clean = qname.strip().lower().rstrip('.')
                keys_to_remove = [k for k in self._entries if k[0] == clean or k[0].endswith('.' + clean)]
                for k in keys_to_remove:
                    del self._entries[k]
                    self._evictions += 1

    def clear(self):
        """Clears all cached entries unconditionally."""
        self.invalidate(None)


    def get_stats(self) -> Dict[str, Any]:
        """Returns real-time telemetry metrics on cache performance."""
        total_queries = self._fresh_hits + self._stale_hits + self._misses
        hit_ratio = round((self._fresh_hits + self._stale_hits) / total_queries * 100, 2) if total_queries > 0 else 0.0

        with self._lock:
            current_entries = len(self._entries)

        with self._inflight_lock:
            inflight_count = len(self._inflight_revalidations)

        return {
            'current_entries': current_entries,
            'entry_count': current_entries,
            'max_entries': self.max_entries,
            'fresh_hits': self._fresh_hits,
            'hits_fresh': self._fresh_hits,
            'stale_hits': self._stale_hits,
            'hits_stale': self._stale_hits,
            'misses': self._misses,
            'hit_ratio_percent': hit_ratio,
            'hit_ratio': hit_ratio,
            'revalidations_dispatched': self._revalidations_dispatched,
            'revalidations_queued': self._revalidations_dispatched,
            'revalidations_succeeded': self._revalidations_succeeded,
            'inflight_revalidations': inflight_count,
            'evictions': self._evictions,
        }


    def close(self):
        """Shuts down background revalidation executor."""
        self._executor.shutdown(wait=False)
