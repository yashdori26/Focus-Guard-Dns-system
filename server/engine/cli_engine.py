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
from .dns64 import embed_ipv4_in_ipv6
from .xdp_filter import XDP_DROP


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
    print("-" * 65)
    print("eBPF / XDP Fast Packet Filter:")
    print(f"  Frames Inspected:            {metrics.get('xdp_frames_inspected', 0):,}")
    print(f"  Kernel Bypass Drops:         {metrics.get('xdp_frames_dropped', 0):,}")
    print("-" * 65)
    print("DNS64 IPv6 Transition:")
    print(f"  Synthetic AAAA Generated:    {metrics.get('dns64_synthetic_aaaa', 0):,}")
    print("-" * 65)
    print("GeoDNS Topology Routing:")
    print(f"  Total Geo Queries:           {metrics.get('geodns_queries', 0):,}")
    print(f"  Geo-Fence Blocked:           {metrics.get('geodns_blocked', 0):,}")
    print("-" * 65)
    print("RFC 9432 Catalog Zones & Zone Transfers:")
    print(f"  Catalog Members:             {metrics.get('catalog_members', 0):,}")
    print(f"  AXFR/IXFR Transfers Served:  {metrics.get('zone_transfers_served', 0):,}")
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


def cmd_dns64_synth(args):
    """Synthesizes IPv6 AAAA record for an IPv4 address according to RFC 6052."""
    v4 = args.ipv4.strip()
    prefix = args.prefix.strip()
    v6 = embed_ipv4_in_ipv6(v4, prefix)
    print("=" * 60)
    print("        FOCUS-DNS RFC 6052 DNS64 SYNTHESIS TOOL        ")
    print("=" * 60)
    print(f"IPv4 Address:      {v4}")
    print(f"DNS64 Prefix:      {prefix}")
    print(f"Synthesized AAAA:  {v6}")
    print("=" * 60)


def cmd_geodns_lookup(args):
    """Simulates a GeoDNS proximity lookup for a domain and client IP."""
    pipeline = get_pipeline()
    res = pipeline.geodns.resolve(args.domain, args.client_ip, ecs_ip=args.ecs)
    print("=" * 60)
    print("        FOCUS-DNS GEODNS TOPOLOGY RESOLUTION REPORT     ")
    print("=" * 60)
    print(f"Domain:            {args.domain}")
    print(f"Client IP:         {args.client_ip}")
    if args.ecs:
        print(f"ECS Subnet:        {args.ecs}")
    print(f"Policy Action:     {res.policy_action.upper()}")
    if res.client_location:
        loc = res.client_location
        print(f"Client Location:   {loc.city}, {loc.country_code} ({loc.country_name}) [{loc.continent_code}]")
        print(f"Coordinates:       {loc.coordinates.latitude:.4f}, {loc.coordinates.longitude:.4f}")
    if res.selected_endpoint:
        ep = res.selected_endpoint
        print(f"Routed Endpoint:   {ep.name} (ID: {ep.endpoint_id})")
        print(f"Endpoint IPv4:     {ep.ipv4_address}")
        if ep.ipv6_address:
            print(f"Endpoint IPv6:     {ep.ipv6_address}")
        print(f"Haversine Distance: {res.distance_km:.2f} km")
        print(f"Selection Reason:  {res.reason}")
    print(f"Failover Occurred: {'YES' if res.failover_occurred else 'NO'}")
    print("=" * 60)


def cmd_xdp_status(args):
    """Displays kernel-bypass eBPF / XDP packet filter stats and active BPF maps."""
    pipeline = get_pipeline()
    st = pipeline.xdp_filter.get_stats()
    print("=" * 60)
    print("         FOCUS-DNS eBPF / XDP PACKET FILTER STATUS     ")
    print("=" * 60)
    print(f"Attached Interface:        {st['interface']}")
    print(f"Total Frames Inspected:    {st['total_frames_inspected']:,}")
    print(f"Total Frames Passed:       {st['total_frames_passed']:,}")
    print(f"Total Frames Dropped:      {st['total_frames_dropped']:,}")
    print(f"Drop Ratio:                {st['drop_ratio_percent']}%")
    print(f"Active BPF Hash Map Rules: {st['active_bpf_ip_rules']:,}")
    print(f"Active BPF LPM CIDR Rules: {st['active_bpf_cidr_rules']:,}")
    print("=" * 60)


def cmd_catalog_list(args):
    """Lists member zones in RFC 9432 Catalog Zone."""
    pipeline = get_pipeline()
    st = pipeline.catalog_zones.get_stats()
    members = pipeline.catalog_zones.list_members()
    print("=" * 60)
    print("         FOCUS-DNS RFC 9432 CATALOG ZONE MEMBERS       ")
    print("=" * 60)
    print(f"Catalog Origin:  {st['catalog_origin']}")
    print(f"Current Serial:  {st['serial']}")
    print(f"Total Members:   {st['member_count']}")
    print("-" * 60)
    for m in members:
        print(f"  • {m['zone_origin']} [Group: {m['group']}, ID: {m['unique_id']}]")
    print("=" * 60)


def cmd_transfer_zone(args):
    """Executes local AXFR zone replication test."""
    pipeline = get_pipeline()
    zone = pipeline.zone_authority.get_zone(args.zone)
    if not zone:
        print(f"Zone {args.zone} does not exist in local authoritative database.")
        return
    req = DNSRecord.question(args.zone, "AXFR")
    rcode, chunks = pipeline.zone_transfer.handle_axfr_request(req, zone, args.client_ip)
    print("=" * 60)
    print("        FOCUS-DNS RFC 5936 AXFR ZONE TRANSFER TEST      ")
    print("=" * 60)
    print(f"Zone Origin:     {args.zone}")
    print(f"Target Client:   {args.client_ip}")
    print(f"Response RCODE:  {rcode}")
    print(f"Stream Chunks:   {len(chunks)} frames generated")
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

    # dns64-synth
    p_dns64 = subparsers.add_parser("dns64-synth", help="Synthesize IPv6 AAAA record from IPv4")
    p_dns64.add_argument("ipv4", help="IPv4 address to synthesize")
    p_dns64.add_argument("--prefix", default="64:ff9b::/96", help="NAT64 IPv6 prefix")

    # geodns-lookup
    p_geo = subparsers.add_parser("geodns-lookup", help="Simulate GeoDNS nearest endpoint resolution")
    p_geo.add_argument("domain", help="Domain name to resolve")
    p_geo.add_argument("client_ip", help="Client IP address")
    p_geo.add_argument("--ecs", default=None, help="Optional EDNS Client Subnet IP")

    # xdp-status
    subparsers.add_parser("xdp-status", help="Show eBPF/XDP driver-level packet filter status")

    # catalog-list
    subparsers.add_parser("catalog-list", help="List member zones in RFC 9432 Catalog Zone")

    # transfer-zone
    p_xfer = subparsers.add_parser("transfer-zone", help="Test RFC 5936 AXFR zone transfer stream")
    p_xfer.add_argument("zone", help="Authoritative zone origin")
    p_xfer.add_argument("--client-ip", default="127.0.0.1", help="Simulated slave client IP")

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
    elif args.command == "dns64-synth":
        cmd_dns64_synth(args)
    elif args.command == "geodns-lookup":
        cmd_geodns_lookup(args)
    elif args.command == "xdp-status":
        cmd_xdp_status(args)
    elif args.command == "catalog-list":
        cmd_catalog_list(args)
    elif args.command == "transfer-zone":
        cmd_transfer_zone(args)


if __name__ == "__main__":
    main()
