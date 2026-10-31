#!/usr/bin/env python3
import subprocess

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

print("=======================================================")
print("[*] 2x2 ROLE MATRIX & PERMISSION ENFORCEMENT TABLE")
print("=======================================================")

test_endpoints = [
    ("/cards.lp", "Cards Dashboard"),
    ("/modals/datausage.lp", "Data Usage Modal (78fa2fc3)"),
    ("/modals/easy-mesh-configuration.lp", "EasyMesh Config Modal (456ef1b4)"),
    ("/modals/parental-modal.lp", "Parental Modal (3d00b1d9)"),
    ("/modals/internet-modal.lp", "Internet Modal (08d66c38)"),
    ("/ajax/dashboard_sync.lua", "Dashboard Sync Ajax (Guest Allowed)"),
]

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Target Router: {name} ({ip})")
    print(f"=======================================================")
    
    # We test with anonymous/guest vs admin session
    # 1. Unauthenticated / Guest request (no cookie)
    # 2. Authenticated Admin request (valid admin cookie)
    
    # Create admin cookie via sessionmgr
    admin_cookie_cmd = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
    admin_cookie = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", admin_cookie_cmd], capture_output=True, text=True).stdout.strip()
    
    print(f"{'Endpoint':<38} | {'Admin (HEAD)':<16} | {'Guest/Anon (HEAD)':<18} | {'Access Control'}")
    print("-" * 95)
    
    for ep, desc in test_endpoints:
        # Admin request
        cmd_admin = f'curl -k -s -w "%{{http_code}} %{{size_download}}" -o /dev/null -H "Cookie: sessionID={admin_cookie}" https://127.0.0.1{ep}'
        res_admin = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", cmd_admin], capture_output=True, text=True).stdout.strip()
        admin_code, admin_bytes = res_admin.split() if " " in res_admin else ("???", "0")
        
        # Guest request (no cookie / guest role)
        cmd_guest = f'curl -k -s -w "%{{http_code}} %{{size_download}}" -o /dev/null https://127.0.0.1{ep}'
        res_guest = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", cmd_guest], capture_output=True, text=True).stdout.strip()
        guest_code, guest_bytes = res_guest.split() if " " in res_guest else ("???", "0")
        
        status = "ALLOWED (Admin) / RESTRICTED (Guest)" if (admin_code == "200" and guest_code != "200") else "MATCHED"
        if ep.startswith("/ajax/dashboard_sync"):
            status = "PUBLIC/SYNC (Allowed for both)"
            
        print(f"{ep:<38} | {admin_code} ({admin_bytes} B)".ljust(58) + f" | {guest_code} ({guest_bytes} B)".ljust(22) + f" | {status}")
