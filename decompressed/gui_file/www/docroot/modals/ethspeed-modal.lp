--pretranslated: do not change this file
 
  -- Localization
  gettext.textdomain('webui-core')

  local ngx = ngx
  local ui_helper = require("web.ui_helper")
  local post_helper = require("web.post_helper")
  local speedValidation = post_helper.getValidateInEnumSelect
  local proxy = require("datamodel")
  local message_helper = require("web.uimessage_helper")
  local match = string.match
  local format = string.format

  local speedSelect = {
    { "auto", T"Auto" },
    { "100", "100 Mbps" },
    { "10", "10 Mbps" },
  }

  -- Board & Port detection
  local sfp_presence = proxy.get("uci.env.rip.sfp")
  local has_sfp = sfp_presence and (sfp_presence[1].value == "1")

  local eth4lanwanmode = proxy.get("uci.ethernet.globals.eth4lanwanmode")
  local is_wan_as_lan = eth4lanwanmode and eth4lanwanmode[1] and (eth4lanwanmode[1].value == "1")

  -- Real-time port link status from sys.eth.port.
  local port_status = proxy.get("sys.eth.port.") or {}
  local real_status = {}
  local real_speed = {}
  for _, v in ipairs(port_status) do
    local p = match(v.path, "sys.eth.port.@(eth%d)")
    if p then
      if v.param == "status" then real_status[p] = v.value end
      if v.param == "speed" then real_speed[p] = v.value end
    end
  end

  local function get_status_badge(port)
    local status = real_status[port]
    local speed = real_speed[port]
    if status == "up" then
      local speed_label = (speed and speed ~= "0" and speed ~= "") and (speed .. " Mbps") or T"Connected"
      return format('<span class="label label-success" style="margin-left: 10px; vertical-align: middle; padding: 3px 8px; border-radius: 3px; font-size: 11px; background-color: #468847; color: white;"><i class="icon-ok-sign"></i> %s</span>', speed_label)
    else
      return format('<span class="label" style="margin-left: 10px; vertical-align: middle; padding: 3px 8px; border-radius: 3px; font-size: 11px; background-color: #999; color: white;"><i class="icon-minus-sign"></i> %s</span>', T"Not Connected")
    end
  end

  -- Build mapParams, mapValid, and port lists for WAN and LAN
  local mapParams = {}
  local mapValid = {}
  local wan_list = {}
  local lan_list = {}

  if has_sfp then
    -- DGA4331 / DGA4132: 4 physical RJ45 ports + SFP
    -- eth0 = Porta 1, eth1 = Porta 2, eth2 = Porta 3
    for i = 0, 2 do
      local p = "eth" .. i
      if proxy.get("uci.ethernet.port.@" .. p .. ".speed") then
        mapParams[p] = "uci.ethernet.port.@" .. p .. ".speed"
        mapValid[p] = speedValidation(speedSelect)
        lan_list[#lan_list + 1] = { port = p, label = T("Port " .. (i + 1)), status_port = p }
      end
    end

    if is_wan_as_lan then
      -- Port 4 operating in LAN mode (eth3)
      if proxy.get("uci.ethernet.port.@eth3.speed") then
        mapParams["eth3"] = "uci.ethernet.port.@eth3.speed"
        mapValid["eth3"] = speedValidation(speedSelect)
        lan_list[#lan_list + 1] = { port = "eth3", label = T"Port 4", status_port = "eth3", sync_port = "eth4" }
      end
    else
      -- Port 4 operating in WAN mode (eth4)
      if proxy.get("uci.ethernet.port.@eth4.speed") then
        mapParams["eth4"] = "uci.ethernet.port.@eth4.speed"
        mapValid["eth4"] = speedValidation(speedSelect)
        wan_list[#wan_list + 1] = { port = "eth4", label = format("%s (WAN)", T"Port 4"), status_port = "eth4", sync_port = "eth3" }
      end
    end
  else
    -- Generic / 5-port boards (e.g. TG789vac v2 with dedicated WAN and 4 LAN ports)
    local eth4_wan = proxy.get("uci.ethernet.port.@eth4.wan")
    if eth4_wan and eth4_wan[1] and eth4_wan[1].value == "1" then
      mapParams["eth4"] = "uci.ethernet.port.@eth4.speed"
      mapValid["eth4"] = speedValidation(speedSelect)
      wan_list[#wan_list + 1] = { port = "eth4", label = T"WAN port", status_port = "eth4" }
    end
    for i = 0, 3 do
      local p = "eth" .. i
      if proxy.get("uci.ethernet.port.@" .. p .. ".speed") then
        mapParams[p] = "uci.ethernet.port.@" .. p .. ".speed"
        mapValid[p] = speedValidation(speedSelect)
        lan_list[#lan_list + 1] = { port = p, label = T("Port " .. (i + 1)), status_port = p }
      end
    end
  end

  local params, _ = post_helper.handleQuery(mapParams, mapValid)

  if ngx.var.request_method == "POST" then
    for _, item in ipairs(wan_list) do
      if item.sync_port and params[item.port] then
        proxy.set("uci.ethernet.port.@" .. item.sync_port .. ".speed", params[item.port])
      end
    end
    for _, item in ipairs(lan_list) do
      if item.sync_port and params[item.port] then
        proxy.set("uci.ethernet.port.@" .. item.sync_port .. ".speed", params[item.port])
      end
    end
    proxy.apply()
    os.execute("/etc/init.d/ethernet reload &")
  end

  ngx.print(ui_helper.createHeader(T"ETH Linespeed", false, false))
  ngx.print('\
<form class="modal-body form-horizontal" method="post" action="modals/ethspeed-modal.lp">\
  <div style="margin-bottom: 15px;">\
    <a href="#" class="btn" data-toggle="modal" data-remote="/modals/ethernet-modal.lp"><i class="icon-arrow-left"></i> '); ngx.print(T"Back"); ngx.print('</a>\
  </div>\
  ');  ngx.print(ui_helper.createMessages(message_helper.popMessages()))  ngx.print('\
')

  if #wan_list > 0 then
    ngx.print('\
  <fieldset>\
    <legend>'); ngx.print(T"ETH-WAN Linespeed"); ngx.print('</legend>\
')
    for _, item in ipairs(wan_list) do
      local row = ui_helper.createInputSelect(item.label, item.port, speedSelect, params[item.port], { select = { class = "span3" } })
      table.insert(row, #row, get_status_badge(item.status_port))
      ngx.print(row)
    end
    ngx.print('\
  </fieldset>\
')
  end

  if #lan_list > 0 then
    ngx.print('\
  <fieldset>\
    <legend>'); ngx.print(T"ETH-LAN Linespeed"); ngx.print('</legend>\
')
    for _, item in ipairs(lan_list) do
      local row = ui_helper.createInputSelect(item.label, item.port, speedSelect, params[item.port], { select = { class = "span3" } })
      table.insert(row, #row, get_status_badge(item.status_port))
      ngx.print(row)
    end
    ngx.print('\
  </fieldset>\
')
  end

  ngx.print('\
</form>\
');  ngx.print(ui_helper.createFooter())  ngx.print('\
');