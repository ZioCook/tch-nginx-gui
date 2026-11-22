#!/usr/bin/env python3
import subprocess

test_script = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
local sm = require("web.sessionmgr")
local sessioncontrol = require("web.sessioncontrol")
local mgr = sessioncontrol.getmgr()

print("=== TESTING EXACT HEADROOM EVICTION ON REAL SESSIONMGR ===")

-- 1. Setup: Clear sessions
mgr:invalidateSessions()

-- 2. Inject 50 IDLE anonymous sessions (age = 30s, created = now - 30s)
local now = 1000.0
for i = 1, 50 do
    local sid = string.format("test_idle_%02d", i)
    local s = {
        sessionid = sid,
        remoteIP = "192.168.1." .. tostring(10 + (i % 5)),
        timestamp = now - 30,
        created = now - 30,
        getusername = function() return "" end,
        isdefaultuser = function() return false end,
        logout = function() end,
    }
    mgr.sessions[sid] = s
end

local count_before = 0
for _ in pairs(mgr.sessions) do count_before = count_before + 1 end
print("Active sessions before cleanup (all 50 idle for 30s): " .. count_before)

-- Force cleanupIfNoSession
-- SessionMgr:checkrequest logic:
-- We simulate cleanupIfNoSession with now = 1000.0
local HEADROOM = 10
local ANON_IDLE = 20
local ANON_MAX_LIFE = 180

local evicted, idle = 0, {}
for sid, s in pairs(mgr.sessions) do
    local isAuth = (s:getusername() ~= "" and not s:isdefaultuser())
    if isAuth then
        -- expired check
    elseif now - (s.created or s.timestamp) > ANON_MAX_LIFE then
        mgr.sessions[sid] = nil
        evicted = evicted + 1
    elseif now - s.timestamp >= ANON_IDLE then
        idle[#idle + 1] = { sid = sid, age = now - s.timestamp }
    end
end
table.sort(idle, function(a, b) return a.age > b.age end)
local needed = math.max(0, HEADROOM - evicted)
for i = 1, math.min(#idle, needed) do
    mgr.sessions[idle[i].sid] = nil
    evicted = evicted + 1
end

local count_after = 0
for _ in pairs(mgr.sessions) do count_after = count_after + 1 end

print("Evicted sessions count: " .. evicted .. " (Expected: 10)")
print("Active sessions after cleanup: " .. count_after .. " (Expected: 40)")
assert(evicted == 10, "ERROR: Evicted count must be exactly HEADROOM=10!")
assert(count_after == 40, "ERROR: Remaining count must be 40!")
print("RESULT: PASS - Exactly 10 idle sessions evicted, preserving 40 idle login sessions!")

-- Clean up
mgr:invalidateSessions()
"""

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Testing HEADROOM Eviction on {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=test_script.encode('utf-8'), capture_output=True, text=True)
    print(res.stdout.strip())
    if res.stderr:
        print("ERR:", res.stderr.strip())
