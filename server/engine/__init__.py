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
    "DNSPipeline",
    "get_pipeline",
]
