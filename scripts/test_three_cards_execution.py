#!/usr/bin/env python3
import subprocess
import json

ROUTERS = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

lua_tester = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path

local output = {}
_G.ngx = {
    ctx = {
        session = {
            hasAccess = function(self, path) return true end,
            getrole = function(self) return "admin" end,
            getRoleId = function(self) return 1 end,
            getLanguage = function(self) return "en-us" end,
        }
    },
    req = {
        get_method = function() return "GET" end,
        get_post_args = function() return {} end,
        get_uri_args = function() return {} end,
        read_body = function() end,
    },
    header = {},
    var = setmetatable({}, {}),
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
}
_G.gettext = { textdomain = function() end, language = function() end }
_G.T = function(s) return s end
_G.N = function(s, p, n) return n == 1 and s or p end

local function run_test()
    local dm = require("datamodel")
    local post_helper = require("web.post_helper")
    local content_helper = require("web.content_helper")
    local ui_helper = require("web.ui_helper")
    local template = require("web.template")
    
    local results = {}
    
    -- 1. Test 011_datausage.lp
    local f_du = io.open("/www/cards/011_datausage.lp", "r")
    local content_du = f_du:read("*a")
    f_du:close()
    
    local lua_du = content_du:gsub("^#![^\\n]*", "")
    if not lua_du:match("^%-%-pretranslated") then
        lua_du = template.translate(lua_du)
    end
    
    local chunk_du, err_du = loadstring(lua_du, "@/www/cards/011_datausage.lp")
    if not chunk_du then
        results["011_datausage"] = { status = "COMPILE_ERROR", error = err_du }
    else
        output = {}
        local ok, exec_err = pcall(chunk_du)
        local html = table.concat(output)
        results["011_datausage"] = {
            status = ok and "OK" or "EXEC_ERROR",
            error = tostring(exec_err),
            html_bytes = #html,
            has_datausage_text = html:find("Data Usage") ~= nil,
            has_bg_icon = html:find("card_bg") ~= nil or html:find("content") ~= nil
        }
    end
    
    -- 2. Test 015_iproutes.lp
    local f_ipr = io.open("/www/cards/015_iproutes.lp", "r")
    local content_ipr = f_ipr:read("*a")
    f_ipr:close()
    
    local lua_ipr = content_ipr:gsub("^#![^\\n]*", "")
    if not lua_ipr:match("^%-%-pretranslated") then
        lua_ipr = template.translate(lua_ipr)
    end
    
    local chunk_ipr, err_ipr = loadstring(lua_ipr, "@/www/cards/015_iproutes.lp")
    if not chunk_ipr then
        results["015_iproutes"] = { status = "COMPILE_ERROR", error = err_ipr }
    else
        output = {}
        local ok, exec_err = pcall(chunk_ipr)
        local html = table.concat(output)
        results["015_iproutes"] = {
            status = ok and "OK" or "EXEC_ERROR",
            error = tostring(exec_err),
            html_bytes = #html,
            has_ip_extras = html:find("IP Extras") ~= nil,
            has_routes = html:find("Route") ~= nil
        }
    end
    
    -- 3. Test 018_relaysetup.lp
    local f_rl = io.open("/www/cards/018_relaysetup.lp", "r")
    local content_rl = f_rl:read("*a")
    f_rl:close()
    
    local lua_rl = content_rl:gsub("^#![^\\n]*", "")
    if not lua_rl:match("^%-%-pretranslated") then
        lua_rl = template.translate(lua_rl)
    end
    
    local chunk_rl, err_rl = loadstring(lua_rl, "@/www/cards/018_relaysetup.lp")
    if not chunk_rl then
        results["018_relaysetup"] = { status = "COMPILE_ERROR", error = err_rl }
    else
        output = {}
        local ok, exec_err = pcall(chunk_rl)
        local html = table.concat(output)
        results["018_relaysetup"] = {
            status = ok and "OK" or "EXEC_ERROR",
            error = tostring(exec_err),
            html_bytes = #html,
            has_relay_setup = html:find("Relay Setup") ~= nil,
            has_pppoe = html:find("PPPoE Relay") ~= nil
        }
    end
    
    -- 4. Test isFeatureEnabled logic (Admin vs Engineer vs Guest vs Nil)
    results["isFeatureEnabled_matrix"] = {
        noCardBackgroundIcons = {
            admin = post_helper.isFeatureEnabled("noCardBackgroundIcons", "admin"),
            engineer = post_helper.isFeatureEnabled("noCardBackgroundIcons", "engineer"),
            guest = post_helper.isFeatureEnabled("noCardBackgroundIcons", "guest"),
            ["nil"] = post_helper.isFeatureEnabled("noCardBackgroundIcons", nil),
        },
        bandsteerDisabled = {
            admin = post_helper.isFeatureEnabled("bandsteerDisabled", "admin"),
            engineer = post_helper.isFeatureEnabled("bandsteerDisabled", "engineer"),
            guest = post_helper.isFeatureEnabled("bandsteerDisabled", "guest"),
            ["nil"] = post_helper.isFeatureEnabled("bandsteerDisabled", nil),
        }
    }
    
    -- Serialize results to JSON
    local json = require("dkjson")
    print("TEST_RESULTS_JSON_START")
    print(json.encode(results))
    print("TEST_RESULTS_JSON_END")
end

run_test()
"""

for name, ip in ROUTERS:
    print(f"\n=======================================================")
    print(f"[*] Testing 3 Hidden Cards & Feature Matrix on {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"],
                         input=lua_tester, capture_output=True, text=True)
    out = res.stdout
    if "TEST_RESULTS_JSON_START" in out and "TEST_RESULTS_JSON_END" in out:
        json_str = out.split("TEST_RESULTS_JSON_START")[1].split("TEST_RESULTS_JSON_END")[0].strip()
        data = json.loads(json_str)
        print(json.dumps(data, indent=2))
    else:
        print("Raw output:", out)
        print("Error output:", res.stderr)
