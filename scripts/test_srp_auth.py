#!/usr/bin/env python3
import subprocess

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

# We write a tiny Lua helper on the router to authenticate a session via SRP
auth_helper = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
local srp = require("srp")
local sessioncontrol = require("web.sessioncontrol")
local dm = require("datamodel")

local username = arg[1] or "admin"
-- Get user password/salt/verifier from uci
local users = dm.get("uci.web.user.")
local srp_salt, srp_verifier, password
if users then
    for _, item in ipairs(users) do
        if item.param == "name" and item.value == username then
            local sec = item.path:match("@([^.]+)%.")
            for _, sub in ipairs(users) do
                if sub.path:find(sec) then
                    if sub.param == "srp_salt" then srp_salt = sub.value end
                    if sub.param == "srp_verifier" then srp_verifier = sub.value end
                end
            end
        end
    end
end

-- If password is known (e.g. via ROUTER_PASS env var)
-- Or we can perform SRP exchange directly with curl
print(string.format("USER=%s SALT=%s VERIFIER=%s", username, tostring(srp_salt), tostring(srp_verifier)))
"""

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Checking SRP user config on {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=auth_helper.encode('utf-8'), capture_output=True, text=True)
    print(res.stdout.strip())
