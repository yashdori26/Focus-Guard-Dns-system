"""
FocusDNS High-Performance Multi-Protocol Engine
Exports:
- RadixTrieMatcher, TrieNode, Match flags
- StaleCacheEngine, CacheState, CacheEntry (RFC 8767)
- DNSSECValidator, DNSSECSignatureState, TrustAnchor (RFC 4033, 4034, 4035)
- DotServer, DotServerThread (RFC 7858 DNS-over-TLS)
- DoqServer, DoqServerThread (RFC 9250 DNS-over-QUIC)
- DNSPipeline, get_pipeline
- ensure_certificates, create_dot_ssl_context, create_doq_quic_configuration
"""

from .radix_trie import (
    RadixTrieMatcher,
    TrieNode,
    FLAG_ALLOWED,
    FLAG_BLOCKED,
    FLAG_WILDCARD,
    FLAG_THREAT_MALWARE,
    FLAG_THREAT_MINER,
    FLAG_THREAT_FEED,
    FLAG_DEEP_FOCUS,
    FLAG_SAFESEARCH,
)
from .stale_cache import StaleCacheEngine, CacheState, CacheEntry
from .dnssec import DNSSECValidator, DNSSECSignatureState, TrustAnchor
from .certs import ensure_certificates, create_dot_ssl_context, create_doq_quic_configuration
from .dot_server import DotServer, DotServerThread
from .doq_server import DoqServer, DoqServerThread
from .edns0 import (
    EDNSProcessor,
    EDNSMessage,
    EDNSClientSubnet,
    DNSCookie,
    ExtendedDNSError,
    EDE_OTHER,
    EDE_PROHIBITED,
    EDE_BLOCKED,
    EDE_FILTERED,
)
from .doh3_server import Doh3Server, Doh3ServerThread
from .threat_analytics import ThreatAnalyticsEngine, ThreatVerdict
from .rate_limiter import DNSRateLimiter, RateLimitAction, TokenBucket
from .upstream_pool import (
    UpstreamPool,
    UpstreamNode,
    UpstreamRoutingStrategy,
    CircuitState,
)
from .zone_authority import (
    AuthoritativeRecord,
    AuthoritativeZone,
    SplitHorizonView,
    ZoneAuthorityEngine,
    TSIGKey,
)
from .dnssec_signer import DNSSECKeyPair, DNSSECSignerEngine
from .cluster_sync import (
    ClusterNode,
    ThreatIntelMessage,
    ClusterSyncEngine,
    AnycastHealthProbe,
    HEALTH_HEALTHY,
    HEALTH_DEGRADED,
    HEALTH_UNHEALTHY,
)
from .benchmark_suite import BenchmarkResult, BenchmarkSuite
from .pipeline import DNSPipeline, get_pipeline

__all__ = [
    "RadixTrieMatcher",
    "TrieNode",
    "FLAG_ALLOWED",
    "FLAG_BLOCKED",
    "FLAG_WILDCARD",
    "FLAG_THREAT_MALWARE",
    "FLAG_THREAT_MINER",
    "FLAG_THREAT_FEED",
    "FLAG_DEEP_FOCUS",
    "FLAG_SAFESEARCH",
    "StaleCacheEngine",
    "CacheState",
    "CacheEntry",
    "DNSSECValidator",
    "DNSSECSignatureState",
    "TrustAnchor",
    "ensure_certificates",
    "create_dot_ssl_context",
    "create_doq_quic_configuration",
    "DotServer",
    "DotServerThread",
    "DoqServer",
    "DoqServerThread",
    "EDNSProcessor",
    "EDNSMessage",
    "EDNSClientSubnet",
    "DNSCookie",
    "ExtendedDNSError",
    "EDE_OTHER",
    "EDE_PROHIBITED",
    "EDE_BLOCKED",
    "EDE_FILTERED",
    "Doh3Server",
    "Doh3ServerThread",
    "ThreatAnalyticsEngine",
    "ThreatVerdict",
    "DNSRateLimiter",
    "RateLimitAction",
    "TokenBucket",
    "UpstreamPool",
    "UpstreamNode",
    "UpstreamRoutingStrategy",
    "CircuitState",
    "AuthoritativeRecord",
    "AuthoritativeZone",
    "SplitHorizonView",
    "ZoneAuthorityEngine",
    "TSIGKey",
    "DNSSECKeyPair",
    "DNSSECSignerEngine",
    "ClusterNode",
    "ThreatIntelMessage",
    "ClusterSyncEngine",
    "AnycastHealthProbe",
    "HEALTH_HEALTHY",
    "HEALTH_DEGRADED",
    "HEALTH_UNHEALTHY",
    "BenchmarkResult",
    "BenchmarkSuite",
    "DNSPipeline",
    "get_pipeline",
]
