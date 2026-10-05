-- UBUS Aggregator (Backend-For-Frontend) for tch-nginx-gui
-- Batches polling data for Gateway, Internet, xDSL, Ports, Telephony, and Devices
-- drastically reducing CPU context-switching, thread creation, and HTTP round-trips.

if not _G.__gc_tuned then
    _G.__gc_tuned = true
    collectgarbage("setpause", 300)
    collectgarbage("setstepmul", 200)
end

if gettext and gettext.textdomain then
    gettext.textdomain('webui-core')
end
local T = T or function(s) return s end

local json = require("dkjson")
local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")
local ngx = ngx
local readfile = content_helper.readfile
local floor = math.floor
local format = string.format
local untaint = string.untaint or function(s) return tostring(s) end

-- Fallback session object for safe execution in any environment
if not ngx.ctx then ngx.ctx = {} end
if not ngx.ctx.session then
    ngx.ctx.session = {
        retrieve = function() return {} end,
        store = function() end,
        getLanguage = function() return "en-us" end,
        hasAccess = function() return true end,
        getRoleId = function() return 1 end,
        checkCSRFtoken = function() return true end,
    }
end

-- Localize session language if present
if gettext and gettext.language then
    local session = ngx.ctx.session
    if session and session.getLanguage then
        gettext.language(session:getLanguage())
    elseif ngx.header and ngx.header['Content-Language'] then
        gettext.language(ngx.header['Content-Language'])
    end
end

