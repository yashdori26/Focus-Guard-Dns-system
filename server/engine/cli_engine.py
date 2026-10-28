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
import base64
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
from .xdp_filter import XDP_DROP
from .cookie_manager import DNSCookieManager
from .secure_forwarder import (
    SecureUpstreamForwarder,
    UpstreamConfig,
    UpstreamProtocol,
    PrivacyProfile,
    SelectionStrategy,
)
from .mdm_server import (
    get_fleet_manager,
    PolicyLockMode,
    SplitTunnelPolicyMode,
    MdmPolicyProfile,
    DeviceStatus,
)
from .attestation_validator import AttestationValidator
from .private_dns_server import PrivateDnsServerManager
from .oem_telemetry_collector import (
    OemTelemetryCollector,
    EVASION_CLEAR_STORAGE,
    EVASION_FORCE_STOP,
    EVASION_ADMIN_DISABLE,
    EVASION_PRIVATE_DNS,
    EXEMPTION_EMERGENCY_CALL,
)
from .dpc_provisioning_server import DpcProvisioningServer
from .kiosk_policy_manager import KioskPolicyManager, KioskProfile
from .managed_config_distributor import ManagedConfigDistributor, TenantAppConfig


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
    print("-" * 65)
    print("RFC 8806 Local Root & Advanced Defenses:")
    print(f"  Hyperlocal Root Queries:     {metrics.get('local_root_queries', 0):,}")
    print(f"  PMTU TC=1 Truncations:       {metrics.get('pmtu_truncations', 0):,}")
    print(f"  Aggressive NSEC Cache Hits:  {metrics.get('aggressive_nsec_hits', 0):,}")
    print(f"  Compact DNSSEC Proofs:       {metrics.get('compact_dnssec_proofs', 0):,}")
    print(f"  RFC 8482 ANY Intercepts:     {metrics.get('rfc8482_any_intercepts', 0):,}")
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


def cmd_svcb_parse(args):
    """Parses and inspects RFC 9460 SVCB/HTTPS presentation record."""
    from .svcb_https import SVCBRecord
    try:
        rec = SVCBRecord.parse_presentation(args.presentation)
        print("=" * 60)
        print("       FOCUS-DNS RFC 9460 SVCB/HTTPS RECORD INSPECTOR   ")
        print("=" * 60)
        print(f"Priority:        {rec.priority} ({'AliasMode' if rec.is_alias_mode else 'ServiceMode'})")
        print(f"Target Name:     {rec.target_name}")
        print(f"SvcParams Total: {len(rec.list_params())}")
        for p in rec.list_params():
            print(f"  • {p.key_name} (Key {p.key}): {p.value}")
        print(f"Wire Size:       {len(rec.to_wire())} octets")
        print("=" * 60)
    except Exception as ex:
        print(f"Error parsing SVCB presentation format: {ex}")


def cmd_root_status(args):
    """Displays RFC 8806 Hyperlocal Root Zone telemetry and hint database."""
    pipeline = get_pipeline()
    st = pipeline.local_root.get_stats()
    print("=" * 60)
    print("       FOCUS-DNS RFC 8806 HYPERLOCAL ROOT ZONE STATUS   ")
    print("=" * 60)
    print(f"Specification:            {st['rfc']}")
    print(f"Root Apex Serial:         {st['serial']}")
    print(f"Root Servers Online:      {st['root_servers_available']} (A.ROOT through M.ROOT)")
    print(f"Registered TLDs:          {st['registered_tlds']}")
    print(f"Total Queries Served:     {st['total_queries_served']:,}")
    print(f"Apex Answers (SOA/NS):    {st['apex_queries_served']:,}")
    print(f"Delegation Referrals:     {st['referrals_served']:,}")
    print(f"Authoritative NXDOMAIN:   {st['nxdomain_served']:,}")
    print("=" * 60)


