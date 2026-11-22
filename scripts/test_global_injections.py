#!/usr/bin/env python3
import subprocess

probe_script = r"""
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path

print("=== CHECKING GLOBAL FRAMEWORK INJECTIONS IN LUA RUNTIME ===")

-- Check what is in _G before web.web / sessionmgr
print("BEFORE requiring web.web / web.sessionmgr:")
print("  ui_helper:      " .. tostring(type(_G.ui_helper)))
print("  post_helper:    " .. tostring(type(_G.post_helper)))
print("  content_helper: " .. tostring(type(_G.content_helper)))
print("  proxy:          " .. tostring(type(_G.proxy)))
print("  session:        " .. tostring(type(_G.session)))
print("  T:              " .. tostring(type(_G.T)))
print("  N:              " .. tostring(type(_G.N)))
print("  gettext:        " .. tostring(type(_G.gettext)))

-- Load web.web
require("web.web")
print("\nAFTER requiring web.web:")
print("  ui_helper:      " .. tostring(type(_G.ui_helper)))
print("  post_helper:    " .. tostring(type(_G.post_helper)))
print("  content_helper: " .. tostring(type(_G.content_helper)))
print("  proxy:          " .. tostring(type(_G.proxy)))
print("  session:        " .. tostring(type(_G.session)))
print("  T:              " .. tostring(type(_G.T)))
print("  N:              " .. tostring(type(_G.N)))
print("  gettext:        " .. tostring(type(_G.gettext)))

-- Check each individual file require behavior in codebase
print("\n--- Summary of Framework Globals ---")
print("1. 'ngx' is injected by the Nginx C/Lua core into _G.")
print("2. 'gettext', 'T', 'N' are injected into _G by 'gettext.textdomain(...)' in web/intl.lua or per-file textdomain.")
print("3. 'ui_helper', 'post_helper', 'content_helper', 'proxy' are standard modules that files require via require('web.ui_helper'), require('web.post_helper'), require('web.content_helper'), require('datamodel').")
print("4. 'session' is provided in request context via ngx.ctx.session = session.proxy in web.sessionmgr.")
"""

for ip in ["192.0.2.6", "192.0.2.3", "192.0.2.7"]:
    print(f"\n=======================================================")
    print(f"[*] Checking Runtime Injections on {ip}")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /tmp/check_inj.lua"], input=probe_script.encode('utf-8'), capture_output=True)
    res_exec = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua /tmp/check_inj.lua; rm -f /tmp/check_inj.lua"], capture_output=True, text=True)
    print(res_exec.stdout.strip())
    if res_exec.stderr:
        print("ERR:", res_exec.stderr.strip())
