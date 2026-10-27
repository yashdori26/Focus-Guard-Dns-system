"""
FocusDNS Engine - Comprehensive CLI Management, Diagnostics & Benchmark Tool
Commands:
- status: Displays unified performance metrics across all 10 engine subsystems
- bench: Multi-threaded latency percentile and QPS throughput benchmark
- trie-lookup: Fast-path Radix Trie blocklist/allowlist/threat matcher query
- threat-eval: Evaluates Shannon entropy, DGA probability, and DNS tunneling risk score
- dnssec-keys: Generates and inspects ECDSA P-256 DNSKEY and parent DS records
- zone-export: Exports authoritative zone into standard RFC 1035 zone file syntax
- health-check: Runs comprehensive multi-protocol Anycast health probes
"""

import argparse
import json
import sys
import time

from dnslib import DNSRecord, QTYPE

from .pipeline import get_pipeline
from .benchmark_suite import BenchmarkSuite
from .threat_analytics import ThreatAnalyticsEngine, calculate_shannon_entropy
from .dnssec_signer import DNSSECSignerEngine
from .zone_authority import AuthoritativeZone, AuthoritativeRecord
from .cluster_sync import AnycastHealthProbe


def cmd_status(args):
    """Outputs real-time operational telemetry for all DNS engine subsystems."""
    pipeline = get_pipeline()
    metrics = pipeline.get_pipeline_metrics()

    print("=" * 65)
    print("      FOCUS-DNS MULTI-PROTOCOL ENGINE STATUS & TELEMETRY      ")
    print("=" * 65)
    print(f"Total Queries Processed:       {metrics['total_queries']:,}")
    print(f"Total Queries Blocked:         {metrics['total_blocked']:,}")
    print("-" * 65)
    print("Radix Trie Matcher:")
    print(f"  Trie Nodes in Memory:        {metrics['trie_nodes']:,}")
    print(f"  Exact Match Rules:           {metrics['trie_exact_rules']:,}")
    print(f"  Wildcard Asterisk Rules:     {metrics['trie_wildcard_rules']:,}")
    print("-" * 65)
    print("RFC 8767 Stale-While-Revalidate Cache:")
    print(f"  Cached Entries:              {metrics['cache_entries']:,}")
    print(f"  Fresh Hits (0ms):            {metrics['cache_hits_fresh']:,}")
    print(f"  Stale Served Hits (0ms):     {metrics['cache_hits_stale']:,}")
    print(f"  Cache Misses:                {metrics['cache_misses']:,}")
    print(f"  Cache Hit Ratio:             {metrics['cache_hit_ratio']}%")
    print(f"  Background Revalidations:    {metrics['cache_revalidations']:,}")
    print("-" * 65)
    print("Threat Analytics & Anomaly Shield:")
    print(f"  Total Queries Analyzed:      {metrics['threat_queries_analyzed']:,}")
    print(f"  DGA High-Entropy Flags:      {metrics['threat_dga_detected']:,}")
    print(f"  DNS Tunneling Exfil Flags:   {metrics['threat_tunneling_detected']:,}")
    print(f"  Fast-Flux Agility Networks:  {metrics['threat_fast_flux_detected']:,}")
    print(f"  High-Risk Threats Blocked:   {metrics['threat_high_risk_blocked']:,}")
    print("-" * 65)
    print("DNS Response Rate Limiter (RRL):")
    print(f"  Tracked Client Subnets/IPs:  {metrics['rate_limiter_tracked_ips']:,}")
    print(f"  Amplification Drops:         {metrics['rate_limiter_dropped']:,}")
    print(f"  SLIP Mitigation Truncations: {metrics['rate_limiter_slipped_tc']:,}")
    print("-" * 65)
    print("Autonomous Upstream Resolver Pool:")
    print(f"  Active Healthy Nodes:        {metrics['upstream_active_nodes']:,}")
    print(f"  Total Upstream Dispatches:   {metrics['upstream_total_queries']:,}")
    print(f"  Automatic Failovers:         {metrics['upstream_failovers']:,}")
    print("-" * 65)
    print("Authoritative Zone & Split-Horizon:")
    print(f"  Configured Zones:            {metrics['zone_authority_zones']:,}")
    print(f"  Authoritative Hits:          {metrics['zone_authority_hits']:,}")
    print("-" * 65)
    print("Cluster Synchronization Mesh:")
    print(f"  Known Cluster Nodes:         {metrics['cluster_size']:,}")
    print(f"  Distributed Banned IPs:      {metrics['cluster_distributed_blocked_ips']:,}")
    print("=" * 65)


def cmd_bench(args):
    """Executes high-throughput stress benchmark."""
    print(f"🚀 Starting FocusDNS benchmark: {args.queries} queries, concurrency {args.concurrency}...")
    suite = BenchmarkSuite(host=args.host, udp_port=args.port)

    if args.direct:
        pipeline = get_pipeline()
        res = suite.run_pipeline_direct_benchmark(pipeline, query_count=args.queries)
    else:
        res = suite.run_udp_benchmark(query_count=args.queries, concurrency=args.concurrency)

    print("\nBenchmark Completed Successfully!")
    print(res.to_markdown())


