#!/usr/bin/env python3
import re
import subprocess

print("=== 1. JS / ECMA-262 REGEX BEHAVIOR ANALYSIS ===")
old_pattern = r'^([a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?.)+[a-zA-Z]{2,6}$'
new_pattern = r'^([a-zA-Z]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6}$'

old_re = re.compile(old_pattern)
new_re = re.compile(new_pattern)

test_cases = [
    ("sip.tim.it", "Valid FQDN with literal dots"),
    ("sipxtimxit", "Invalid name without dots (dots replaced by 'x')"),
    ("abcdefgh", "Invalid plain name with no dots"),
    ("sub.domain.com", "Valid FQDN with subdomains"),
    ("subxdomainxcom", "Invalid name with 'x' instead of dots"),
    ("invalid_char.com", "Invalid character '_' in hostname"),
]

for tc, desc in test_cases:
    old_m = bool(old_re.match(tc))
    new_m = bool(new_re.match(tc))
    print(f"Input: {tc:<18} | Old (unescaped '.'): {'PASS (false positive)' if old_m else 'FAIL'} | New (escaped '\\.'): {'PASS (valid)' if new_m else 'FAIL (rejected)'} | {desc}")

print("\n=== 2. EMITTED HTML ATTRIBUTE VERIFICATION ACROSS ROUTERS ===")
routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

for name, ip in routers:
    get_cookie = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
    c_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", get_cookie], capture_output=True, text=True)
    cookie = c_res.stdout.strip()
    
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f'curl -k -s -H "Cookie: sessionID={cookie}" https://127.0.0.1/modals/mmpbx-dect-modal.lp'], capture_output=True, text=True)
    html = res.stdout
    
    lines = [line.strip() for line in html.splitlines() if "baseName" in line]
    print(f"\n[*] {name} ({ip}):")
    print(f"  Modal response length: {len(html)} bytes")
    for l in lines:
        print(f"  Line: {l}")
