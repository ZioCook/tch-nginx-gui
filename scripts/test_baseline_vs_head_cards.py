import subprocess
import difflib

# 1. Fetch baseline content from git tag or commit before changes (76762e3e)
files = ["011_datausage.lp", "015_iproutes.lp", "018_relaysetup.lp"]

lua_runner = """
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
    header = {},
    var = setmetatable({}, {}),
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
local post_helper = require("web.post_helper")
local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")

local function render_code(lua_code, user_role)
    output = {}
    _G.ngx.ctx.session.getrole = function() return user_role end
    
    local code = lua_code:gsub("^#![^\\n]*", "")
    if not code:match("^%-%-pretranslated") then
        code = template.translate(code)
    end
    
    local chunk, err = loadstring(code, "test_chunk")
    if not chunk then
        return nil, err
    end
    
    local ok, res_err = pcall(chunk)
    if not ok then
        return nil, res_err
    end
    return table.concat(output)
end

-- Read baseline and head from files in /tmp
local f_b = io.open("/tmp/card_baseline.lp", "r")
local code_b = f_b:read("*a")
f_b:close()

local f_h = io.open("/tmp/card_head.lp", "r")
local code_h = f_h:read("*a")
f_h:close()

local out_b_admin, err_b = render_code(code_b, "admin")
local out_h_admin, err_h = render_code(code_h, "admin")

if err_b then print("BASELINE_ERR: " .. tostring(err_b)) end
if err_h then print("HEAD_ERR: " .. tostring(err_h)) end

print("--- BASELINE OUTPUT (ADMIN) ---")
print(out_b_admin or "")
print("--- HEAD OUTPUT (ADMIN) ---")
print(out_h_admin or "")
"""

ip = "192.0.2.6"

print("================================================================================")
print("=== BASELINE (76762e3e) vs HEAD HTML OUTPUT COMPARISON ON 3 HIDDEN CARDS ===")
print("================================================================================\n")

cards_info = [
    ("011_datausage.lp", "78fa2fc3^"),
    ("015_iproutes.lp", "3966be0b^"),
    ("018_relaysetup.lp", "7e7b2eab^"),
]

for card, parent_commit in cards_info:
    print(f"[*] CARD: {card} (Baseline: {parent_commit})")
    # Get baseline content from git parent commit
    cmd_b = ["git", "show", f"{parent_commit}:decompressed/gui_file/www/cards/{card}"]
    content_b = subprocess.run(cmd_b, capture_output=True, text=True).stdout
    
    # Get head content from disk
    with open(f"decompressed/gui_file/www/cards/{card}", "r", encoding="utf-8") as fh:
        content_h = fh.read()
        
    # Upload both to router
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /tmp/card_baseline.lp"], input=content_b, text=True, capture_output=True)
    subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "cat > /tmp/card_head.lp"], input=content_h, text=True, capture_output=True)
    
    # Run comparison runner
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=lua_runner, text=True, capture_output=True)
    out = res.stdout
    
    parts = out.split("--- HEAD OUTPUT (ADMIN) ---")
    out_b = parts[0].replace("--- BASELINE OUTPUT (ADMIN) ---", "").strip()
    out_h = parts[1].strip() if len(parts) > 1 else ""
    
    byte_diff = len(out_h.encode('utf-8')) - len(out_b.encode('utf-8'))
    print(f"  Baseline size: {len(out_b.encode('utf-8'))} bytes")
    print(f"  HEAD size:     {len(out_h.encode('utf-8'))} bytes")
    print(f"  Byte Diff:     {byte_diff:+d} bytes")
    
    if out_b == out_h:
        print("  -> Output HTML: PERFECT MATCH (0 character diff, 100% identical)")
    else:
        print("  -> Output HTML: DIFF DETECTED (Expected feature flag effect):")
        diff = list(difflib.unified_diff(out_b.splitlines(keepends=True), out_h.splitlines(keepends=True), fromfile="baseline", tofile="head"))
        print("".join(diff[:15]))
    print("-" * 80)
