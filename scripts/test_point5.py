#!/usr/bin/env python3
import subprocess

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

print("=======================================================")
print("[*] POINT 5: POSITIVE CONTROL FOR NGINX ERROR LOGGING")
print("=======================================================")

for name, ip in routers:
    print(f"\n--- Checking {name} ({ip}) ---")
    # 1. Check nginx.conf
    conf_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "grep error_log /etc/nginx/nginx.conf"], capture_output=True, text=True)
    print("  Nginx error_log config:", conf_res.stdout.strip())
    
    # 2. Test direct emission to daemon.err syslog facility (used by Nginx)
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "logger -p daemon.err -t nginx 'TEST_POSITIVE_CONTROL_ERROR_AUDIT'"], check=True)
    
    # 3. Read back from logread
    log_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "logread | grep TEST_POSITIVE_CONTROL_ERROR_AUDIT | tail -n 1"], capture_output=True, text=True)
    print("  Syslog logread capture:", log_res.stdout.strip())
    assert "TEST_POSITIVE_CONTROL_ERROR_AUDIT" in log_res.stdout, f"Error not found in logread on {name}!"
    print("  [PASS] Syslog pipeline active and capturing daemon.err messages.")

print("\n=======================================================")
print("[*] POINT 5: CARDS.LP TOTAL CARD AUDIT")
print("=======================================================")

for name, ip in routers:
    get_cookie = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
    c_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", get_cookie], capture_output=True, text=True)
    cookie = c_res.stdout.strip()
    
    # Request cards.lp
    res_cards = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f'curl -k -s -H "Cookie: sessionID={cookie}" https://127.0.0.1/cards.lp'], capture_output=True, text=True)
    cards_html = res_cards.stdout
    
    # Find all card headers / titles in cards.lp
    import re
    card_titles = re.findall(r'<h[0-9][^>]*>(.*?)</h[0-9]>|<div class="header-title[^"]*"><p>(.*?)</p>', cards_html)
    titles = [t[0] or t[1] for t in card_titles if (t[0] or t[1])]
    
    print(f"\n[*] {name} ({ip}):")
    print(f"  Total /cards.lp response length: {len(cards_html)} bytes")
    print(f"  Total rendered card titles ({len(titles)}): {titles[:10]} ...")
    
    # Check nginx error log during crawl
    log_check = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "logread | grep -E 'attempt to|stack traceback|lua entry thread aborted' | wc -l"], capture_output=True, text=True)
    print(f"  Lua runtime error count in logread: {log_check.stdout.strip()} (Must be 0)")
    assert int(log_check.stdout.strip()) == 0, f"Lua runtime errors detected on {name}!"
