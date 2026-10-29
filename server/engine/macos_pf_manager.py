"""
macOS BSD Packet Filter (PF) Anchor Configuration Engine.

Manages low-level /etc/pf.anchors/com.focusguard packet filter integration on macOS:
1. Intercepts raw sockets and localhost loopback DNS queries before reachability checks.
2. Hard blocks outbound TCP 443 to public DoH servers and TCP 853 to DoT servers.
3. Inviolable Life-Safety Exemption: APNs (5223), DHCP (67/68), and local Apple services pass cleanly.
4. Conditional Uninstallation: Disabling the anchor is strictly rejected during active focus mode.
"""

from typing import Dict, Any, List, Set


class MacOsPfManager:
    """Manages BSD PF anchor configuration files and rules on macOS."""

    ANCHOR_PATH = "/etc/pf.anchors/com.focusguard"
    ANCHOR_NAME = "com.focusguard"

    ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220"
    ]

    def __init__(self):
        self.is_anchor_active = False
        self.is_focus_locked = False
        self.remaining_timer_seconds = 0

    def set_focus_lock(self, locked: bool, remaining_seconds: int = 0) -> None:
        """Sets conditional uninstallation lock."""
        self.is_focus_locked = locked
        self.remaining_timer_seconds = max(0, remaining_seconds)

    def can_uninstall(self) -> bool:
        """Evaluates Conditional Uninstallation Law."""
        return (not self.is_focus_locked) and (self.remaining_timer_seconds == 0)

    def generate_anchor_rules(self) -> str:
        """Generates /etc/pf.anchors/com.focusguard file content."""
        ips_str = " ".join(self.ROGUE_DOH_IPS)
        return f"""# FocusGuard macOS BSD Packet Filter Anchor ({self.ANCHOR_NAME})
# Life-Safety Exemptions: Never block DHCP, APNs, or local DNS stub
pass out quick proto udp to any port 67:68
pass out quick proto tcp to any port 5223
pass on lo0 proto {{ udp tcp }} to 127.0.0.1 port 53

# Anti-Bypass Guard: Drop Rogue DNS-over-TLS (Port 853)
block drop out quick proto tcp to any port 853
block drop out quick proto udp to any port 853

# Anti-Bypass Guard: Drop Rogue Direct DoH Server IPs (Port 443)
table <focus_rogue_doh> {{ {ips_str} }}
block drop out quick proto tcp to <focus_rogue_doh> port 443

# Redirect standard port 53 DNS to local FocusDNS daemon
rdr pass on lo0 proto {{ udp tcp }} from any to any port 53 -> 127.0.0.1 port 53
"""

    def generate_anchor_activation_script(self) -> str:
        """Generates shell script to load anchor into pfctl."""
        return f"""#!/bin/sh
# FocusGuard macOS PF Activation Script
cat << 'EOF' > {self.ANCHOR_PATH}
{self.generate_anchor_rules()}
EOF

# Load and evaluate anchor in pfctl
pfctl -a {self.ANCHOR_NAME} -f {self.ANCHOR_PATH}
pfctl -e 2>/dev/null
echo "FocusGuard macOS PF anchor loaded successfully."
"""

    def generate_anchor_teardown_script(self) -> str:
        """Generates anchor flush script (strictly locked if focus active)."""
        if not self.can_uninstall():
            raise PermissionError(
                f"ERROR_ACCESS_DENIED: Cannot teardown macOS PF anchor while focus session is active "
                f"({self.remaining_timer_seconds}s remaining)."
            )

        return f"""#!/bin/sh
# FocusGuard macOS PF Clean Teardown
pfctl -a {self.ANCHOR_NAME} -F all
rm -f {self.ANCHOR_PATH}
echo "FocusGuard macOS PF anchor cleanly dismantled."
"""

    def get_status(self) -> Dict[str, Any]:
        return {
            "anchor_name": self.ANCHOR_NAME,
            "anchor_path": self.ANCHOR_PATH,
            "is_anchor_active": self.is_anchor_active,
            "is_focus_locked": self.is_focus_locked,
            "remaining_timer_seconds": self.remaining_timer_seconds,
            "can_uninstall": self.can_uninstall(),
            "rogue_doh_ips_count": len(self.ROGUE_DOH_IPS)
        }
