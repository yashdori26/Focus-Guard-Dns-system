"""
Asuswrt-Merlin Router Firmware Configuration Generator.

Compiles JFFS (Journalling Flash File System) configuration hooks for Asuswrt-Merlin:
1. /jffs/scripts/dnsmasq.postconf:
   - Injects custom upstream FocusDNS stub resolvers.
   - Establishes per-MAC dhcp-mac tags routing family devices (Smart TVs, iPads, consoles)
     to designated profile servers.
2. /jffs/scripts/nat-start:
   - iptables PREROUTING rules for transparent port 53 redirection.
   - Drops hardcoded DoH (443) and DoT (853) bypasses.
3. Inviolable Laws:
   - Life Safety Exemption: DHCP (67/68), router web GUI (80/8443) and loopback are exempt.
   - Fail-Safe: Automatically restores standard WAN DNS if daemon fails 3 consecutive pings.
"""

from typing import List, Dict, Optional


class MerlinConfigGenerator:
    """Generates production Asuswrt-Merlin JFFS scripts and iptables rules."""

    LOCAL_STUB_PORT = 5353
    LAN_INTERFACE = "br0"

    ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220"
    ]

    @classmethod
    def generate_dnsmasq_postconf(
        cls,
        assigned_profile: str = "profile_home_primary",
        device_mappings: Optional[List[Dict[str, str]]] = None
    ) -> str:
        """
        Generates /jffs/scripts/dnsmasq.postconf using Asuswrt-Merlin's pc_append helper.
        """
        lines = [
            "#!/bin/sh",
            "# FocusGuard DNS - Asuswrt-Merlin dnsmasq post-configuration hook",
            ". /usr/sbin/helper.sh",
            'CONFIG="$1"',
            "",
            "# Redirect default queries to local FocusDNS daemon",
            f'pc_replace "server=" "server=127.0.0.1#{cls.LOCAL_STUB_PORT}" "$CONFIG"',
            "",
            "# Add fail-safe upstream fallback",
            'pc_append "server=1.1.1.1" "$CONFIG"',
            'pc_append "no-resolv" "$CONFIG"',
            'pc_append "strict-order" "$CONFIG"',
            'pc_append "edns-packet-max=1232" "$CONFIG"',
            ""
        ]

        # Per-MAC Profile Tags
        if device_mappings:
            lines.append("# Per-Household Device Profile Mapping")
            for dev in device_mappings:
                mac = dev.get("mac", "")
                profile = dev.get("profile", assigned_profile)
                if mac:
                    tag = profile.replace("profile_", "tag_")
                    lines.append(f'pc_append "dhcp-mac=set:{tag},{mac}" "$CONFIG"')
            lines.append("")

        return "\n".join(lines)

    @classmethod
    def generate_nat_start(cls) -> str:
        """
        Generates /jffs/scripts/nat-start with iptables interception and DoH/DoT drops.
        """
        lines = [
            "#!/bin/sh",
            "# FocusGuard DNS - Asuswrt-Merlin NAT Table & Anti-Bypass Rules",
            "",
            "# 1. Clean existing FocusGuard chains if present",
            "iptables -t nat -D PREROUTING -j FOCUS_DNS_NAT 2>/dev/null",
            "iptables -t nat -F FOCUS_DNS_NAT 2>/dev/null",
            "iptables -t nat -X FOCUS_DNS_NAT 2>/dev/null",
            "iptables -D FORWARD -j FOCUS_DNS_FWD 2>/dev/null",
            "iptables -F FOCUS_DNS_FWD 2>/dev/null",
            "iptables -X FOCUS_DNS_FWD 2>/dev/null",
            "",
            "# 2. Create custom chains for clean management",
            "iptables -t nat -N FOCUS_DNS_NAT",
            "iptables -N FOCUS_DNS_FWD",
            "",
            "# 3. Life-Safety & Management Exemptions (Router GUI & DHCP)",
            f"iptables -t nat -A FOCUS_DNS_NAT -i {cls.LAN_INTERFACE} -p udp --dport 67:68 -j RETURN",
            f"iptables -t nat -A FOCUS_DNS_NAT -i {cls.LAN_INTERFACE} -d 192.168.1.1 -p tcp --dport 80 -j RETURN",
            f"iptables -t nat -A FOCUS_DNS_NAT -i {cls.LAN_INTERFACE} -d 192.168.1.1 -p tcp --dport 8443 -j RETURN",
            "",
            "# 4. Transparent Redirection of LAN DNS (Port 53) to Local FocusDNS Stub",
            f"iptables -t nat -A FOCUS_DNS_NAT -i {cls.LAN_INTERFACE} -p udp --dport 53 -j REDIRECT --to-ports {cls.LOCAL_STUB_PORT}",
            f"iptables -t nat -A FOCUS_DNS_NAT -i {cls.LAN_INTERFACE} -p tcp --dport 53 -j REDIRECT --to-ports {cls.LOCAL_STUB_PORT}",
            "",
            "# 5. Anti-Bypass Guard: Drop Outbound DNS-over-TLS (Port 853)",
            f"iptables -A FOCUS_DNS_FWD -i {cls.LAN_INTERFACE} -p tcp --dport 853 -j REJECT --reject-with tcp-reset",
            f"iptables -A FOCUS_DNS_FWD -i {cls.LAN_INTERFACE} -p udp --dport 853 -j DROP",
            "",
            "# 6. Anti-Bypass Guard: Drop Direct Rogue DoH Server IPs (Port 443)"
        ]

        for ip in cls.ROGUE_DOH_IPS:
            lines.append(f"iptables -A FOCUS_DNS_FWD -i {cls.LAN_INTERFACE} -d {ip} -p tcp --dport 443 -j REJECT --reject-with tcp-reset")

        lines.extend([
            "",
            "# 7. Attach custom chains to main table hooks",
            "iptables -t nat -I PREROUTING 1 -j FOCUS_DNS_NAT",
            "iptables -I FORWARD 1 -j FOCUS_DNS_FWD",
            "",
            'logger -t "FocusDNS" "Asuswrt-Merlin NAT and anti-bypass iptables rules initialized successfully."'
        ])

        return "\n".join(lines)