def cmd_threat_eval(args):
    """Evaluates domain using Shannon entropy and stream heuristics."""
    domain = args.domain.strip().lower().rstrip(".")
    engine = ThreatAnalyticsEngine()
    verdict = engine.analyze_domain(domain, qtype_str=args.qtype.upper())

    entropy = calculate_shannon_entropy(domain.split(".")[0])

    print("=" * 60)
    print(f"   FOCUS-DNS THREAT ANALYTICS EVALUATION: {domain}")
    print("=" * 60)
    print(f"Domain Name:            {verdict.domain}")
    print(f"Record Type:            {args.qtype.upper()}")
    print(f"Shannon Entropy:        {verdict.entropy} (Subdomain label: {entropy})")
    print(f"Composite Risk Score:   {verdict.risk_score} / 100")
    print(f"Final Action / Verdict: {verdict.verdict}")
    print(f"DGA Detected:           {'YES' if verdict.is_dga else 'NO'}")
    print(f"Tunneling Detected:     {'YES' if verdict.is_tunneling else 'NO'}")
    print(f"Fast-Flux Agility:      {'YES' if verdict.is_fast_flux else 'NO'}")
    print("-" * 60)
    print("Diagnostic Reasons:")
    for r in verdict.reasons:
        print(f"  - {r}")
    print("=" * 60)


def cmd_dnssec_keys(args):
    """Generates and displays DNSKEY and parent DS records for zone."""
    zone = args.zone.strip().lower().rstrip(".")
    signer = DNSSECSignerEngine(zone)
    keys = signer.get_dnskey_records()
    ds = signer.ksk.generate_ds_record(zone)

    print("=" * 65)
    print(f"   FOCUS-DNS DNSSEC CRYPTOGRAPHIC ANCHORS: {zone}")
    print("=" * 65)
    for k in keys:
        print(f"[{k['type']}] Key Tag: {k['key_tag']} | Flags: {k['flags']} | Algorithm: {k['algorithm']}")
        print(f"Public Key (Base64):\n  {k['public_key_b64']}\n")

    print("-" * 65)
    print("Parent Zone Delegation Signer (DS) Record (RFC 4034):")
    print(f"  Name:        {ds['name']}.")
    print(f"  Key Tag:     {ds['key_tag']}")
    print(f"  Algorithm:   {ds['algorithm']} (ECDSA P-256 SHA-256)")
    print(f"  Digest Type: {ds['digest_type']} (SHA-256)")
    print(f"  Digest Hex:  {ds['digest_hex']}")
    print("=" * 65)


def cmd_health_check(args):
    """Executes multi-protocol Anycast probe suite."""
    probe = AnycastHealthProbe(host=args.host, udp_port=args.udp_port, dot_port=args.dot_port, http_port=args.http_port)
    status = probe.execute_full_check()
    rep = probe.get_status_report()

    print("=" * 60)
    print("      FOCUS-DNS ANYCAST MULTI-PROTOCOL HEALTH REPORT      ")
    print("=" * 60)
    print(f"Overall Cluster Health:  {rep['overall_status']}")
    print(f"Anycast Route Ready:     {'YES (Announce BGP)' if rep['anycast_ready'] else 'NO (Withdraw BGP)'}")
    print(f"UDP DNS (5354):          {'UP (Canary Pass)' if rep['udp_ok'] else 'DOWN'}")
    print(f"DoT TLS (8853):          {'UP' if rep['dot_ok'] else 'DOWN'}")
    print(f"HTTP REST / DoH (8080):  {'UP' if rep['http_ok'] else 'DOWN'}")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(description="FocusDNS High-Performance Engine CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # status
    subparsers.add_parser("status", help="Show live engine telemetry and performance counters")

    # bench
    p_bench = subparsers.add_parser("bench", help="Run throughput and latency benchmark")
    p_bench.add_argument("--queries", type=int, default=1000, help="Total queries to generate")
    p_bench.add_argument("--concurrency", type=int, default=10, help="Concurrent worker threads")
    p_bench.add_argument("--host", default="127.0.0.1", help="Target server host")
    p_bench.add_argument("--port", type=int, default=5354, help="Target UDP port")
    p_bench.add_argument("--direct", action="store_true", help="Run direct in-memory pipeline benchmark")

    # threat-eval
    p_threat = subparsers.add_parser("threat-eval", help="Evaluate domain threat risk and Shannon entropy")
    p_threat.add_argument("domain", help="Domain name to evaluate")
    p_threat.add_argument("--qtype", default="A", help="DNS record type")

    # dnssec-keys
    p_dnssec = subparsers.add_parser("dnssec-keys", help="Inspect DNSKEY and DS records for zone")
    p_dnssec.add_argument("zone", help="Zone origin (e.g. corp.local)")

    # health-check
    p_health = subparsers.add_parser("health-check", help="Run Anycast multi-protocol health probe")
    p_health.add_argument("--host", default="127.0.0.1")
    p_health.add_argument("--udp-port", type=int, default=5354)
    p_health.add_argument("--dot-port", type=int, default=8853)
    p_health.add_argument("--http-port", type=int, default=8080)

    args = parser.parse_args()

    if args.command == "status":
        cmd_status(args)
    elif args.command == "bench":
        cmd_bench(args)
    elif args.command == "threat-eval":
        cmd_threat_eval(args)
    elif args.command == "dnssec-keys":
        cmd_dnssec_keys(args)
    elif args.command == "health-check":
        cmd_health_check(args)


if __name__ == "__main__":
    main()