def cmd_pmtu_status(args):
    """Displays PMTU buffer limits and TCP fallback manager status."""
    pipeline = get_pipeline()
    pmtu_st = pipeline.pmtu.get_stats()
    tcp_st = pipeline.tcp_fallback.get_stats()
    print("=" * 60)
    print("      FOCUS-DNS RFC 8900 PMTU & TRUNCATION MANAGER      ")
    print("=" * 60)
    print(f"Configured UDP Payload:   {pmtu_st['max_udp_payload_configured']} bytes (Flag Day)")
    print(f"Flag Day Clamping:        {'ENFORCED' if pmtu_st['enforce_flag_day_limit'] else 'DISABLED'}")
    print(f"UDP Packets Evaluated:    {pmtu_st['udp_packets_evaluated']:,}")
    print(f"TC=1 Truncation Events:   {pmtu_st['truncation_events']:,} ({pmtu_st['truncation_rate_percent']}%)")
    print("-" * 60)
    print(f"Active TCP Connections:   {tcp_st['active_tcp_connections']:,}")
    print(f"Total TCP Handled:        {tcp_st['total_tcp_connections']:,}")
    print(f"Rejected Connections:     {tcp_st['rejected_connections']:,}")
    print("=" * 60)


def cmd_metrics_dump(args):
    """Dumps live Prometheus exposition format metrics."""
    pipeline = get_pipeline()
    print(pipeline.prometheus.export_metrics_text())


def cmd_fuzz_run(args):
    """Runs automated DNS wire mutation fuzzing cycle."""
    from .dns_fuzzer import DNSFuzzHarness, LoopVulnerabilityDetector
    from dnslib import DNSQuestion
    base = DNSRecord(q=DNSQuestion("fuzz.local", QTYPE.A)).pack()

    def safe_parser(data):
        is_loop, _ = LoopVulnerabilityDetector.inspect_pointer_loops(data)
        if is_loop:
            raise ValueError("Loop rejected")
        return DNSRecord.parse(data)

    harness = DNSFuzzHarness(target_parser=safe_parser)
    print(f"🚀 Running {args.iterations} hostile wire fuzzing iterations...")
    st = harness.run_fuzz_cycle(base, iterations=args.iterations)
    print("=" * 60)
    print("        FOCUS-DNS WIRE PROTOCOL FUZZING RESULTS         ")
    print("=" * 60)
    print(f"Total Mutations Tested:   {st['total_fuzz_iterations']:,}")
    print(f"Cyclic Loops Neutralized: {st['loops_neutralized']:,}")
    print(f"Safe Exceptions Handled:  {st['safe_exceptions_handled']:,}")
    print(f"Fatal Crashes Detected:   {st['fatal_crashes']}")
    print(f"Zero Crash Guarantee:     {'PASS' if st['zero_crash_guarantee_met'] else 'FAIL'}")
    print("=" * 60)


def cmd_cookie_gen(args):
    """Generates an RFC 9018 Version 1 DNS Server Cookie."""
    mgr = DNSCookieManager()
    client_cookie = args.client_cookie.encode("utf-8") if len(args.client_cookie) == 8 else bytes.fromhex(args.client_cookie)
    if len(client_cookie) != 8:
        print("Error: Client cookie must be 8 octets (ASCII or 16-hex characters)")
        return
    server_cookie = mgr.generate_server_cookie(client_cookie, args.client_ip)
    print("=" * 60)
    print("      RFC 9018 INTEROPERABLE DNS SERVER COOKIE        ")
    print("=" * 60)
    print(f"Client IP:         {args.client_ip}")
    print(f"Client Cookie:     {client_cookie.hex()}")
    print(f"Server Cookie:     {server_cookie.hex()}")
    print(f"  Version:         0x{server_cookie[0]:02x} (RFC 9018 v1)")
    print(f"  Reserved:        {server_cookie[1:4].hex()}")
    ts = int.from_bytes(server_cookie[4:8], byteorder="big")
    print(f"  Timestamp:       {ts} ({time.ctime(ts)})")
    print(f"  HMAC-SHA256:     {server_cookie[8:16].hex()} (truncated 64-bit)")
    print("=" * 60)


def cmd_cookie_validate(args):
    """Validates an RFC 9018 DNS Server Cookie."""
    mgr = DNSCookieManager()
    client_cookie = bytes.fromhex(args.client_cookie) if len(args.client_cookie) == 16 else args.client_cookie.encode("utf-8")
    server_cookie = bytes.fromhex(args.server_cookie)
    valid, reason = mgr.validate_cookie(client_cookie, server_cookie, args.client_ip)
    print("=" * 60)
    print("       RFC 9018 SERVER COOKIE VALIDATION RESULT       ")
    print("=" * 60)
    print(f"Client IP:     {args.client_ip}")
    print(f"Client Cookie: {client_cookie.hex()}")
    print(f"Server Cookie: {server_cookie.hex()}")
    print(f"Validation:    {'VALID' if valid else 'INVALID'}")
    print(f"Status Reason: {reason}")
    print("=" * 60)


