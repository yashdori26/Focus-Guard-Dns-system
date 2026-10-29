"""
DD-WRT Router Firmware Firewall & NVRAM Manager.

Generates NVRAM configuration commands for DD-WRT:
1. rc_firewall:
   - Intercepts port 53 UDP/TCP and forwards to local FocusDNS daemon (5353).
   - Enforces drop rules against hardcoded DoH (443) and DoT (853) resolvers.
2. rc_startup:
   - Downloads and executes FocusDNS stub daemon.
3. Inviolable Laws:
   - Life Safety Exemption: DHCP (67/68) and router web admin port (80) bypass cleanly.
   - Conditional Uninstallation Law: Generates locked script when focus timer is running.
"""

from typing import Dict, Any, List, Optional


class DdWrtFirewallManager:
    """Compiles and manages DD-WRT NVRAM firewall scripts."""

    LOCAL_PORT = 5353
    LAN_IF = "br0"

    ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112"
    ]

    def __init__(self, profile_id: str = "profile_home_primary"):
        self.profile_id = profile_id
        self.is_locked = False
        self.remaining_timer_seconds = 0

    def set_lock(self, locked: bool, remaining_seconds: int = 0) -> None:
        """Sets anti-tamper lock state."""
        self.is_locked = locked
        self.remaining_timer_seconds = max(0, remaining_seconds)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        return (not self.is_locked) and (self.remaining_timer_seconds == 0)

    def generate_rc_firewall(self) -> str:
        """Generates DD-WRT rc_firewall script."""
        lines = [
            "#!/bin/sh",
            "# DD-WRT FocusGuard DNS Firewall Script",
            "",
            "# Allow Router Web UI & DHCP",
            f"iptables -t nat -I PREROUTING -i {self.LAN_IF} -p udp --dport 67:68 -j ACCEPT",
            f"iptables -t nat -I PREROUTING -i {self.LAN_IF} -p tcp --dport 80 -j ACCEPT",
            "",
            "# Intercept Port 53 DNS and Redirect to FocusDNS Daemon",
            f"iptables -t nat -A PREROUTING -i {self.LAN_IF} -p udp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT}",
            f"iptables -t nat -A PREROUTING -i {self.LAN_IF} -p tcp --dport 53 -j REDIRECT --to-ports {self.LOCAL_PORT}",
            "",
            "# Drop Rogue DNS-over-TLS (Port 853)",
            f"iptables -I FORWARD -i {self.LAN_IF} -p tcp --dport 853 -j DROP",
            f"iptables -I FORWARD -i {self.LAN_IF} -p udp --dport 853 -j DROP",
            "",
            "# Drop Rogue Hardcoded DoH IPs (Port 443)"
        ]

        for ip in self.ROGUE_DOH_IPS:
            lines.append(f"iptables -I FORWARD -i {self.LAN_IF} -d {ip} -p tcp --dport 443 -j REJECT")

        lines.extend([
            "",
            'echo "FocusGuard DNS firewall active." > /dev/kmsg'
        ])

        return "\n".join(lines)

    def generate_nvram_commit_commands(self) -> str:
        """Generates NVRAM CLI commit sequence for 1-click installation."""
        firewall_script = self.generate_rc_firewall().replace("\n", "\\n").replace('"', '\\"')
        startup_script = f"/opt/bin/focus_dns_daemon --profile {self.profile_id} &"

        return f"""# 1-Click DD-WRT FocusGuard Installation
nvram set rc_firewall="{firewall_script}"
nvram set rc_startup="{startup_script}"
nvram commit
/tmp/etc/config/firewall.sh
logger "FocusDNS configured on DD-WRT router."
"""

    def generate_uninstall_commands(self) -> str:
        """Generates clean uninstallation commands or raises error if locked."""
        if not self.can_uninstall():
            raise PermissionError(
                f"ERROR_ACCESS_DENIED: Cannot uninstall FocusDNS from DD-WRT while focus session is active "
                f"({self.remaining_timer_seconds}s remaining)."
            )

        return """# FocusGuard DD-WRT Clean Uninstallation
nvram unset rc_firewall
nvram unset rc_startup
nvram commit
# Flush iptables redirection
iptables -t nat -F PREROUTING
iptables -F FORWARD
killall focus_dns_daemon 2>/dev/null
logger "FocusDNS cleanly uninstalled from DD-WRT router."
"""