-- Universal HTML flattener for nested tables produced by ui_helper
local function html_flatten(tbl)
    if not tbl then return "" end
    if type(tbl) == "string" then return tbl end
    if type(tbl) == "userdata" then return tostring(untaint(tbl)) end
    local parts = {}
    local function walk(t)
        local tt = type(t)
        if tt == "table" then
            for _, v in pairs(t) do
                walk(v)
            end
        elseif tt == "userdata" then
            parts[#parts + 1] = tostring(untaint(t))
        elseif t ~= nil then
            parts[#parts + 1] = tostring(t)
        end
    end
    walk(tbl)
    return table.concat(parts)
end

-- Parse requested modules from POST or GET
local req_modules_str = ""
if ngx.req and ngx.req.get_method and ngx.req.get_method() == "POST" then
    pcall(ngx.req.read_body)
    local post_args = ngx.req.get_post_args and ngx.req.get_post_args()
    req_modules_str = (post_args and post_args.modules) or ""
end
if req_modules_str == "" and ngx.req and ngx.req.get_uri_args then
    local uri_args = ngx.req.get_uri_args()
    req_modules_str = (uri_args and uri_args.modules) or ""
end

req_modules_str = untaint(req_modules_str)

local requested = {}
if req_modules_str ~= "" and req_modules_str ~= "all" then
    for mod in req_modules_str:gmatch("([^,]+)") do
        local m = untaint(mod:gsub("%s+", ""))
        if m ~= "" then
            requested[m] = true
        end
    end
else
    requested["all"] = true
end

local function need(mod)
    return requested["all"] == true or requested[mod] == true
end

local result = {}

--------------------------------------------------------------------------------
-- 1. GATEWAY (CPU, RAM, Uptime, Load, Connections)
--------------------------------------------------------------------------------
local function get_gateway()
    local ram_data = proxy.get("sys.mem.RAMUsed")
    local ram = (ram_data and ram_data[1] and tonumber(ram_data[1].value)) or 0

    local cpu_usage = "0"
    local f = io.open("/proc/stat", "r")
    if f then
        local line = f:read("*l")
        f:close()
        if line then
            local user, nice, sys, idle, iowait, irq, softirq, steal = line:match("^cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
            if user then
                local cur_idle = tonumber(idle) + tonumber(iowait)
                local cur_total = cur_idle + tonumber(user) + tonumber(nice) + tonumber(sys) + tonumber(irq) + tonumber(softirq) + tonumber(steal)

                local up_f = io.open("/proc/uptime", "r")
                local now = up_f and up_f:read("*n")
                if up_f then up_f:close() end
                if not now then now = os.time() end

                local prev_file = io.open("/tmp/.cpu_prev", "r")
                if prev_file then
                    local prev_total = prev_file:read("*n")
                    local prev_idle = prev_file:read("*n")
                    local prev_time = prev_file:read("*n")
                    prev_file:close()
                    if prev_total and prev_idle and cur_total > prev_total then
                        local elapsed = (prev_time and (now - prev_time)) or 999
                        if elapsed >= 1 and elapsed <= 12 then
                            local dt = cur_total - prev_total
                            local di = cur_idle - prev_idle
                            if dt > 0 and di >= 0 and di <= dt then
                                cpu_usage = tostring(floor(((dt - di) / dt) * 100))
                            end
                        end
                    end
                end

                local out_file = io.open("/tmp/.cpu_prev", "w")
                if out_file then
                    out_file:write(format("%d %d %.2f\n", cur_total, cur_idle, now))
                    out_file:close()
                end
            end
        end
    end

    if cpu_usage == "0" then
        local c = proxy.get("sys.proc.CurrentCPUUsage")
        if c and c[1] and c[1].value and c[1].value ~= "" then
            cpu_usage = c[1].value
        else
            local c_old = proxy.get("sys.proc.CPUUsage")
            if c_old and c_old[1] and c_old[1].value and c_old[1].value ~= "" then
                cpu_usage = c_old[1].value
            end
        end
    end

    return {
        cpuusage = (cpu_usage or "0") .. "%",
        ram_used = floor(ram / 1024),
        uptime = post_helper.secondsToTime(readfile("/proc/uptime", "number", floor)) or "",
        connection = readfile("/proc/sys/net/netfilter/nf_conntrack_count") or "",
        system_time = os.date("%d/%m/%Y %Hh:%Mm:%Ss", os.time()),
        cpuload = (readfile("/proc/loadavg", "string") or ""):sub(1, 14),
    }
end

--------------------------------------------------------------------------------
-- 2. WAN / INTERNET ACCESS
--------------------------------------------------------------------------------
local function get_wan()
    local content_uci = {
        wan_proto = "uci.network.interface.@wan.proto",
        wan_auto = "uci.network.interface.@wan.auto",
        wan_ipv6 = "uci.network.interface.@wan.ipv6",
        wan_mode = "uci.network.config.wan_mode",
    }
    content_helper.getExactContent(content_uci)

    local is_bridged = (content_uci.wan_mode == "bridge") or (content_uci.wan_proto == "none") or (content_uci.wan_auto == "0" and content_uci.wan_proto == "")

    if is_bridged then
        local lan_data = {
            ipaddr = "uci.network.interface.@lan.ipaddr",
            gateway = "uci.network.interface.@lan.gateway",
            operstate = "sys.class.net.@br-lan.operstate",
        }
        content_helper.getExactContent(lan_data)

        if not lan_data.gateway or lan_data.gateway == "" then
            local rpc_gw = proxy.get("rpc.network.interface.@lan.nexthop")
            if rpc_gw and rpc_gw[1] and rpc_gw[1].value ~= "" then
                lan_data.gateway = rpc_gw[1].value
            end
        end
        if not lan_data.ipaddr or lan_data.ipaddr == "" then
            local rpc_ip = proxy.get("rpc.network.interface.@lan.ipaddr")
            if rpc_ip and rpc_ip[1] and rpc_ip[1].value ~= "" then
                lan_data.ipaddr = rpc_ip[1].value
            end
        end

        local dns_val = ""
        local rpc_dns = proxy.get("rpc.network.interface.@lan.dnsservers")
        if rpc_dns and rpc_dns[1] and rpc_dns[1].value ~= "" then
            dns_val = rpc_dns[1].value
        else
            local uci_dns = proxy.get("uci.network.interface.@lan.dns.@1.value")
            if uci_dns and uci_dns[1] and uci_dns[1].value ~= "" then
                dns_val = uci_dns[1].value
            elseif lan_data.gateway and lan_data.gateway ~= "" then
                dns_val = lan_data.gateway
            end
        end
        if dns_val:match(",") then
            dns_val = dns_val:gsub(",", ", ")
        end

        local lan_up = proxy.get("rpc.network.interface.@lan.up")
        local is_up = (lan_data.operstate == "up") or (lan_up and lan_up[1] and lan_up[1].value == "1")
        local is_connected = is_up and (lan_data.gateway ~= "" or lan_data.ipaddr ~= "")
        local light_color = is_connected and "1" or "4"
        local light_text = is_connected and T"Bridge / Access Point" or T"Bridge Not Configured"
        local attributes = { light = { id = "Internet_State_Led" }, span = { id = "Internet_State_Enabled" } }
        local status_light = ui_helper.createSimpleLight(light_color, light_text, attributes, "fas fa-network-wired")

        local ip_text = (lan_data.ipaddr ~= "") and format(T'Device IP: <strong>%s</strong><br/>', lan_data.ipaddr) or ""
        local gw_text = (lan_data.gateway ~= "") and format(T'Gateway: <strong>%s</strong><br/>', lan_data.gateway) or ""
        local dns_text = (dns_val ~= "") and format(T'DNS: <strong>%s</strong><br/>', dns_val) or ""

        return {
            status_light = status_light,
            WAN_IP_text = ip_text,
            WAN_IPv6_text = gw_text,
            uptime_text = dns_text,
            wan_uptime = "",
            wan_uptime_extended = "",
            status = is_connected and T"Connected" or T"Disconnected",
            WAN_IP = lan_data.ipaddr or "",
            WAN_IPv6 = "",
            concentrator_name = "",
            wangateway = lan_data.gateway or "",
            wandns = dns_val or "",
            ppp_status = "",
            ppp_light = "",
            ppp_state = "",
            ipv6_light = "",
            ipv6_state = "",
        }
    else
        local content_rpc = {
            wan_ppp_state = "rpc.network.interface.@wan.ppp.state",
            wan_ppp_error = "rpc.network.interface.@wan.ppp.error",
            ipaddr = "rpc.network.interface.@wan.ipaddr",
            wan_uptime = "rpc.network.interface.@wan.uptime",
            up = "rpc.network.interface.@wan.up",
            nexthop = "rpc.network.interface.@wan.nexthop",
            dns_wan = "rpc.network.interface.@wan.dnsservers",
            concentrator_name = "rpc.network.interface.@wan.ppp.access_concentrator_name",
        }

        local ok_v6, internethelper = pcall(require, "internethelper")
        if ok_v6 and internethelper and internethelper.getIpv6Content then
            for v6Key, v6Value in pairs(internethelper.getIpv6Content()) do
                content_rpc[v6Key] = v6Value
            end
        end

        content_helper.getExactContent(content_rpc)

        content_rpc.ipaddr = content_rpc.ipaddr or ""
        content_rpc.ip6addr = content_rpc.ip6addr or ""
        content_rpc.ip6prefix = content_rpc.ip6prefix or ""
        content_rpc.dns_wan = content_rpc.dns_wan or ""
        content_rpc.nexthop = content_rpc.nexthop or ""
        content_rpc.concentrator_name = content_rpc.concentrator_name or ""
        content_rpc.wan_ppp_state = content_rpc.wan_ppp_state or ""
        content_rpc.wan_ppp_error = content_rpc.wan_ppp_error or ""
        content_rpc.wan_uptime = content_rpc.wan_uptime or ""

        if content_rpc.dns_wan:match(",") then
            content_rpc.dns_wan = content_rpc.dns_wan:gsub(",", ", ")
        end

        local is_up = (content_rpc.up == "1")
        local status_str = is_up and T"Connected" or T"Disconnected"

        local IPv6State = "none"
        if content_uci.wan_ipv6 ~= "1" then
            IPv6State = "disabled"
        elseif content_rpc.ip6prefix ~= "" then
            IPv6State = "prefix"
        else
            IPv6State = "noprefix"
        end

        local ipv6_light_map = { none = "0", noprefix = "2", prefix = "1" }
        local ipv6_state_map = { none = T"IPv6 Disabled", noprefix = T"IPv6 Connecting", prefix = T"IPv6 Connected" }

        local is_pppoe = (content_uci.wan_mode == "pppoe" or content_uci.wan_mode == "pppoa" or content_uci.wan_proto == "pppoe" or content_uci.wan_proto == "pppoa")
        local is_static = (content_uci.wan_mode == "static" or content_uci.wan_proto == "static")

        local status_light = ""
        local ppp_status = ""
        local ppp_light = ""
        local ppp_state = ""
        local attributes = { light = {}, span = {} }

        if is_pppoe then
            local ppp_state_map = {
                disabled = T"PPP disabled",
                disconnecting = T"PPP disconnecting",
                connected = T"PPP connected",
                connecting = T"PPP connecting",
                disconnected = T"PPP disconnected",
                error = T"PPP error",
                AUTH_TOPEER_FAILED = T"PPP authentication failed",
                NEGOTIATION_FAILED = T"PPP negotiation failed",
            }
            local ppp_light_map = {
                disabled = "0",
                disconnected = "4",
                disconnecting = "2",
                connecting = "2",
                connected = "1",
                error = "4",
                AUTH_TOPEER_FAILED = "4",
                NEGOTIATION_FAILED = "4",
            }

            if content_uci.wan_auto ~= "0" then
                content_uci.wan_auto = "1"
                ppp_status = format("%s", content_rpc.wan_ppp_state)
                if ppp_status == "" or ppp_status == "authenticating" then
                    ppp_status = "connecting"
                elseif not ppp_state_map[ppp_status] then
                    ppp_status = "error"
                end

                if not (content_rpc.wan_ppp_error == "" or content_rpc.wan_ppp_error == "USER_REQUEST") then
                    if ppp_state_map[content_rpc.wan_ppp_error] then
                        ppp_status = content_rpc.wan_ppp_error
                    else
                        ppp_status = "error"
                    end
                end
            else
                ppp_status = "disabled"
            end

            ppp_light = ppp_light_map[ppp_status] or "4"
            ppp_state = ppp_state_map[ppp_status] or T"Unknown"
            attributes.light.id = "Internet_State_Led"
            attributes.span.id = "Internet_State_Enabled"
            status_light = ui_helper.createSimpleLight(ppp_light, ppp_state, attributes, "fa-at")
        elseif is_static then
            local static_state_map = { disabled = T"Static disabled", connected = T"Static on" }
            local static_light_map = { disabled = "0", connected = "1" }
            local static_state = (content_uci.wan_auto ~= "0" and content_rpc.ipaddr ~= "") and "connected" or "disabled"
            attributes.light.id = "Internet_State_Led"
            attributes.span.id = "Internet_State_Enabled"
            status_light = ui_helper.createSimpleLight(static_light_map[static_state], static_state_map[static_state], attributes, "fa-at")
        else
            -- DHCP routed mode or default
            local dhcp_state_map = { disabled = T"DHCP disabled", connected = T"DHCP on", connecting = T"DHCP connecting" }
            local dhcp_light_map = { disabled = "0", connecting = "2", connected = "1" }
            local dhcp_state = (content_uci.wan_auto == "0") and "disabled" or ((content_rpc.ipaddr ~= "") and "connected" or "connecting")
            attributes.light.id = "Internet_DHCP_LED"
            attributes.span.id = "Internet_DHCP_Status"
            status_light = ui_helper.createSimpleLight(dhcp_light_map[dhcp_state], dhcp_state_map[dhcp_state], attributes, "fa-at")
        end

        local wan_uptime_time = post_helper.secondsToTimeShort(content_rpc.wan_uptime) or ""

        return {
            status_light = status_light or "",
            WAN_IP_text = (content_rpc.ipaddr ~= "") and format(T'WAN IP is <strong>%s</strong><br/>', content_rpc.ipaddr) or "",
            WAN_IPv6_text = (content_rpc.ip6addr ~= "") and format(T'WAN IPv6 is <strong>%s</strong><br/>', content_rpc.ip6addr) or "",
            uptime_text = (wan_uptime_time ~= "") and format(T"Uptime: <strong>%s</strong>", wan_uptime_time) or "",
            wan_uptime = wan_uptime_time,
            wan_uptime_extended = post_helper.secondsToTime(content_rpc.wan_uptime) or "",
            status = status_str,
            WAN_IP = content_rpc.ipaddr,
            WAN_IPv6 = content_rpc.ip6addr,
            concentrator_name = content_rpc.concentrator_name,
            wangateway = content_rpc.nexthop,
            wandns = content_rpc.dns_wan,
            ppp_status = ppp_status,
            ppp_light = ppp_light,
            ppp_state = ppp_state,
            ipv6_light = ipv6_light_map[IPv6State] or "0",
            ipv6_state = ipv6_state_map[IPv6State] or "",
        }
    end
end

--------------------------------------------------------------------------------
-- 3. XDSL STATUS & STATS
--------------------------------------------------------------------------------
local function get_xdsl()
    local xdata = {
        status = "sys.class.xdsl.@line0.LinkStatus",
        dsl_linerate_up_max = "sys.class.xdsl.@line0.UpstreamMaxRate",
        dsl_linerate_down_max = "sys.class.xdsl.@line0.DownstreamMaxRate",
        dsl_linerate_up = "sys.class.xdsl.@line0.UpstreamCurrRate",
        dsl_linerate_down = "sys.class.xdsl.@line0.DownstreamCurrRate",
        dsl_margin_up = "sys.class.xdsl.@line0.UpstreamNoiseMargin",
        dsl_margin_down = "sys.class.xdsl.@line0.DownstreamNoiseMargin",
        dsl_attenuation_up = "sys.class.xdsl.@line0.UpstreamAttenuation",
        dsl_attenuation_down = "sys.class.xdsl.@line0.DownstreamAttenuation",
        dsl_power_up = "sys.class.xdsl.@line0.UpstreamPower",
        dsl_power_down = "sys.class.xdsl.@line0.DownstreamPower",
        dsl_type = "sys.class.xdsl.@line0.ModulationType",
        dsl_margin_SNRM_up = "sys.class.xdsl.@line0.UpstreamSNRMpb",
        dsl_margin_SNRM_down = "sys.class.xdsl.@line0.DownstreamSNRMpb",
        dslam_chipset = "rpc.xdslctl.DslamChipset",
        dslam_version = "rpc.xdslctl.DslamVersion",
        dsl_profile = "rpc.xdslctl.DslProfile",
        dsl_port = "rpc.xdslctl.DslamPort",
        dslam_version_raw = "rpc.xdslctl.DslamVersionRaw",
        dsl_serial = "rpc.xdslctl.DslamSerial",
    }
    content_helper.getExactContent(xdata)

    local function formatRate(value)
        local rate = tonumber(value)
        if not rate then return T"Can't recover data" end
        return floor(rate / 10) / 100 .. " Mbps"
    end

    if xdata.dsl_linerate_down and xdata.dsl_linerate_down ~= "0" and xdata.dsl_linerate_down ~= "" then
        xdata.dsl_linerate_up = formatRate(xdata.dsl_linerate_up)
        xdata.dsl_linerate_down = formatRate(xdata.dsl_linerate_down)
        xdata.dsl_linerate_up_max = formatRate(xdata.dsl_linerate_up_max)
        xdata.dsl_linerate_down_max = formatRate(xdata.dsl_linerate_down_max)

        if not string.match(xdata.dsl_type or "", "ADSL") then
            xdata.dsl_margin_down = xdata.dsl_margin_SNRM_down
            xdata.dsl_margin_up = xdata.dsl_margin_SNRM_up
        end

        if string.match(xdata.dslam_chipset or "", "BDCM") then
            xdata.dslam_chipset = "Broadcom (" .. xdata.dslam_chipset .. ")"
        elseif string.match(xdata.dslam_chipset or "", "IFTN") then
            xdata.dslam_chipset = "Infineon (" .. xdata.dslam_chipset .. ")"
        end

        if string.match(xdata.status or "", "Showtime") then
            xdata.status = T"Connected"
        elseif not xdata.status or xdata.status == "" then
            xdata.status = T"Disconnected"
        else
            xdata.status = T(xdata.status)
        end
    else
        for k in pairs(xdata) do
            if k == "status" then
                xdata[k] = (xdata.status and xdata.status ~= "") and T(xdata.status) or T"Disconnected"
            else
                xdata[k] = "N/A"
            end
        end
    end
    xdata.dsl_margin_SNRM_down = nil
    xdata.dsl_margin_SNRM_up = nil
    xdata.dslam_version_raw = nil

    return xdata
end

--------------------------------------------------------------------------------
-- 4. ETHERNET PORTS TABLE
--------------------------------------------------------------------------------
local function get_ports()
    local ethname = "eth3"
    local p4 = proxy.get("sys.eth.port.@eth4.status")
    if p4 and p4[1] and p4[1].value then
        ethname = "eth4"
    end

    local qtn = proxy.get("uci.env.var.qtn_eth_mac")
    local quantenna_wifi = (qtn and qtn[1] and qtn[1].value ~= "")

    local port_columns = {
        { header = T"Type", name = "type", param = "paramindex", type = "text", readonly = true },
        { header = T"Status", name = "status", param = "status", type = "text", readonly = true },
        { header = T"Speed", name = "speed", param = "speed", type = "text", readonly = true },
        { header = T"Mode", name = "mode", param = "mode", type = "text", readonly = true },
    }
    local port_options = { canEdit = false, canAdd = false, canDelete = false, tableid = "port", basepath = "sys.eth.port.@." }

    local port_filter = function(d)
        d.status_light = "1"
        if d.speed == "1000" then
            d.status_light = "1"
            d.speed = "1 Gbps"
        elseif d.speed == "100" then
            d.status_light = "2"
            d.speed = "100 Mbps"
        elseif d.speed == "10" then
            d.status_light = "3"
            d.speed = "10 Mbps"
        elseif d.speed == "" or d.speed == "0" then
            d.status_light = "0"
            d.speed = "-"
        end
        if not d.mode or d.mode == "" or d.mode == "0BASE-T" then d.mode = "-" end
        d.status = ui_helper.createSimpleLight(d.status_light, "", {}, "fas fa-ethernet")

        if quantenna_wifi and d.paramindex:match("eth5") then
            return false
        elseif d.paramindex == ethname then
            local uwan = proxy.get("uci.ethernet.port.@" .. ethname .. ".wan")
            if uwan and uwan[1] and uwan[1].value == "1" then
                d.paramindex = "WAN"
            end
        else
            local port = d.paramindex:match("^eth(%d+)$")
            if port then
                d.paramindex = "LAN " .. (tonumber(port) + 1)
            end
        end
        return true
    end

    local port_data = content_helper.loadTableData(port_options.basepath, port_columns, port_filter, nil) or {}

    local mode_labels = {
        bgn = "b/g/n",
        gn = "g/n",
        anac = "a/n/ac",
        an = "a/n",
        bgnax = "b/g/n/ax",
        anacax = "a/n/ac/ax",
        ax = "ax",
        ac = "ac",
    }

    local radio_names = proxy.getPN("rpc.wireless.radio.", true) or {}
    local seen_radios = {}
    for _, radio_entry in ipairs(radio_names) do
        local radio = radio_entry.path:match("^rpc%.wireless%.radio%.@([%w_]+)%.$")
        if radio and not seen_radios[radio] then
            seen_radios[radio] = true
            local base_path = "rpc.wireless.radio.@" .. radio .. "."
            local wifi_content = {
                status = base_path .. "admin_state",
                speed = base_path .. "phy_rate",
                mode = base_path .. "standard",
                band = base_path .. "supported_frequency_bands",
            }
            content_helper.getExactContent(wifi_content)
            local enabled = wifi_content.status == "1"
            local speed = tonumber(wifi_content.speed)
            local band = wifi_content.band and wifi_content.band ~= "" and wifi_content.band or radio
            local speed_str = "-"
            if enabled and speed then
                if speed >= 1000000 then
                    speed_str = format("%.1f Gbps", speed / 1000000)
                else
                    speed_str = format("%d Mbps", floor(speed / 1000))
                end
            end
            port_data[#port_data + 1] = {
                "Wi-Fi " .. band,
                ui_helper.createSimpleLight(wifi_content.status or "0", "", {}, "fa fa-wifi"),
                speed_str,
                enabled and (mode_labels[wifi_content.mode] or wifi_content.mode or "-") or "-",
            }
        end
    end

    table.sort(port_data, function(a, b)
        return tostring(a[1]) < tostring(b[1])
    end)

    local port_table = ui_helper.createTable(port_columns, port_data, port_options, nil, nil)

    return { port_table = html_flatten(port_table) }
end

--------------------------------------------------------------------------------
-- 5. CONNECTED DEVICES TABLE
--------------------------------------------------------------------------------
local function get_devices()
    local devices_columns = {
        { header = T"Hostname", name = "FriendlyName", param = "FriendlyName", type = "text", additional_class = 'data-toggle="tooltip_mac"' },
        { header = T"IPv4", name = "ipv4", param = "IPv4", type = "text" },
        { header = T"InterfaceType", name = "interfacetype", param = "InterfaceType", type = "text" },
        { header = T"SSID", name = "ssid", param = "SSID", type = "text" },
    }
    local devices_options = { canEdit = false, canAdd = false, canDelete = false, tableid = "devices", basepath = "rpc.hosts.host." }

    local devices_filter = function(d)
        if d["State"] and d["State"] == "0" then return false end
        local l2 = d["L2Interface"] or ""
        if l2:match("^wl0") then
            d["InterfaceType"] = "Wireless - 2.4GHz"
        elseif l2:match("^wl1") then
            d["InterfaceType"] = "Wireless - 5GHz"
        elseif l2:match("eth*") then
            d["InterfaceType"] = "Ethernet - " .. (d.Port or "")
        elseif l2:match("moca*") then
            d["InterfaceType"] = "MoCA"
        end
        d["FriendlyName"] = (d["FriendlyName"] or "") .. '<div id="mac_data" style="display:none">' .. (d["MACAddress"] or "") .. '</div>'
        return true
    end

    local devices_data = content_helper.loadTableData(devices_options.basepath, devices_columns, devices_filter, nil)
    local dev_table = ui_helper.createTable(devices_columns, devices_data, devices_options, nil, nil)

    return { device_table = html_flatten(dev_table) }
end

--------------------------------------------------------------------------------
-- 6. TELEPHONY (MMPBX) STATUS & TABLE
--------------------------------------------------------------------------------
local function get_mmpbx()
    local mmpbx_state = "0"
    local mmpbx_state_uci = proxy.get("uci.mmpbx.mmpbx.@global.enabled")
    if not mmpbx_state_uci or not mmpbx_state_uci[1] or mmpbx_state_uci[1].value == "" then
        mmpbx_state_uci = proxy.get("uci.mmpbx.global.enabled")
    end
    if mmpbx_state_uci and mmpbx_state_uci[1] and mmpbx_state_uci[1].value == "1" then
        local rpc_state = proxy.get("rpc.mmpbx.state")
        if not rpc_state or not rpc_state[1] or rpc_state[1].value ~= "NA" then
            mmpbx_state = "1"
        end
    end

    local basic = { span = { class = "span3" } }
    local mmpbx_info = (mmpbx_state == "1") and T"Telephony enabled" or T"Telephony disabled"
    local mmpbx_status_html = html_flatten(ui_helper.createLabel(T"Service", ui_helper.createSimpleLight(mmpbx_state, mmpbx_info), basic))
    local mmpbx_table_html = ""

    if mmpbx_state == "1" then
        local mmpbxd_columns = {
            { header = T"Name", name = "sip_account_name", param = "name", type = "text", readonly = true },
            { header = T"User Name", name = "sip_user_name", param = "uri", type = "text", readonly = true },
            { header = T"Status", name = "sip_status", param = "profileUsable", type = "text", readonly = true },
        }
        local mmpbxd_options = { canEdit = false, canAdd = false, canDelete = false, tableid = "mmpbxd", basepath = "rpc.mmpbx.profile." }
        local mmpbxd_filter = function(d)
            if d.profileUsable == "true" then
                d.profileUsable = ui_helper.createSimpleLight("1", T"Registered")
            else
                d.profileUsable = ui_helper.createSimpleLight("4", T"Registration failed")
            end
            return true
        end
        local mmpbxd_data = content_helper.loadTableData(mmpbxd_options.basepath, mmpbxd_columns, mmpbxd_filter, nil)
        if mmpbxd_data and #mmpbxd_data > 0 then
            mmpbx_table_html = html_flatten(ui_helper.createTable(mmpbxd_columns, mmpbxd_data, mmpbxd_options, nil, nil))
        else
            mmpbx_table_html = html_flatten(ui_helper.createLabel(T"Line Status", T"No registered accounts", basic))
        end
    end

    return {
        mmpbx_status = mmpbx_status_html,
        mmpbx_table = mmpbx_table_html,
    }
end

--------------------------------------------------------------------------------
-- 7. NET (Real-time Network Throughput Rates via /proc/net/dev)
--------------------------------------------------------------------------------
local has_netrate, netrate = pcall(require, "netrate")

local function get_net()
    if not has_netrate then
        return { status = "unavailable", rates = {} }
    end
    local rates, status = netrate.sample()
    rates = rates or {}

    local wan_dev
    local rpc_wan = proxy.get("rpc.network.interface.@wan.device")
    if rpc_wan and rpc_wan[1] and rpc_wan[1].value ~= "" then
        wan_dev = rpc_wan[1].value
    end
    if not wan_dev or wan_dev == "" then
        for _, candidate in ipairs({ "ppp0", "eth4", "ptm0", "erouter0", "dsl0" }) do
            if rates[candidate] then
                wan_dev = candidate
                break
            end
        end
    end

    local lan_dev = "br-lan"
    if not rates[lan_dev] and rates["eth0"] then
        lan_dev = "eth0"
    end

    return {
        status = status or "ok",
        wan_ifname = wan_dev or "unknown",
        lan_ifname = lan_dev,
        wan = (wan_dev and rates[wan_dev]) or { rx = 0, tx = 0 },
        lan = rates[lan_dev] or { rx = 0, tx = 0 },
        rates = rates,
    }
end

--------------------------------------------------------------------------------
-- PRE-SERIALIZED MODULE CACHE & ASSEMBLE RESPONSE
--------------------------------------------------------------------------------
local function sanitize_value(v, seen)
    seen = seen or {}
    local tv = type(v)
    if tv == "table" then
        if seen[v] then return nil end
        seen[v] = true
        local res = {}
        for k, val in pairs(v) do
            local clean_k = (type(k) == "userdata") and tostring(untaint(k)) or tostring(k)
            res[clean_k] = sanitize_value(val, seen)
        end
        return res
    elseif tv == "userdata" then
        return tostring(untaint(v))
    else
        return v
    end
end

local function json_exception(reason, value, state, defaultmessage)
    if type(value) == "userdata" then
        return json.quotestring(tostring(untaint(value)))
    end
    if json.encodeexception then
        return json.encodeexception(reason, value, state, defaultmessage)
    end
    return json.quotestring("<" .. tostring(defaultmessage) .. ">")
end

local function encode_module_payload(data)
    local clean_data = sanitize_value(data)
    local buf = {}
    if json.encode(clean_data, { indent = false, buffer = buf, exception = json_exception }) then
        return table.concat(buf)
    end
    return "{}"
end

local _jcache = _G._dashboard_jcache
if not _jcache then
    _jcache = {}
    _G._dashboard_jcache = _jcache
end

local session = ngx.ctx and ngx.ctx.session
local role = (session and session.getRoleId and session:getRoleId()) or "default"

local function module_json(name, ttl, builder)
    local bucket = _jcache[role]
    if not bucket then
        bucket = {}
        _jcache[role] = bucket
    end
    local e = bucket[name]
    local now = os.time()
    if e and ttl > 0 then
        local d = now - e.t
        if d >= 0 and d < e.ttl then
            return e.s
        end
    end
    local ok, data = pcall(builder)
    local s
    if ok and data then
        s = encode_module_payload(data)
    else
        s = "{}"
        if ngx and ngx.log then
            ngx.log(ngx.ERR, "dashboard_sync " .. name .. ": " .. tostring(data))
        end
    end
    bucket[name] = { s = s, t = now, ttl = ok and ttl or 2 }
    return s
end

local pieces = {}
if need("gateway") then
    pieces[#pieces + 1] = '"gateway":' .. module_json("gateway", 0, get_gateway)
end
if need("wan") then
    pieces[#pieces + 1] = '"wan":' .. module_json("wan", 5, get_wan)
end
if need("xdsl") then
    pieces[#pieces + 1] = '"xdsl":' .. module_json("xdsl", 15, get_xdsl)
end
if need("ports") then
    pieces[#pieces + 1] = '"ports":' .. module_json("ports", 10, get_ports)
end
if need("devices") then
    pieces[#pieces + 1] = '"devices":' .. module_json("devices", 10, get_devices)
end
if need("mmpbx") then
    pieces[#pieces + 1] = '"mmpbx":' .. module_json("mmpbx", 15, get_mmpbx)
end
if need("net") then
    pieces[#pieces + 1] = '"net":' .. module_json("net", 0, get_net)
end

if ngx and ngx.header then
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.header["Cache-Control"] = "no-cache, no-store, must-revalidate"
end

ngx.say("{" .. table.concat(pieces, ",") .. "}")
if ngx and ngx.exit and ngx.HTTP_OK then
    ngx.exit(ngx.HTTP_OK)
end
