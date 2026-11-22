--pretranslated: do not change this file
 
--[[
Version 1.0 DHCP Relay Setup Page

  - Allow direct configuration of DHCP Relay

]]
-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local post_helper = require("web.post_helper")

local uci_pppoerelay_status = "0"

local relay_Params = {
    uci_pppoerelay_laninterface = "uci.network.interface.@lan.pppoerelay.@1.value",
}

local relay_valid = {}

local wan_ifname_data = proxy.get("uci.network.interface.@wan.ifname")
local wan_ifname = (wan_ifname_data and wan_ifname_data[1] and wan_ifname_data[1].value) or ""

if ngx.req.get_method() == "POST" then
  local post_args = ngx.req.get_post_args()
  if post_args and post_args.uci_pppoerelay_status == "1" and wan_ifname ~= "" then
    proxy.set(relay_Params["uci_pppoerelay_laninterface"], wan_ifname)
  else
    proxy.set(relay_Params["uci_pppoerelay_laninterface"], "")
  end
  proxy.apply()
end

local relay_Values = post_helper.handleQuery(relay_Params, relay_valid)
local title = T"Relay Setup"
  ngx.print('\
\
');  ngx.print(ui_helper.createHeader(title, false, false))   ngx.print('\
<div class="modal-body update">\
');
ngx.print(ui_helper.createMessages(message_helper.popMessages()))
  ngx.print('\
<form class="form-horizontal" method="post" action="/modals/relay-modal.lp">');

if wan_ifname ~= "" and wan_ifname == relay_Values["uci_pppoerelay_laninterface"] then
  uci_pppoerelay_status = "1"
end
ngx.print('\
<fieldset>\
  <legend>');  ngx.print( T"PPPoE Relay" ); ngx.print('</legend>\
       ');
        local html = {}
        html[#html + 1] = ui_helper.createSwitch(T"Status", "uci_pppoerelay_status", uci_pppoerelay_status)
        ngx.print(html)

         ngx.print('\
\
</fieldset>\
\
</form>\
</div>\
');  ngx.print(ui_helper.createFooter())   ngx.print('\
');