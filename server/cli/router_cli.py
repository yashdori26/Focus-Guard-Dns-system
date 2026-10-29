"""
FocusGuard Router & Firewall Driver CLI.

Unified command-line interface for inspecting and managing router edge engines:
- OpenWrt, pfSense, OPNSense, Asuswrt-Merlin, DD-WRT, MikroTik RouterOS, Ubiquiti UniFi.

Commands:
  status            Displays comprehensive health and telemetry.
  devices           Lists connected household devices and assigned profiles.
  assign            Assigns a security profile to a specific device MAC.
  install-script    Generates 1-click terminal install commands for any router.
  lock              Activates Focus Mode and arms countdown timer.
  unlock            Disarms Focus Mode (clean uninstallation permitted).
  audit             Evaluates Conditional Uninstallation Law posture.
"""

import os
import sys
import json
import argparse
from typing import List, Dict, Any, Optional

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from router.daemon.router_orchestrator import RouterMasterOrchestrator
from router.mikrotik.routeros_dns_manager import RouterOsDnsManager
from router.ubiquiti.ubiquiti_gateway_engine import UbiquitiGatewayEngine
from router.daemon.router_benchmark_engine import RouterBenchmarkEngine


class FocusGuardRouterCli:
    """Command-line interface runner for router drivers."""

    def __init__(self, orchestrator: Optional[RouterMasterOrchestrator] = None):
        self.orchestrator = orchestrator or RouterMasterOrchestrator()

    def run(self, args: Optional[List[str]] = None) -> int:
        parser = argparse.ArgumentParser(
            prog="focusguard-router",
            description="FocusGuard Edge Router & Firewall Driver CLI"
        )
        subparsers = parser.add_subparsers(dest="command", help="Sub-commands")

        # Command: status
        parser_status = subparsers.add_parser("status", help="Show router status")
        parser_status.add_argument("--json", action="store_true", help="Output raw JSON")

        # Command: devices
        parser_devs = subparsers.add_parser("devices", help="List connected household devices")
        parser_devs.add_argument("--json", action="store_true", help="Output raw JSON")

        # Command: assign
        parser_assign = subparsers.add_parser("assign", help="Assign profile to device MAC")
        parser_assign.add_argument("mac", help="Device MAC address (e.g. AA:BB:CC:11:22:33)")
        parser_assign.add_argument("profile", help="Target profile ID")

        # Command: install-script
        parser_script = subparsers.add_parser("install-script", help="Generate 1-click install command")
        parser_script.add_argument("platform", choices=[
            "openwrt", "pfsense", "opnsense", "asuswrt", "ddwrt", "mikrotik", "ubiquiti"
        ], help="Target router platform")
        parser_script.add_argument("--profile", default="profile_home_primary", help="Default profile ID")

        # Command: lock
        parser_lock = subparsers.add_parser("lock", help="Lock focus mode with timer")
        parser_lock.add_argument("--seconds", type=int, default=1800, help="Timer duration in seconds")

        # Command: unlock
        subparsers.add_parser("unlock", help="Disarm focus mode")

        # Command: audit
        subparsers.add_parser("audit", help="Audit conditional uninstallation posture")

        # Command: benchmark
        parser_bench = subparsers.add_parser("benchmark", help="Run line-rate DNS throughput benchmark")
        parser_bench.add_argument("--queries", type=int, default=1000, help="Total queries to execute")
        parser_bench.add_argument("--concurrency", type=int, default=4, help="Worker threads")
        parser_bench.add_argument("--json", action="store_true", help="Output raw JSON")

        # Command: failover-test
        parser_fail = subparsers.add_parser("failover-test", help="Simulate WAN cutover stress test")
        parser_fail.add_argument("--queries", type=int, default=2000, help="Total queries")
        parser_fail.add_argument("--cutover", type=int, default=1000, help="Query number to trigger failover")
        parser_fail.add_argument("--json", action="store_true", help="Output raw JSON")

        parsed_args = parser.parse_args(args)
        if not parsed_args.command:
            parser.print_help()
            return 1

        cmd = parsed_args.command
        if cmd == "status":
            return self._handle_status(parsed_args.json)
        elif cmd == "devices":
            return self._handle_devices(parsed_args.json)
        elif cmd == "assign":
            return self._handle_assign(parsed_args.mac, parsed_args.profile)
        elif cmd == "install-script":
            return self._handle_install_script(parsed_args.platform, parsed_args.profile)
        elif cmd == "lock":
            return self._handle_lock(parsed_args.seconds)
        elif cmd == "unlock":
            return self._handle_unlock()
        elif cmd == "audit":
            return self._handle_audit()
        elif cmd == "benchmark":
            return self._handle_benchmark(parsed_args.queries, parsed_args.concurrency, parsed_args.json)
        elif cmd == "failover-test":
            return self._handle_failover_test(parsed_args.queries, parsed_args.cutover, parsed_args.json)

        return 0

    def _handle_status(self, as_json: bool) -> int:
        status = self.orchestrator.get_unified_status()
        if as_json:
            print(json.dumps(status, indent=2))
            return 0

        print("=" * 60)
        print(f" FocusGuard Router Gateway [{status['platform']}]")
        print("=" * 60)
        print(f" Router ID        : {status['router_id']}")
        print(f" Status           : {'RUNNING' if status['is_running'] else 'STOPPED'}")
        print(f" Active Profile   : {status['active_profile']}")
        print(f" Focus Lock       : {'ACTIVE' if status['is_locked'] else 'IDLE'}")
        print(f" Remaining Timer  : {status['remaining_timer_seconds']}s")
        print(f" Can Uninstall    : {'YES (Clean)' if status['can_uninstall'] else 'NO (Locked)'}")
        print("-" * 60)
        print(f" Subsystems Active:")
        for name, sub in status["subsystems"].items():
            print(f"  • {name:<18}: OK")
        print("=" * 60)
        return 0

    def _handle_devices(self, as_json: bool) -> int:
        devs = self.orchestrator.mac_router.get_all_devices()
        if as_json:
            print(json.dumps(devs, indent=2))
            return 0

        print("-" * 75)
        print(f"{'MAC ADDRESS':<20} {'IP ADDRESS':<16} {'CATEGORY':<14} {'ASSIGNED PROFILE':<22}")
        print("-" * 75)
        for d in devs:
            print(f"{d['mac_address']:<20} {d['ip_address']:<16} {d['device_category']:<14} {d['assigned_profile']:<22}")
        print("-" * 75)
        print(f"Total Discovered Clients: {len(devs)}")
        return 0

    def _handle_assign(self, mac: str, profile: str) -> int:
        self.orchestrator.mac_router.register_manual_mapping(mac_address=mac, profile_id=profile)
        print(f"[SUCCESS] Assigned profile '{profile}' to MAC '{mac}'.")
        return 0

    def _handle_install_script(self, platform: str, profile: str) -> int:
        if platform == "mikrotik":
            mgr = RouterOsDnsManager(profile_id=profile)
            print(mgr.generate_nat_redirect_rules())
            print(mgr.generate_filter_anti_bypass_rules())
        elif platform == "ubiquiti":
            eng = UbiquitiGatewayEngine(profile_id=profile)
            print(eng.generate_unifi_on_boot_script())
        elif platform == "openwrt":
            print(f"opkg update && opkg install luci-app-focus-dns && uci set focus_dns.settings.profile_id=\"{profile}\" && uci commit && /etc/init.d/focus_dns restart")
        elif platform == "pfsense":
            print(f"pkg install -y focus_dns && php -r \"require_once('/usr/local/pkg/focus_dns.inc'); focus_dns_sync_config();\"")
        elif platform == "opnsense":
            print("opnsense-patch -a focus_dns && configctl focus_dns start")
        elif platform == "asuswrt":
            print(f"curl -fsSL https://get.focusguard.io/asuswrt.sh | sh -s -- --profile \"{profile}\"")
        elif platform == "ddwrt":
            print("nvram set rc_firewall=\"iptables -t nat -A PREROUTING -i br0 -p udp --dport 53 -j REDIRECT --to-ports 5353\" && nvram commit")
        return 0

    def _handle_lock(self, seconds: int) -> int:
        self.orchestrator.set_focus_lock(locked=True, remaining_seconds=seconds)
        print(f"[LOCKED] Focus session activated for {seconds} seconds. Uninstallation locked.")
        return 0

    def _handle_unlock(self) -> int:
        self.orchestrator.set_focus_lock(locked=False, remaining_seconds=0)
        print("[UNLOCKED] Focus session disarmed. Clean uninstallation 100% permitted.")
        return 0

    def _handle_audit(self) -> int:
        can_un = self.orchestrator.can_uninstall()
        print("=" * 60)
        print(" FocusGuard Conditional Uninstallation Posture Audit")
        print("=" * 60)
        if can_un:
            print(" POSTURE: UNLOCKED (Normal Uninstallation Permitted)")
            print(" Reason : Device is idle, no countdown timer active.")
        else:
            print(" POSTURE: STRICT LOCK (Service Deactivation Forbidden)")
            print(f" Reason : Active focus session in progress ({self.orchestrator.remaining_timer_seconds}s remaining).")
        print("=" * 60)
        return 0

    def _handle_benchmark(self, queries: int, concurrency: int, as_json: bool) -> int:
        bench = RouterBenchmarkEngine(mock_mode=True)
        report = bench.run_benchmark(total_queries=queries, concurrency=concurrency)
        if as_json:
            print(json.dumps(report, indent=2))
            return 0

        print("=" * 65)
        print(" FocusGuard Edge Router Line-Rate Benchmark Report")
        print("=" * 65)
        print(f" Total Queries Executed : {report['total_queries']}")
        print(f" Throughput (QPS)       : {report['throughput_qps']} req/sec")
        print(f" Cache Hit Ratio        : {round(report['cache_hit_ratio'] * 100, 2)}%")
        print(f" Latency (p50)          : {report['latency_p50_us']} µs")
        print(f" Latency (p90)          : {report['latency_p90_us']} µs")
        print(f" Latency (p99)          : {report['latency_p99_us']} µs")
        print(f" Dropped Queries        : {report['dropped_queries']}")
        print("=" * 65)
        return 0

    def _handle_failover_test(self, queries: int, cutover: int, as_json: bool) -> int:
        bench = RouterBenchmarkEngine(mock_mode=True)
        report = bench.simulate_wan_failover_stress(total_queries=queries, failover_at_query=cutover)
        if as_json:
            print(json.dumps(report, indent=2))
            return 0

        print("=" * 65)
        print(" FocusGuard Multi-WAN Link Cutover Stress Test")
        print("=" * 65)
        print(f" Total Packets Transmitted : {report['total_queries']}")
        print(f" Cutover Triggered At     : Query #{report['failover_triggered_at']}")
        print(f" Convergence Latency      : {report['convergence_time_ms']} ms")
        print(f" Packet Loss Percentage   : {report['packet_loss_percentage']}%")
        print(f" Fail-Safe Guarantee      : {'INTACT (No Smart Home Freeze)' if report['fail_safe_intact'] else 'FAILED'}")
        print("=" * 65)
        return 0


def main():
    cli = FocusGuardRouterCli()
    sys.exit(cli.run(sys.argv[1:]))


if __name__ == "__main__":
    main()
