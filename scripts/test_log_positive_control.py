#!/usr/bin/env python3
import subprocess
import time

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

print("===================================================================")
print("[*] 1. PRODUCING REAL LUA ERROR IN NGINX (.lp) & VERIFYING SYSLOG")
print("===================================================================")

for name, ip in routers:
    print(f"\n--- Target Router: {name} ({ip}) ---")
    
    # 1. Fetch current login.lp
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat /www/docroot/login.lp"], capture_output=True, text=True, check=True)
    orig_login = res.stdout
    
    # 2. Inject error trigger at the very top (after pretranslated line)
    injected_login = orig_login.replace("--pretranslated: do not change this file", "--pretranslated: do not change this file\nif ngx.req.get_uri_args().provoke_err == '1' then error('REAL_LUA_NGINX_ERROR_POSITIVE_CONTROL') end", 1)
    
    # 3. Upload modified login.lp and restart/reload Nginx to clear LP cache
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /www/docroot/login.lp"], input=injected_login.encode('utf-8'), check=True)
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "/etc/init.d/nginx restart"], check=True)
    time.sleep(1)
    
    try:
        # 4. Trigger error via HTTP request
        res_http = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "curl -k -s -w '%{http_code}' -o /dev/null 'https://127.0.0.1/login.lp?provoke_err=1'"], capture_output=True, text=True)
        http_code = res_http.stdout.strip()
        print(f"  HTTP Trigger Response Code: {http_code} (Expected: 500)")
        
        # 5. Check syslog / logread for the exact Nginx Lua error log
        res_log = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "logread | grep REAL_LUA_NGINX_ERROR_POSITIVE_CONTROL | tail -n 1"], capture_output=True, text=True)
        log_line = res_log.stdout.strip()
        print(f"  Syslog capture from Nginx: {log_line}")
        assert "REAL_LUA_NGINX_ERROR_POSITIVE_CONTROL" in log_line, f"Error not found in syslog on {name}!"
        print(f"  [PASS] Real Nginx Lua error caught by syslog pipeline on {name}!")
    finally:
        # 6. Restore original login.lp and restart Nginx
        subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /www/docroot/login.lp"], input=orig_login.encode('utf-8'), check=True)
        subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "/etc/init.d/nginx restart"], check=True)
        time.sleep(1)

print("\n===================================================================")
print("[*] 2. LOGREAD RING BUFFER CAPACITY & ROTATION CHECK DURING CRAWL")
print("===================================================================")

for name, ip in routers:
    print(f"\n--- Checking Ring Buffer on {name} ({ip}) ---")
    
    # 1. Insert start marker in syslog
    marker = f"START_CRAWL_MARKER_{int(time.time())}"
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f"logger -p daemon.info -t crawl '{marker}'"], check=True)
    
    # 2. Perform crawl of all endpoints
    crawl_script = """
    COOKIE=$(lua -e 'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())')
    for f in $(find /www/cards /www/docroot/modals /www/docroot/ajax -type f -name "*.lp" -o -name "*.lua"); do
        ep=${f#/www/docroot}
        [ "$ep" = "$f" ] && ep=${f#/www}
        curl -k -s -o /dev/null -H "Cookie: sessionID=$COOKIE" "https://127.0.0.1$ep"
    done
    """
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", crawl_script], check=True)
    
    # 3. Check if start marker is STILL in logread (proving ring buffer did NOT rotate)
    check_marker = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f"logread | grep '{marker}'"], capture_output=True, text=True)
    marker_found = marker in check_marker.stdout
    print(f"  Start marker present in logread post-crawl: {marker_found}")
    assert marker_found, f"Ring buffer rotated on {name}!"
    
    # 4. Check for Lua errors during crawl
    err_check = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", f"logread | grep -E 'attempt to|stack traceback|lua entry thread aborted' | grep -v 'POSITIVE_CONTROL' | wc -l"], capture_output=True, text=True)
    err_count = int(err_check.stdout.strip())
    print(f"  Lua runtime errors during full crawl: {err_count}")
    assert err_count == 0, f"Errors found during crawl on {name}!"
    print(f"  [PASS] Crawl completed on {name} with 0 buffer rotation and 0 runtime errors.")
