import subprocess
import json
import time
import requests

ROUTERS = {
    "DGA4331": "192.0.2.6",
    "DGA4132": "192.0.2.3",
    "TG789":   "192.0.2.7",
}

def run_ssh(ip, cmd):
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", f"root@{ip}", cmd],
                         capture_output=True, text=True)
    return res.returncode, res.stdout, res.stderr

def scp_file(local_path, ip, remote_path):
    res = subprocess.run(["scp", "-o", "StrictHostKeyChecking=no", local_path, f"root@{ip}:{remote_path}"],
                         capture_output=True, text=True)
    return res.returncode == 0

def main():
    print("=== STEP 1: DEPLOY UPDATED FILES TO ALL 3 ROUTERS ===")
    files_to_deploy = [
        ("decompressed/gui_file/www/docroot/ajax/dashboard_sync.lua", "/www/docroot/ajax/dashboard_sync.lua"),
        ("decompressed/gui_file/www/docroot/modals/mmpbx-dect-modal.lp", "/www/docroot/modals/mmpbx-dect-modal.lp"),
    ]
    
    for name, ip in ROUTERS.items():
        print(f"\nDeploying to {name} ({ip})...")
        for local_file, remote_file in files_to_deploy:
            ok = scp_file(local_file, ip, remote_file)
            print(f"  SCP {local_file} -> {remote_file}: {'OK' if ok else 'FAIL'}")
        
        # Restart nginx to reload bytecode / cache
        rc, out, err = run_ssh(ip, "/etc/init.d/nginx restart")
        print(f"  Nginx restart on {name}: rc={rc}")

    print("\n=== STEP 2: TEST DASHBOARD_SYNC (ANONYMOUS VS AUTHENTICATED) ===")
    for name, ip in ROUTERS.items():
        url = f"http://{ip}/ajax/dashboard_sync.lua?modules=all"
        # 1. Anonymous request
        r_anon = requests.get(url, timeout=5)
        print(f"[{name}] Anonymous GET /ajax/dashboard_sync.lua?modules=all -> HTTP {r_anon.status_code}, Body: {r_anon.text.strip()}")
        
        # 2. Get session cookie for admin
        s = requests.Session()
        # Login or use SRP/direct session creation on router
        # Let's create an admin session via test script on router
        sess_cmd = "lua -e 'local sm = require(\"web.sessionmgr\"); local s = sm.newSession(); s.user = {name=\"admin\", role=\"admin\"}; print(s.id)'"
        rc, sess_id, _ = run_ssh(ip, sess_cmd)
        sess_id = sess_id.strip()
        
        r_admin = requests.get(url, cookies={"session_id": sess_id}, timeout=5)
        print(f"[{name}] Admin GET /ajax/dashboard_sync.lua?modules=all -> HTTP {r_admin.status_code}, Size: {len(r_admin.text)} bytes")
        try:
            data = r_admin.json()
            print(f"[{name}] Admin JSON modules returned: {list(data.keys())}")
        except Exception as e:
            print(f"[{name}] JSON decode error: {e}")

    print("\n=== STEP 3: TEST HIDDEN CARDS (011_datausage, 015_iproutes, 018_relaysetup) ===")
    for name, ip in ROUTERS.items():
        print(f"\n--- Testing Hidden Cards on {name} ({ip}) ---")
        # 1. Check baseline card count
        sess_cmd = "lua -e 'local sm = require(\"web.sessionmgr\"); local s = sm.newSession(); s.user = {name=\"admin\", role=\"admin\"}; print(s.id)'"
        rc, sess_id, _ = run_ssh(ip, sess_cmd)
        sess_id = sess_id.strip()
        
        r_cards_before = requests.get(f"http://{ip}/cards.lp", cookies={"session_id": sess_id}, timeout=5)
        count_before = r_cards_before.text.count('class="smallcard"')
        print(f"  Cards visible BEFORE unhiding: {count_before}")
        
        # 2. Unhide datausage, iproutes, relaysetup
        unhide_cmd = """
        uci set web.card_datausage.hide='0' 2>/dev/null || uci set web.datausage.hide='0' 2>/dev/null
        uci set web.card_iproutes.hide='0' 2>/dev/null || uci set web.iproutes.hide='0' 2>/dev/null
        uci set web.card_relaysetup.hide='0' 2>/dev/null || uci set web.relaysetup.hide='0' 2>/dev/null
        uci commit web
        """
        run_ssh(ip, unhide_cmd)
        
        # 3. Request cards.lp again
        r_cards_unhidden = requests.get(f"http://{ip}/cards.lp", cookies={"session_id": sess_id}, timeout=5)
        count_unhidden = r_cards_unhidden.text.count('class="smallcard"')
        print(f"  Cards visible AFTER unhiding: {count_unhidden}")
        
        # Check presence of specific card texts
        has_datausage = "Data Usage" in r_cards_unhidden.text or "datausage" in r_cards_unhidden.text
        has_iproutes = "Routing" in r_cards_unhidden.text or "iproutes" in r_cards_unhidden.text or "IPv4 Routes" in r_cards_unhidden.text
        has_relaysetup = "PPPoE Relay" in r_cards_unhidden.text or "relaysetup" in r_cards_unhidden.text
        print(f"  Datausage card rendered: {has_datausage}")
        print(f"  IPRoutes card rendered: {has_iproutes}")
        print(f"  RelaySetup card rendered: {has_relaysetup}")
        
        # 4. Check logread for errors during card rendering
        rc, log_out, _ = run_ssh(ip, "logread | grep -E 'nginx.*(error|attempt to|stack traceback)' | tail -n 10")
        print(f"  Logread error check: {log_out.strip() if log_out.strip() else '0 errors (CLEAN)'}")
        
        # 5. Restore original UCI settings
        hide_cmd = """
        uci set web.card_datausage.hide='1' 2>/dev/null || uci set web.datausage.hide='1' 2>/dev/null
        uci set web.card_iproutes.hide='1' 2>/dev/null || uci set web.iproutes.hide='1' 2>/dev/null
        uci set web.card_relaysetup.hide='1' 2>/dev/null || uci set web.relaysetup.hide='1' 2>/dev/null
        uci commit web
        """
        run_ssh(ip, hide_cmd)
        
        # 6. Verify restored count
        r_cards_restored = requests.get(f"http://{ip}/cards.lp", cookies={"session_id": sess_id}, timeout=5)
        count_restored = r_cards_restored.text.count('class="smallcard"')
        print(f"  Cards visible AFTER restoring: {count_restored}")

    print("\n=== STEP 4: TEST isFeatureEnabled & ROLE MATRIX (ADMIN vs ENGINEER vs GUEST) ===")
    for name, ip in ROUTERS.items():
        print(f"\n--- Feature Matrix on {name} ({ip}) ---")
        cmd_feat = """lua -e '
        local proxy = require("datamodel")
        local ph = require("web.post_helper")
        
        local feats = {"noCardBackgroundIcons", "bandsteerDisabled", "custom_feature"}
        for _, f in ipairs(feats) do
            print("Feature:", f)
            print("  roles in uci:", json and json.encode(proxy.get("uci.web.feature.@"..f..".")) or "nil")
            print("  role=admin:   ", ph.isFeatureEnabled(f, "admin"))
            print("  role=engineer:", ph.isFeatureEnabled(f, "engineer"))
            print("  role=guest:   ", ph.isFeatureEnabled(f, "guest"))
            print("  role=nil (old):", ph.isFeatureEnabled(f, nil))
        end
        '"""
        rc, out, err = run_ssh(ip, cmd_feat)
        print(out)

    print("\n=== STEP 5: DECT BASE NAME VALIDATION TEST ===")
    # Test rendered HTML input tag in mmpbx-dect-modal.lp
    for name, ip in ROUTERS.items():
        sess_cmd = "lua -e 'local sm = require(\"web.sessionmgr\"); local s = sm.newSession(); s.user = {name=\"admin\", role=\"admin\"}; print(s.id)'"
        rc, sess_id, _ = run_ssh(ip, sess_cmd)
        r_dect = requests.get(f"http://{ip}/modals/mmpbx-dect-modal.lp", cookies={"session_id": sess_id.strip()}, timeout=5)
        
        # Extract baseName input HTML
        for line in r_dect.text.splitlines():
            if "name=\"baseName\"" in line or "id=\"baseName\"" in line:
                print(f"[{name}] baseName HTML: {line.strip()}")

if __name__ == "__main__":
    main()
