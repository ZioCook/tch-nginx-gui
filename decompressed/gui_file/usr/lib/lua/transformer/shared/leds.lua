local open, string = io.open, string
local match = string.match
local lfs = require("lfs")
local uci = require("transformer.mapper.ucihelper")

local M = {}
local ledPath = "/sys/class/leds/"


local function isDir(path)
  local mode = lfs.attributes(path, "mode")
  if mode and mode == "directory" then
    return true
  end
  return false
end

--- Get the led(seven-color) mixed status
-- @param #table red led info
-- @param #table green led info
-- @param #table blue led info
-- @return #string led status /Blinking/Netdev/On/Off
local function getLedMixStatus(red, green, blue)
  local mixStatus = ""
  local rStatus, gStatus, bStatus
  if red then
    rStatus = M.getLedStatus(red.trigger, red.brightness)
  end
  if green then
    gStatus = M.getLedStatus(green.trigger, green.brightness)
  end
  if blue then
    bStatus = M.getLedStatus(blue.trigger, blue.brightness)
  end
  if rStatus == "Blinking" or gStatus == "Blinking" or bStatus == "Blinking" then
    mixStatus = "Blinking"
  elseif rStatus == "Netdev" or gStatus == "Netdev" or bStatus == "Netdev" then
    mixStatus = "Netdev"
  elseif rStatus == "On" or gStatus == "On" or bStatus == "On" then
    mixStatus = "On"
  else
    mixStatus = "Off"
  end
  return mixStatus
end

--- Get led(color is red/green/blue) status
-- @param #string led trigger mode /none/default-on/pattern/timer/netdev
-- @param #integer led brightness
-- @return #string led status /Blinking/Netdev/On/Off
function M.getLedStatus(mode, brightness)
  local status = ""
  if mode == "none" then
    if brightness == 0 then
      status = "Off"
    else
      status = "On"
    end
  elseif mode == "default-on" then
    status = "On"
  elseif mode == "pattern" or mode == "timer" then
    status = "Blinking"
  elseif mode == "netdev" then
    status = "Netdev"
  end
  return status
end

--- Get the led(seven-color) mixed color
-- @param #table red led info
-- @param #table green led info
-- @param #table blue led info
-- @return #string led mixed color /White/Orange/Magenta/Red/Cyan/Green/Blue/None
local function getLedMixColor(redInfo, greenInfo, blueInfo)
  local rBrightness, gBrightness, bBrightness
  if redInfo ~= nil then
    rBrightness = redInfo.brightness
  end
  if greenInfo ~= nil then
    gBrightness = greenInfo.brightness
  end
  if blueInfo ~= nil then
    bBrightness = blueInfo.brightness
  end
  local color = "None"
  local red, green, blue = false, false, false
  if rBrightness ~= nil and rBrightness > 0 then
    red = true
  end
  if gBrightness ~= nil and gBrightness > 0 then
    green = true
  end
  if bBrightness ~= nil and bBrightness > 0 then
    blue = true
  end
  if red and green and blue then
    color = "White"
  elseif red and green then
    color = "Orange"
  elseif red and blue then
    color = "Magenta"
  elseif red then
    color = "Red"
  elseif green and blue then
    color = "Cyan"
  elseif green then
    color = "Green"
  elseif blue then
    color = "Blue"
  end
  return color
end

--- Get led(color is red/green/blue) brightness level
-- @param #integer led brightness
-- @param #integer led max brightness
--@return #string led brightness level /None/Low/Middle/High
function M.getLedLevel(brightness, maxBrightness)
  if brightness == nil or type(brightness) ~= "number" then
    return 100
  end
  if maxBrightness == nil or type(maxBrightness) ~= "number" then
    return 100
  end

  return (brightness/maxBrightness)*100
end

--- Get the led(seven-color) brightness level
---- @param #table red led info
---- @param #table green led info
---- @param #table blue led info
---- @return #string led brightness level /None/Low/Middle/High
local function getLedMixBrightness(red, green, blue)
  local rLevel, gLevel, bLevel
  local leddivider = 0
  local ledtotal = 0
  if red then
    rLevel = M.getLedLevel(red.brightness, red.max_brightness)
    leddivider = leddivider + 1
    ledtotal = ledtotal + rLevel
    if ((green == nil or green.brightness==0) and (blue == nil or blue.brightness==0)) then
      return rLevel.."%"
    end
  end
  if green then
    gLevel = M.getLedLevel(green.brightness, green.max_brightness)
    leddivider = leddivider + 1
    ledtotal = ledtotal + gLevel
    if ((red == nil or red.brightness==0) and (blue == nil or blue.brightness==0)) then
      return gLevel.."%"
    end
  end
  if blue then
    bLevel = M.getLedLevel(blue.brightness, blue.max_brightness)
    leddivider = leddivider + 1
    ledtotal = ledtotal + bLevel
    if ((green == nil or green.brightness==0) and (red == nil or red.brightness==0)) then
      return bLevel.."%"
    end
  end
  local rounded = ledtotal/leddivider
  return rounded.."%"
end

