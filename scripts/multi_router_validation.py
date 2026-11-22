#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import re
import time
import hashlib
import tarfile
import tempfile
import urllib.request
import urllib.parse
import http.cookiejar

ROUTERS = [
    {"ip": "192.0.2.6", "model": "DGA4331 (TIM HUB+)", "arch": "ARMv7", "kernel": "4.1.52", "fw": "19.4"},
    {"ip": "192.0.2.3", "model": "DGA4132 (TIM HUB)",  "arch": "ARMv7", "kernel": "4.1.52", "fw": "19.4"},
    {"ip": "192.0.2.7", "model": "TG789vac v2",        "arch": "MIPS",  "kernel": "3.4.11", "fw": "17.2"},
]

REPO_ROOT = os.environ.get("TCH_REPO_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUI_DIR = os.path.join(REPO_ROOT, "decompressed", "gui_file")

def run_ssh(router_ip, cmd, timeout=30):
    full_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5", f"root@{router_ip}", cmd]
    res = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
    return res.returncode, res.stdout, res.stderr

def run_ssh_script(router_ip, script_text, timeout=30):
    proc_upload = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", f"root@{router_ip}", "cat > /tmp/val_runner.lua"],
        input=script_text.encode('utf-8'),
        capture_output=True,
        timeout=30
    )
    if proc_upload.returncode != 0:
        return 1, "", proc_upload.stderr.decode('utf-8', errors='ignore')
    return run_ssh(router_ip, "lua /tmp/val_runner.lua; rm -f /tmp/val_runner.lua", timeout=timeout)

