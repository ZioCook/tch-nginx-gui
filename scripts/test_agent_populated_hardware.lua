-- Hardware test script for populated branch in agent-list modals
local output = {}

local function append_val(v)
    if type(v) == "table" then
        for _, item in ipairs(v) do
            append_val(item)
        end
    else
        table.insert(output, tostring(v))
    end
end

-- Session store
local session_data = { mac = "AABBCCDDEE01" }

-- Mock ngx MUST be defined before requiring web modules
_G.ngx = {
    HTTP_OK = 200,
    print = function(...)
        for _, s in ipairs({...}) do
            append_val(s)
        end
    end,
    say = function(...)
        for _, s in ipairs({...}) do
            append_val(s)
            table.insert(output, "\n")
        end
    end,
    var = setmetatable({}, {
        __index = function(t, k) return "" end,
        __newindex = function(t, k, v) rawset(t, k, v) end
    }),
    ctx = {
        session = {
            store = function(self, k, v) session_data[k] = v end,
            retrieve = function(self, k) return session_data[k] end,
            checkCSRFtoken = function() return true end,
            hasAccess = function() return true end
        }
    },
    req = {
        read_body = function() end,
        get_method = function() return "GET" end,
        get_uri_args = function() return { iface = "AABBCCDDEE01" } end,
        get_post_args = function() return {} end
    },
    header = {},
    sleep = function() end,
    exit = function() end
}

-- gettext / translation stubs
_G.gettext = { textdomain = function() end }
_G.T = function(s) return s end
_G.N = function(s) return s end

local lp = require("web.lp")
local ui_helper = require("web.ui_helper")
local post_helper = require("web.post_helper")
local content_helper = require("web.content_helper")

-- Mock datamodel proxy
local datamodel = require("datamodel")
local orig_get = datamodel.get
datamodel.get = function(path)
    if path == "rpc.multiap.device." then
        return {
            { path = "rpc.multiap.device.@AABBCCDDEE01.", param = "device_name", value = "Extender-01" },
            { path = "rpc.multiap.device.@AABBCCDDEE01.", param = "mac", value = "AABBCCDDEE01" }
        }
    elseif path:find("%.radio%.$") then
        return {
            { path = "rpc.multiap.device.@AABBCCDDEE01.radio.@001122334455.", param = "radio_id", value = "001122334455" },
            { path = "rpc.multiap.device.@AABBCCDDEE01.radio.@001122334455.", param = "freq", value = "radio_2G" },
            { path = "rpc.multiap.device.@AABBCCDDEE01.radio.@001122334466.", param = "radio_id", value = "001122334466" },
            { path = "rpc.multiap.device.@AABBCCDDEE01.radio.@001122334466.", param = "freq", value = "radio_5G" }
        }
    elseif path:find("%.bss%.%@%.$") or path:find("%.bss%.$") then
        return {
            { path = path .. "@1.", param = "bssid", value = "00:11:22:33:44:55" },
            { path = path .. "@1.", param = "ssid", value = "MeshSSID" },
            { path = path .. "@1.", param = "security", value = "WPA2" },
            { path = path .. "@1.", param = "enabled", value = "1" },
            { path = path .. "@1.", param = "backhaul", value = "0" }
        }
    elseif path:find("%.tx_pwr$") then
        return { { path = path, param = "tx_pwr", value = "100" } }
    elseif path:find("%.bss_count$") then
        return { { path = path, param = "bss_count", value = "4" } }
    end
    return orig_get(path)
end

local function test_file(filepath, label)
    output = {}
    local fn, err = lp.load(filepath)
    if not fn then
        io.write(label .. " LOAD ERROR: " .. tostring(err) .. "\n")
        return
    end
    local ok, exec_err = pcall(fn)
    if not ok then
        io.write(label .. " EXEC ERROR: " .. tostring(exec_err) .. "\n")
        return
    end
    local rendered = table.concat(output)
    
    local out_file = "/tmp/" .. label .. "_rendered.html"
    local f = io.open(out_file, "w")
    f:write(rendered)
    f:close()
    
    io.write("------------------------------------------------------------------------\n")
    io.write("TEST TARGET: " .. label .. " (" .. filepath .. ")\n")
    io.write("  Rendered size (bytes): " .. #rendered .. "\n")
    io.flush()
    os.execute("sh /tmp/check_tags.sh " .. out_file)
end

io.write("\n========================================================================\n")
io.write("=== [1] DEPLOYED REFINED FIXES (COMMIT 505e7c01) ===\n")
io.write("========================================================================\n")
test_file("/www/docroot/modals/agent-list-2g.lp", "agent_2g_505e7c01")
test_file("/www/docroot/modals/agent-list-5g.lp", "agent_5g_505e7c01")

io.write("\n========================================================================\n")
io.write("=== [2] NEGATIVE CONTROL: REGRESSED COMMIT (1f1cedfd) ===\n")
io.write("========================================================================\n")
test_file("/tmp/agent-list-2g-1f1cedfd.lp", "agent_2g_1f1cedfd")
test_file("/tmp/agent-list-5g-1f1cedfd.lp", "agent_5g_1f1cedfd")

