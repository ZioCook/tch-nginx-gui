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
  if brightness == nil or brightness == 0 then
    return "Off"
  end
  if mode == "none" or mode == "default-on" then
    return "On"
  elseif mode == "pattern" or mode == "timer" then
    return "Blinking"
  elseif mode == "netdev" then
    return "On"
  else
    return "On"
  end
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
      return math.floor(rLevel + 0.5) .. "%"
    end
  end
  if green then
    gLevel = M.getLedLevel(green.brightness, green.max_brightness)
    leddivider = leddivider + 1
    ledtotal = ledtotal + gLevel
    if ((red == nil or red.brightness==0) and (blue == nil or blue.brightness==0)) then
      return math.floor(gLevel + 0.5) .. "%"
    end
  end
  if blue then
    bLevel = M.getLedLevel(blue.brightness, blue.max_brightness)
    leddivider = leddivider + 1
    ledtotal = ledtotal + bLevel
    if ((green == nil or green.brightness==0) and (red == nil or red.brightness==0)) then
      return math.floor(bLevel + 0.5) .. "%"
    end
  end
  if leddivider == 0 then
    return "0%"
  end
  local rounded = math.floor((ledtotal/leddivider) + 0.5)
  return rounded.."%"
end

local function checkNetdevActive(ledFile)
  local df = open(ledFile .. "/device_name", "r")
  if not df then return false end
  local devices = df:read("*all")
  df:close()
  if not devices then return false end
  for dev in devices:gmatch("%S+") do
    local cf = open("/sys/class/net/" .. dev .. "/carrier", "r")
    if cf then
      local c = cf:read("*all"):gsub("%s+", "")
      cf:close()
      if c == "1" then return true end
    end
    local of = open("/sys/class/net/" .. dev .. "/operstate", "r")
    if of then
      local o = of:read("*all"):gsub("%s+", "")
      of:close()
      if o == "up" then return true end
    end
  end
  return false
end

local function readLedFromDir(ledFile)
  local trigger = "none"
  local brightness = 0
  local max_brightness = 255
  local fd = open(ledFile .. "/trigger", "r")
  if fd then
    local out = fd:read("*all")
    fd:close()
    if out then trigger = match(out, "%[([^%]]+)%]") or "none" end
  end
  fd = open(ledFile .. "/max_brightness", "r")
  if fd then
    local out = fd:read("*all")
    fd:close()
    if out then max_brightness = tonumber(out) or 255 end
  end
  fd = open(ledFile .. "/brightness", "r")
  if fd then
    local out = fd:read("*all")
    fd:close()
    if out then brightness = tonumber(out) or 0 end
  end

  if trigger == "netdev" then
    if checkNetdevActive(ledFile) then
      brightness = max_brightness
    else
      brightness = 0
    end
  elseif trigger == "timer" or trigger == "pattern" or trigger == "default-on" then
    brightness = max_brightness
  end

  return {
    trigger = trigger,
    brightness = brightness,
    max_brightness = max_brightness
  }
end

--- Get all the leds information from path /sys/class/leds/
-- @return #table led info
function M.getLedsInfo()
  local ledsInfo = {}
  if not isDir(ledPath) then
    return ledsInfo
  end

  local uci_lib = require("uci")
  local cursor = uci_lib and uci_lib.cursor and uci_lib.cursor()
  local has_ledfw_controls = false
  if cursor then
    cursor:foreach("ledfw", "control", function(t)
      local name = t["name"]
      if name then
        local colors = {"red", "green", "blue", "orange", "white"}
        for _, col in ipairs(colors) do
          local id = t[col]
          if id and isDir(ledPath .. id) then
            has_ledfw_controls = true
            if ledsInfo[name] == nil then
              ledsInfo[name] = {}
            end
            ledsInfo[name][col] = readLedFromDir(ledPath .. id)
          end
        end
      end
    end)
  end

  if not has_ledfw_controls then
    for file in lfs.dir(ledPath) do
      local name = match(file, "(.+):")
      local color = match(file, ":(.+)")
      if name and color then
        local ledFile = ledPath .. file
        if isDir(ledFile) then
          if ledsInfo[name] == nil then
            ledsInfo[name] = {}
          end
          ledsInfo[name][color] = readLedFromDir(ledFile)
        end
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
      elseif k2 == "orange" and v2.brightness and v2.brightness > 0 then
        if not redInfo then redInfo = v2 end
        if not greenInfo then greenInfo = v2 end
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
