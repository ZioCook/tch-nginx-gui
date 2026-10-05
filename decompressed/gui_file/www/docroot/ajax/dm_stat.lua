-- /ajax/dm_stat.lua: Diagnostic endpoint for datamodel memoization stats
local json = require("dkjson")
local dm_memo = require("web.dm_memo")

if ngx and ngx.header then
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
end

local stats = dm_memo.stats or {}
local total = (stats.hits or 0) + (stats.misses or 0)
local hit_rate = (total > 0) and string.format("%.1f%%", (stats.hits / total) * 100) or "0.0%"

local resp = {
    mode = dm_memo.get_mode(),
    hits = stats.hits or 0,
    misses = stats.misses or 0,
    flushes = stats.flushes or 0,
    bypass = stats.bypass or 0,
    hit_rate = hit_rate,
    total_calls = total,
}

local buf = {}
if json.encode(resp, { indent = true, buffer = buf }) then
    ngx.say(buf)
else
    ngx.say("{}")
end

if ngx and ngx.exit and ngx.HTTP_OK then
    ngx.exit(ngx.HTTP_OK)
end
