--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local format = string.format
local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local proxy = require("datamodel")

local session = ngx.ctx.session
local modalPath
if session:hasAccess("/modals/broadband-modal.lp") then
    modalPath = "/modals/broadband-modal.lp"
end

-- Inspect physical Ethernet ports
local port_names = {
    eth0 = T"LAN 1",
    eth1 = T"LAN 2",
    eth2 = T"LAN 3",
    eth3 = T"LAN 4",
    eth4 = T"WAN / LAN 4",
}

local connected_ports = {}
local any_carrier = false

for port, label in pairs(port_names) do
    local carrier = proxy.get("sys.class.net.@" .. port .. ".carrier")
    if carrier and carrier[1].value == "1" then
        any_carrier = true
        local speed = proxy.get("sys.class.net.@" .. port .. ".speed")
        local speed_val = (speed and speed[1].value ~= "" and speed[1].value ~= "0") and (speed[1].value .. " Mbps") or T"Attivo"
        connected_ports[#connected_ports + 1] = {
            name = label,
            speed = speed_val,
        }
    end
end

local br_operstate = proxy.get("sys.class.net.@br-lan.operstate")
local is_up = (br_operstate and br_operstate[1].value == "up") and any_carrier

local intf_state_map = {
    connected = T"Bridge / AP Attivo",
    disconnected = T"Bridge Disconnesso",
}
local intf_light_map = {
    connected = "1",
    disconnected = "4",
}
local intf_state = is_up and "connected" or "disconnected"

ngx.print(ui_helper.createCardHeader(T"Broadband", modalPath))
ngx.print('\
<div class="content card_bg" data-bg-text="&#xf0b2;">\
  <div class="divtable">\
')
ngx.print(ui_helper.createSimpleLight(intf_light_map[intf_state], intf_state_map[intf_state], nil, "fas fa-network-wired"))

if #connected_ports > 0 then
    for _, p in ipairs(connected_ports) do
        ngx.print(format('<p class="subinfos">&emsp;<i class="fas fa-plug" style="color:#5cb85c;"></i> %s: <strong>%s</strong></p>', p.name, p.speed))
    end
else
    ngx.print('<p class="subinfos">&emsp;<i class="fas fa-exclamation-triangle" style="color:#f0ad4e;"></i> ' .. T"Nessun cavo Ethernet collegato" .. '</p>')
end

ngx.print('<p class="subinfos text-muted" style="margin-top: 6px;"><i class="fas fa-check-circle" style="color:#5cb85c;"></i> ' .. T"Modem xDSL / GPON: Disattivato" .. '</p>')

ngx.print('\
  </div>\
</div>\
')