def cmd_forwarder_status(args):
    """Inspects RFC 8310 / RFC 9103 Secure Upstream Forwarder pool status."""
    fwd = SecureUpstreamForwarder(strategy=SelectionStrategy.FASTEST)
    fwd.add_upstream(UpstreamConfig("1.1.1.1", 853, UpstreamProtocol.DOT, "cloudflare-dns.com", priority=1))
    fwd.add_upstream(UpstreamConfig("8.8.8.8", 853, UpstreamProtocol.DOT, "dns.google", priority=2))
    fwd.add_upstream(UpstreamConfig("9.9.9.9", 853, UpstreamProtocol.DOT, "dns.quad9.net", priority=3))
    st = fwd.get_status()
    print("=" * 65)
    print("    RFC 8310 / RFC 9103 SECURE UPSTREAM FORWARDER POOL        ")
    print("=" * 65)
    print(f"Active Selection Strategy:   {st['strategy'].upper()}")
    print(f"Configured Endpoints:       {st['endpoints_count']}")
    print(f"TLS Sessions Cached:        {st['tls_sessions_cached']}")
    print("-" * 65)
    for ep in st["endpoints"]:
        print(f"Endpoint: {ep['endpoint_id']}")
        print(f"  Server Name:    {ep['server_name']}")
        print(f"  Privacy:        {ep['privacy_profile'].upper()}")
        print(f"  Circuit State:  {ep['circuit_state'].upper()}")
        print(f"  Available:      {ep['is_available']}")
        print(f"  EWMA Latency:   {ep['ewma_latency_ms']} ms")
    print("=" * 65)


def cmd_mdm_fleet(args):
    """Displays enterprise MDM fleet status and conditional uninstallation posture."""
    fm = get_fleet_manager()
    telemetry = fm.get_fleet_telemetry()
    print("=" * 70)
    print("         FOCUS-DNS ENTERPRISE MDM & DEVICE FLEET TELEMETRY       ")
    print("=" * 70)
    print(f"Total Enrolled Endpoints:      {telemetry['total_devices']}")
    print(f"Uninstallation Locked Count:   {telemetry['uninstallation_locked_devices']}")
    print(f"Device Admin Active:           {telemetry['device_admin_active_devices']}")
    print(f"Tampered Security Alerts:      {telemetry['tampered_devices']}")
    print(f"Active MDM Policy Profiles:    {telemetry['policies_count']}")
    print("-" * 70)
    print(f"{'DEVICE ID':<16} {'NAME':<18} {'PLATFORM':<10} {'LOCK STATE':<12} {'INTEGRITY':<10}")
    print("-" * 70)
    for dev in telemetry['devices']:
        lock_str = "LOCKED" if not dev['can_uninstall'] else "UNLOCKED"
        print(f"{dev['device_id']:<16} {dev['device_name'][:17]:<18} {dev['platform']:<10} {lock_str:<12} {dev['integrity_score']}/100")
    if not telemetry['devices']:
        print("  (No devices currently enrolled)")
    print("=" * 70)


