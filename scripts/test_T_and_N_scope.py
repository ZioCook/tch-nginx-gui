#!/usr/bin/env python3
import subprocess

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

print("===================================================================")
print("[*] 1. MEASURING type(T), type(N) IN CARD, MODAL, AND AJAX .LUA")
print("===================================================================")

probe_code = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
local lp = require("web.lp")

print("--- 1. INSIDE .LP TEMPLATE ENVIRONMENT (web.lp) ---")
-- Translate & load snippet
local trans = lp.translate([[--pretranslated: do not change this file
return type(T), type(N), type(gettext), type(ngx)
]])
local f = loadstring(trans)
local env = getfenv(f)
require("web.web") -- initializes intl/web
-- Simulate insertGettext from web.lua
local intl = require("web.intl")
local gt = intl.load_gettext()
env.T = gt.gettext
env.N = gt.ngettext
env.gettext = gt
local t_type, n_type, gt_type, ngx_type = f()
print(string.format("  In .LP: type(T)=%s, type(N)=%s, type(gettext)=%s, type(ngx)=%s", t_type, n_type, gt_type, ngx_type))

print("\\n--- 2. INSIDE STANDALONE .LUA RUNTIME (BEFORE INTL / GETTEXT) ---")
print(string.format("  In standalone .LUA: type(_G.T)=%s, type(_G.N)=%s, type(_G.gettext)=%s, type(_G.ngx)=%s",
    type(_G.T), type(_G.N), type(_G.gettext), type(_G.ngx)))
"""

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Target Router: {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=probe_code.encode('utf-8'), capture_output=True, text=True)
    print(res.stdout.strip())
    if res.stderr:
        print("ERR:", res.stderr.strip())
