-- dm_memo.lua: Per-request memoization of datamodel.get/getPN (Lua 5.1, ngx.ctx)
-- Eliminates redundant IPC socket round-trips to the Transformer daemon within a single HTTP request.

local M = {}

-- Mode: "off" | "audit" (counts duplicate calls, does not return cache) | "on" (returns cached clone)
local MODE        = "audit"
local MAX_AGE     = 1.0    -- seconds: valid only within single request execution window
local MAX_ENTRIES = 256

-- Conservative blacklist: NEVER memoize volatile/live counters, diagnostics or loop variables
local NEVER = {
    "modgui", "%.stats", "bytes", "packets", "uptime", "temperature", "cpu", "load",
    "diag", "ping", "traceroute", "%.log", "state", "status", "nf_conntrack",
}

local READERS  = { get = true, getPN = true }
local MUTATORS = { "set", "add", "del", "apply" }

local stats = { hits = 0, misses = 0, flushes = 0, bypass = 0 }
M.stats = stats

local function get_ngx()
    return rawget(_G, "ngx") or _G.ngx
end

local function get_ctx()
    local n = get_ngx()
    return n and n.ctx
end

local function now()
    local n = get_ngx()
    if n and n.now then return n.now() end
    return os.time()
end

local function req_cache()
    local n = get_ngx()
    if not n then return nil end
    local ok, ctx = pcall(get_ctx)
    if not ok or type(ctx) ~= "table" then return nil end
    local c = ctx.__dm_memo
    if not c then
        c = { e = {}, n = 0 }
        ctx.__dm_memo = c
    end
    return c
end

local function clone(v, depth)
    if type(v) ~= "table" or depth > 4 then return v end
    local t = {}
    for k, x in pairs(v) do
        t[k] = clone(x, depth + 1)
    end
    return t
end

local function make_key(name, ...)
    local n = select("#", ...)
    if n == 0 then return nil end
    local parts = { name }
    for i = 1, n do
        local a = select(i, ...)
        local ta = type(a)
        if ta == "string" then
            for j = 1, #NEVER do
                if a:find(NEVER[j]) then return nil end
            end
            parts[i + 1] = a
        elseif ta == "boolean" or ta == "number" then
            parts[i + 1] = tostring(a)
        else
            return nil
        end
    end
    return table.concat(parts, "\1")
end

local function flush()
    local c = req_cache()
    if c then
        c.e = {}
        c.n = 0
        stats.flushes = stats.flushes + 1
    end
end
M.flush = flush

local function store(c, key, t, ...)
    local res = ...
    if type(res) == "table" then
        if c.n >= MAX_ENTRIES then
            c.e = {}
            c.n = 0
        end
        c.e[key] = { v = clone(res, 0), t = t }
        c.n = c.n + 1
    end
    return ...
end

local function after(...) flush(); return ... end

local function wrap_reader(dm, name)
    local orig = dm[name]
    if type(orig) ~= "function" then return end
    dm[name] = function(...)
        local c = req_cache()
        local key = c and make_key(name, ...)
        if not key then
            stats.bypass = stats.bypass + 1
            return orig(...)
        end
        local t = now()
        local e = c.e[key]
        if e then
            local age = t - e.t
            if age >= 0 and age < MAX_AGE then
                stats.hits = stats.hits + 1
                if MODE == "on" then
                    return clone(e.v, 0)
                end
            end
        end
        stats.misses = stats.misses + 1
        return store(c, key, t, orig(...))
    end
end

local function wrap_mutator(dm, name)
    local orig = dm[name]
    if type(orig) ~= "function" then return end
    dm[name] = function(...)
        flush()
        return after(orig(...))
    end
end

local TARGETS  = { "get", "getPN", "set", "add", "del", "apply" }

function M.install(dm)
    if MODE == "off" or not get_ngx() or rawget(dm, "__dm_memo") then return dm end
    local names, seen = {}, {}
    for _, k in ipairs(TARGETS) do
        if type(dm[k]) == "function" and not seen[k] then
            seen[k] = true
            names[#names + 1] = k
        end
    end
    for k, v in pairs(dm) do
        if type(v) == "function" and not seen[k] then
            seen[k] = true
            names[#names + 1] = k
        end
    end
    local raw_get = dm.get
    for i = 1, #names do
        local k = names[i]
        if READERS[k] then
            wrap_reader(dm, k)
        else
            wrap_mutator(dm, k)
        end
    end
    rawset(dm, "get_fresh", raw_get)
    rawset(dm, "__dm_memo", true)
    return dm
end

function M.set_mode(mode)
    if mode == "off" or mode == "audit" or mode == "on" then
        MODE = mode
    end
end

function M.get_mode()
    return MODE
end

return M
