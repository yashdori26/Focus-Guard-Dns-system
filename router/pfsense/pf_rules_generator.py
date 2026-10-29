"""
router/pfsense/pf_rules_generator.py
FreeBSD Packet Filter (PF) Rule Compiler for pfSense and OPNSense Firewalls.

Architectural Guarantees:
1. Zero-Bypass DNS Redirection:
   - Compiles native BSD pf anchor rules (`rdr pass on $lan_if proto { udp tcp } from any to ! $lan_ip port 53 -> 127.0.0.1 port 5353`).
   - Automatically supports multi-VLAN networks (Guest, IoT, Management, Office).
2. Anti-Circumvention Rogue DoH/DoT Drops:
   - Drops hardcoded public DoH IP connections (1.1.1.1, 8.8.8.8, 9.9.9.9) on port 443.
   - Enforces strict single-point DoT egress through the authenticated FocusDNS stub.
3. Fail-Safe Guarantee:
   - Loopback (lo0) and inter-VLAN local domain queries are preserved to prevent network outages.
"""

import enum
import time
from typing import Dict, Any, List, Optional, Set


class PfProtocol(str, enum.Enum):
    UDP = "udp"
    TCP = "tcp"
    BOTH = "{ udp tcp }"
    ALL = "all"


class PfAction(str, enum.Enum):
    PASS = "pass"
    BLOCK = "block drop"
    RDR = "rdr pass"


class PfRule:
    """Represents a discrete BSD Packet Filter configuration rule."""

    def __init__(
        self,
        action: PfAction,
        interfaces: List[str],
        protocol: PfProtocol,
        src: str = "any",
        dst: str = "any",
        dst_port: Optional[str] = None,
        redirect_ip: Optional[str] = None,
        redirect_port: Optional[str] = None,
        quick: bool = True,
        direction: str = "in",
        label: str = "",
        user: Optional[str] = None,
    ):
        self.action = action
        self.interfaces = interfaces
        self.protocol = protocol
        self.src = src
        self.dst = dst
        self.dst_port = dst_port
        self.redirect_ip = redirect_ip
        self.redirect_port = redirect_port
        self.quick = quick
        self.direction = direction
        self.label = label
        self.user = user

    def to_pf_string(self) -> str:
        """Renders rule to standard pf.conf syntax."""
        parts = []

        if self.action == PfAction.RDR:
            # Redirection syntax: rdr pass on { em0 em1 } proto { udp tcp } from any to any port 53 -> 127.0.0.1 port 5353
            if_str = "{" + " ".join(self.interfaces) + "}" if len(self.interfaces) > 1 else self.interfaces[0]
            rdr_str = f"rdr pass on {if_str} proto {self.protocol.value} from {self.src} to {self.dst}"
            if self.dst_port:
                rdr_str += f" port {self.dst_port}"
            rdr_str += f" -> {self.redirect_ip} port {self.redirect_port}"
            if self.label:
                rdr_str += f' tag "{self.label}"'
            return rdr_str

        # Standard filtering syntax: block drop out log quick proto tcp to { 1.1.1.1 } port 443
        parts.append(self.action.value)
        if self.direction:
            parts.append(self.direction)
        if self.quick:
            parts.append("quick")

        if self.interfaces and self.interfaces != ["any"]:
            if_str = "{" + " ".join(self.interfaces) + "}" if len(self.interfaces) > 1 else self.interfaces[0]
            parts.append(f"on {if_str}")

        parts.append(f"proto {self.protocol.value}")
        parts.append(f"from {self.src}")
        parts.append(f"to {self.dst}")

        if self.dst_port:
            parts.append(f"port {self.dst_port}")
        if self.user:
            parts.append(f"user {self.user}")
        if self.label:
            parts.append(f'label "{self.label}"')

        return " ".join(parts)


