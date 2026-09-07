--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local proxy = require("datamodel")
local format = string.format
require("web.taint")
local untaint = string.untaint or function(x) return x end

local lan_info = {
    ipaddr = "uci.network.interface.@lan.ipaddr",
    netmask = "uci.network.interface.@lan.netmask",
    gateway = "uci.network.interface.@lan.gateway",
    ifname = "uci.network.interface.@lan.ifname",
}
content_helper.getExactContent(lan_info)

local dns_val = ""
local rpc_dns = proxy.get("rpc.network.interface.@lan.dnsservers")
if rpc_dns and rpc_dns[1] and rpc_dns[1].value ~= "" then
    dns_val = rpc_dns[1].value
else
    local uci_dns = proxy.get("uci.network.interface.@lan.dns.@1.value")
    if uci_dns and uci_dns[1] and uci_dns[1].value ~= "" then
        dns_val = uci_dns[1].value
    elseif lan_info.gateway ~= "" then
        dns_val = lan_info.gateway
    end
end
if dns_val:match(",") then
    dns_val = dns_val:gsub(",", ", ")
end

local info_alert = {
    alert = {
        class = "alert alert-success"
    }
}

local html = {}
html[#html + 1] = ui_helper.createAlertBlock(T"Il modem router sta operando in <strong>Modalità Bridge / Access Point Switch</strong>.<br/>" ..
    T"I moduli interni xDSL e GPON SFP sono stati spenti per risparmiare energia ed azzerare il calore.<br/>" ..
    T"Tutte le porte Ethernet e la rete Wi-Fi sono collegate direttamente al bridge di rete (br-lan).", info_alert)

html[#html + 1] = '<fieldset>'
html[#html + 1] = '<legend>' .. T"Stato Porte Ethernet (Switch)" .. '</legend>'

local port_map = {
    { id = "eth0", name = "Porta LAN 1" },
    { id = "eth1", name = "Porta LAN 2" },
    { id = "eth2", name = "Porta LAN 3" },
    { id = "eth3", name = "Porta LAN 4" },
    { id = "eth4", name = "Porta WAN / LAN 4" },
}

for _, p in ipairs(port_map) do
    local carrier = proxy.get("sys.class.net.@" .. p.id .. ".carrier")
    local status_str = "Disconnesso"
    local status_color = "default"
    if carrier and carrier[1].value == "1" then
        local speed = proxy.get("sys.class.net.@" .. p.id .. ".speed")
        local speed_val = (speed and speed[1].value ~= "" and speed[1].value ~= "0") and (speed[1].value .. " Mbps") or "Collegato"
        status_str = format("Collegato (%s)", speed_val)
        status_color = "success"
    end
    html[#html + 1] = ui_helper.createLabel(T(p.name), format('<span class="label label-%s">%s</span>', status_color, status_str))
end

html[#html + 1] = '</fieldset>'

html[#html + 1] = '<fieldset>'
html[#html + 1] = '<legend>' .. T"Parametri Rete Locale (AP)" .. '</legend>'
html[#html + 1] = ui_helper.createLabel(T"Indirizzo IP Router/AP:", untaint(lan_info.ipaddr))
html[#html + 1] = ui_helper.createLabel(T"Subnet Mask:", untaint(lan_info.netmask))
html[#html + 1] = ui_helper.createLabel(T"Gateway Predefinito:", (lan_info.gateway ~= "" and lan_info.gateway ~= nil) and untaint(lan_info.gateway) or "-")
html[#html + 1] = ui_helper.createLabel(T"Server DNS:", (dns_val ~= "" and dns_val ~= nil) and untaint(dns_val) or "-")
html[#html + 1] = ui_helper.createLabel(T"IGMP Snooping (IPTV):", "Attivo sul bridge locale")
html[#html + 1] = ui_helper.createLabel(T"Server DHCP Locale:", "Disattivato (gestito dal router principale)")
html[#html + 1] = '</fieldset>'

ngx.print(html)