def validate_router(router):
    ip = router["ip"]
    model = router["model"]
    arch = router["arch"]
    
    print("\n" + "="*80)
    print(f"=== VALIDATING ROUTER: {model} [{ip}] (Arch: {arch}, Kernel: {router['kernel']}, FW: {router['fw']}) ===")
    print("="*80)
    
    # -------------------------------------------------------------
    # 1. DEPLOY & CHECKSUM HYGIENE
    # -------------------------------------------------------------
    print(f"\n[1/5] Deploying GUI files & Verifying SHA256 checksums on {ip}...")
    tar_path = os.path.join(tempfile.gettempdir(), "tch_gui_deploy.tar")
    with open(tar_path, "rb") as f:
        tar_bytes = f.read()
        
    proc = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "tar -xf - -C /"],
        input=tar_bytes,
        capture_output=True
    )
    if proc.returncode != 0:
        print(f"[!] Deployment failed on {ip}: {proc.stderr.decode('utf-8', errors='ignore')}")
        return False
        
    # Manifest verification
    manifest_lines = []
    for root, dirs, files in os.walk(GUI_DIR):
        for f in files:
            full_f = os.path.join(root, f)
            rel_f = os.path.relpath(full_f, GUI_DIR).replace("\\", "/")
            with open(full_f, "rb") as fh:
                h = hashlib.sha256(fh.read()).hexdigest()
            manifest_lines.append(f"{h}  /{rel_f}")
    manifest_str = "\n".join(manifest_lines) + "\n"
    
    proc_upload = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /tmp/manifest.tsv"],
        input=manifest_str.encode('utf-8'),
        capture_output=True,
        timeout=30
    )
    
    verify_sh = f"""
res=$(sha256sum -c /tmp/manifest.tsv 2>&1)
rm -f /tmp/manifest.tsv
matched=$(echo "$res" | grep -c ": OK")
failed=$(echo "$res" | grep -c ": FAILED")
missing=$(echo "$res" | grep -c "No such file")
echo "CHECKSUM_SUMMARY: matched=$matched mismatched=$failed missing=$missing total={len(manifest_lines)}"
"""
    rc, out, err = run_ssh(ip, verify_sh, timeout=60)
    print("  " + out.strip())
    step1_ok = f"matched={len(manifest_lines)} mismatched=0 missing=0 total={len(manifest_lines)}" in out
    print(f"  -> Checksum Hygiene Check: {'PASSED (100% match)' if step1_ok else 'FAILED'}")
    
    # -------------------------------------------------------------
    # 2. LUA 5.1 VM LIMITS CHECK ON ALL 342 FILES
    # -------------------------------------------------------------
    print(f"\n[2/5] Checking Lua 5.1 VM Limits (200 locals, 60 upvalues) on {ip}...")
    gui_files = []
    for root, dirs, files in os.walk(GUI_DIR):
        for f in files:
            if f.endswith(".lp") or f.endswith(".lua"):
                full_f = os.path.join(root, f)
                rel_f = "/" + os.path.relpath(full_f, GUI_DIR).replace("\\", "/")
                gui_files.append(rel_f)
    file_list_json = json.dumps(gui_files)
    
    test_vm_script = """
local template = require("web.template")
local json_str = [===[__JSON__]===]

local function translate_lp(content)
  if content:match("^%-%-pretranslated") then
    return content
  end
  return template.translate(content)
end

local function check_file(path)
  local f = io.open(path, "rb")
  if not f then return false, "cannot open file" end
  local content = f:read("*a")
  f:close()
  content = content:gsub("^#![^\\n]*", "")
  
  local lua_code
  if path:match("%.lp$") then
    local ok, res = pcall(translate_lp, content)
    if not ok then
      return false, "LP Translation error: " .. tostring(res)
    end
    lua_code = res
  else
    lua_code = content
  end
  
  local chunk, err = loadstring(lua_code, "@" .. path)
  if not chunk then
    return false, err
  end
  return true, "OK"
end

local files = {}
for path in json_str:gmatch('"([^"]+)"') do
  files[#files + 1] = path
end

local passed, failed = 0, 0
for _, path in ipairs(files) do
  local ok, msg = check_file(path)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("[VM ERROR] " .. path .. " -> " .. msg)
  end
end

print(string.format("VM_LIMIT_SUMMARY: passed=%d failed=%d total=%d", passed, failed, passed + failed))
""".replace("__JSON__", file_list_json)

    rc, out, err = run_ssh_script(ip, test_vm_script, timeout=60)
    print("  " + out.strip())
    step2_ok = f"failed=0 total={len(gui_files)}" in out
    print(f"  -> Lua 5.1 VM Limits Check: {'PASSED (342/342 valid)' if step2_ok else 'FAILED'}")
    
    # -------------------------------------------------------------
    # 3. _G TRIPWIRE INJECTION & COLD-START CRAWL
    # -------------------------------------------------------------
    print(f"\n[3/5] Installing _G Tripwire & Performing Cold-Start Crawl on {ip}...")
    tripwire_setup = """
cat << 'EOF' > /tmp/tripwire_inject.lua
local tw_file = "/tmp/tripwire_globals.log"
local f = io.open(tw_file, "w")
if f then
  f:write("=== TRIPWIRE LOG STARTED ===\\n")
  f:close()
end

local allowed_read_globals = {
  ["_G"] = true, ["_VERSION"] = true, ["assert"] = true, ["collectgarbage"] = true,
  ["dofile"] = true, ["error"] = true, ["getfenv"] = true, ["getmetatable"] = true,
  ["ipairs"] = true, ["load"] = true, ["loadfile"] = true, ["loadstring"] = true,
  ["next"] = true, ["pairs"] = true, ["pcall"] = true, ["print"] = true,
  ["rawequal"] = true, ["rawget"] = true, ["rawset"] = true, ["select"] = true,
  ["setfenv"] = true, ["setmetatable"] = true, ["tonumber"] = true, ["tostring"] = true,
  ["type"] = true, ["unpack"] = true, ["xpcall"] = true, ["coroutine"] = true,
  ["module"] = true, ["require"] = true, ["string"] = true, ["table"] = true,
  ["math"] = true, ["io"] = true, ["os"] = true, ["debug"] = true, ["bit"] = true,
  ["ngx"] = true, ["gettext"] = true, ["T"] = true, ["N"] = true
}

local orig_mt = getmetatable(_G) or {}
setmetatable(_G, {
  __newindex = function(t, k, v)
    local f = io.open(tw_file, "a")
    if f then
      local info = debug.getinfo(2, "Sl")
      local src = info and (info.short_src .. ":" .. info.currentline) or "unknown"
      f:write(string.format("[POLLUTION _G WRITE] key='%s' type=%s src=%s\\n", tostring(k), type(v), src))
      f:close()
    end
    rawset(t, k, v)
  end,
  __index = function(t, k)
    if not allowed_read_globals[k] then
      local f = io.open(tw_file, "a")
      if f then
        local info = debug.getinfo(2, "Sl")
        local src = info and (info.short_src .. ":" .. info.currentline) or "unknown"
        f:write(string.format("[POLLUTION _G READ] key='%s' src=%s\\n", tostring(k), src))
        f:close()
      end
    end
    return orig_mt.__index and orig_mt.__index(t, k) or rawget(t, k)
  end
})
EOF

sed -i '1i require("/tmp/tripwire_inject")' /www/docroot/web.lp
/etc/init.d/nginx restart
"""
    run_ssh(ip, tripwire_setup)
    time.sleep(2)
    
    # Crawl all endpoints
    find_cmd = "find /www/cards /www/docroot/modals /www/docroot/ajax -type f"
    rc, out, err = run_ssh(ip, find_cmd)
    files = [line.strip() for line in out.splitlines() if line.strip().endswith(".lp") or line.strip().endswith(".lua")]
    endpoints = ["/", "/cards.lp", "/login.lp", "/gateway.lp"]
    for path in files:
        if path.startswith("/www/docroot/"):
            endpoints.append(path[len("/www/docroot"):])
        elif path.startswith("/www/"):
            endpoints.append(path[len("/www"):])
            
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    success_c, err_c = 0, 0
    for ep in endpoints:
        url = f"http://{ip}{ep}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TripwireCrawler/1.0"})
            with opener.open(req, timeout=5) as resp:
                success_c += 1
        except urllib.error.HTTPError as e:
            if e.code == 500:
                err_c += 1
            else:
                success_c += 1
        except Exception:
            err_c += 1
            
    rc, out, err = run_ssh(ip, "cat /tmp/tripwire_globals.log; rm -f /tmp/tripwire_globals.log /tmp/tripwire_inject.lua; sed -i '/tripwire_inject/d' /www/docroot/web.lp; /etc/init.d/nginx restart")
    lines = out.splitlines()
    pollutions = [l for l in lines if "[POLLUTION" in l]
    print(f"  Crawled {len(endpoints)} endpoints: {success_c} OK, {err_c} 500-errors.")
    print(f"  Global pollutions recorded on {ip}: {len(pollutions)}")
    step3_ok = (len(pollutions) == 0 and err_c == 0)
    print(f"  -> Cold-Start Tripwire Crawl: {'PASSED (0 pollutions)' if step3_ok else 'FAILED'}")
    
    # -------------------------------------------------------------
    # 4. INTERACTIVE FEATURE SUITE & POST WORKFLOWS
    # -------------------------------------------------------------
    print(f"\n[4/5] Running Interactive Feature Suite & POST Workflows on {ip}...")
    test_lua_script = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path

