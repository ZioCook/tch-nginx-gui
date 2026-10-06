-- Enable localization
gettext.textdomain('webui-core')

local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")
local proxy = require("datamodel")
local json = require("dkjson")
local post_helper = require("web.post_helper")
local ngx = ngx

if ngx.req.get_method() == "POST" then
	datatype = ngx.req.get_uri_args().datatype
end

local data= {}

if datatype and datatype== "xdsl" then
	local sub, format, floor = string.sub, string.format, math.floor

	data = {
		status = "sys.class.xdsl.@line0.LinkStatus",
		dsl_linerate_up_max = "sys.class.xdsl.@line0.UpstreamMaxRate",
		dsl_linerate_down_max = "sys.class.xdsl.@line0.DownstreamMaxRate",
		dsl_linerate_up = "sys.class.xdsl.@line0.UpstreamCurrRate",
		dsl_linerate_down = "sys.class.xdsl.@line0.DownstreamCurrRate",
		dsl_margin_up = "sys.class.xdsl.@line0.UpstreamNoiseMargin",
		dsl_margin_down = "sys.class.xdsl.@line0.DownstreamNoiseMargin",
		dsl_attenuation_up = "sys.class.xdsl.@line0.UpstreamAttenuation",
		dsl_attenuation_down = "sys.class.xdsl.@line0.DownstreamAttenuation",
		dsl_power_up = "sys.class.xdsl.@line0.UpstreamPower",
		dsl_power_down = "sys.class.xdsl.@line0.DownstreamPower",
		dsl_type = "sys.class.xdsl.@line0.ModulationType",
		dsl_margin_SNRM_up = "sys.class.xdsl.@line0.UpstreamSNRMpb",
		dsl_margin_SNRM_down = "sys.class.xdsl.@line0.DownstreamSNRMpb",
		dslam_chipset = "rpc.xdslctl.DslamChipset",
		dslam_version = "rpc.xdslctl.DslamVersion",
		dsl_profile = "rpc.xdslctl.DslProfile",
		dsl_port = "rpc.xdslctl.DslamPort",
		dslam_version_raw = "rpc.xdslctl.DslamVersionRaw",
		dsl_serial = "rpc.xdslctl.DslamSerial",
	}

	content_helper.getExactContent(data)

	local function formatRate(value)
		local rate = tonumber(value)
		if not rate then
			return T"Can't recover data"
		end
		return floor(rate / 10) / 100 .. " Mbps"
	end

	local has_xdsl = data.status and data.status ~= ""
		or tonumber(data.dsl_linerate_up)
		or tonumber(data.dsl_linerate_down)
		or tonumber(data.dsl_linerate_up_max)
		or tonumber(data.dsl_linerate_down_max)

	if not has_xdsl then
		-- This endpoint is also installed on Ethernet/GPON-only devices.
		data = {
			status = T"Disconnected",
			dslam_chipset = "N/A",
		}
	elseif data.dsl_linerate_down ~= "0" then
			data.dsl_linerate_up = formatRate(data.dsl_linerate_up)
			data.dsl_linerate_down = formatRate(data.dsl_linerate_down)
			data.dsl_linerate_up_max = formatRate(data.dsl_linerate_up_max)
			data.dsl_linerate_down_max = formatRate(data.dsl_linerate_down_max)

			if not string.match(data.dsl_type or "", "ADSL") then
				data.dsl_margin_down = data.dsl_margin_SNRM_down
				data.dsl_margin_up = data.dsl_margin_SNRM_up
			end

			if string.match(data.dslam_chipset or "", "BDCM") then
				data.dslam_chipset = "Broadcom" .. " ( " .. data.dslam_chipset .. " )"
			elseif string.match(data.dslam_chipset or "", "IFTN") then
				data.dslam_chipset = "Infineon" .. " ( " .. data.dslam_chipset .. " )"
			end

			data.dslam_version_raw = data.dslam_version_raw or ""
			if not ( string.sub(data.dslam_version_raw, 1, 2) == "0x" ) then
				if data.dslam_version_raw == "" then
					data.dslam_chipset = T"Can't recover DSLAM version."
			else
				data.dslam_chipset = format(T"Invalid version, can't convert. Raw value: %s", data.dslam_version_raw)
			end
		end

		data.dslam_version_raw = nil

			if string.match(data.status or "", "Showtime") then
				data["status"] = T"Connected"
			elseif not data.status or data.status == "" then
				data["status"] = T"Disconnected"
		else
			data["status"] = T(data.status)
		end
	else
		for index in pairs(data) do
			if not ( index == "status" ) then
				data[index] = "N/A"
			end
		end
	end
