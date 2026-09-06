--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")

local lan_info = {
    ipaddr = "uci.network.interface.@lan.ipaddr",
    netmask = "uci.network.interface.@lan.netmask",
    gateway = "uci.network.interface.@lan.gateway",
    dns = "uci.network.interface.@lan.dns",
    ifname = "uci.network.interface.@lan.ifname",
}
content_helper.getExactContent(lan_info)

local info_alert = {
    alert = {
        class = "alert alert-info"
    }
}

local html = {}
html[#html + 1] = ui_helper.createAlertBlock(T"Il dispositivo sta funzionando in <strong>Modalità Bridge / Access Point Switch</strong>.<br/>Il modem xDSL è disattivato per ridurre consumo e calore.<br/>Tutte le porte Ethernet operano sul bridge locale (br-lan) e inoltrano il traffico direttamente al router principale.", info_alert)

html[#html + 1] = '<fieldset>'
html[#html + 1] = '<legend>' .. T"Stato Rete Locale / Uplink" .. '</legend>'
html[#html + 1] = ui_helper.createLabel(T"Indirizzo IP Locale:", lan_info.ipaddr)
html[#html + 1] = ui_helper.createLabel(T"Subnet Mask:", lan_info.netmask)
html[#html + 1] = ui_helper.createLabel(T"Gateway Predefinito:", lan_info.gateway ~= "" and lan_info.gateway or T"Non impostato")
html[#html + 1] = ui_helper.createLabel(T"Server DNS:", lan_info.dns ~= "" and lan_info.dns or T"Non impostato")
html[#html + 1] = ui_helper.createLabel(T"Porte Bridge LAN:", lan_info.ifname)
html[#html + 1] = '</fieldset>'

ngx.print(html)
