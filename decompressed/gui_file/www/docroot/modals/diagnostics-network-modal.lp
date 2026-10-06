--pretranslated: do not change this file
 
-- Localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local ipairs = ipairs
local match, format, lower = string.match, string.format, string.lower

local function getValue(path)
  local result = proxy.get(path)
  return result and result[1] and result[1].value or ""
end

local function hasPath(path)
  local result = proxy.get(path)
  return result and result[1] ~= nil
end

local ports = {"eth0", "eth1", "eth2", "eth3"}
local first_column_txt = {T"Port 1", T"Port 2", T"Port 3", T"Port 4"}

-- resetting traffic counters button
local clear_network_stats = {
  controls = {
    class = "clear_network_stats"
  },
  button = {
    ["data-name"] = "stats_reset",
    ["data-value"] = "RESET"
  }
}

local isEth4Included = false
local sfp_enabled = getValue("uci.env.rip.sfp") == "1"
local has_gpon = hasPath("rpc.optical.Interface.1.Status") or hasPath("rpc.gpon.ploam.state")
if not sfp_enabled then
  local eth4 = proxy.getPN("sys.class.net.@eth4.", true)
  if eth4 and next(eth4) then
    ports[#ports+1] = "eth4"
    first_column_txt[#first_column_txt+1] = T"Port 5"
    isEth4Included = true
  end
end
if sfp_enabled or has_gpon then
  ports[#ports+1] = "gpon"
  first_column_txt[#first_column_txt+1] = T"SFP"
end
local eth = {}
for k,v in ipairs(ports) do
  if v == "gpon" then
    local base_path = "rpc.optical.Interface.1."
    eth["op" .. v] = base_path .. "Status"
    eth["sp" .. v] = base_path .. "OpticalSignalLevel"
  else
    local base_path = "sys.class.net.@" .. v
    eth["op" .. v] = base_path .. ".operstate"
    eth["sp" .. v] = base_path .. ".speed"
  end
end
content_helper.getExactContent(eth)

local ports_speed = {}
local speed = proxy.get("sys.eth.port.") or {}
for _,f in ipairs(speed) do
  if f["param"] == "speed" and f["value"] ~= "" and f["value"] ~= "0" then
    ports_speed[match(f["path"], "sys.eth.port.@(eth%d)")] = f["value"]
  end
end
if not ports_speed["gpon"] and ports_speed["eth4"] then
  ports_speed["gpon"] = ports_speed["eth4"]
end

local function isSfpConnected()
  local op = lower(eth["opgpon"] or "")
  if op == "up" or op == "present" then
    return true
  end
  local link = lower(getValue("rpc.optical.link.SfpLinkStatus"))
  if link == "up" then
    return true
  end
  local eth4_op = lower(getValue("sys.class.net.@eth4.operstate"))
  if eth4_op == "up" then
    return true
  end
  return false
end

local portAttr = {
  socket = {
    class = "socket-form"
  }
}
  ngx.print('\
');  ngx.print(ui_helper.createHeader(T"Diagnostics", false, false, 2) ); ngx.print('\
<div class="modal-body update">\
');  
  local lp = require("web.lp")
  lp.setpath("/www/snippets/")
  lp.include("tabs-diagnostics.lp")
  ngx.print('\
');  
-- dummy form so that refresh button knows which page to reload, keep it
  ngx.print('\
  <form class="form-horizontal" method="post" action="modals/diagnostics-network-modal.lp">\
  </form>\
  <style>\
    .sfp-slot {\
      width: 50px;\
      height: 45px;\
      margin: 5px auto;\
      position: relative;\
      display: flex;\
      align-items: center;\
      justify-content: center;\
      cursor: pointer;\
      border-radius: 3px;\
      transition: all .3s;\
    }\
    .sfp-slot:hover {\
      transform: scale(1.08);\
    }\
    .sfp-slot .sfp-img {\
      max-width: 44px;\
      max-height: 38px;\
      display: block;\
      margin: 0 auto;\
      object-fit: contain;\
      transition: all .3s;\
    }\
    .sfp-slot.connected .sfp-img {\
      filter: drop-shadow(0 0 4px rgba(105, 196, 105, 0.85));\
    }\
    .sfp-slot.disconnected .sfp-img {\
      opacity: 0.45;\
      filter: grayscale(70%);\
    }\
    .sfp-slot .socket-light {\
      position: absolute;\
      width: 10px;\
      height: 5px;\
      bottom: 0;\
    }\
    .sfp-slot .socket-light.align-left {\
      left: 2px;\
    }\
    .sfp-slot .socket-light.align-right {\
      right: 2px;\
    }\
    .sfp-slot .socket-light.off {\
      background-color: #999;\
      border: 1px solid #737373;\
    }\
    .sfp-slot .socket-light.green {\
      background-color: #69c469;\
      border: 1px solid #3fa13f;\
      box-shadow: 0 0 4px rgba(0, 220, 0, 1);\
    }\
  </style>\
  <fieldset id="diagnostics-network-tab">\
	<fieldset>\
	<legend>');  ngx.print( T"Ports State" ); ngx.print('</legend>\
	<div class="control-group">\
      <div class="controls">\
      ');  for k, v in ipairs(ports) do  ngx.print('\
        <div class="span2 simple-desc">\
        ');  
          if v == "gpon" then
            local is_up = isSfpConnected()
            local sfp_class = is_up and "connected" or "disconnected"
            ngx.print('\
            <div class="sfp-slot socket-form ' .. sfp_class .. '" id="sfp" title="SFP">\
              <picture>\
                <source srcset="/img/SFP_new.webp" type="image/webp">\
                <img src="/img/SFP_new.png" alt="SFP" class="sfp-img">\
              </picture>\
              <div class="socket-light off align-right" style="opacity:.5;"></div>\
              <div class="socket-light off align-left" style="opacity:.5;"></div>\
            ')
            if is_up then
              ngx.print('<div class="socket-light green align-right"></div>')
              if ports_speed[v] and ports_speed[v] ~= "0" and ports_speed[v] ~= "" then
                ngx.print('<div class="socket-light green align-left"></div>')
              end
            end
            ngx.print('</div>')
            if is_up then
              ngx.print('<p class="socket-legend" id="' .. v .. '">' .. T"Connected-SFP" .. '</p>')
              if ports_speed[v] and ports_speed[v] ~= "0" and ports_speed[v] ~= "" then
                ngx.print('<p class="socket-legend">(' .. format(T"%s Mbps", ports_speed[v]) .. ')</p>')
              end
            else
              ngx.print('<p class="socket-legend grayLight" id="' .. v .. '">' .. T"Not connected" .. '</p>')
            end
          else
            if isEth4Included and match(v, "eth") and getValue("uci.ethernet.port.@"..v..".wan") == "1" then
              portAttr.socket.class = "red socket-form"
            else
              portAttr.socket.class = "yellow socket-form"
            end
            ngx.print(ui_helper.createSwitchPort(tostring(k), lower(eth["op" .. v] or ""), eth["sp" .. v], portAttr))
            if eth["op" .. v] == "up" then
              ngx.print('<p class="socket-legend" id="' .. v .. '">' .. T"Connected" .. '</p>')
              if ports_speed[v] then
                ngx.print('<p class="socket-legend">(' .. format(T"%s Mbps", ports_speed[v]) .. ')</p>')
              end
            else
              ngx.print('<p class="socket-legend grayLight" id="' .. v .. '">' .. T"Not connected" .. '</p>')
            end
          end
          ngx.print('\
        </div>\
      ');  end  ngx.print('\
      </div>\
    </div>\
	</fieldset>\
	<fieldset>\
    <legend class="networkStat">');  ngx.print( T"Network Statistics" ); ngx.print('</legend>\
    ');  
      local wireless = proxy.get("rpc.wireless.ssid.") or {}
      local wirelessindex = content_helper.convertResultToObject("rpc.wireless.ssid.@.",wireless) or {}
      for _,v in ipairs(wirelessindex) do
        ports[#ports+1] = v.paramindex
		local band = v.radio and getValue("rpc.wireless.radio.@" .. v.radio .. ".supported_frequency_bands") or ""
		local band_label = band ~= "" and ("(" .. band .. ")") or ""
		first_column_txt[#first_column_txt+1] = (v.ssid or v.paramindex) .. band_label
      end

local post_content
if ngx.var.request_method == "POST" then
  post_content = ngx.req.get_post_args()
  local base_path
  if post_content["stats_reset"] == "RESET" then
    for _,v in ipairs(ports) do
      if string.match(v, "wl") then
        base_path = "rpc.wireless.ssid.@"..v..".stats.reset"
      elseif match(v, "gpon") then
        base_path = "rpc.optical.Interface.1.Stats.reset"
        if proxy.getPN("sys.class.net.@eth4.", true) then
          proxy.set("sys.class.net.@eth4.statistics.reset", "1")
        end
      else
        base_path = "sys.class.net.@"..v..".statistics.reset"
      end
      proxy.set(base_path, "true")
    end
    proxy.apply()
  end
  local action = ngx.req.get_post_args().action
  local success = false
  for i,v in ipairs(ports) do
    if action == v and string.match(v,"eth") then
      success = proxy.set("sys.class.net.@"..v..".statistics.reset", "1")
    elseif action == v and string.match(v,"wl") then
      success = proxy.set("rpc.wireless.ssid.@"..v..".stats.reset", "1")
    elseif action == v and string.match(v,"gpon") then
      success = proxy.set("rpc.optical.Interface.1.Stats.reset", "1")
      if proxy.getPN("sys.class.net.@eth4.", true) then
        proxy.set("sys.class.net.@eth4.statistics.reset", "1")
      end
    elseif action == "resetall" then
      for x,y in ipairs(ports) do
        if string.match(y, "wl") then
          proxy.set("rpc.wireless.ssid.@"..y..".stats.reset", "1")
        elseif match(y, "eth") then
          proxy.set("sys.class.net.@"..y..".statistics.reset", "1")
        elseif match(y, "gpon") then
          proxy.set("rpc.optical.Interface.1.Stats.reset", "1")
          if proxy.getPN("sys.class.net.@eth4.", true) then
            proxy.set("sys.class.net.@eth4.statistics.reset", "1")
          end
        end
      end
      success = true
    end
    if success then
      proxy.apply();
    end
  end
end

local base_path
local param = {"rx_bytes", "rx_bytes", "tx_bytes", "rx_packets", "tx_packets", "rx_errors", "tx_errors"}
local gpon_param = {"BytesReceived", "BytesReceived", "BytesSent", "PacketsReceived", "PacketsSent", "ErrorsReceived", "ErrorsSent"}
local datarows ={}
for k,v in ipairs(ports) do
  datarows[k]={}
  if string.match(v, "wl") then
    base_path = "rpc.wireless.ssid.@" .. v ..".stats."
  elseif match(v, "gpon") then
    base_path = "rpc.optical.Interface.1.Stats."
  else
    base_path = "sys.class.net.@" .. v .. ".statistics."
  end
  if match(v, "gpon") then
    for kk,vv in ipairs(gpon_param) do
      datarows[k][kk] = base_path .. vv
    end
  else
    for kk,vv in ipairs(param) do
      datarows[k][kk] = base_path .. vv
    end
  end
  content_helper.getExactContent(datarows[k])
  if match(v, "gpon") then
    local rx = tonumber(datarows[k][2]) or 0
    local tx = tonumber(datarows[k][3]) or 0
    if rx == 0 and tx == 0 and proxy.getPN("sys.class.net.@eth4.", true) then
      local eth4_stats = {}
      for kk,vv in ipairs(param) do
        eth4_stats[kk] = "sys.class.net.@eth4.statistics." .. vv
      end
      content_helper.getExactContent(eth4_stats)
      local e4_rx = tonumber(eth4_stats[2]) or 0
      local e4_tx = tonumber(eth4_stats[3]) or 0
      if e4_rx > 0 or e4_tx > 0 then
        for kk = 2, 7 do
          datarows[k][kk] = eth4_stats[kk]
        end
      end
    end
  end
  datarows[k][8] = ui_helper.createSimpleButton(T"Reset Stats", nil, {controls = {class = string.format("clear_network_stats_%s",v)}, button = {["data-name"] = "action", ["data-value"] = string.format("%s",v),}})
end

  --re-write the first column
  for k,v in ipairs(first_column_txt) do
    if datarows[k] then
      datarows[k][1] = v
    end
  end

  --Column Names
  local columns ={}
  for i=1, 8 do
    columns[i]={}
  end
  columns[1]["header"] = T"Interface"
  columns[2]["header"] = T"Rx Bytes"
  columns[3]["header"] = T"Tx Bytes"
  columns[4]["header"] = T"Rx Packets"
  columns[5]["header"] = T"Tx Packets"
  columns[6]["header"] = T"Rx Errors"
  columns[7]["header"] = T"Tx Errors"
  columns[8]["header"] = T"Reset"
  local options = { tableid = "networkstats", canEdit = false, canAdd = false, canDelete = false }
  -- table that shows the Statistics data
  ngx.print(ui_helper.createTable(columns, datarows, options))
    ngx.print('\
  <center>\
    ');  ngx.print( ui_helper.createSimpleButton(T"Reset Stats", "icon-bolt", clear_network_stats)); ngx.print('\
  </center>\
  </fieldset>\
  </fieldset>\
</div>\
');  ngx.print(ui_helper.createFooter() ); ngx.print('\
');
