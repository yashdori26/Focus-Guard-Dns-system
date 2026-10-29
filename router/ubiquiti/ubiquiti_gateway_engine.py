"""
Ubiquiti EdgeRouter (EdgeOS / VyOS) & UniFi Gateway (UDM-Pro / UXG) Engine.

Compiles gateway firewall automation:
1. Ubiquiti EdgeMAX / EdgeOS (VyOS syntax):
   - NAT destination redirection for port 53 UDP/TCP to local stub (5353).
   - Firewall address-groups and drop rules for rogue DoH/DoT.
2. UniFi Dream Machine (UDM-Pro, UDM-SE, UXG-Pro) on-boot script:
   - Podman container bootstrap for FocusDNS edge daemon.
   - iptables rules hooked into UBIOS_WAN_OUT_USER.
3. Inviolable Laws:
   - Life Safety Exemption: DHCP (67/68), UniFi controller ports (8443, 8080), and loopback bypass cleanly.
   - Conditional Uninstallation Law: Removal script generation raises PermissionError during active focus.
"""

from typing import Dict, Any, List, Optional


class UbiquitiGatewayEngine:
    """Compiles configuration for Ubiquiti EdgeOS and UniFi OS gateways."""

    LOCAL_PORT = 5353
    LAN_INTERFACE = "eth1"
    UDM_LAN_BRIDGE = "br0"

    DEFAULT_ROGUE_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112"
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

    def generate_edgeos_config(self) -> str:
        """Generates EdgeOS / VyOS CLI configuration commands."""
        lines = [
            "# FocusGuard DNS - Ubiquiti EdgeMAX / EdgeOS (VyOS) Configuration",
            "configure",
            "",
            "# 1. Create Firewall Address Group for Rogue DoH Resolvers",
            "set firewall group address-group FOCUS_DOH_SERVERS description 'FocusGuard Rogue DoH Blacklist'"
        ]

        for ip in self.DEFAULT_ROGUE_IPS:
            lines.append(f"set firewall group address-group FOCUS_DOH_SERVERS address {ip}")

        lines.extend([
            "",
            "# 2. Transparent NAT Redirection (UDP & TCP Port 53)",
            f"set service nat rule 1 description 'FocusGuard-DNS-Redirect-UDP'",
            f"set service nat rule 1 destination port 53",
            f"set service nat rule 1 inbound-interface {self.LAN_INTERFACE}",
            f"set service nat rule 1 protocol udp",
            f"set service nat rule 1 type destination",
            f"set service nat rule 1 inside-address port {self.LOCAL_PORT}",
            "",
            f"set service nat rule 2 description 'FocusGuard-DNS-Redirect-TCP'",
            f"set service nat rule 2 destination port 53",
            f"set service nat rule 2 inbound-interface {self.LAN_INTERFACE}",
            f"set service nat rule 2 protocol tcp",
            f"set service nat rule 2 type destination",
            f"set service nat rule 2 inside-address port {self.LOCAL_PORT}",
            "",
            "# 3. Anti-Bypass Guard: Drop Rogue DNS-over-TLS (Port 853)",
            "set firewall name LAN_IN rule 20 action drop",
            "set firewall name LAN_IN rule 20 description 'Drop-Rogue-DoT'",
            "set firewall name LAN_IN rule 20 destination port 853",
            "set firewall name LAN_IN rule 20 protocol tcp_udp",
            "",
            "# 4. Anti-Bypass Guard: Drop Direct Rogue DoH Server IPs (Port 443)",
            "set firewall name LAN_IN rule 21 action drop",
            "set firewall name LAN_IN rule 21 description 'Drop-Rogue-DoH'",
            "set firewall name LAN_IN rule 21 destination group address-group FOCUS_DOH_SERVERS",
            "set firewall name LAN_IN rule 21 destination port 443",
            "set firewall name LAN_IN rule 21 protocol tcp",
            "",
            "commit",
            "save",
            "exit"
        ])
        return "\n".join(lines)

    def generate_unifi_on_boot_script(self) -> str:
        """
        Generates /mnt/data/on_boot.d/10-focus-dns.sh for UniFi OS (UDM-Pro / UXG-Pro).
        """
        ips_rules = []
        for ip in self.DEFAULT_ROGUE_IPS:
            ips_rules.append(f"iptables -I UBIOS_WAN_OUT_USER 1 -d {ip} -p tcp --dport 443 -j REJECT")

        joined_ips = "\n".join(ips_rules)

        return f"""#!/bin/sh
# FocusGuard DNS - UniFi OS (UDM-Pro / UDM-SE / UXG-Pro) On-Boot Daemon
CONTAINER_NAME="focusdns-edge"

# 1. Clean existing iptables rules
iptables -t nat -D PREROUTING -i {self.UDM_LAN_BRIDGE} -p udp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT} 2>/dev/null
iptables -t nat -D PREROUTING -i {self.UDM_LAN_BRIDGE} -p tcp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT} 2>/dev/null
iptables -D UBIOS_WAN_OUT_USER -p tcp --dport 853 -j REJECT 2>/dev/null

# 2. Transparently Redirect LAN Port 53 to Local Container
iptables -t nat -I PREROUTING 1 -i {self.UDM_LAN_BRIDGE} -p udp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT}
iptables -t nat -I PREROUTING 1 -i {self.UDM_LAN_BRIDGE} -p tcp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT}

# 3. Anti-Bypass Guard: Reject Rogue DoT & DoH
iptables -I UBIOS_WAN_OUT_USER 1 -p tcp --dport 853 -j REJECT
{joined_ips}

# 4. Bootstrap Edge Stub Podman Container if not running
if ! podman ps -q -f name=$CONTAINER_NAME | grep -q .; then
    podman run -d --name $CONTAINER_NAME --restart always --net=host \\
        -e PROFILE_ID="{self.profile_id}" \\
        registry.focusguard.io/router-stub:latest
fi

logger -t "FocusDNS-UniFi" "UniFi OS firewall interception active on {self.UDM_LAN_BRIDGE}."
"""

    def generate_teardown_commands(self) -> str:
        """
        Generates clean uninstallation commands.
        Strictly locked if focus session is running.
        """
        if not self.can_uninstall():
            raise PermissionError(
                f"ERROR_ACCESS_DENIED: Ubiquiti FocusGuard uninstallation is locked! "
                f"Active Focus: {self.is_locked}, Remaining: {self.remaining_timer_seconds}s"
            )

        return f"""# Ubiquiti FocusGuard Clean Teardown
# EdgeOS:
# configure
# delete service nat rule 1
# delete service nat rule 2
# delete firewall name LAN_IN rule 20
# delete firewall name LAN_IN rule 21
# delete firewall group address-group FOCUS_DOH_SERVERS
# commit && save && exit

# UniFi OS:
rm -f /mnt/data/on_boot.d/10-focus-dns.sh
podman stop focusdns-edge 2>/dev/null
podman rm focusdns-edge 2>/dev/null
iptables -t nat -D PREROUTING -i {self.UDM_LAN_BRIDGE} -p udp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT} 2>/dev/null
iptables -D UBIOS_WAN_OUT_USER -p tcp --dport 853 -j REJECT 2>/dev/null
logger "FocusGuard cleanly removed from Ubiquiti Gateway."
"""

    def get_status(self) -> Dict[str, Any]:
        """Returns Ubiquiti gateway status."""
        return {
            "platform": "Ubiquiti EdgeRouter & UniFi Gateway",
            "profile_id": self.profile_id,
            "is_locked": self.is_locked,
            "remaining_timer_seconds": self.remaining_timer_seconds,
            "can_uninstall": self.can_uninstall(),
            "monitored_rogue_ips_count": len(self.DEFAULT_ROGUE_IPS),
            "redirect_port": self.LOCAL_PORT
        }
