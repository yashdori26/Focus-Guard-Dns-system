--[[
    FocusGuard DNS - LuCI CBI Model for Smart Queue Management & CAKE QoS
    Configures real-time packet prioritization and focus-mode bandwidth policing.
]]--

local m, s, o
local uci = require("luci.model.uci").cursor()

m = Map("focus_dns", translate("FocusGuard Smart Queue Management (SQM)"),
    translate("Prioritizes emergency calling and FocusDNS query resolution using the Linux CAKE algorithm."))

s = m:section(NamedSection, "settings", "focus_dns", translate("QoS & Traffic Shaper Parameters"))
s.anonymous = false

-- SQM Master Enable
o = s:option(Flag, "sqm_enabled", translate("Enable CAKE Traffic Shaping"),
    translate("Active queue management eliminates bufferbloat and latency spikes."))
o.default = o.enabled
o.rmempty = false

-- Download Bandwidth
o = s:option(Value, "download_mbps", translate("Download Bandwidth (Mbps)"),
    translate("Set to 95% of your measured ISP WAN download speed."))
o.datatype = "uinteger"
o.default = "100"
o.rmempty = false

-- Upload Bandwidth
o = s:option(Value, "upload_mbps", translate("Upload Bandwidth (Mbps)"),
    translate("Set to 95% of your measured ISP WAN upload speed."))
o.datatype = "uinteger"
o.default = "20"
o.rmempty = false

-- DiffServ Profile
o = s:option(ListValue, "diffserv_profile", translate("DiffServ Tin Classification"),
    translate("Separates latency-sensitive voice/DNS traffic from bulk downloads."))
o:value("diffserv4", translate("DiffServ 4-Tin (Voice, Video, Best-Effort, Bulk)"))
o:value("diffserv3", translate("DiffServ 3-Tin (Low-Latency, Best-Effort, Bulk)"))
o.default = "diffserv4"

-- Life Safety VoIP Exemption
o = s:option(Flag, "prioritize_emergency_voip", translate("Prioritize Emergency & VoIP Traffic"),
    translate("Guarantees zero-packet-drop classification (DSCP EF) for 911/SIP calls."))
o.default = o.enabled
o.readonly = true -- Hardcoded inviolable life-safety rule

-- Focus Distraction Throttling
o = s:option(Flag, "throttle_streaming_in_focus", translate("Throttle High-Bandwidth Video in Focus"),
    translate("Polices streaming and gaming bandwidth to DSCP CS1 when a focus timer is active."))
o.default = o.enabled

return m