def cmd_mdm_device(args):
    """Displays detailed diagnostics for an enrolled device."""
    fm = get_fleet_manager()
    dev = fm.get_device(args.device_id)
    if not dev:
        print(f"Error: Device '{args.device_id}' is not enrolled.")
        sys.exit(1)
    d = dev.to_dict()
    print("=" * 60)
    print(f"  DEVICE DETAILS: {d['device_name']} ({d['device_id']})")
    print("=" * 60)
    print(f"Platform / OS:        {d['platform']} (OS: {d['os_version']})")
    print(f"Policy Profile:       {d['profile_id']}")
    print(f"Status:               {d['status'].upper()}")
    print(f"Device Owner:         {'YES' if d['device_owner_enrolled'] else 'NO'}")
    print(f"Device Admin:         {'ACTIVE' if d['device_admin_active'] else 'INACTIVE'}")
    print(f"Protection Active:    {'YES' if d['is_protection_active'] else 'NO'}")
    print(f"Timer Active:         {'YES' if d['is_timer_active'] else 'NO'} ({d['remaining_timer_sec']}s remaining)")
    print(f"Can Uninstall:        {'YES (Clean)' if d['can_uninstall'] else 'NO (STRICTLY LOCKED)'}")
    print(f"Integrity Score:      {d['integrity_score']} / 100")
    print(f"Quarantined Apps:     {d['quarantined_apps_count']}")
    print(f"Split Tunnel Exempt:  {d['split_tunnel_exempt_count']}")
    print(f"Last Seen:            {d['last_seen_sec_ago']}s ago")
    print("=" * 60)


def cmd_mdm_check_uninstall(args):
    """Evaluates whether an endpoint is permitted to uninstall FocusDNS."""
    fm = get_fleet_manager()
    allowed, reason = fm.evaluate_uninstall_permission(args.device_id)
    print("-" * 60)
    print(f"UNINSTALLATION PERMISSION CHECK FOR: {args.device_id}")
    print(f"Allowed: {allowed}")
    print(f"Reason:  {reason}")
    if allowed:
        print(">> Status: UNINSTALL PERMITTED (Normal Mode, no active restrictions)")
    else:
        print(">> Status: UNINSTALLATION BLOCKED (Active Focus/Timer Protection)")
    print("-" * 60)


def cmd_mdm_policy(args):
    """Views or configures enterprise MDM policy profile."""
    fm = get_fleet_manager()
    pid = args.profile_id or "default"
    pol = fm.get_policy(pid)
    if args.set_lock_mode:
        try:
            mode = PolicyLockMode(args.set_lock_mode)
        except ValueError:
            print(f"Invalid lock mode: {args.set_lock_mode}. Options: always_allowed, conditional_on_protection, always_locked")
            sys.exit(1)
        if not pol:
            pol = MdmPolicyProfile(pid, f"Policy-{pid}", lock_mode=mode)
        else:
            pol.lock_mode = mode
            pol.version += 1
            pol.updated_at = time.time()
        fm.set_policy(pol)
        print(f"Policy '{pid}' lock mode updated to: {mode.value}")
    elif pol:
        p = pol.to_dict()
        print("=" * 60)
        print(f"  MDM POLICY PROFILE: {p['name']} ({p['profile_id']})")
        print("=" * 60)
        print(f"Lock Mode:            {p['lock_mode']}")
        print(f"Split Tunnel Mode:    {p['split_tunnel_mode']}")
        print(f"Disallow Safe Boot:   {p['disallow_safe_boot']}")
        print(f"Disallow VPN Config:  {p['disallow_vpn_config']}")
        print(f"Camera Disabled:      {p['camera_disabled']}")
        print(f"Exempt Packages ({len(p['exempt_packages'])}):")
        for pkg in p['exempt_packages']:
            print(f"  - {pkg}")
        print(f"Version:              v{p['version']}")
        print("=" * 60)
    else:
        print(f"Policy '{pid}' not found.")


def cmd_mdm_attest(args):
    """Issues challenge nonce and checks hardware attestation."""
    validator = AttestationValidator()
    device_id = args.device_id
    nonce = validator.generate_nonce(device_id)
    print("=" * 60)
    print(f"  KEYSTORE HARDWARE ATTESTATION: {device_id}")
    print("=" * 60)
    print(f"Challenge Nonce (CSPRNG): {nonce}")
    print("Simulating EC P-256 Keymaster Signature...")
    mock_sig = base64.b64encode(b"\x30\x45\x02\x20mock_ecdsa_r_component_bytes_12345\x02\x21\x00mock_ecdsa_s_component_bytes_12345").decode("utf-8")
    res = validator.verify_assertion(
        device_id=device_id,
        payload=f"FOCUS_MDM_ASSERTION:{device_id}",
        nonce=nonce,
        signature_base64=mock_sig,
        timestamp_ms=int(time.time() * 1000),
    )
    print(f"Valid:              {res.is_valid}")
    print(f"Security Level:     {res.security_level}")
    print(f"Hardware Backed:    {res.is_hardware_backed}")
    print(f"Keymaster Alias:    {res.key_alias}")
    print("=" * 60)


