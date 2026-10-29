"""
Router Smart Queue Management (SQM) & CAKE Traffic Shaping Controller.

Configures Linux 'tc' and CAKE (Common Applications Kept Enhanced) algorithm
on home edge routers running OpenWrt, Asuswrt, or DD-WRT.

Inviolable Life-Safety Exemption:
- Emergency VoIP / SIP calling (DSCP EF / 46) is assigned to the ultra-low latency Tin 0.
- FocusDNS queries (port 53, 853, DoH) are assigned priority DSCP CS6 / 48.
- Recreational streaming and gaming bandwidth is throttled during active focus sessions.
"""

from typing import Dict, Any, List, Optional


class RouterSqmController:
    """Compiles tc CAKE queue management rules for router interfaces."""

    LAN_IF = "br-lan"
    WAN_IF = "eth0"

    def __init__(self, download_mbps: int = 100, upload_mbps: int = 20):
        self.download_mbps = download_mbps
        self.upload_mbps = upload_mbps
        self.is_focus_active = False

    def set_focus_mode(self, active: bool) -> None:
        """Toggles focus mode QoS profiles."""
        self.is_focus_active = active

    def generate_tc_cake_ingress_rules(self) -> str:
        """Generates ingress shaping rules with DSCP priority classes."""
        rate = f"{self.download_mbps}mbit"
        lines = [
            "#!/bin/sh",
            "# FocusGuard DNS - CAKE Ingress Smart Queue Management",
            f"tc qdisc del dev {self.LAN_IF} root 2>/dev/null",
            f"tc qdisc add dev {self.LAN_IF} root cake bandwidth {rate} diffserv4 nat dual-srchost wash",
            "",
            "# Life Safety: Prioritize Emergency SIP/VoIP to Voice Tin (DSCP EF/46)",
            f"iptables -t mangle -A PREROUTING -p udp -m multiport --dports 5060,5061,10000:20000 -j DSCP --set-dscp-class EF",
            "",
            "# Life Safety: Prioritize DNS query resolution (DSCP CS6/48)",
            f"iptables -t mangle -A PREROUTING -p udp --dport 53 -j DSCP --set-dscp-class CS6",
            f"iptables -t mangle -A PREROUTING -p tcp --dport 53 -j DSCP --set-dscp-class CS6",
            f"iptables -t mangle -A PREROUTING -p tcp --dport 853 -j DSCP --set-dscp-class CS6"
        ]

        if self.is_focus_active:
            lines.extend([
                "",
                "# Focus Session Active: Throttle Background Bulk Distractions (DSCP CS1/8)",
                f"iptables -t mangle -A PREROUTING -p tcp -m multiport --dports 1935,3478,443 -m length --length 1000:65535 -j DSCP --set-dscp-class CS1",
                'logger -t "FocusDNS-SQM" "Enforced Strict CAKE DiffServ shaping for active focus session."'
            ])

        return "\n".join(lines)

    def generate_tc_cake_egress_rules(self) -> str:
        """Generates egress shaping rules on router WAN uplink."""
        rate = f"{self.upload_mbps}mbit"
        return f"""#!/bin/sh
# FocusGuard DNS - CAKE Egress Traffic Shaping on WAN ({self.WAN_IF})
tc qdisc del dev {self.WAN_IF} root 2>/dev/null
tc qdisc add dev {self.WAN_IF} root cake bandwidth {rate} diffserv4 nat dual-dsthost wash
logger -t "FocusDNS-SQM" "Mounted CAKE egress queue on {self.WAN_IF} ({rate})."
"""

    def get_status(self) -> Dict[str, Any]:
        return {
            "lan_interface": self.LAN_IF,
            "wan_interface": self.WAN_IF,
            "download_mbps": self.download_mbps,
            "upload_mbps": self.upload_mbps,
            "is_focus_active": self.is_focus_active,
            "algorithm": "CAKE-DiffServ4"
        }
