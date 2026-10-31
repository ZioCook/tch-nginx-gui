import subprocess
import requests

ip = "192.0.2.6"

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
            getCSRFtoken = function(self) return "TEST_CSRF" end,
        }
    },
    header = {},
    var = setmetatable({ uri = "/modals/easy-mesh-configuration.lp" }, {}),
    req = {
        get_method = function() return "GET" end,
        get_post_args = function() return {} end,
        get_uri_args = function() return {} end,
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
}
_G.gettext = { textdomain = function() end, language = function() end }
_G.T = function(s) return s end
_G.N = function(s, p, n) return n == 1 and s or p end

local template = require("web.template")

local f = io.open("/www/docroot/modals/easy-mesh-configuration.lp", "r")
local code = f:read("*a")
f:close()

code = code:gsub("^#![^\\n]*", "")
if not code:match("^%-%-pretranslated") then
    code = template.translate(code)
end

local chunk, err = loadstring(code, "easymesh")
if not chunk then
    print("ERR:", err)
else
    local ok, rerr = pcall(chunk)
    local html = table.concat(output)
    print("STATUS:", ok and "OK" or ("ERR: " .. tostring(rerr)), "SIZE:", #html)
    print("CONTAINS bandsteerDisabled var:", html:find("bandsteerDisabled") ~= nil)
    print("CONTAINS ap0_state:", html:find("ap0_state") ~= nil)
end
"""

res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=lua_tester, text=True, capture_output=True)
print("EasyMesh Execution Output on DGA4331:")
print(res.stdout)
if res.stderr:
    print("Stderr:", res.stderr)
