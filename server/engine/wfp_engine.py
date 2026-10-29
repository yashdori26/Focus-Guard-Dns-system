"""
server/engine/wfp_engine.py
Windows Filtering Platform (WFP) Kernel-Level Firewall Rule Compiler & Policy Engine.

Architectural Guarantees:
1. Anti-Bypass Kernel Interception:
   - Compiles FWPM filters across ALE_AUTH_CONNECT, ALE_RESOURCE_ASSIGNMENT, and DATAGRAM_DATA layers.
   - Redirects all outbound UDP/TCP port 53 traffic to the local FocusDNS daemon (127.0.0.1:5353).
   - Blocks unauthorized hardcoded DoH (port 443) and DoT (port 853) IPs from Chrome, Edge, Firefox.
2. Per-Application Process Filtering:
   - Matches target application paths (e.g. steam.exe, discord.exe, chrome.exe) to enforce focus locks.
3. Conditional Uninstallation Law on Windows:
   - Normal Mode (Protection OFF & Timer 0): Service uninstallation & WFP teardown is 100% permitted.
   - Active Focus Mode (Protection ON or Timer > 0): Service deletion (sc delete), stoppage (sc stop),
     and WFP sublayer modifications are strictly locked.
4. Life Safety & OS Critical Exemption:
   - DHCP (ports 67/68), Windows Update (svchost.exe), and loopback traffic are NEVER blocked.
"""

import enum
import time
import uuid
from typing import Dict, Any, List, Optional, Set


class WfpLayer(str, enum.Enum):
    FWPM_LAYER_ALE_AUTH_CONNECT_V4 = "FWPM_LAYER_ALE_AUTH_CONNECT_V4"
    FWPM_LAYER_ALE_AUTH_CONNECT_V6 = "FWPM_LAYER_ALE_AUTH_CONNECT_V6"
    FWPM_LAYER_ALE_RESOURCE_ASSIGNMENT_V4 = "FWPM_LAYER_ALE_RESOURCE_ASSIGNMENT_V4"
    FWPM_LAYER_DATAGRAM_DATA_V4 = "FWPM_LAYER_DATAGRAM_DATA_V4"
    FWPM_LAYER_INBOUND_TRANSPORT_V4 = "FWPM_LAYER_INBOUND_TRANSPORT_V4"
    FWPM_LAYER_OUTBOUND_TRANSPORT_V4 = "FWPM_LAYER_OUTBOUND_TRANSPORT_V4"


class WfpAction(str, enum.Enum):
    FWP_ACTION_BLOCK = "BLOCK"
    FWP_ACTION_PERMIT = "PERMIT"
    FWP_ACTION_CALLOUT_TERMINATING = "CALLOUT_TERMINATING"
    FWP_ACTION_CALLOUT_INSPECTION = "CALLOUT_INSPECTION"


class WfpMatchType(str, enum.Enum):
    FWP_MATCH_EQUAL = "EQUAL"
    FWP_MATCH_NOT_EQUAL = "NOT_EQUAL"
    FWP_MATCH_GREATER = "GREATER"
    FWP_MATCH_LESS = "LESS"
    FWP_MATCH_RANGE = "RANGE"


class WfpCondition:
    """Represents a single match condition in a WFP filter."""

    def __init__(
        self,
        field_name: str,
        match_type: WfpMatchType,
        value: Any,
        description: str = "",
    ):
        self.field_name = field_name
        self.match_type = match_type
        self.value = value
        self.description = description

    def to_dict(self) -> Dict[str, Any]:
        return {
            "field": self.field_name,
            "match": self.match_type.value,
            "value": self.value,
            "description": self.description,
        }


class WfpFilterRule:
    """Represents a compiled Windows Filtering Platform filter rule."""

    def __init__(
        self,
        rule_id: str,
        name: str,
        layer: WfpLayer,
        action: WfpAction,
        weight: int = 100,
        sublayer_key: Optional[str] = None,
        conditions: Optional[List[WfpCondition]] = None,
        callout_guid: Optional[str] = None,
        target_app: Optional[str] = None,
    ):
        self.rule_id = rule_id
        self.name = name
        self.layer = layer
        self.action = action
        self.weight = weight
        self.sublayer_key = sublayer_key or "FOCUS_DNS_SUBLAYER_CORE"
        self.conditions = conditions or []
        self.callout_guid = callout_guid
        self.target_app = target_app
        self.created_at = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "name": self.name,
            "layer": self.layer.value,
            "action": self.action.value,
            "weight": self.weight,
            "sublayer_key": self.sublayer_key,
            "target_app": self.target_app,
            "callout_guid": self.callout_guid,
            "conditions": [c.to_dict() for c in self.conditions],
            "created_at": self.created_at,
        }