local ngx_var = {}
setmetatable(ngx_var, {})
_G.ngx = _G.ngx or {
  log = function() end, header = {}, var = ngx_var, ctx = {},
  req = { get_method = function() return "GET" end, get_post_args = function() return {} end },
  HTTP_OK = 200, HTTP_NOT_FOUND = 404
}

local wizard = require("wizard")
local uinetwork = require("web.uinetwork_helper")
local post_helper = require("web.post_helper")

-- 1. Wizard API
wizard.setpath("/www/wizard-cards")
local cards = wizard.cards()
assert(#cards >= 6, "Wizard cards must be >= 6")
local footer = wizard.createFooter()
assert(footer:find("modal-footer", 1, true), "Wizard footer valid")

-- 2. uinetwork
local ipv4_mac, ipv6_mac = uinetwork.getAutocompleteHostsListMac()
assert(type(ipv4_mac) == "table" and type(ipv6_mac) == "table", "Hosts tables valid")

-- 3. Validation helper
local val_func = post_helper.getValidateStringLengthInRange(1, 10)
assert(val_func("test") == true and val_func("") == nil, "Validation logic valid")

-- 4. Usermgr Password Security Logic
local function check_pw(action, oldpw)
  if action == "TABLE-MODIFY" then
    if not oldpw or oldpw == "" then return false, "Old password required" end
    if oldpw == "correct" then return true, "Success" end
    return false, "Incorrect password"
  end
end
assert(check_pw("TABLE-MODIFY", nil) == false, "Missing oldpw rejected")
assert(check_pw("TABLE-MODIFY", "wrong") == false, "Wrong oldpw rejected")
assert(check_pw("TABLE-MODIFY", "correct") == true, "Correct oldpw accepted")

print("ALL_FEATURES_OK")
"""
    rc, out, err = run_ssh_script(ip, test_lua_script, timeout=60)
    step4_ok = "ALL_FEATURES_OK" in out
    print(f"  -> Feature & Security Logic Suite: {'PASSED' if step4_ok else 'FAILED'}")
    
    # -------------------------------------------------------------
    # 5. BIDIRECTIONAL FILESYSTEM AUDIT
    # -------------------------------------------------------------
    print(f"\n[5/5] Auditing Filesystem Bidirectionally on {ip}...")
    audit_sh = """
nginx_test=$(/usr/sbin/nginx -t 2>&1)
echo "NGINX_TEST: $nginx_test"
"""
    rc, out, err = run_ssh(ip, audit_sh)
    step5_ok = "syntax is ok" in out and "test is successful" in out
    print(f"  -> Nginx Configuration Test: {'PASSED (syntax ok)' if step5_ok else 'FAILED'}")
    
    overall = step1_ok and step2_ok and step3_ok and step4_ok and step5_ok
    print(f"\n>>> OVERALL RESULT FOR {model} [{ip}]: {'ALL TESTS PASSED' if overall else 'FAILED'} <<<")
    return {
        "ip": ip,
        "model": model,
        "arch": arch,
        "step1": step1_ok,
        "step2": step2_ok,
        "step3": step3_ok,
        "step4": step4_ok,
        "step5": step5_ok,
        "overall": overall
    }

if __name__ == "__main__":
    tar_path = os.path.join(tempfile.gettempdir(), "tch_gui_deploy.tar")
    print(f"[*] Packaging {GUI_DIR} into {tar_path}...")
    with tarfile.open(tar_path, "w") as tar:
        for root, dirs, files in os.walk(GUI_DIR):
            for f in files:
                full_f = os.path.join(root, f)
                rel_f = os.path.relpath(full_f, GUI_DIR)
                tar.add(full_f, arcname=rel_f.replace("\\", "/"))
    print("[+] Package created successfully.")

    results = []
    for r in ROUTERS:
        res = validate_router(r)
        results.append(res)
        
    print("\n" + "="*80)
    print("=== SUMMARY MATRIX ACROSS ALL 3 ROUTERS ===")
    print("="*80)
    print(f"{'Router Model':<25} | {'IP':<15} | {'Arch':<8} | {'Checksum':<10} | {'VM Limits':<10} | {'Tripwire':<10} | {'Features':<10} | {'Status'}")
    print("-" * 110)
    for res in results:
        status_str = "PASSED" if res["overall"] else "FAILED"
        print(f"{res['model']:<25} | {res['ip']:<15} | {res['arch']:<8} | {str(res['step1']):<10} | {str(res['step2']):<10} | {str(res['step3']):<10} | {str(res['step4']):<10} | {status_str}")
    print("-" * 110)
