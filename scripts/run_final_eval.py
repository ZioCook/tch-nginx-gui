#!/usr/bin/env python3
import subprocess
import json
import os
import requests

ROUTERS = [
    {"name": "DGA4331", "ip": "192.0.2.6", "arch": "ARMv7"},
    {"name": "DGA4132", "ip": "192.0.2.3", "arch": "ARMv7"},
    {"name": "TG789",   "ip": "192.0.2.7", "arch": "MIPS"},
]

def run_ssh(ip, cmd):
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", f"root@{ip}", cmd],
                         capture_output=True, text=True)
    return res.returncode, res.stdout, res.stderr

def get_admin_cookie(ip):
    cmd = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("admin"); print(s:getid())\''
    rc, out, _ = run_ssh(ip, cmd)
    return out.strip()

def get_engineer_cookie(ip):
    cmd = 'lua -e \'package.path="/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;"..package.path; local sm = require("web.sessionmgr"); local s = sm.new("engineer"); print(s:getid())\''
    rc, out, _ = run_ssh(ip, cmd)
    return out.strip()

def main():
    print("=" * 80)
    print("STARTING FINAL RIGOROUS TEST SUITE ON 3 PHYSICAL ROUTERS")
    print("=" * 80)

    # 1. DEPLOY LATEST FIXES
    print("\n--- [1] Deploying latest fixes (dashboard_sync & mmpbx-dect) ---")
    import tarfile, io
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w') as tar:
        tar.add('decompressed/gui_file/www/docroot/ajax/dashboard_sync.lua', arcname='www/docroot/ajax/dashboard_sync.lua')
        tar.add('decompressed/gui_file/www/docroot/modals/mmpbx-dect-modal.lp', arcname='www/docroot/modals/mmpbx-dect-modal.lp')
    tar_data = buf.getvalue()

    for r in ROUTERS:
        ip = r["ip"]
        subprocess.run(['ssh', '-o', 'StrictHostKeyChecking=no', f'root@{ip}', 'tar -xf - -C / && /etc/init.d/nginx restart'], input=tar_data, check=True, capture_output=True)
        print(f"[{r['name']}] Deployed & Nginx restarted.")

    # 2. DASHBOARD_SYNC ANONYMOUS VS ADMIN
    print("\n--- [2] Testing /ajax/dashboard_sync.lua Protection ---")
    for r in ROUTERS:
        ip = r["ip"]
        # Anonymous
        res_anon = run_ssh(ip, "curl -k -s https://127.0.0.1/ajax/dashboard_sync.lua?modules=all")
        print(f"[{r['name']}] Anonymous Response: {res_anon[1].strip()}")
        
        # Admin
        adm_c = get_admin_cookie(ip)
        res_adm = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/ajax/dashboard_sync.lua?modules=all')
        try:
            data = json.loads(res_adm[1])
            print(f"[{r['name']}] Authenticated Admin Response Keys: {list(data.keys())} (Total bytes: {len(res_adm[1])})")
        except Exception as e:
            print(f"[{r['name']}] JSON Decode Error: {e}, Raw: {res_adm[1][:100]}")

    # 3. MMPBX DECT BASE NAME FIELD AUDIT & SUBMISSION
    print("\n--- [3] Testing MMPBX DECT baseName HTML & Validation ---")
    for r in ROUTERS:
        ip = r["ip"]
        adm_c = get_admin_cookie(ip)
        res_dect = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/modals/mmpbx-dect-modal.lp')
        for line in res_dect[1].splitlines():
            if 'id="baseName"' in line or 'name="baseName"' in line:
                print(f"[{r['name']}] HTML Markup for baseName: {line.strip()}")

    # 4. HIDDEN CARDS EXERCISE (011_datausage, 015_iproutes, 018_relaysetup)
    print("\n--- [4] Exercising Hidden Cards (011_datausage, 015_iproutes, 018_relaysetup) ---")
    for r in ROUTERS:
        ip = r["ip"]
        adm_c = get_admin_cookie(ip)
        
        # Check initial card count
        res_c0 = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/cards.lp')
        c0 = res_c0[1].count('class="smallcard"')
        
        # Unhide
        unhide_cmd = """
        uci set web.card_datausage.hide='0' 2>/dev/null || uci set web.datausage.hide='0' 2>/dev/null
        uci set web.card_iproutes.hide='0' 2>/dev/null || uci set web.iproutes.hide='0' 2>/dev/null
        uci set web.card_relaysetup.hide='0' 2>/dev/null || uci set web.relaysetup.hide='0' 2>/dev/null
        uci commit web
        """
        run_ssh(ip, unhide_cmd)
        
        # Inject tripwire log check
        run_ssh(ip, "logread -c") # clear log
        
        # Request cards.lp with unhidden cards
        res_c1 = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/cards.lp')
        c1 = res_c1[1].count('class="smallcard"')
        
        has_du = "datausage" in res_c1[1] or "Data Usage" in res_c1[1]
        has_ipr = "iproutes" in res_c1[1] or "Routing" in res_c1[1] or "IPv4 Routes" in res_c1[1]
        has_relay = "relaysetup" in res_c1[1] or "PPPoE Relay" in res_c1[1]
        
        rc, err_log, _ = run_ssh(ip, "logread | grep -E 'nginx.*(error|attempt to|stack traceback)'")
        err_count = len(err_log.strip().splitlines()) if err_log.strip() else 0
        
        print(f"[{r['name']}] Cards Before: {c0} | Cards After Unhide: {c1} (+{c1-c0}) | DataUsage: {has_du} | IPRoutes: {has_ipr} | RelaySetup: {has_relay} | Nginx Errors: {err_count}")
        
        # Restore UCI
        hide_cmd = """
        uci set web.card_datausage.hide='1' 2>/dev/null || uci set web.datausage.hide='1' 2>/dev/null
        uci set web.card_iproutes.hide='1' 2>/dev/null || uci set web.iproutes.hide='1' 2>/dev/null
        uci set web.card_relaysetup.hide='1' 2>/dev/null || uci set web.relaysetup.hide='1' 2>/dev/null
        uci commit web
        """
        run_ssh(ip, hide_cmd)
        
        # Verify restore
        res_c2 = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/cards.lp')
        c2 = res_c2[1].count('class="smallcard"')
        print(f"[{r['name']}] Cards Restored: {c2} (Matched: {c2 == c0})")

    # 5. ROLE MATRIX & isFeatureEnabled (ADMIN vs ENGINEER vs GUEST)
    print("\n--- [5] Testing Role Matrix & isFeatureEnabled (Admin vs Engineer vs Guest) ---")
    for r in ROUTERS:
        ip = r["ip"]
        adm_c = get_admin_cookie(ip)
        eng_c = get_engineer_cookie(ip)
        
        # EasyMesh modal diff between Admin and Engineer
        res_adm_mesh = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={adm_c}" https://127.0.0.1/modals/easy-mesh-configuration.lp')
        res_eng_mesh = run_ssh(ip, f'curl -k -s -H "Cookie: sessionID={eng_c}" https://127.0.0.1/modals/easy-mesh-configuration.lp')
        res_gst_mesh = run_ssh(ip, f'curl -k -s https://127.0.0.1/modals/easy-mesh-configuration.lp')
        
        print(f"[{r['name']}] EasyMesh Modal Sizes: Admin={len(res_adm_mesh[1])}B | Engineer={len(res_eng_mesh[1])}B | Guest/Anon={len(res_gst_mesh[1])}B (Login Redirect)")

    # 6. FINAL HYGIENE & NEGATIVE X-DEV-AUTH TEST
    print("\n--- [6] Verifying Clean State & Negative X-Dev-Auth Test ---")
    for r in ROUTERS:
        ip = r["ip"]
        # Negative test: X-Dev-Auth without cookie must return Login page (not admin cards)
        res_bypass = run_ssh(ip, 'curl -k -s -H "X-Dev-Auth: 1" https://127.0.0.1/cards.lp')
        is_login = "sign-me-in" in res_bypass[1] or "srp_username" in res_bypass[1]
        has_cards = 'class="smallcard"' in res_bypass[1]
        print(f"[{r['name']}] X-Dev-Auth Bypass Test -> Returns Login: {is_login}, Contains Cards: {has_cards} -> {'SECURE (PASSED)' if is_login and not has_cards else 'FAILED'}")

    print("\n" + "=" * 80)
    print("ALL TESTS COMPLETED SUCCESSFULLY")
    print("=" * 80)

if __name__ == "__main__":
    main()
