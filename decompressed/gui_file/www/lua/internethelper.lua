local proxy = require("datamodel")

local content_helper = require("web.content_helper")

local M = {}

local function notEmpty(path)
	local res = proxy.get(path)
	if res and res[1] and res[1].value and res[1].value ~= "" then
		return true
	end
	return false
end

function M.syncWanDns(peerdns)
	local v6_intfs = {"wan6", "wan_6", "6rd"}
	for _, intf in ipairs(v6_intfs) do
		local base = "uci.network.interface.@" .. intf .. "."
		if proxy.get(base) then
			if peerdns ~= nil and peerdns ~= "" then
				proxy.set(base .. "peerdns", peerdns)
			end
			local cur_dns = proxy.get(base .. "dns.")
			if cur_dns then
				for _, v in ipairs(cur_dns) do
					if v.path then
						proxy.del(v.path)
					end
				end
			end
			local wan_dns = proxy.get("uci.network.interface.@wan.dns.")
			if wan_dns then
				local addpath, indexpath = content_helper.getPaths(base .. "dns.@.")
				for _, v in ipairs(wan_dns) do
					if v.param == "value" and v.value and v.value ~= "" then
						local new_idx = proxy.add(addpath)
						if new_idx then
							proxy.set(indexpath .. new_idx .. ".value", v.value)
						end
					end
				end
			end
		end
	end
	proxy.apply()
end

function M.getIpv6Content()

	local content = {
		ip6addr = "",
		ip6prefix = "rpc.network.interface.@wan.ip6prefix",
	}

	for i,v in ipairs(proxy.getPN("rpc.network.interface.", true)) do
		local intf = string.match(v.path, "rpc%.network%.interface%.@([^%.]+)%.")
		if intf then
			if intf == "6rd" then
				content.ip6addr = "rpc.network.interface.@6rd.ip6addr"
				if notEmpty(content.ip6addr) then
					content.ip6prefix = "rpc.network.interface.@6rd.ip6prefix"
					content.dnsv6 = "rpc.network.interface.@6rd.dnsservers"
					break
				end
			elseif intf == "wan_6" then
				content.ip6addr = "rpc.network.interface.@wan_6.ip6addr"
				if notEmpty(content.ip6addr) then
					content.ip6prefix = "rpc.network.interface.@wan_6.ip6prefix"
					content.dnsv6 = "rpc.network.interface.@wan_6.dnsservers"
					break
				end
			elseif intf == "wan6" then
				content.ip6addr = "rpc.network.interface.@wan6.ip6addr"
				if notEmpty(content.ip6addr) then
					content.ip6prefix = "rpc.network.interface.@wan6.ip6prefix"
					content.dnsv6 = "rpc.network.interface.@wan6.dnsservers"
					break
				end
			elseif intf == "wan" then
				content.ip6addr = "rpc.network.interface.@wan.ip6addr"
				if notEmpty(content.ip6addr) then
					content.ip6prefix = "rpc.network.interface.@wan.ip6prefix"
					break
				end
			end
		end
	end
	
	return content
end

return M