def cmd_mdm_private_dns(args):
    """Evaluates Private DNS (DoT) compliance."""
    mgr = PrivateDnsServerManager()
    device_id = args.device_id
    mode = args.mode or "opportunistic"
    specifier = args.specifier or ""
    res = mgr.evaluate_device_dns(device_id, mode, specifier)
    print("=" * 60)
    print(f"  PRIVATE DNS (DoT) COMPLIANCE: {device_id}")
    print("=" * 60)
    print(f"Reported Mode:       {res['reported_mode']}")
    print(f"Reported Specifier:  {res['reported_specifier'] or '(None - Local VPN tunnel active)'}")
    print(f"Compliant:           {res['compliant']}")
    print(f"Reason:              {res['reason']}")
    print(f"Recommended Action:  {res['recommended_action']}")
    print("Life Safety Notice:  Emergency calls (911/112) remain 100% exempt from DNS policy.")
    print("=" * 60)


def cmd_mdm_oem_risk(args):
    """Calculates OEM evasion risk score and breakdown."""
    collector = OemTelemetryCollector()
    device_id = args.device_id
    collector.record_event(
        event_id="ev_001",
        device_id=device_id,
        oem_vendor=args.vendor or "Samsung OneUI",
        event_type=EVASION_ADMIN_DISABLE if args.simulate_tamper else EXEMPTION_EMERGENCY_CALL,
        package_name="com.android.settings",
        window_title="Device Admin Apps",
    )
    risk = collector.calculate_device_risk_score(device_id)
    print("=" * 60)
    print(f"  OEM EVASION RISK AUDIT: {device_id} ({risk['oem_vendor']})")
    print("=" * 60)
    print(f"Risk Score:          {risk['risk_score']} / 100")
    print(f"Risk Level:          {risk['risk_level']}")
    print(f"Recent Events:       {risk['recent_event_count']}")
    print(f"Breakdown:           {risk['event_breakdown']}")
    print("=" * 60)


def cmd_mdm_provision(args):
    """Generates an Android Enterprise Zero-Touch enrollment token and QR payload."""
    server = DpcProvisioningServer()
    tenant = args.tenant or "default_enterprise"
    name = args.name or "CLI Enrollment Token"
    strict = args.strict_uninstall
    tok = server.create_enrollment_token(
        tenant_id=tenant,
        name=name,
        max_uses=args.max_uses or 10,
        ttl_seconds=args.ttl or 86400 * 7,
    )
    qr_payload = server.generate_zero_touch_qr_payload(
        token_id=tok.token_id,
        server_url=args.server_url,
        wifi_ssid=args.wifi_ssid,
        wifi_password=args.wifi_pass,
        enforce_strict_uninstall_lock=strict,
    )
    print("=" * 65)
    print(f"  ANDROID ENTERPRISE ZERO-TOUCH PROVISIONING: {tenant}")
    print("=" * 65)
    print(f"Token ID:           {tok.token_id}")
    print(f"Max Uses:           {tok.max_uses}")
    print(f"Strict Lock Mode:   {strict} (Clean uninstall permitted when False)")
    print(f"APK Package:        {server.package_name}")
    print(f"DPC Component:      {server.component_name}")
    print(f"APK Checksum:       {server.apk_signature_sha256}")
    print("-" * 65)
    print("QR Code JSON Payload:")
    print(json.dumps(qr_payload, indent=2))
    print("=" * 65)


def cmd_mdm_kiosk(args):
    """Evaluates or lists LockTask dedicated kiosk policies."""
    mgr = KioskPolicyManager()
    profile_id = args.profile or "default"
    prof = mgr.get_profile(profile_id)
    if not prof:
        print(f"Kiosk profile '{profile_id}' not found.")
        return
    p = prof.to_dict()
    print("=" * 65)
    print(f"  LOCKTASK DEDICATED KIOSK PROFILE: {p['name']} ({p['profile_id']})")
    print("=" * 65)
    print(f"Primary App:          {p['primary_app']}")
    print(f"System Info:          {p['allow_system_info']}")
    print(f"Keyguard:             {p['allow_keyguard']}")
    print(f"Enforce on Focus:     {p['enforce_on_focus']}")
    print(f"Whitelisted Packages ({len(p['allowed_packages'])}):")
    for pkg in p['allowed_packages']:
        is_emer = pkg in ("com.android.phone", "com.google.android.dialer", "com.samsung.incallui", "com.android.server.telecom")
        tag = " [MANDATORY EMERGENCY CALL EXEMPTION]" if is_emer else ""
        print(f"  - {pkg}{tag}")
    print("-" * 65)
    print("Notice: Normal mode removes kiosk bounds allowing clean uninstallation.")
    print("=" * 65)


