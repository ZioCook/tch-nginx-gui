local io, string, table, tonumber, tostring = io, string, table, tonumber, tostring
local proxy = require("datamodel")
local untaint = string.untaint or function(x) return x end
local M = {}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content and content:gsub("^%s+", ""):gsub("%s+$", "") or nil
end

-- Get CPU Governors
function M.getAvailableGovernors()
  local raw = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors")
  local governors = {}
  if raw then
    for gov in raw:gmatch("%S+") do
      governors[#governors + 1] = { gov, gov:gsub("^%l", string.upper) }
    end
  end
  return governors
end

-- Check if CPU core hotplug is supported
function M.hasCoreHotplug()
  local f = io.open("/sys/devices/system/cpu/cpu1/online", "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- Get CPU Frequencies
function M.getAvailableFrequencies()
  local raw = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies")
  local freqs = {}
  if raw then
    for f in raw:gmatch("%S+") do
      local num = tonumber(f)
      if num then
        local label
        if num >= 1000000 then
          label = string.format("%.1f GHz", num / 1000000)
        else
          label = string.format("%d MHz", math.floor(num / 1000))
        end
        freqs[#freqs + 1] = { tostring(num), label }
      end
    end
    -- Sort frequencies ascending
    table.sort(freqs, function(a, b) return (tonumber(a[1]) or 0) < (tonumber(b[1]) or 0) end)
  end
  return freqs
end

-- Get CPU Live Status
function M.getCpuStatus()
  local cur_freq = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
  local cur_gov = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
  local min_freq = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq")
  local max_freq = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq")
  local cpu1_online = read_file("/sys/devices/system/cpu/cpu1/online")

  local cur_freq_str = "N/A"
  if cur_freq and tonumber(cur_freq) then
    local num = tonumber(cur_freq)
    if num >= 1000000 then
      cur_freq_str = string.format("%.1f GHz", num / 1000000)
    else
      cur_freq_str = string.format("%d MHz", math.floor(num / 1000))
    end
  end

  local has_cpufreq = (cur_gov ~= nil or cur_freq ~= nil)
  local cores = (cpu1_online == "0") and 1 or 2

  if not has_cpufreq then
    local cpuinfo = read_file("/proc/cpuinfo")
    if cpuinfo then
      local bogomips = cpuinfo:match("BogoMIPS%s*:%s*([%d%.]+)")
      if bogomips then
        local bm = tonumber(bogomips)
        if bm and bm > 300 and bm < 500 then
          cur_freq_str = "400 MHz"
        elseif bm and bm > 1500 then
          cur_freq_str = "1.0 GHz"
        elseif bm then
          cur_freq_str = string.format("%d MHz", math.floor(bm))
        end
      end
      local count = 0
      for _ in cpuinfo:gmatch("processor%s*:") do
        count = count + 1
      end
      if count > 0 then
        cores = count
      end
    end
  end

  return {
    governor = cur_gov or "N/A",
    cur_freq = cur_freq_str,
    cur_freq_raw = cur_freq or "N/A",
    min_freq = min_freq or "N/A",
    max_freq = max_freq or "N/A",
    cores_online = cores,
    has_cpufreq = has_cpufreq,
  }
end

-- Read Hardware / Wi-Fi Temperatures
function M.getTemperatures()
  local temps = {}

  -- 1. Broadcom Wi-Fi 2.4GHz (wl0)
  local f_wl0 = io.popen("wl -i wl0 phy_tempsense 2>/dev/null")
  if f_wl0 then
    local out = f_wl0:read("*a")
    f_wl0:close()
    if out then
      local val = out:match("(%d+)%s*%(") or out:match("^(%d+)")
      if val and tonumber(val) and tonumber(val) > 0 then
        temps[#temps + 1] = {
          sensor = "Wi-Fi 2.4 GHz (Broadcom)",
          temp = tonumber(val),
          unit = "°C",
          chip = "wl0",
        }
      end
    end
  end

  -- 2. Quantenna Wi-Fi 5GHz (qtn_call_qcsapi.sh)
  local f_qtn = io.popen("qtn_call_qcsapi.sh get_temperature wifi0 2>/dev/null")
  if f_qtn then
    local out = f_qtn:read("*a")
    f_qtn:close()
    if out then
      local rfic = out:match("temperature_rfic_internal%s*=%s*([%d%.]+)")
      local bbic = out:match("temperature_bbic_internal%s*=%s*([%d%.]+)")
      if rfic and tonumber(rfic) and tonumber(rfic) > 0 then
        temps[#temps + 1] = {
          sensor = "Wi-Fi 5 GHz RFIC (Quantenna)",
          temp = math.floor(tonumber(rfic) + 0.5),
          unit = "°C",
          chip = "qtn-rfic",
        }
      end
      if bbic and tonumber(bbic) and tonumber(bbic) > 0 then
        temps[#temps + 1] = {
          sensor = "Wi-Fi 5 GHz BBIC (Quantenna)",
          temp = math.floor(tonumber(bbic) + 0.5),
          unit = "°C",
          chip = "qtn-bbic",
        }
      end
    end
  end

  -- 3. Broadcom Wi-Fi 5GHz (wl1) for models with Broadcom 5G
  if #temps < 2 then
    local f_wl1 = io.popen("wl -i wl1 phy_tempsense 2>/dev/null")
    if f_wl1 then
      local out = f_wl1:read("*a")
      f_wl1:close()
      if out then
        local val = out:match("(%d+)%s*%(") or out:match("^(%d+)")
        if val and tonumber(val) and tonumber(val) > 0 then
          temps[#temps + 1] = {
            sensor = "Wi-Fi 5 GHz (Broadcom)",
            temp = tonumber(val),
            unit = "°C",
            chip = "wl1",
          }
        end
      end
    end
  end

  -- 4. Thermal Zones (if any)
  for idx = 0, 3 do
    local f_tz = io.open("/sys/class/thermal/thermal_zone" .. idx .. "/temp", "r")
    if not f_tz then break end
    local line = f_tz:read("*l")
    f_tz:close()
    local val = line and tonumber(line:match("%d+"))
    if val then
      if val > 1000 then val = math.floor(val / 1000) end
      temps[#temps + 1] = {
        sensor = "SoC Thermal Zone " .. idx,
        temp = val,
        unit = "°C",
        chip = "soc",
      }
    end
  end

  return temps
end

-- Get Memory & Swap Info
function M.getMemoryInfo()
  local meminfo = read_file("/proc/meminfo")
  local res = {
    mem_total = 0,
    mem_free = 0,
    mem_available = 0,
    buffers = 0,
    cached = 0,
    swap_total = 0,
    swap_free = 0,
    swappiness = tonumber(read_file("/proc/sys/vm/swappiness")) or 60,
    vfs_cache_pressure = tonumber(read_file("/proc/sys/vm/vfs_cache_pressure")) or 100,
  }

  if meminfo then
    res.mem_total = tonumber(meminfo:match("MemTotal:%s*(%d+)")) or 0
    res.mem_free = tonumber(meminfo:match("MemFree:%s*(%d+)")) or 0
    res.mem_available = tonumber(meminfo:match("MemAvailable:%s*(%d+)")) or 0
    res.buffers = tonumber(meminfo:match("Buffers:%s*(%d+)")) or 0
    res.cached = tonumber(meminfo:match("Cached:%s*(%d+)")) or 0
    res.swap_total = tonumber(meminfo:match("SwapTotal:%s*(%d+)")) or 0
    res.swap_free = tonumber(meminfo:match("SwapFree:%s*(%d+)")) or 0

    -- Fallback for Linux kernels < 3.14 (e.g. 3.4 on TG789vac v2) without MemAvailable
    if res.mem_available == 0 then
      res.mem_available = res.mem_free + res.buffers + res.cached
    end
  end

  res.swap_used = res.swap_total - res.swap_free
  res.buff_cache = res.buffers + res.cached
  return res
end

-- Drop caches action
function M.dropCaches()
  os.execute("sync && echo 3 > /proc/sys/vm/drop_caches")
  return true
end

return M
