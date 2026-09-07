local ipairs, string = ipairs, string
local format = string.format
local proxy = require("datamodel")
local frequency = {}
local M = {}

local function getFrequencyBand(v)
  if frequency[v] then
    return frequency[v]
  end
  local path = format("rpc.wireless.radio.@%s.supported_frequency_bands",v)
  local radio = proxy.get(path)[1].value
  frequency[v] = radio
  return radio
end

function M.getSSID()
  local ssid_list = {}
  -- Build a map of iface -> ap_isolation
  local ap_isolation_map = {}
  for _, ap_v in ipairs(proxy.getPN("rpc.wireless.ap.", true)) do
    local iface = proxy.get(ap_v.path .. "ssid")
    local iso = proxy.get(ap_v.path .. "ap_isolation")
    if iface and iface[1] and iso and iso[1] then
      ap_isolation_map[iface[1].value] = iso[1].value
    end
  end

  for _, v in ipairs(proxy.getPN("rpc.wireless.ssid.", true)) do
    local path = v.path
    local iface = path:match("rpc%.wireless%.ssid%.@([^%.]+)%.")
    local values = proxy.get(path .. "radio" , path .. "ssid", path .. "oper_state")
    if values then
      local is_guest = (ap_isolation_map[iface] == "1")
      local oper_state = values[3] and values[3].value or "0"
      -- Skip disabled guest SSIDs from card display
      if not (is_guest and oper_state == "0") then
        local ap_display_name = proxy.get(path .. "ap_display_name")[1].value
        local display_ssid
        if ap_display_name ~= "" then
          display_ssid = ap_display_name
        elseif proxy.get(path .. "stb")[1].value == "1" then
          display_ssid = "IPTV"
        else
          display_ssid = values[2].value
        end
        ssid_list[#ssid_list+1] = {
          radio = getFrequencyBand(values[1].value),
          ssid = display_ssid,
          state = oper_state,
        }
      end
    end
  end
  return ssid_list
end



return M
