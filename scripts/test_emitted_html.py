#!/usr/bin/env python3
import subprocess

test_script = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
local ui_helper = require("web.ui_helper")

local base_name_class = {
    input = {
        pattern= "^([a-zA-Z]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,6}$",
        maxlength= "16",
        class= "span4",
    }
}

local out = ui_helper.createInputText("Base Name", "baseName", "sip.tim.it", base_name_class)

local function flatten(t)
    if type(t) == "table" then
        local s = ""
        for _, v in ipairs(t) do s = s .. flatten(v) end
        return s
    else
        return tostring(t)
    end
end

print("EMITTED_HTML: " .. flatten(out))
"""

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Checking Emitted HTML on {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=test_script.encode('utf-8'), capture_output=True, text=True)
    print(res.stdout.strip())
    if res.stderr:
        print("ERR:", res.stderr.strip())
