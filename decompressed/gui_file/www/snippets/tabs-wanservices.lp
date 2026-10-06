--pretranslated: do not change this file

gettext.textdomain('webui-core')

local items = {
    {"wanservices-modal.lp", T"Port Forward"},
    {"upnp-modal.lp", T"UPnP"},
    {"wol-modal.lp", T"WoL / WoW"},
	{"customdns-modal.lp", T"Custom DNS"},
	{"dyndns-modal.lp", T"DDNS"},
	{"dmz-modal.lp", T"DMZ"},
}

local proxy = require("datamodel")
local mabr_check = proxy.get("rpc.X_TELECOMITALIA_IT_MABRAgent.Status")
if mabr_check and mabr_check[1] then
    table.insert(items, {"mabr-agentinfo-modal.lp", T"M-ABR"})
end

require("sharedModalTabHelper").createModalTab(items)