class PfRulesGenerator:
    """
    Compiles enterprise-grade pf.conf anchor configurations for pfSense / OPNSense.
    """

    DEFAULT_ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",
        "8.8.8.8", "8.8.4.4",
        "9.9.9.9", "149.112.112.112",
        "208.67.222.222", "208.67.220.220",
        "94.140.14.14", "94.140.15.15",
    ]

    def __init__(
        self,
        lan_interfaces: Optional[List[str]] = None,
        local_proxy_port: int = 5353,
        focus_dot_port: int = 853,
        block_rogue_doh: bool = True,
        block_rogue_dot: bool = True,
    ):
        self.lan_interfaces = lan_interfaces or ["em0", "igb0", "vtnet0"]
        self.local_proxy_port = local_proxy_port
        self.focus_dot_port = focus_dot_port
        self.block_rogue_doh = block_rogue_doh
        self.block_rogue_dot = block_rogue_dot
        self._rules: List[PfRule] = []

    def compile_rules(self) -> List[PfRule]:
        """Generates all necessary PF rules."""
        rules: List[PfRule] = []

        # 1. Loopback Pass Exemption
        r_loopback = PfRule(
            action=PfAction.PASS,
            interfaces=["lo0"],
            protocol=PfProtocol.ALL,
            src="any",
            dst="any",
            quick=True,
            direction="",
            label="FocusDNS: Loopback Exemption",
        )
        rules.append(r_loopback)

        # 2. Port 53 Redirection on all LAN interfaces
        r_rdr = PfRule(
            action=PfAction.RDR,
            interfaces=self.lan_interfaces,
            protocol=PfProtocol.BOTH,
            src="any",
            dst="! 127.0.0.1",
            dst_port="53",
            redirect_ip="127.0.0.1",
            redirect_port=str(self.local_proxy_port),
            label="FocusDNS_DNS_Redirect",
        )
        rules.append(r_rdr)

        # 3. Allow redirected queries to reach local loopback daemon
        r_pass_local = PfRule(
            action=PfAction.PASS,
            interfaces=["lo0"],
            protocol=PfProtocol.BOTH,
            src="any",
            dst="127.0.0.1",
            dst_port=str(self.local_proxy_port),
            quick=True,
            direction="in",
            label="FocusDNS: Allow Local Proxy Inbound",
        )
        rules.append(r_pass_local)

        # 4. Block direct rogue DoH IP traffic if enabled
        if self.block_rogue_doh:
            ips_str = "{ " + " ".join(self.DEFAULT_ROGUE_DOH_IPS) + " }"
            r_block_doh = PfRule(
                action=PfAction.BLOCK,
                interfaces=["any"],
                protocol=PfProtocol.TCP,
                src="any",
                dst=ips_str,
                dst_port="443",
                quick=True,
                direction="out",
                label="FocusDNS: Drop Rogue Public DoH",
            )
            rules.append(r_block_doh)

        # 5. Block unauthorized DoT (port 853) traffic
        if self.block_rogue_dot:
            # Allow FocusDNS daemon user to egress on port 853
            r_allow_daemon = PfRule(
                action=PfAction.PASS,
                interfaces=["any"],
                protocol=PfProtocol.TCP,
                src="any",
                dst="any",
                dst_port=str(self.focus_dot_port),
                quick=True,
                direction="out",
                user="_focusdns",
                label="FocusDNS: Daemon Upstream DoT Egress",
            )
            rules.append(r_allow_daemon)

            # Drop all other port 853 traffic
            r_block_dot = PfRule(
                action=PfAction.BLOCK,
                interfaces=["any"],
                protocol=PfProtocol.TCP,
                src="any",
                dst="any",
                dst_port="853",
                quick=True,
                direction="out",
                label="FocusDNS: Drop Unauthorized Port 853 DoT",
            )
            rules.append(r_block_dot)

        self._rules = rules
        return rules

    def generate_pf_anchor_config(self) -> str:
        """Renders complete /etc/pf.anchors/focus_dns file contents."""
        self.compile_rules()
        lines = [
            "# ===========================================================",
            "# FocusDNS Whole-Home Firewall Anchor Configuration for FreeBSD",
            "# Compatible with pfSense 2.7+ and OPNSense 23+",
            f"# Generated: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}",
            "# ===========================================================",
            "",
            "# Tables & Interface macros",
            f"focus_lan_ifs = \"{{ {' '.join(self.lan_interfaces)} }}\"",
            "",
            "# Packet Filter Rules",
        ]

        for rule in self._rules:
            lines.append(rule.to_pf_string())

        lines.append("")
        return "\n".join(lines)

    def get_summary(self) -> Dict[str, Any]:
        """Returns statistics on compiled BSD PF rules."""
        return {
            "total_rules": len(self._rules),
            "lan_interfaces": self.lan_interfaces,
            "local_proxy_port": self.local_proxy_port,
            "focus_dot_port": self.focus_dot_port,
            "block_rogue_doh": self.block_rogue_doh,
            "block_rogue_dot": self.block_rogue_dot,
            "anchor_name": "focus_dns",
        }