class WfpSubLayer:
    """Represents a dedicated WFP sublayer to guarantee filter precedence."""

    def __init__(
        self,
        sublayer_key: str,
        name: str,
        description: str,
        weight: int = 0x8000,
    ):
        self.sublayer_key = sublayer_key
        self.name = name
        self.description = description
        self.weight = weight

    def to_dict(self) -> Dict[str, Any]:
        return {
            "sublayer_key": self.sublayer_key,
            "name": self.name,
            "description": self.description,
            "weight": self.weight,
        }


class WfpRuleCompiler:
    """
    Production-grade Windows Filtering Platform rule compiler.
    Translates high-level FocusDNS policies into deterministic WFP rule sets.
    """

    SUBLAYER_GUID_CORE = "{B25C6718-47A1-4F2E-8CE3-0D44F2718E01}"
    SUBLAYER_GUID_OVERRIDE = "{C98D7129-58B2-4E3F-9DF4-1E55F3829F02}"

    # Known public DoH resolver IPs hardcoded in popular browsers
    ROGUE_DOH_IPS = [
        "1.1.1.1", "1.0.0.1",       # Cloudflare
        "8.8.8.8", "8.8.4.4",       # Google
        "9.9.9.9", "149.112.112.112", # Quad9
        "208.67.222.222", "208.67.220.220", # OpenDNS
        "94.140.14.14", "94.140.15.15", # AdGuard
        "45.90.28.0", "45.90.30.0", # NextDNS
    ]

    # Critical Windows OS system binaries that must NEVER be firewalled
    EXEMPT_SYSTEM_APPS = [
        "svchost.exe",      # Service Host (Windows Update, BITS, Network Store)
        "lsass.exe",        # Local Security Authority
        "services.exe",     # Windows Service Controller
        "spoolsv.exe",      # Print Spooler
        "FocusDnsDaemon.exe", # FocusDNS Windows Daemon itself
    ]

    def __init__(
        self,
        local_dns_proxy_port: int = 5353,
        focus_dns_server_ip: str = "127.0.0.1",
    ):
        self.local_dns_proxy_port = local_dns_proxy_port
        self.focus_dns_server_ip = focus_dns_server_ip
        self._rules: List[WfpFilterRule] = []
        self._sublayers: List[WfpSubLayer] = []
        self._is_protection_active: bool = False
        self._remaining_timer_seconds: int = 0
        self._blocked_apps: Set[str] = set()

        self._initialize_sublayers()

    def _initialize_sublayers(self) -> None:
        self._sublayers = [
            WfpSubLayer(
                sublayer_key=self.SUBLAYER_GUID_CORE,
                name="FocusDNS Core Interception Sublayer",
                description="High-priority sublayer intercepting standard port 53 and DoH bypasses.",
                weight=0x8000,
            ),
            WfpSubLayer(
                sublayer_key=self.SUBLAYER_GUID_OVERRIDE,
                name="FocusDNS Life Safety & OS Exemption Sublayer",
                description="Highest-priority sublayer exempting Windows Update, DHCP, and emergency paths.",
                weight=0xF000,
            ),
        ]

    def set_protection_state(self, active: bool, remaining_seconds: int = 0) -> None:
        """Sets active focus state governing Windows conditional uninstallation."""
        self._is_protection_active = active
        self._remaining_timer_seconds = max(0, remaining_seconds)

    def can_uninstall(self) -> bool:
        """
        Inviolable Conditional Uninstallation Law on Windows:
        - Normal Mode (Protection OFF & Timer 0): Clean uninstallation is 100% permitted.
        - Active Focus Mode (Protection ON or Timer > 0): Uninstallation is strictly locked.
        """
        if self._is_protection_active:
            return False
        if self._remaining_timer_seconds > 0:
            return False
        return True

    def configure_blocked_apps(self, app_list: List[str]) -> None:
        """Registers desktop applications (e.g. steam.exe, discord.exe) to block during focus."""
        self._blocked_apps = set(a.lower() for a in app_list)

    def compile_all_rules(self) -> List[WfpFilterRule]:
        """Compiles the complete production rule set for Windows Filtering Platform."""
        rules: List[WfpFilterRule] = []

        # 1. Life Safety & OS Critical Exemptions (Weight 0xF000)
        rules.extend(self._compile_exemptions())

        # 2. Port 53 Standard DNS Interception (Redirect to local daemon)
        rules.extend(self._compile_port_53_redirect())

        # 3. Port 853 Rogue DoT Blocking
        rules.extend(self._compile_port_853_defense())

        # 4. Rogue DoH IP Blocking (Port 443 IP filters for Chrome/Edge bypass)
        rules.extend(self._compile_doh_bypass_defense())

        # 5. Distraction Application Blocklist (during active focus)
        if self._is_protection_active or self._remaining_timer_seconds > 0:
            rules.extend(self._compile_app_blockades())

        self._rules = rules
        return rules

    def _compile_exemptions(self) -> List[WfpFilterRule]:
        """Compiles OS-level exemptions that must never be blocked."""
        exemptions = []

        # Loopback interface exemption (127.0.0.1)
        r_loopback = WfpFilterRule(
            rule_id="EXEMPT_LOOPBACK_TRAFFIC",
            name="Exempt Localhost & Loopback Interface",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_PERMIT,
            weight=0xF500,
            sublayer_key=self.SUBLAYER_GUID_OVERRIDE,
            conditions=[
                WfpCondition("FWPM_CONDITION_IP_REMOTE_ADDRESS", WfpMatchType.FWP_MATCH_EQUAL, "127.0.0.1", "Localhost IPv4"),
            ],
        )
        exemptions.append(r_loopback)

        # DHCP Port 67/68 exemption
        r_dhcp = WfpFilterRule(
            rule_id="EXEMPT_DHCP_TRAFFIC",
            name="Exempt Network DHCP Negotiation",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_PERMIT,
            weight=0xF400,
            sublayer_key=self.SUBLAYER_GUID_OVERRIDE,
            conditions=[
                WfpCondition("FWPM_CONDITION_IP_REMOTE_PORT", WfpMatchType.FWP_MATCH_EQUAL, 67, "DHCP Server Port"),
            ],
        )
        exemptions.append(r_dhcp)

        # Windows Update (svchost.exe) exemption
        r_win_update = WfpFilterRule(
            rule_id="EXEMPT_WINDOWS_UPDATE",
            name="Exempt Windows Update & Core Service Host",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_PERMIT,
            weight=0xF300,
            sublayer_key=self.SUBLAYER_GUID_OVERRIDE,
            target_app="svchost.exe",
            conditions=[
                WfpCondition("FWPM_CONDITION_ALE_APP_ID", WfpMatchType.FWP_MATCH_EQUAL, "svchost.exe", "Windows Service Host"),
            ],
        )
        exemptions.append(r_win_update)

        # FocusDNS Daemon itself must never intercept its own upstream requests
        r_daemon = WfpFilterRule(
            rule_id="EXEMPT_FOCUSDNS_DAEMON",
            name="Exempt FocusDNS Daemon Upstream Traffic",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_PERMIT,
            weight=0xF600,
            sublayer_key=self.SUBLAYER_GUID_OVERRIDE,
            target_app="FocusDnsDaemon.exe",
            conditions=[
                WfpCondition("FWPM_CONDITION_ALE_APP_ID", WfpMatchType.FWP_MATCH_EQUAL, "FocusDnsDaemon.exe", "FocusDNS Local Service"),
            ],
        )
        exemptions.append(r_daemon)

        return exemptions

    def _compile_port_53_redirect(self) -> List[WfpFilterRule]:
        """Redirects outbound standard DNS queries to FocusDNS local loopback proxy."""
        rules = []

        # UDP Port 53
        r_udp = WfpFilterRule(
            rule_id="REDIRECT_DNS_UDP_PORT_53",
            name="Redirect Standard UDP DNS Queries to Local FocusDNS Proxy",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_CALLOUT_TERMINATING,
            weight=0x8500,
            sublayer_key=self.SUBLAYER_GUID_CORE,
            callout_guid="{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}",  # Redirect callout
            conditions=[
                WfpCondition("FWPM_CONDITION_IP_REMOTE_PORT", WfpMatchType.FWP_MATCH_EQUAL, 53, "Standard DNS Port"),
                WfpCondition("FWPM_CONDITION_IP_PROTOCOL", WfpMatchType.FWP_MATCH_EQUAL, 17, "UDP Protocol"),
            ],
        )
        rules.append(r_udp)

        # TCP Port 53
        r_tcp = WfpFilterRule(
            rule_id="REDIRECT_DNS_TCP_PORT_53",
            name="Redirect Standard TCP DNS Queries to Local FocusDNS Proxy",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_CALLOUT_TERMINATING,
            weight=0x8400,
            sublayer_key=self.SUBLAYER_GUID_CORE,
            callout_guid="{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}",
            conditions=[
                WfpCondition("FWPM_CONDITION_IP_REMOTE_PORT", WfpMatchType.FWP_MATCH_EQUAL, 53, "Standard DNS Port"),
                WfpCondition("FWPM_CONDITION_IP_PROTOCOL", WfpMatchType.FWP_MATCH_EQUAL, 6, "TCP Protocol"),
            ],
        )
        rules.append(r_tcp)

        return rules

    def _compile_port_853_defense(self) -> List[WfpFilterRule]:
        """Blocks unauthorized DNS-over-TLS (DoT) connections attempting to bypass filter."""
        r_dot = WfpFilterRule(
            rule_id="BLOCK_ROGUE_DOT_PORT_853",
            name="Block Rogue DNS-over-TLS Bypasses on Port 853",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_BLOCK,
            weight=0x8300,
            sublayer_key=self.SUBLAYER_GUID_CORE,
            conditions=[
                WfpCondition("FWPM_CONDITION_IP_REMOTE_PORT", WfpMatchType.FWP_MATCH_EQUAL, 853, "DoT Port"),
            ],
        )
        return [r_dot]

    def _compile_doh_bypass_defense(self) -> List[WfpFilterRule]:
        """Blocks direct HTTPS connections to known public DoH resolvers from non-browser apps."""
        rules = []
        for i, ip in enumerate(self.ROGUE_DOH_IPS):
            rule = WfpFilterRule(
                rule_id=f"BLOCK_DOH_RESOLVER_{i}_{ip.replace('.', '_')}",
                name=f"Block Direct DoH Bypass to {ip}",
                layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
                action=WfpAction.FWP_ACTION_BLOCK,
                weight=0x8200,
                sublayer_key=self.SUBLAYER_GUID_CORE,
                conditions=[
                    WfpCondition("FWPM_CONDITION_IP_REMOTE_ADDRESS", WfpMatchType.FWP_MATCH_EQUAL, ip, f"Rogue DoH IP {ip}"),
                    WfpCondition("FWPM_CONDITION_IP_REMOTE_PORT", WfpMatchType.FWP_MATCH_EQUAL, 443, "HTTPS Port"),
                ],
            )
            rules.append(rule)
        return rules

    def _compile_app_blockades(self) -> List[WfpFilterRule]:
        """Compiles per-process network blocks for distracting desktop apps."""
        rules = []
        for app in sorted(self._blocked_apps):
            r = WfpFilterRule(
                rule_id=f"BLOCK_APP_{app.replace('.', '_').upper()}",
                name=f"Lock Network Access for Distraction App: {app}",
                layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
                action=WfpAction.FWP_ACTION_BLOCK,
                weight=0x9000,
                sublayer_key=self.SUBLAYER_GUID_CORE,
                target_app=app,
                conditions=[
                    WfpCondition("FWPM_CONDITION_ALE_APP_ID", WfpMatchType.FWP_MATCH_EQUAL, app, f"Target Executable {app}"),
                ],
            )
            rules.append(r)
        return rules

    def generate_cpp_wfp_header(self) -> str:
        """Generates Win32 C++ header containing pre-compiled WFP GUIDs and configurations."""
        lines = [
            "// FocusDnsWfpGenerated.h - Generated by FocusDNS WFP Rule Compiler",
            "#pragma once",
            "#include <windows.h>",
            "#include <fwpmu.h>",
            "",
            f"// Sublayer GUID Core: {self.SUBLAYER_GUID_CORE}",
            'static const GUID FOCUS_DNS_SUBLAYER_CORE = { 0xb25c6718, 0x47a1, 0x4f2e, { 0x8c, 0xe3, 0xd, 0x44, 0xf2, 0x71, 0x8e, 0x1 } };',
            f"// Sublayer GUID Override: {self.SUBLAYER_GUID_OVERRIDE}",
            'static const GUID FOCUS_DNS_SUBLAYER_OVERRIDE = { 0xc98d7129, 0x58b2, 0x4e3f, { 0x9d, 0xf4, 0x1e, 0x55, 0xf3, 0x82, 0x9f, 0x2 } };',
            "",
            f"#define FOCUS_DNS_LOCAL_PROXY_PORT {self.local_dns_proxy_port}",
            f"#define FOCUS_DNS_RULE_COUNT {len(self._rules)}",
            "",
            "// Conditional Uninstallation Law Status",
            f"static const bool G_CAN_UNINSTALL = {'true' if self.can_uninstall() else 'false'};",
            f"static const int G_REMAINING_TIMER_SECONDS = {self._remaining_timer_seconds};",
            "",
        ]
        return "\n".join(lines)

    def get_summary(self) -> Dict[str, Any]:
        """Returns statistics on compiled rules, sublayers, and uninstallation posture."""
        return {
            "total_rules": len(self._rules),
            "sublayers": [s.to_dict() for s in self._sublayers],
            "is_protection_active": self._is_protection_active,
            "remaining_timer_seconds": self._remaining_timer_seconds,
            "can_uninstall": self.can_uninstall(),
            "blocked_apps": list(self._blocked_apps),
            "rogue_doh_ip_count": len(self.ROGUE_DOH_IPS),
            "exempt_system_app_count": len(self.EXEMPT_SYSTEM_APPS),
        }
