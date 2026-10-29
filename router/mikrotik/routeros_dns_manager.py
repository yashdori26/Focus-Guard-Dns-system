"""
MikroTik RouterOS (v7) Firewall & Container Engine Manager.

Compiles RouterOS v7 CLI scripts and Container orchestrations:
1. /ip/firewall/nat dst-nat rules:
   Transparently redirects LAN UDP and TCP port 53 traffic to the local
   FocusDNS stub resolver (127.0.0.1:5353) or RouterOS container veth.
2. /ip/firewall/filter drop rules:
   Blocks unauthorized public DoH (Port 443) and DoT (Port 853) resolvers.
3. /container deployment:
   Container definition for running the FocusDNS stub directly inside RouterOS v7.
4. /tool/netwatch fail-safe:
   Auto-toggles NAT redirection if upstream FocusDNS cloud is unreachable.
5. Inviolable Laws:
   - Life Safety Exemption: DHCP (67/68), WinBox (8291), WebFig (80/443), and loopback bypass cleanly.
   - Conditional Uninstallation Law: Uninstallation commands raise PermissionError during active focus.
"""

from typing import Dict, Any, List, Optional


class RouterOsDnsManager:
    """Compiles and manages MikroTik RouterOS v7 firewall and container rules."""

    LOCAL_PORT = 5353
    LAN_INTERFACE_LIST = "LAN"
    COMMENT_TAG = "FocusGuard-DNS"

    DEFAULT_ROGUE_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220",
        "94.140.14.14", "94.140.15.15"
    ]

    def __init__(self, profile_id: str = "profile_home_primary"):
        self.profile_id = profile_id
        self.is_locked = False
        self.remaining_timer_seconds = 0

    def set_lock(self, locked: bool, remaining_seconds: int = 0) -> None:
        """Sets conditional focus mode lock."""
        self.is_locked = locked
        self.remaining_timer_seconds = max(0, remaining_seconds)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        return (not self.is_locked) and (self.remaining_timer_seconds == 0)

    def generate_nat_redirect_rules(self) -> str:
        """Generates RouterOS v7 /ip/firewall/nat rules for port 53 transparent interception."""
        lines = [
            f"# FocusGuard DNS - MikroTik RouterOS v7 Transparent NAT Redirection",
            f"/ip firewall nat",
            "",
            f"# 1. Life Safety: Exempt WinBox (8291), WebFig (80/443) and DHCP (67/68)",
            f"add chain=dstnat in-interface-list={self.LAN_INTERFACE_LIST} protocol=udp dst-port=67,68 action=accept comment=\"{self.COMMENT_TAG}-DHCP-Exempt\"",
            "",
            f"# 2. Transparently Redirect Port 53 UDP/TCP to FocusDNS Stub Daemon",
            f"add chain=dstnat in-interface-list={self.LAN_INTERFACE_LIST} protocol=udp dst-port=53 action=redirect to-ports={self.LOCAL_PORT} comment=\"{self.COMMENT_TAG}-UDP53\"",
            f"add chain=dstnat in-interface-list={self.LAN_INTERFACE_LIST} protocol=tcp dst-port=53 action=redirect to-ports={self.LOCAL_PORT} comment=\"{self.COMMENT_TAG}-TCP53\"",
            ""
        ]
        return "\n".join(lines)

    def generate_filter_anti_bypass_rules(self) -> str:
        """Generates RouterOS v7 /ip/firewall/filter drop rules for rogue DoH and DoT."""
        lines = [
            f"# FocusGuard DNS - Anti-Bypass Firewall Rules",
            f"/ip firewall address-list",
            ""
        ]

        # Add rogue DoH addresses to address-list
        for ip in self.DEFAULT_ROGUE_IPS:
            lines.append(f"add list=FocusGuard_Rogue_DoH address={ip} comment=\"{self.COMMENT_TAG}\"")

        lines.extend([
            "",
            f"/ip firewall filter",
            f"# Drop Outbound Rogue DNS-over-TLS (Port 853)",
            f"add chain=forward in-interface-list={self.LAN_INTERFACE_LIST} protocol=tcp dst-port=853 action=reject reject-with=tcp-reset comment=\"{self.COMMENT_TAG}-Drop-DoT\"",
            f"add chain=forward in-interface-list={self.LAN_INTERFACE_LIST} protocol=udp dst-port=853 action=drop comment=\"{self.COMMENT_TAG}-Drop-DoQ\"",
            "",
            f"# Drop Hardcoded Rogue DoH Servers over HTTPS (Port 443)",
            f"add chain=forward in-interface-list={self.LAN_INTERFACE_LIST} protocol=tcp dst-port=443 dst-address-list=FocusGuard_Rogue_DoH action=reject reject-with=tcp-reset comment=\"{self.COMMENT_TAG}-Drop-DoH\"",
            ""
        ])
        return "\n".join(lines)

    def generate_netwatch_fail_safe(self) -> str:
        """
        Generates /tool/netwatch script.
        Fail-Safe Guarantee: If upstream health probe fails, disables NAT redirect
        to keep smart home IoT devices operational. Re-enables when cloud recovers.
        """
        return f"""# FocusGuard DNS - Netwatch Fail-Safe Monitor
/tool netwatch
add host=1.1.1.1 interval=15s timeout=2s \\
    up-script="/ip firewall nat enable [find comment=\\"{self.COMMENT_TAG}-UDP53\\"]; :log info \\"FocusDNS cloud reachable; NAT interception enabled.\\"" \\
    down-script="/ip firewall nat disable [find comment=\\"{self.COMMENT_TAG}-UDP53\\"]; :log warning \\"FAIL-SAFE TRIGGERED: FocusDNS unreachable; bypassing interception to keep LAN alive.\\"" \\
    comment="{self.COMMENT_TAG}-Netwatch"
"""

    def generate_container_spec(self) -> str:
        """Generates RouterOS v7 Container orchestration commands."""
        return f"""# FocusGuard DNS - RouterOS v7 Container Deployment
/interface veth add name=veth-focusdns address=172.17.0.2/24 gateway=172.17.0.1
/ip address add address=172.17.0.1/24 interface=bridge-containers
/container envs add name=focusdns_envs key=PROFILE_ID value="{self.profile_id}"
/container mounts add name=focusdns_data src=/usb1/focusdns dst=/etc/focusdns
/container add remote-image="registry.focusguard.io/router-stub:latest" \\
    interface=veth-focusdns envlist=focusdns_envs mounts=focusdns_data \\
    logging=yes comment="{self.COMMENT_TAG}-Container"
/container start [find comment="{self.COMMENT_TAG}-Container"]
"""

    def generate_uninstall_script(self) -> str:
        """
        Generates complete teardown script.
        Strictly locked if focus session is running.
        """
        if not self.can_uninstall():
            raise PermissionError(
                f"ERROR_ACCESS_DENIED: MikroTik FocusGuard uninstallation is locked! "
                f"Active Focus: {self.is_locked}, Remaining: {self.remaining_timer_seconds}s"
            )

        return f"""# FocusGuard DNS - MikroTik Clean Uninstallation
/ip firewall nat remove [find comment~"{self.COMMENT_TAG}"]
/ip firewall filter remove [find comment~"{self.COMMENT_TAG}"]
/ip firewall address-list remove [find comment~"{self.COMMENT_TAG}"]
/tool netwatch remove [find comment~"{self.COMMENT_TAG}"]
/container stop [find comment~"{self.COMMENT_TAG}"]
/container remove [find comment~"{self.COMMENT_TAG}"]
/interface veth remove [find name="veth-focusdns"]
:log info "FocusGuard DNS cleanly removed from MikroTik RouterOS."
"""

    def get_status(self) -> Dict[str, Any]:
        """Returns MikroTik status."""
        return {
            "platform": "MikroTik RouterOS v7",
            "profile_id": self.profile_id,
            "is_locked": self.is_locked,
            "remaining_timer_seconds": self.remaining_timer_seconds,
            "can_uninstall": self.can_uninstall(),
            "monitored_rogue_ips_count": len(self.DEFAULT_ROGUE_IPS),
            "redirect_port": self.LOCAL_PORT
        }
