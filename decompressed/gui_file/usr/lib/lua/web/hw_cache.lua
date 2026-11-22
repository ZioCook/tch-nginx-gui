-- Worker-scoped hardware, kernel capability, and sync state cache.
-- Persisted via package.loaded across web.lua loadfile() request invocations
-- without storing state in _G.

collectgarbage("setpause", 300)
collectgarbage("setstepmul", 200)

local ok_dm, proxy = pcall(require, "datamodel")
if not ok_dm then
    proxy = nil
end
pcall(require, "web.taint")

local io_open = io.open
local io_popen = io.popen
local pcall = pcall
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local type = type
local str_untaint = rawget(string, "untaint")

local M = {}

local NIL = {}
local dm_cache = {}
local eth4_cached = nil
local eth4_dm_checked = false
local tun_cached = nil
local config_tun_checked = false
local is_4_1_52_cached = nil
local is_armv7_cached = nil

local sync_mem = {
    cpu_prev = nil,
    wan_dev = nil,
    wan_dev_ts = 0,
    jcache = {},
}

local function untaint_val(v)
    if v == nil then
        return nil
    end
    local fn = str_untaint or rawget(string, "untaint")
    if fn then
        return fn(v)
    end
    return tostring(v)
end

local function is_transient_ipc_err(err)
    if type(err) ~= "string" then
        return false
    end
    local lower = err:lower()
    return lower:find("timeout", 1, true) ~= nil
        or lower:find("connect", 1, true) ~= nil
        or lower:find("temporar", 1, true) ~= nil
end

local function get_boot_const(path)
    local cached = dm_cache[path]
    if cached ~= nil then
        if cached == NIL then
            return nil
        end
        return cached
    end
    if not proxy or not proxy.get then
        return nil
    end
    local ok, res, err = pcall(proxy.get, path)
    if ok then
        if res and res[1] and res[1].value ~= nil then
            local val = untaint_val(res[1].value)
            dm_cache[path] = val
            return val
        end
        if res ~= nil or not is_transient_ipc_err(err) then
            dm_cache[path] = NIL
        end
    end
    return nil
end

function M.sync_state()
    return sync_mem
end

function M.get_cpu_type()
    return get_boot_const("rpc.system.modgui.CPUtype") or ""
end

function M.get_marketing_version()
    return get_boot_const("uci.version.version.@version[0].marketing_version") or ""
end

function M.get_sfp()
    return get_boot_const("uci.env.rip.sfp")
end

function M.get_qtn_eth_mac()
    return get_boot_const("uci.env.var.qtn_eth_mac")
end

function M.has_eth4()
    if eth4_cached then
        return true
    end
    local f = io_open("/sys/class/net/eth4/operstate", "r")
    if f then
        f:close()
        eth4_cached = true
        return true
    end
    if not eth4_dm_checked and proxy and proxy.get then
        local ok, p4, err = pcall(proxy.get, "sys.eth.port.@eth4.status")
        if ok then
            if p4 and p4[1] and p4[1].value ~= nil then
                eth4_cached = true
                eth4_dm_checked = true
                return true
            end
            if p4 ~= nil or not is_transient_ipc_err(err) then
                eth4_dm_checked = true
            end
        end
    end
    return false
end

function M.kernel_has_tun()
    if tun_cached then
        return true
    end
    local f = io_open("/dev/net/tun", "r")
    if f then
        f:close()
        tun_cached = true
        return true
    end
    if not config_tun_checked then
        config_tun_checked = true
        local cfg = io_open("/proc/config.gz", "r")
        if cfg then
            cfg:close()
            if io_popen then
                local cmd = io_popen("zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_TUN=y$'; echo $?", "r")
                if cmd then
                    local res = cmd:read("*line")
                    cmd:close()
                    if res == "0" then
                        tun_cached = true
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function is_kernel_4_1_52()
    if is_4_1_52_cached ~= nil then
        return is_4_1_52_cached
    end
    local matched = false
    local f = io_open("/proc/version", "r")
    if f then
        local line = f:read("*line")
        f:close()
        if line and line:match("^Linux version 4%.1%.52%s") then
            matched = true
        end
    end
    is_4_1_52_cached = matched
    return matched
end

local function is_cpu_armv7()
    if is_armv7_cached ~= nil then
        return is_armv7_cached
    end
    local matched = false
    local f = io_open("/proc/cpuinfo", "r")
    if f then
        local chunk = f:read(512)
        f:close()
        if chunk and chunk:find("ARMv7", 1, true) then
            matched = true
        end
    else
        matched = (M.get_cpu_type() == "armv7l")
    end
    is_armv7_cached = matched
    return matched
end

function M.tun_install_supported()
    if M.kernel_has_tun() then
        return true
    end
    return is_cpu_armv7() and is_kernel_4_1_52()
end

function M.read_ram_used_kb(path)
    local f = io_open(path or "/proc/meminfo", "r")
    if not f then
        return nil
    end
    local total, avail, free, buffers, cached
    local lines_read = 0
    for line in f:lines() do
        lines_read = lines_read + 1
        local k, v = line:match("^([%w_%(%)]+):%s*(%d+)%s+kB")
        if k then
            local n = tonumber(v)
            if k == "MemTotal" then
                total = n
            elseif k == "MemAvailable" then
                avail = n
            elseif k == "MemFree" then
                free = n
            elseif k == "Buffers" then
                buffers = n
            elseif k == "Cached" then
                cached = n
            end
            if total and avail then
                break
            end
        end
        if lines_read >= 16 and total and free and buffers and cached then
            break
        end
    end
    f:close()
    if not total then
        return nil
    end
    local used
    if avail then
        used = total - avail
    elseif free then
        used = total - free - (buffers or 0) - (cached or 0)
    else
        return nil
    end
    if used < 0 then
        used = 0
    end
    return used
end

return M