else
	local ppp_status, ppp_light_map, ppp_state_map

	local table = table
	local format = string.format
	local content_uci = {
		wan_proto = "uci.network.interface.@wan.proto",
		wan_auto = "uci.network.interface.@wan.auto",
		wan_ipv6 = "uci.network.interface.@wan.ipv6",
		wan_ifname = "uci.network.interface.@wan.ifname",
		wan_mode = "uci.network.config.wan_mode",
	}
	content_helper.getExactContent(content_uci)

	if content_uci.wan_mode == "bridge" then
		local lan_data = {
			ipaddr = "uci.network.interface.@lan.ipaddr",
			gateway = "uci.network.interface.@lan.gateway",
			operstate = "sys.class.net.@br-lan.operstate",
		}
		content_helper.getExactContent(lan_data)

		if not lan_data.gateway or lan_data.gateway == "" then
			local rpc_gw = proxy.get("rpc.network.interface.@lan.nexthop")
			if rpc_gw and rpc_gw[1] and rpc_gw[1].value ~= "" then
				lan_data.gateway = rpc_gw[1].value
			end
		end

		if not lan_data.ipaddr or lan_data.ipaddr == "" then
			local rpc_ip = proxy.get("rpc.network.interface.@lan.ipaddr")
			if rpc_ip and rpc_ip[1] and rpc_ip[1].value ~= "" then
				lan_data.ipaddr = rpc_ip[1].value
			end
		end

		local dns_val = ""
		local rpc_dns = proxy.get("rpc.network.interface.@lan.dnsservers")
		if rpc_dns and rpc_dns[1] and rpc_dns[1].value ~= "" then
			dns_val = rpc_dns[1].value
		else
			local uci_dns = proxy.get("uci.network.interface.@lan.dns.@1.value")
			if uci_dns and uci_dns[1] and uci_dns[1].value ~= "" then
				dns_val = uci_dns[1].value
			elseif lan_data.gateway ~= "" then
				dns_val = lan_data.gateway
			end
		end
		if dns_val:match(",") then
			dns_val = dns_val:gsub(",", ", ")
		end

		local lan_up = proxy.get("rpc.network.interface.@lan.up")
		local is_up = (lan_data.operstate == "up") or (lan_up and lan_up[1] and lan_up[1].value == "1")
		local is_connected = is_up and (lan_data.gateway ~= "" or lan_data.ipaddr ~= "")
		local light_color = is_connected and "1" or "4"
		local light_text = is_connected and T"Bridge / Access Point" or T"Bridge Not Configured"
		local attributes = { light = { id = "Internet_State_Led" }, span = { id = "Internet_State_Enabled" } }
		local status_light = ui_helper.createSimpleLight(light_color, light_text, attributes, "fas fa-network-wired")

		local ip_text = ""
		if lan_data.ipaddr ~= "" then
			ip_text = format(T'Device IP: <strong>%s</strong>' .. '<br/>', lan_data.ipaddr)
		end
		local gw_text = ""
		if lan_data.gateway ~= "" then
			gw_text = format(T'Gateway: <strong>%s</strong>' .. '<br/>', lan_data.gateway)
		end
		local dns_text = ""
		if dns_val ~= "" then
			dns_text = format(T'DNS: <strong>%s</strong>' .. '<br/>', dns_val)
		end

		data = {
			status_light = status_light or "",
			WAN_IP_text = ip_text,
			WAN_IPv6_text = gw_text,
			uptime_text = dns_text,
			wan_uptime = "",
			wan_uptime_extended = "",
			ppp_status = "",
			ppp_light = "",
			ppp_state = "",
			WAN_IP = lan_data.ipaddr,
			WAN_IPv6 = "",
			concentrator_name = "",
			ipv6_light = "",
			ipv6_state = "",
			status = is_connected and T"Connected" or T"Disconnected",
			wangateway = lan_data.gateway,
			wandns = dns_val
		}
	else
		local wan_interface = "wan"

		local content_rpc = {
			wan_ppp_state = "rpc.network.interface.@wan.ppp.state",
			wan_ppp_error = "rpc.network.interface.@wan.ppp.error",
			ipaddr = "rpc.network.interface.@wan.ipaddr",
			wan_uptime = "rpc.network.interface.@wan.uptime",
			up = "rpc.network.interface.@".. wan_interface ..".up",
			nexthop = "rpc.network.interface.@wan.nexthop",
			dns_wan = "rpc.network.interface.@wan.dnsservers",
			concentrator_name = "rpc.network.interface.@wan.ppp.access_concentrator_name",
		}

		local internethelper = require("internethelper")

		for v6Key, v6Value in pairs(internethelper.getIpv6Content()) do
			content_rpc[v6Key] = v6Value
		end

		content_helper.getExactContent(content_rpc)

		content_rpc.ipaddr = content_rpc.ipaddr or ""
		content_rpc.ip6addr = content_rpc.ip6addr or ""
		content_rpc.ip6prefix = content_rpc.ip6prefix or ""
		content_rpc.dns_wan = content_rpc.dns_wan or ""
		content_rpc.nexthop = content_rpc.nexthop or ""
		content_rpc.concentrator_name = content_rpc.concentrator_name or ""
		content_rpc.wan_ppp_state = content_rpc.wan_ppp_state or ""
		content_rpc.wan_ppp_error = content_rpc.wan_ppp_error or ""
		content_rpc.wan_uptime = content_rpc.wan_uptime or ""

		if content_rpc.dns_wan:match(",") then
			content_rpc.dns_wan = content_rpc.dns_wan:gsub(","," , ")
		end

		if content_rpc.up == "1" then
			content_rpc.up = T"Connected"
		else
			content_rpc.up = T"Disconnected"
		end

		local IPv6State = "none"

		if content_uci.wan_ipv6 ~= "1" then
			IPv6State = "disabled"
		elseif content_rpc.ip6prefix ~= "" then
			IPv6State = "prefix"
		else
			IPv6State = "noprefix"
		end

		local untaint_mt = require("web.taint").untaint_mt
		local ipv6_state_map = {
			none = T"IPv6 Disabled",
			noprefix = T"IPv6 Connecting",
			prefix = T"IPv6 Connected",
		}

		setmetatable(ipv6_state_map, untaint_mt)

		local ipv6_light_map = {
			none = "off",
			noprefix = "orange",
			prefix = "green",
		}
		setmetatable(ipv6_light_map, untaint_mt)

		local status_light
		local attributes = { light = { } ,span = { } }

		if content_uci.wan_mode == "pppoe" or content_uci.wan_mode == "pppoa" then
			local ppp_state_map = {
				disabled = T"PPP disabled",
				disconnecting = T"PPP disconnecting",
				connected = T"PPP connected",
				connecting = T"PPP connecting",
				disconnected = T"PPP disconnected",
				error = T"PPP error",
				AUTH_TOPEER_FAILED = T"PPP authentication failed",
				NEGOTIATION_FAILED = T"PPP negotiation failed",
			}

			local untaint_mt = require("web.taint").untaint_mt
			setmetatable(ppp_state_map, untaint_mt)

			local ppp_light_map = {
				disabled = "0",--"off"
				disconnected = "4",--"red"
				disconnecting = "2",--"orange"
				connecting = "2",--"orange"
				connected = "1",--"green"
				error = "4",--"red"
				AUTH_TOPEER_FAILED = "4",--"red"
				NEGOTIATION_FAILED = "4",--"red"
			}

			setmetatable(ppp_light_map, untaint_mt)

			local ppp_status
			if content_uci.wan_auto ~= "0" then
			-- WAN enabled
			content_uci.wan_auto = "1"
			ppp_status = format("%s", content_rpc.wan_ppp_state) -- untaint
			if ppp_status == "" or ppp_status == "authenticating" then
				ppp_status = "connecting"
			elseif not ppp_state_map[ppp_status] then
				ppp_status = "error"
			end

			if not (content_rpc.wan_ppp_error == "" or content_rpc.wan_ppp_error == "USER_REQUEST") then
				if ppp_state_map[content_rpc.wan_ppp_error] then
					ppp_status = content_rpc.wan_ppp_error
				else
					ppp_status = "error"
				end
			end
			else
			-- WAN disabled
			ppp_status = "disabled"
			end

			local ppp_light, ppp_state, WAN_IP, ipv6_light, ipv6_state
			if ppp_status then
				ppp_light = ppp_light_map[ppp_status]
				ppp_state = ppp_state_map[ppp_status]
				if content_rpc["ipaddr"] and content_rpc["ipaddr"]:len() > 0 then
					WAN_IP = content_rpc["ipaddr"]
				elseif content_rpc["ip6addr"] and content_rpc["ip6addr"]:len() > 0 then
					WAN_IP = content_rpc["ip6addr"]
				end
				if ppp_status == "connected" and IPv6State ~= "disabled" then
					ipv6_light = ipv6_light_map[IPv6State]
					ipv6_state = ipv6_state_map[IPv6State]
				end
			end

			status_light = ui_helper.createSimpleLight(ppp_light_map[ppp_status], ppp_state_map[ppp_status] , attributes , "fa-at")
		elseif content_uci.wan_mode == "static" then

			-- Figure out interface state
			local static_state = "disabled"
			local static_state_map = {
				disabled = T"Static disabled",
				connected = T"Static on",
			}

			local static_light_map = {
			disabled = "0",--"off",
			connected = "1",--"green",
			}

			if content_uci.wan_auto ~= "0" and content_rpc["ipaddr"]:len() > 0 then
				static_state = "connected"
			end

			status_light = ui_helper.createSimpleLight(static_light_map[static_state], static_state_map[static_state] , attributes , "fa-at")
		else
			-- DHCP routed mode or default
			local dhcp_state = "connecting"
			local dhcp_state_map = {
				disabled = T"DHCP disabled",
				connected = T"DHCP on",
				connecting = T"DHCP connecting",
			}

			local dhcp_light_map = {
				disabled = "0",
				connecting = "2",
				connected = "1",
			}

			if content_uci.wan_auto ~= "0" then
				if content_rpc["ipaddr"] and content_rpc["ipaddr"]:len() > 0 then
					dhcp_state = "connected"
				else
					dhcp_state = "connecting"
				end
			else
				dhcp_state = "disabled"
			end

			attributes.light.id = "Internet_DHCP_LED"
			attributes.span.id = "Internet_DHCP_Status"
			status_light = ui_helper.createSimpleLight(dhcp_light_map[dhcp_state], dhcp_state_map[dhcp_state], attributes, "fa-at")
		end

		local wan_uptime = content_rpc["wan_uptime"]
		local wan_uptime_time = post_helper.secondsToTimeShort(wan_uptime)

		data = {
			status_light = status_light or "",
			WAN_IP_text = (content_rpc.ipaddr and content_rpc.ipaddr ~= "") and format(T'WAN IP is <strong>%s</strong>'..'<br/>', content_rpc.ipaddr) or "",
			WAN_IPv6_text = (content_rpc.ip6addr and content_rpc.ip6addr ~= "") and format(T'WAN IPv6 is <strong>%s</strong>'..'<br/>', content_rpc.ip6addr) or "",
			uptime_text = (wan_uptime_time and wan_uptime_time ~= "") and format(T"Uptime" .. ": <strong>%s</strong>", wan_uptime_time) or "",
			wan_uptime = wan_uptime_time or "",
			wan_uptime_extended = post_helper.secondsToTime(wan_uptime) or "",
			ppp_status = ppp_status or "",
			ppp_light = ppp_light or "",
			ppp_state = ppp_state or "",
			WAN_IP = content_rpc.ipaddr or "",
			WAN_IPv6 = content_rpc.ip6addr or "",
			concentrator_name = content_rpc.concentrator_name or "",
			ipv6_light = ipv6_light or "",
			ipv6_state = ipv6_state or "",
			status = content_rpc.up,
			wangateway = content_rpc.nexthop or "",
			wandns = content_rpc.dns_wan or ""
		}
	end
end


local buffer = {}
if json.encode (data, { indent = false, buffer = buffer }) then
 ngx.say(buffer)
else
 ngx.say("{}")
end
ngx.exit(ngx.HTTP_OK)
