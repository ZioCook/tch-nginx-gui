--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")
local dyntab_helper = require("web.dyntab_helper")
local untaint_mt = require("web.taint").untaint_mt

local bmh = require("broadbandmode_helper")

local tabdata = dyntab_helper.process(bmh)

-- Process the selected mode if any
local imh = require("internetmode_helper")

local mode_data = {}
local mode_default = "" -- the default mode to use
for _,v in ipairs(imh) do
    mode_data[v.name] = v
    if v.default == true then
        mode_default = v.name
    end
end

mode_data = setmetatable(mode_data, untaint_mt)

local mode_active = "default"
local content_uci = {
    mode_active = "uci.network.config.wan_mode",
	wan_ifname = "uci.network.interface.@wan.ifname",
    wan_proto = "uci.network.interface.@wan.proto",
    wwan_up = "rpc.network.interface.@wwan.up",
}
content_helper.getExactContent(content_uci)
if content_uci.mode_active ~= "" then
    -- Get current mode by 'wan_mode'
    mode_active = content_uci.mode_active
elseif content_uci.wan_proto ~="" then
    --'wan_mode' not there, then get @wan.proto
    mode_active = content_uci.wan_proto
end

local is_bridge = (mode_active == "bridge" or content_uci.wan_proto == "none")

local wan_interface = "wan"
	
if is_bridge then
	wan_interface = content_uci.wan_ifname
end

local content = {
  wan_ppp_state = "rpc.network.interface.@wan.ppp.state",
  wan_ppp_error = "rpc.network.interface.@wan.ppp.error",
  wan_ppp_ll_intf = "rpc.network.interface.@wan.ppp.ll_intf",
  up = "rpc.network.interface.@".. wan_interface ..".up",
  ipaddr = "rpc.network.interface.@wan.ipaddr",
  concentrator_name = "rpc.network.interface.@wan.ppp.access_concentrator_name",
  nexthop = "rpc.network.interface.@wan.nexthop",
  dns_wan = "rpc.network.interface.@wan.dnsservers",
  uptime = "rpc.network.interface.@wan.uptime",
}

local internethelper = require("internethelper")

for v6Key, v6Value in pairs(internethelper.getIpv6Content()) do
	content[v6Key] = v6Value
end

content_helper.getExactContent(content)

local lan_data = {}
local dns_val = ""
if is_bridge then
	lan_data = {
		ipaddr = "uci.network.interface.@lan.ipaddr",
		gateway = "uci.network.interface.@lan.gateway",
		operstate = "sys.class.net.@br-lan.operstate",
	}
	content_helper.getExactContent(lan_data)

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
end

if not ( content["uptime"] == "" ) then
	content["uptime"] = post_helper.secondsToTime(content["uptime"])
end

if content.dns_wan and content.dns_wan:match(",") then
	content.dns_wan = content.dns_wan:gsub(","," , ")
end

  ngx.print('\
\
<div class="infocard" id="wanstatsinfotab">\
  <div class="smallcard">\
    ');  ngx.print( ui_helper.createCardHeader(T"WAN Stats", nil, nil, nil, nil) ); ngx.print('\
    <div class="content card_bg" data-bg-text="&#xf0ac;">\
	<div class="divtable">\
	<form class="form-horizontal">\
	<fieldset>');
	
	local basic = {
      span = {
        class = "span4"
      },
    }
	
	local html = {}
	
	if not is_bridge then
		basic.span["data-bind"] = "text: status"
		html[#html + 1] = ui_helper.createLabel(T"Status", ui_helper.createSimpleLight(content.up, content.up == "1" and T"Connected" or T"Disconnected", nil, "fa fa-at"), basic)
	else
		local is_connected = (lan_data.operstate == "up" and lan_data.gateway ~= "")
		basic.span["data-bind"] = "text: status"
		html[#html + 1] = ui_helper.createLabel(T"Status", ui_helper.createSimpleLight(is_connected and "1" or "4", is_connected and T"Connected" or T"Disconnected", nil, "fas fa-network-wired"), basic)
	end
	basic.span["data-bind"] = nil
	local bb_desc = (tabdata and tabdata.current and tabdata.current.description) or T"Broadband"
	local mode_desc = (mode_data[mode_active] and mode_data[mode_active].description) or (is_bridge and T"Bridge mode" or mode_active)
	html[#html + 1] = ui_helper.createLabel(T"Broadband Connection", bb_desc , basic)
	html[#html + 1] = ui_helper.createLabel(T"Connection Type", mode_desc , basic)
	if not is_bridge then
		basic.span["data-bind"] = "text: WAN_IP"
		html[#html+1] = ui_helper.createLabel(T"IPv4 address", content["ipaddr"], basic)
		basic.span["data-bind"] = "text: WAN_IPv6"
		html[#html+1] = ui_helper.createLabel(T"IPv6 address", content["ip6addr"], basic)
		if mode_active:match("ppp") and content["concentrator_name"] ~= "" then
			basic.span["data-bind"] = "text: concentrator_name"
			html[#html+1] = ui_helper.createLabel(T"Concentrator Name", content["concentrator_name"], basic)
		end
		basic.span["data-bind"] = "text: wangateway"
		html[#html+1] = ui_helper.createLabel(T"Gateway", content["nexthop"], basic)
		basic.span["data-bind"] = "text: wandns"
		html[#html+1] = ui_helper.createLabel(T"DNS servers", content["dns_wan"], basic)
		basic.span["data-bind"] = "text: wan_uptime_extended"
		html[#html + 1] = ui_helper.createLabel(T"Uptime", content["uptime"],  basic)
	else
		basic.span["data-bind"] = "text: WAN_IP"
		html[#html+1] = ui_helper.createLabel(T"Device IP", lan_data["ipaddr"], basic)
		basic.span["data-bind"] = "text: wangateway"
		html[#html+1] = ui_helper.createLabel(T"Gateway", lan_data["gateway"], basic)
		basic.span["data-bind"] = "text: wandns"
		html[#html+1] = ui_helper.createLabel(T"DNS servers", dns_val, basic)
	end
	
	ngx.print(html)
ngx.print('\
	  </fieldset>\
	  </form>\
	  </div>\
    </div>\
  </div>\
</div>\
<script>\
$(document).ready(function () {\
	new modgui.createAjaxUpdateCard("wanstatsinfotab","/ajax/internet.lua","InfoWanStatsCardInterval",5000);\
})\
</script>\
'); 
