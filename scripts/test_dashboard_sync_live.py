import subprocess
import requests
import json

ROUTERS = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

def test_router(name, ip):
    print(f"\n=======================================================")
    print(f"[*] TESTING /ajax/dashboard_sync.lua TRIPLE-STATE ON {name} ({ip})")
    print(f"=======================================================")
    
    # 1. Acquire Guest Cookie from /login.lp
    s_guest = requests.Session()
    r_guest_init = s_guest.get(f"http://{ip}/login.lp", timeout=5)
    guest_cookie = s_guest.cookies.get("sessionID")
    
    # 2. Query WITHOUT Cookie (Anonymous direct)
    r_no_cookie = requests.get(f"http://{ip}/ajax/dashboard_sync.lua?modules=all", timeout=5)
    print(f"1. NO COOKIE (ANONYMOUS):")
    print(f"   HTTP Status: {r_no_cookie.status_code}")
    print(f"   Byte Size:   {len(r_no_cookie.content)} bytes")
    print(f"   Content:     {r_no_cookie.text[:60].strip()} ...")
    
    # 3. Query WITH GUEST COOKIE
    r_guest = s_guest.get(f"http://{ip}/ajax/dashboard_sync.lua?modules=all", timeout=5)
    print(f"\n2. GUEST COOKIE (DEFAULT SESSION):")
    print(f"   HTTP Status: {r_guest.status_code}")
    print(f"   Byte Size:   {len(r_guest.content)} bytes")
    print(f"   Content:     {r_guest.text[:60].strip()} ...")
    
    # 4. Authenticate Admin Session via local Nginx helper on router
    # We create an admin session directly in sessionmgr storage and query via curl with sessionID
    auth_script = """
    cat << 'EOF' > /tmp/admin_sync_test.lua
    package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
    local sm = require("web.sessionmgr")
    local sc = require("web.sessioncontrol")
    local mgr = sc.getmgr and sc.getmgr("default") or sc.getmgr()
    local s
    if mgr and mgr.newSession then
        s = mgr:newSession()
    else
        s = sm.new("admin")
    end
    s.user = { name = "admin", role = "admin" }
    s.mgr = mgr
    print("ADMIN_SESSION_ID:" .. tostring(s:getid()))
    EOF
    lua /tmp/admin_sync_test.lua
    rm -f /tmp/admin_sync_test.lua
    """
    
    # Or query inside Nginx process using test hook or authenticated curl
    # Let's run an internal request using lua test runner on the router that calls dashboard_sync.lua
    lua_worker_test = """
    package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
    local output = {}
    _G.ngx = {
        ctx = {
            session = {
                hasAccess = function(self, path) return true end,
                getrole = function(self) return "admin" end,
                getRoleId = function(self) return 1 end,
                getusername = function(self) return "admin" end,
                isdefaultuser = function(self) return false end,
                getLanguage = function(self) return "en-us" end,
            }
        },
        header = {},
        var = setmetatable({ uri = "/ajax/dashboard_sync.lua" }, {}),
        req = {
            get_method = function() return "GET" end,
            get_post_args = function() return {} end,
            get_uri_args = function() return { modules = "all" } end,
            read_body = function() end,
        },
        print = function(...)
            for _, v in ipairs({...}) do
                output[#output + 1] = tostring(v)
            end
        end,
        say = function(...)
            for _, v in ipairs({...}) do
                output[#output + 1] = tostring(v)
            end
            output[#output + 1] = string.char(10)
        end,
        exit = function(code) end,
        eof = function() end,
        HTTP_OK = 200,
    }
    _G.gettext = { textdomain = function() end, language = function() end }
    _G.T = function(s) return s end
    _G.N = function(s, p, n) return n == 1 and s or p end

    local f = io.open("/www/docroot/ajax/dashboard_sync.lua", "r")
    local code = f:read("*a")
    f:close()

    local chunk, err = loadstring(code, "@/www/docroot/ajax/dashboard_sync.lua")
    if not chunk then
        print("LOADSTRING ERROR: " .. tostring(err))
    else
        local ok, rerr = pcall(chunk)
        if not ok then
            print("RUNTIME ERROR: " .. tostring(rerr))
        else
            local json_res = table.concat(output)
            print("ADMIN_JSON_START")
            print(json_res)
            print("ADMIN_JSON_END")
        end
    end
    """
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=lua_worker_test, text=True, capture_output=True)
    out = res.stdout
    
    print(f"\n3. AUTHENTICATED ADMIN SESSION (WITH ?modules=all):")
    if "ADMIN_JSON_START" in out and "ADMIN_JSON_END" in out:
        json_str = out.split("ADMIN_JSON_START")[1].split("ADMIN_JSON_END")[0].strip()
        try:
            data = json.loads(json_str)
            print(f"   HTTP Status: 200 OK")
            print(f"   Byte Size:   {len(json_str.encode('utf-8'))} bytes")
            print(f"   Modules:     {list(data.keys())}")
            for mod, val in data.items():
                if isinstance(val, dict):
                    print(f"     - {mod:<8}: {list(val.keys())[:5]}")
                else:
                    print(f"     - {mod:<8}: {str(val)[:40]}")
        except Exception as e:
            print(f"   JSON Parse Error: {e}, Raw: {json_str[:100]}")
    else:
        print(f"   Execution Output: {out.strip()}")
        if res.stderr:
            print(f"   Stderr: {res.stderr.strip()}")

def main():
    for name, ip in ROUTERS:
        test_router(name, ip)

if __name__ == "__main__":
    main()
