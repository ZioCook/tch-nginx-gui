-- netrate.lua: High-efficiency network throughput monitor (/proc/net/dev)
-- Computes real-time byte rates without fork+exec, handles 32-bit wrap, clock jumps, and long pauses.

local io_open, tonumber = io.open, tonumber
local s_match, s_gmatch, s_rep = string.match, string.gmatch, string.rep
local m_floor = math.floor

local M = {}

local WRAP32  = 4294967296  -- 2^32
local MIN_DT  = 1.0         -- s: minimum window between real samples (shared across concurrent requests)
local MAX_BPS = 160e6       -- B/s: maximum physical rate for GbE (~1.28 Gbit/s)
local MAX_DT  = 20          -- s: maximum valid interval before rebase

local LINE_PAT = "^%s*([^:%s]+):%s*(%d+)" .. s_rep("%s+%d+", 7) .. "%s+(%d+)"

local function read_uptime()
    local f = io_open("/proc/uptime", "r")
    if not f then return nil end
    local s = f:read("*l")
    f:close()
    return s and tonumber(s_match(s, "^(%d+%.?%d*)")) or nil
end

local function read_netdev()
    local f = io_open("/proc/net/dev", "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local t = {}
    for line in s_gmatch(data, "[^\n]+") do
        local name, rx, tx = s_match(line, LINE_PAT)
        if name then t[name] = { tonumber(rx), tonumber(tx) } end
    end
    return t
end

local read_up, read_dev = read_uptime, read_netdev

local st = { t = nil, ifs = nil, rates = {}, status = "init" }
local is64 = {}

local function counter_delta(key, prev, cur, dt)
    if prev >= WRAP32 or cur >= WRAP32 then is64[key] = true end
    if cur >= prev then return cur - prev end
    if is64[key] then return nil end          -- 64-bit dropped => interface reset
    local d = cur + WRAP32 - prev             -- Hypothesis: single 32-bit wrap
    if d <= MAX_BPS * dt then return d end
    return nil                                -- Implausible => interface reset
end

function M.sample()
    local t = read_up()
    if not t then return st.rates, "noclock" end

    local bt = st.t
    if bt and t >= bt and (t - bt) < MIN_DT then
        return st.rates, st.status            -- Shared window still fresh
    end

    local cur = read_dev()
    if not cur then return st.rates, "nodev" end

    local dt = bt and (t - bt)
    if not dt or dt < 0 or dt > MAX_DT then   -- First tick, long tab sleep, or clock anomaly
        st.t, st.ifs, st.status = t, cur, "rebase"
        return st.rates, "rebase"
    end

    local rates, prev = {}, st.ifs
    for name, c in pairs(cur) do
        local p = prev[name]
        if p then
            local rxd = counter_delta(name .. ":rx", p[1], c[1], dt)
            local txd = counter_delta(name .. ":tx", p[2], c[2], dt)
            if c[1] < p[1] and c[2] < p[2] then rxd, txd = nil, nil end
            rates[name] = {
                rx = rxd and m_floor(rxd / dt + 0.5) or nil,
                tx = txd and m_floor(txd / dt + 0.5) or nil,
            }
        end
    end
    st.t, st.ifs, st.rates, st.status = t, cur, rates, "ok"
    return rates, "ok"
end

return M
