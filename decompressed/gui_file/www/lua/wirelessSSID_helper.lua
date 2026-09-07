local ipairs, string = ipairs, string
local format = string.format
local proxy = require("datamodel")
local untaint = string.untaint or function(x) return x end
local frequency = {}
local M = {}

local function get_untainted(path)
  local res = proxy.get(path)
  if res and res[1] and res[1].value ~= nil then
    return untaint(res[1].value)
  end
  return nil
end

local function getFrequencyBand(v)
  v = untaint(v)
  if frequency[v] then
    return frequency[v]
  end
  local path = format("rpc.wireless.radio.@%s.supported_frequency_bands", v)
  local radio = get_untainted(path) or ""
  frequency[v] = radio
  return radio
end

-- Checks whether a given interface is a guest SSID
local function isGuestInterface(iface)
  iface = untaint(iface)
  if iface == "wl0_1" or iface == "wl1_1" then
    return true
  end
  -- Check ap_isolation from ap2/ap3/ap0/ap1
  for _, ap in ipairs({"ap2", "ap3", "ap0", "ap1"}) do
    local ap_iface = get_untainted("uci.wireless.wifi-ap.@" .. ap .. ".iface")
    if ap_iface == iface then
      local iso = get_untainted("uci.wireless.wifi-ap.@" .. ap .. ".ap_isolation")
      if iso == "1" then
        return true
      end
    end
  end
  -- Check network name
  local net = get_untainted("uci.wireless.wifi-iface.@" .. iface .. ".network")
  if net and (net:find("guest") or net:find("wlnet_b")) then
    return true
  end
  return false
end

-- Checks whether the guest network feature is enabled in UCI
local function isGuestConfigEnabled(iface)
  iface = untaint(iface)
  local state = get_untainted("uci.wireless.wifi-iface.@" .. iface .. ".state")
  return (state == "1")
end

function M.getSSID()
  local ssid_list = {}
  local ssids = proxy.getPN("rpc.wireless.ssid.", true)
  if not ssids then
    return ssid_list
  end

  for _, v in ipairs(ssids) do
    local path = v.path
    local iface = path:match("rpc%.wireless%.ssid%.@([^%.]+)%.")
    if iface then
      iface = untaint(iface)
      local is_guest = isGuestInterface(iface)
      local show_ssid = true

      if is_guest then
        -- If guest network is deactivated in configuration, do NOT show it on the card
        if not isGuestConfigEnabled(iface) then
          show_ssid = false
        end
      end

      if show_ssid then
        local radio = get_untainted(path .. "radio") or ""
        local ssid_name = get_untainted(path .. "ssid") or iface
        local ap_display_name = get_untainted(path .. "ap_display_name")
        local stb = get_untainted(path .. "stb")
        local oper_state = get_untainted(path .. "oper_state") or "0"

        local display_ssid = ssid_name
        if ap_display_name and ap_display_name ~= "" then
          display_ssid = ap_display_name
        elseif stb == "1" then
          display_ssid = "IPTV"
        end

        ssid_list[#ssid_list+1] = {
          iface = iface,
          radio = getFrequencyBand(radio),
          ssid = display_ssid,
          state = oper_state,
          is_guest = is_guest,
        }
      end
    end
  end

  return ssid_list
end

return M
