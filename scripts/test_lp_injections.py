#!/usr/bin/env python3
import subprocess

lp_content = """--pretranslated: do not change this file
ngx.header['Content-Type'] = 'text/plain'
ngx.print("type(ui_helper) = " .. tostring(type(ui_helper)) .. "\\n")
ngx.print("type(post_helper) = " .. tostring(type(post_helper)) .. "\\n")
ngx.print("type(content_helper) = " .. tostring(type(content_helper)) .. "\\n")
ngx.print("type(proxy) = " .. tostring(type(proxy)) .. "\\n")
ngx.print("type(session) = " .. tostring(type(session)) .. "\\n")
ngx.print("type(T) = " .. tostring(type(T)) .. "\\n")
ngx.print("type(N) = " .. tostring(type(N)) .. "\\n")
ngx.print("type(gettext) = " .. tostring(type(gettext)) .. "\\n")
ngx.print("type(ngx) = " .. tostring(type(ngx)) .. "\\n")
"""

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Testing LP Injections on {name} ({ip})")
    print(f"=======================================================")
    
    # 1. Upload test file to /www/docroot/test_types.lp
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /www/docroot/test_types.lp"], input=lp_content.encode('utf-8'), check=True)
    
    # 2. Request without session (public/anonymous)
    res_unauth = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "curl -k -s https://127.0.0.1/test_types.lp"], capture_output=True, text=True)
    print("--- WITHOUT SESSION (Anonymous GET /test_types.lp) ---")
    print(res_unauth.stdout.strip())
    
    # 3. Request with authenticated session
    # Create an admin session via sessionmgr and make request with Cookie
    create_session_cmd = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
    cookie_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", create_session_cmd], capture_output=True, text=True)
    cookie = cookie_res.stdout.strip()
    
    res_auth = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f'curl -k -s -H "Cookie: sessionid={cookie}" https://127.0.0.1/test_types.lp'], capture_output=True, text=True)
    print("\n--- WITH SESSION (Authenticated GET /test_types.lp) ---")
    print(res_auth.stdout.strip())
    
    # 4. Clean up
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "rm -f /www/docroot/test_types.lp"], check=True)
