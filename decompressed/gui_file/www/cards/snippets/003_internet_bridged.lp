--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local format = string.format

local lan_data = {
    ipaddr = "uci.network.interface.@lan.ipaddr",
    gateway = "uci.network.interface.@lan.gateway",
    dns = "uci.network.interface.@lan.dns",
    operstate = "sys.class.net.@br-lan.operstate",
}
content_helper.getExactContent(lan_data)

local is_connected = (lan_data.operstate == "up" and lan_data.gateway ~= "")
local light_color = is_connected and "1" or "4"
local light_text = is_connected and T"Bridge / Access Point" or T"Bridge Non Configurato"

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
    ip_text = format(T'IP Dispositivo: <strong>%s</strong>' .. '<br/>', lan_data.ipaddr)
end
ngx.print('<div data-bind="html: WAN_IP_text">' .. ip_text .. '</div>')

local gw_text = ""
if lan_data.gateway ~= "" then
    gw_text = format(T'Gateway: <strong>%s</strong>' .. '<br/>', lan_data.gateway)
end
ngx.print('<div data-bind="html: WAN_IPv6_text">' .. gw_text .. '</div>')

local dns_text = ""
if lan_data.dns ~= "" then
    dns_text = format(T'DNS: <strong>%s</strong>' .. '<br/>', lan_data.dns)
end
ngx.print('<div data-bind="html: uptime_text">' .. dns_text .. '</div>')

ngx.print('\
  </p>\
</span>\
')
