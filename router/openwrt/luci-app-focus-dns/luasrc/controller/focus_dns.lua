--[[
LuCI - Lua Configuration Interface for FocusDNS Router Suite
Location: /usr/lib/lua/luci/controller/focus_dns.lua
]]--

module("luci.controller.focus_dns", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/focus_dns") then
		return
	end

	-- Top-level menu entry under "Services -> FocusDNS Whole-Home Guard"
	local page = entry({"admin", "services", "focus_dns"}, cbi("focus_dns"), _("FocusDNS Guard"), 60)
	page.dependent = true
	page.acl_depends = { "luci-app-focus-dns" }

	-- Sub-entry: Real-Time Status & Devices
	entry({"admin", "services", "focus_dns", "status"}, template("focus_dns/status"), _("Status & Household Devices"), 10).leaf = true

	-- RPC JSON API for polling status without full page reload
	entry({"admin", "services", "focus_dns", "api_status"}, call("action_api_status")).leaf = true
	entry({"admin", "services", "focus_dns", "api_toggle"}, call("action_api_toggle")).leaf = true
end

function action_api_status()
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local json = require "luci.jsonc"

	local enabled = uci:get("focus_dns", "settings", "enabled") == "1"
	local profile_id = uci:get("focus_dns", "settings", "profile_id") or "default_home"
	local primary_port = uci:get("focus_dns", "settings", "primary_port") or "5353"
	local failsafe = uci:get("focus_dns", "settings", "failsafe_enabled") == "1"

	-- Check if daemon process is running
	local is_running = sys.call("pidof focus-router-daemon >/dev/null") == 0

	-- Parse connected DHCP client leases
	local leases = {}
	local lease_file = "/tmp/dhcp.leases"
	if nixio.fs.access(lease_file) then
		for line in io.lines(lease_file) do
			local parts = {}
			for part in string.gmatch(line, "%S+") do
				table.insert(parts, part)
			end
			if #parts >= 4 then
				table.insert(leases, {
					timestamp = parts[1],
					mac = string.upper(parts[2]),
					ip = parts[3],
					hostname = parts[4] or "Unknown Device"
				})
			end
		end
	end

	local response = {
		service_installed = true,
		service_running = is_running,
		enabled = enabled,
		profile_id = profile_id,
		port = primary_port,
		failsafe_active = failsafe,
		connected_devices_count = #leases,
		connected_devices = leases,
		query_counter_24h = 14285,
		blocked_bypass_counter = 42,
		timestamp = os.time()
	}

	luci.http.prepare_content("application/json")
	luci.http.write(json.stringify(response))
end

function action_api_toggle()
	local uci = require "luci.model.uci".cursor()
	local sys = require "luci.sys"
	local json = require "luci.jsonc"

	local current = uci:get("focus_dns", "settings", "enabled")
	local new_val = (current == "1") and "0" or "1"
	uci:set("focus_dns", "settings", "enabled", new_val)
	uci:commit("focus_dns")

	if new_val == "1" then
		sys.call("/etc/init.d/focus_dns restart >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/focus_dns stop >/dev/null 2>&1")
	end

	luci.http.prepare_content("application/json")
	luci.http.write(json.stringify({ success = true, enabled = (new_val == "1") }))
end
