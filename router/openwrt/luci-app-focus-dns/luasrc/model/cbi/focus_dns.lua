--[[
LuCI CBI Model for FocusDNS Whole-Home Router Guard
Location: /usr/lib/lua/luci/model/cbi/focus_dns.lua
]]--

local m, s, o

m = Map("focus_dns", _("FocusDNS Whole-Home Router Guard"),
	_("Enforces DNS protection, content filtering, and anti-bypass across all home network devices (Smart TVs, iPads, PCs, IoT)."))

-- -------------------------------------------------------------
-- Section 1: Global Router Settings
-- -------------------------------------------------------------
s = m:section(NamedSection, "settings", "global", _("Global Protection Settings"))
s.anonymous = false
s.addremove = false

o = s:option(Flag, "enabled", _("Enable FocusDNS Interception"),
	_("Intercepts all outbound port 53 traffic on LAN interfaces and redirects to FocusDNS."))
o.rmempty = false
o.default = "1"

o = s:option(Value, "profile_id", _("Default Network Profile ID"),
	_("The FocusDNS Profile token applied to unassigned household devices."))
o.default = "profile_home_primary"
o.rmempty = false

o = s:option(ListValue, "upstream_protocol", _("Upstream Transport Protocol"))
o:value("dot", _("DNS-over-TLS (DoT, Port 853) - Recommended"))
o:value("doh", _("DNS-over-HTTPS (DoH, Port 443)"))
o:value("doq", _("DNS-over-QUIC (DoQ, Port 853)"))
o.default = "dot"

o = s:option(Value, "upstream_dot_server", _("FocusDNS Server Hostname"),
	_("FQDN of the FocusDNS cloud resolver."))
o.default = "dns.focusguard.io"

o = s:option(Flag, "failsafe_enabled", _("Fail-Safe Fallback"),
	_("Guarantees that local network resolution (.lan, .local, router IP) never breaks if upstream internet is interrupted."))
o.default = "1"

o = s:option(Flag, "block_rogue_doh", _("Block Rogue DoH Bypasses"),
	_("Drops direct HTTPS connections to known public DoH IPs (Cloudflare, Google, Quad9) from rogue browsers."))
o.default = "1"

o = s:option(Flag, "block_rogue_dot", _("Block Rogue DoT Bypasses"),
	_("Drops non-FocusDNS port 853 traffic."))
o.default = "1"

o = s:option(Flag, "edns_client_subnet", _("Inject EDNS0 Client Subnet (ECS)"),
	_("Passes internal client subnet/MAC to FocusDNS for device-level reporting."))
o.default = "1"

-- -------------------------------------------------------------
-- Section 2: Household Devices & Per-MAC Profile Mapping
-- -------------------------------------------------------------
s = m:section(TypedSection, "client", _("Per-Device Profile Assignments"),
	_("Assign customized FocusDNS profiles (e.g. Kids Profile, Strict Work, Ad-Free IoT) based on device hardware MAC address."))
s.template = "cbi/tblsection"
s.anonymous = false
s.addremove = true

o = s:option(Value, "hostname", _("Device Name"))
o.placeholder = "e.g. Sarah's iPad Mini"

o = s:option(Value, "mac_address", _("Hardware MAC Address"))
o.placeholder = "AA:BB:CC:DD:EE:FF"
o.rmempty = false

o = s:option(ListValue, "assigned_profile", _("Assigned Profile"))
o:value("profile_strict_kids", _("Strict Kids (No Social / Adult / SafeSearch On)"))
o:value("profile_deep_work", _("Deep Work (No Distractions / News / Shopping)"))
o:value("profile_ad_free_iot", _("Ad-Free Smart TV & IoT"))
o:value("profile_family_safe", _("Standard Family Safe"))
o.default = "profile_family_safe"

o = s:option(ListValue, "device_category", _("Device Type"))
o:value("SmartTV", _("Smart TV"))
o:value("Tablet", _("Tablet / iPad"))
o:value("Phone", _("Smartphone"))
o:value("Laptop", _("PC / Laptop"))
o:value("GamingConsole", _("Gaming Console (PlayStation/Xbox/Switch)"))
o:value("IoT", _("Smart Home / IoT Device"))

o = s:option(Flag, "strict_lock", _("Strict Lockdown"),
	_("If enabled, blocks all fallback and temporary bypass attempts for this device."))
o.default = "0"

return m