--- Get all the leds information from path /sys/class/leds/
-- @return #table led info
function M.getLedsInfo()
  local ledsInfo = {}
  if not isDir(ledPath) then
    return ledsInfo
  end
  for file in lfs.dir(ledPath) do
    local name = match(file, "(.+):")
    local color = match(file, ":(.+)")
    if name and color then
      if ledsInfo[name] == nil then
        ledsInfo[name] = {}
      end
      ledsInfo[name][color] = {}
      local ledFile = ledPath .. file
      if lfs.attributes(ledFile, "mode") == "directory" then
        local fd = open(ledFile .. "/trigger", "r")
        if not fd then
          break
        end
        local output = fd:read("*all")
        if output then
          local trigger = match(output, "%[(.+)%]")
          if trigger then
            ledsInfo[name][color].trigger = trigger
          end
        end
        fd:close()
        fd = open(ledFile .. "/brightness", "r")
        if not fd then
          break
        end
        output = fd:read("*all")
        if output then
          local brightness = tonumber(output)
          if brightness then
            ledsInfo[name][color].brightness = brightness
          end
        end
        fd:close()
        fd = open(ledFile .. "/max_brightness", "r")
        if not fd then
          break
        end
        output = fd:read("*all")
        if output then
          local max_brightness = tonumber(output)
          if max_brightness then
            ledsInfo[name][color].max_brightness = max_brightness
          end
        end
        fd:close()
      end
    end
  end
  if next(ledsInfo) == nil then
    local uci_lib = require("uci")
    local cursor = uci_lib and uci_lib.cursor and uci_lib.cursor()

    -- Power
    ledsInfo["power"] = {
      green = { trigger = "default-on", brightness = 255, max_brightness = 255 }
    }

    -- Broadband / DSL
    local bbStatus = "Off"
    local xdsl = io.open("/sys/class/xdsl/status", "r") or io.open("/proc/driver/enet/status", "r")
    if xdsl then
      local content = xdsl:read("*all")
      xdsl:close()
      if content:match("up") or content:match("Showtime") then
        bbStatus = "On"
      end
    end
    if bbStatus == "Off" and cursor then
      local proto = cursor:get("network", "wan", "proto")
      if proto and proto ~= "" then
        bbStatus = "On"
      end
    end
    ledsInfo["broadband"] = {
      green = { trigger = bbStatus == "On" and "default-on" or "none", brightness = bbStatus == "On" and 255 or 0, max_brightness = 255 }
    }

    -- Internet
    local inetStatus = "Off"
    local routes = io.open("/proc/net/route", "r")
    if routes then
      for line in routes:lines() do
        local iface, dest = line:match("^([^%s]+)%s+([0-9A-Fa-f]+)")
        if dest == "00000000" then
          inetStatus = "On"
          break
        end
      end
      routes:close()
    end
    ledsInfo["internet"] = {
      green = { trigger = inetStatus == "On" and "default-on" or "none", brightness = inetStatus == "On" and 255 or 0, max_brightness = 255 }
    }

    -- Wireless 2.4GHz
    local wl0_state = cursor and cursor:get("wireless", "radio_2G", "state")
    local wl0Status = (wl0_state == "1" or wl0_state == "on") and "On" or "Off"
    ledsInfo["wireless_2.4GHz"] = {
      green = { trigger = wl0Status == "On" and "default-on" or "none", brightness = wl0Status == "On" and 255 or 0, max_brightness = 255 }
    }

    -- Wireless 5GHz
    local wl1_state = cursor and cursor:get("wireless", "radio_5G", "state")
    local wl1Status = (wl1_state == "1" or wl1_state == "on") and "On" or "Off"
    ledsInfo["wireless_5GHz"] = {
      green = { trigger = wl1Status == "On" and "default-on" or "none", brightness = wl1Status == "On" and 255 or 0, max_brightness = 255 }
    }

    -- Ethernet
    local ethStatus = "Off"
    for i = 0, 3 do
      local eth = io.open("/sys/class/net/eth" .. i .. "/operstate", "r")
      if eth then
        local state = eth:read("*all"):gsub("%s+", "")
        eth:close()
        if state == "up" then
          ethStatus = "On"
          break
        end
      end
    end
    ledsInfo["ethernet"] = {
      green = { trigger = ethStatus == "On" and "default-on" or "none", brightness = ethStatus == "On" and 255 or 0, max_brightness = 255 }
    }

    -- WPS
    ledsInfo["wps"] = {
      green = { trigger = "none", brightness = 0, max_brightness = 255 }
    }
  end
  for k1, v1 in pairs(ledsInfo) do
    local redInfo, greenInfo, blueInfo
    for k2, v2 in pairs(v1) do
      if k2 == "red" then
        redInfo = v2
      elseif k2 == "green" then
        greenInfo = v2
      elseif k2 == "blue" then
        blueInfo = v2
      elseif k2 == "white" and v1["red"] == nil and v1["green"] == nil and v1["blue"] == nil then --needed for ambient led of DGA4131FWB
        redInfo = v2
        greenInfo = v2
        blueInfo = v2
      end
    end
    local mixColor = getLedMixColor(redInfo, greenInfo, blueInfo)
    local mixStatus = getLedMixStatus(redInfo, greenInfo, blueInfo)
    local mixBrightness = getLedMixBrightness(redInfo, greenInfo, blueInfo)
    ledsInfo[k1].mixColor = mixColor
    ledsInfo[k1].mixStatus = mixStatus
    ledsInfo[k1].mixBrightness = mixBrightness
  end
  return ledsInfo
end

return M