def cmd_mdm_appconfig(args):
    """Generates Managed Configurations (AppConfig) XML/JSON bundle."""
    distributor = ManagedConfigDistributor()
    tenant = args.tenant or "default_enterprise"
    cfg = distributor.get_tenant_config(tenant)
    if not cfg:
        print(f"AppConfig for tenant '{tenant}' not found.")
        return
    print("=" * 65)
    print(f"  MANAGED CONFIGURATIONS (APPCONFIG): {tenant}")
    print("=" * 65)
    print(f"Server URL:         {cfg.server_url}")
    print(f"Strict Uninstall:   {cfg.enforce_strict_uninstall_lock}")
    print(f"Kiosk Enabled:      {cfg.kiosk_enabled}")
    print(f"Approved DoT Host:  {cfg.approved_dot_host}")
    print("-" * 65)
    print("AppConfig Restrictions Bundle JSON:")
    print(json.dumps(cfg.to_appconfig_bundle(), indent=2))
    print("=" * 65)


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

    # svcb-parse
    p_svcb = subparsers.add_parser("svcb-parse", help="Parse and inspect RFC 9460 SVCB/HTTPS presentation string")
    p_svcb.add_argument("presentation", help="Presentation string (e.g. '1 . alpn=h2,h3 port=443')")

    # root-status
    subparsers.add_parser("root-status", help="Show RFC 8806 Hyperlocal Root Zone telemetry")

    # pmtu-status
    subparsers.add_parser("pmtu-status", help="Show RFC 8900 PMTU and TCP Fallback manager status")

    # metrics-dump
    subparsers.add_parser("metrics-dump", help="Dump live Prometheus exposition format metrics")

    # fuzz-run
    p_fuzz = subparsers.add_parser("fuzz-run", help="Run automated DNS wire protocol mutation fuzzing")
    p_fuzz.add_argument("--iterations", type=int, default=100, help="Number of fuzzing mutations to execute")

    # cookie-gen
    p_ckgen = subparsers.add_parser("cookie-gen", help="Generate RFC 9018 Version 1 DNS Server Cookie")
    p_ckgen.add_argument("client_cookie", help="8-octet client cookie (ASCII or 16-hex characters)")
    p_ckgen.add_argument("client_ip", help="Client IP address")

    # cookie-validate
    p_ckval = subparsers.add_parser("cookie-validate", help="Validate RFC 9018 DNS Server Cookie")
    p_ckval.add_argument("client_cookie", help="8-octet client cookie")
    p_ckval.add_argument("server_cookie", help="16-octet server cookie (32 hex characters)")
    p_ckval.add_argument("client_ip", help="Client IP address")

    # forwarder-status
    subparsers.add_parser("forwarder-status", help="Show RFC 8310/9103 Secure Upstream Forwarder pool status")

    # mdm-fleet
    subparsers.add_parser("mdm-fleet", help="Show enterprise MDM fleet status and uninstallation lock posture")

    # mdm-device
    p_mdev = subparsers.add_parser("mdm-device", help="Show detailed telemetry for an enrolled device")
    p_mdev.add_argument("device_id", help="Device identifier (e.g., android-12345)")

    # mdm-check-uninstall
    p_mchk = subparsers.add_parser("mdm-check-uninstall", help="Evaluate if endpoint is permitted to uninstall FocusDNS")
    p_mchk.add_argument("device_id", help="Device identifier to evaluate")

    # mdm-policy
    p_mpol = subparsers.add_parser("mdm-policy", help="Inspect or configure MDM uninstallation & split-tunnel policy")
    p_mpol.add_argument("--profile-id", default="default", help="Policy profile ID")
    p_mpol.add_argument("--set-lock-mode", choices=["always_allowed", "conditional_on_protection", "always_locked"], help="Update uninstallation lock mode")

    # mdm-attest
    p_matt = subparsers.add_parser("mdm-attest", help="Issue challenge nonce and verify KeyStore hardware attestation")
    p_matt.add_argument("device_id", help="Device identifier to attest")

    # mdm-private-dns
    p_mpdns = subparsers.add_parser("mdm-private-dns", help="Evaluate Android 9+ Private DNS compliance")
    p_mpdns.add_argument("device_id", help="Device identifier")
    p_mpdns.add_argument("--mode", default="opportunistic", choices=["off", "opportunistic", "strict"], help="Reported Private DNS mode")
    p_mpdns.add_argument("--specifier", default="", help="Custom DoT hostname specifier")

    # mdm-oem-risk
    p_mrisk = subparsers.add_parser("mdm-oem-risk", help="Evaluate Multi-OEM evasion risk score")
    p_mrisk.add_argument("device_id", help="Device identifier")
    p_mrisk.add_argument("--vendor", default="Samsung OneUI", help="OEM vendor name")
    p_mrisk.add_argument("--simulate-tamper", action="store_true", help="Simulate active settings evasion attempt")

    # mdm-provision
    p_mprov = subparsers.add_parser("mdm-provision", help="Generate Android Enterprise Zero-Touch enrollment token and QR payload")
    p_mprov.add_argument("--tenant", default="default_enterprise", help="Enterprise tenant ID")
    p_mprov.add_argument("--name", default="Corporate Provisioning Token", help="Token label")
    p_mprov.add_argument("--max-uses", type=int, default=10, help="Max enrollment uses")
    p_mprov.add_argument("--ttl", type=int, default=604800, help="Token validity TTL in seconds")
    p_mprov.add_argument("--server-url", default=None, help="Override MDM server URL")
    p_mprov.add_argument("--wifi-ssid", default=None, help="Provisioning Wi-Fi SSID")
    p_mprov.add_argument("--wifi-pass", default=None, help="Provisioning Wi-Fi password")
    p_mprov.add_argument("--strict-uninstall", action="store_true", help="Enforce uninstallation lock immediately on provision")

    # mdm-kiosk
    p_mkiosk = subparsers.add_parser("mdm-kiosk", help="Inspect LockTask dedicated kiosk profiles")
    p_mkiosk.add_argument("--profile", default="default", help="Kiosk profile ID")

    # mdm-appconfig
    p_mappcfg = subparsers.add_parser("mdm-appconfig", help="Export Managed Configurations AppConfig payload")
    p_mappcfg.add_argument("--tenant", default="default_enterprise", help="Tenant ID")

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
    elif args.command == "svcb-parse":
        cmd_svcb_parse(args)
    elif args.command == "root-status":
        cmd_root_status(args)
    elif args.command == "pmtu-status":
        cmd_pmtu_status(args)
    elif args.command == "metrics-dump":
        cmd_metrics_dump(args)
    elif args.command == "fuzz-run":
        cmd_fuzz_run(args)
    elif args.command == "cookie-gen":
        cmd_cookie_gen(args)
    elif args.command == "cookie-validate":
        cmd_cookie_validate(args)
    elif args.command == "forwarder-status":
        cmd_forwarder_status(args)
    elif args.command == "mdm-fleet":
        cmd_mdm_fleet(args)
    elif args.command == "mdm-device":
        cmd_mdm_device(args)
    elif args.command == "mdm-check-uninstall":
        cmd_mdm_check_uninstall(args)
    elif args.command == "mdm-policy":
        cmd_mdm_policy(args)
    elif args.command == "mdm-attest":
        cmd_mdm_attest(args)
    elif args.command == "mdm-private-dns":
        cmd_mdm_private_dns(args)
    elif args.command == "mdm-oem-risk":
        cmd_mdm_oem_risk(args)
    elif args.command == "mdm-provision":
        cmd_mdm_provision(args)
    elif args.command == "mdm-kiosk":
        cmd_mdm_kiosk(args)
    elif args.command == "mdm-appconfig":
        cmd_mdm_appconfig(args)


if __name__ == "__main__":
    main()
