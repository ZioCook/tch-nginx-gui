--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local proxy = require("datamodel")
local format = string.format

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

ngx.print('\
<span id="bridge-internet-tab">\
  <span data-bind="html: status_light">\
')
ngx.print(ui_helper.createSimpleLight(light_color, light_text, attributes, "fas fa-network-wired"))
ngx.print('\
  </span>\
  <p class="subinfos">\
')

local ip_text = ""
if lan_data.ipaddr ~= "" then
    ip_text = format(T'Device IP: <strong>%s</strong>' .. '<br/>', lan_data.ipaddr)
end
ngx.print('<div data-bind="html: WAN_IP_text">' .. ip_text .. '</div>')

local gw_text = ""
if lan_data.gateway ~= "" then
    gw_text = format(T'Gateway: <strong>%s</strong>' .. '<br/>', lan_data.gateway)
end
ngx.print('<div data-bind="html: WAN_IPv6_text">' .. gw_text .. '</div>')

local dns_text = ""
if dns_val ~= "" then
    dns_text = format(T'DNS: <strong>%s</strong>' .. '<br/>', dns_val)
end
ngx.print('<div data-bind="html: uptime_text">' .. dns_text .. '</div>')

ngx.print('\
  </p>\
</span>\
')
