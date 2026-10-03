--pretranslated: do not change this file
 
  -- Localization
  gettext.textdomain('webui-core')

  local ngx = ngx
  local ui_helper = require("web.ui_helper")
  local post_helper = require("web.post_helper")
  local speedValidation = post_helper.getValidateInEnumSelect
  local proxy = require("datamodel")
  local message_helper = require("web.uimessage_helper")

  local speedSelect = {
    { "auto", T"Auto" },
    { "100", "100 Mbps" },
    { "10", "10 Mbps" },
  }

  local mapParams = {}
  local mapValid = {}
  local wan_ports = {}
  local lan_ports = {}

  for i = 0, 5 do
    local ethPort = "eth" .. i
    local path = "uci.ethernet.port.@" .. ethPort .. "."
    local speedCheck = proxy.get(path .. "speed")
    if speedCheck and speedCheck[1] and speedCheck[1].value then
      mapParams[ethPort] = path .. "speed"
      mapValid[ethPort] = speedValidation(speedSelect)
      local is_wan = proxy.get(path .. "wan")
      if is_wan and is_wan[1] and is_wan[1].value == "1" then
        wan_ports[#wan_ports + 1] = ethPort
      else
        lan_ports[#lan_ports + 1] = ethPort
      end
    end
  end

  local params, _ = post_helper.handleQuery(mapParams, mapValid)

  if ngx.var.request_method == "POST" then
    os.execute("/etc/init.d/ethernet reload &")
  end

  ngx.print(ui_helper.createHeader(T"ETH Linespeed", false, false))
  ngx.print('\
<form class="modal-body form-horizontal" method="post" action="modals/ethspeed-modal.lp">\
  <div style="margin-bottom: 15px;">\
    <a href="#" class="btn" data-remote="/modals/ethernet-modal.lp"><i class="icon-arrow-left"></i> '); ngx.print(T"Back"); ngx.print('</a>\
  </div>\
  ');  ngx.print(ui_helper.createMessages(message_helper.popMessages()))  ngx.print('\
')

  if #wan_ports > 0 then
    ngx.print('\
  <fieldset>\
    <legend>'); ngx.print(T"ETH-WAN Linespeed"); ngx.print('</legend>\
')
    for _, port in ipairs(wan_ports) do
      ngx.print(ui_helper.createInputSelect(T"WAN port", port, speedSelect, params[port]))
    end
    ngx.print('\
  </fieldset>\
')
  end

  if #lan_ports > 0 then
    ngx.print('\
  <fieldset>\
    <legend>'); ngx.print(T"ETH-LAN Linespeed"); ngx.print('</legend>\
')
    local html = {}
    for i, port in ipairs(lan_ports) do
      html[#html+1] = ui_helper.createInputSelect(T("Port " .. i), port, speedSelect, params[port])
    end
    ngx.print(html)
    ngx.print('\
  </fieldset>\
')
  end

  ngx.print('\
</form>\
');  ngx.print(ui_helper.createFooter())  ngx.print('\
');