gettext.textdomain('webui-core')
local proxy = require("datamodel")
local gsub = string.gsub

local function get_ifnames()
    local ifnames = proxy.get("uci.network.interface.@lan.ifname")
    return (ifnames and ifnames[1].value) or ""
end

local function get_wan_ifname()
    local wan_ifname = proxy.get("uci.network.interface.@wan.ifname")
    return (wan_ifname and wan_ifname[1].value) or "eth4"
end

return {
    {
        name = "dhcp",
        default = true,
        description = T"DHCP routed mode",
        view = "internet-dhcp-routed.lp",
        card = "003_internet_dhcp_routed.lp",
        check = {
            { "uci.network.interface.@wan.proto", "^dhcp$"},
        },
        operations = function()
            local ifnames = get_ifnames()
            local wan_ifname = get_wan_ifname()
            proxy.set("uci.network.interface.@wan.proto", "dhcp")
            proxy.set("uci.network.config.wan_mode", "dhcp")
            proxy.set("uci.network.interface.@lan.ifname", gsub(gsub(ifnames, wan_ifname, ""), "%s$", ""))
            os.execute("/usr/share/transformer/scripts/apply_service_modes.sh &")
            return true
        end,
    },
    {
        name = "pppoe",
        default = false,
        description = T"PPPoE routed",
        view = "internet-pppoe-routed.lp",
        card = "003_internet_pppoe_routed.lp",
        check = {
            { "uci.network.interface.@wan.proto", "^pppoe$"},
        },
        operations = function()
            local ifnames = get_ifnames()
            local wan_ifname = get_wan_ifname()
            proxy.set("uci.network.interface.@wan.proto", "pppoe")
            proxy.set("uci.network.config.wan_mode", "pppoe")
            proxy.set("uci.network.interface.@lan.ifname", gsub(gsub(ifnames, wan_ifname, ""), "%s$", ""))
            os.execute("/usr/share/transformer/scripts/apply_service_modes.sh &")
            return true
        end,
    },
    {
        name = "pppoa",
        default = false,
        description = T"PPPoA routed",
        view = "internet-pppoa-routed.lp",
        card = "003_internet_pppoe_routed.lp",
        check = {
            { "uci.network.interface.@wan.proto", "^pppoa$"},
        },
        operations = function()
            local ifnames = get_ifnames()
            local wan_ifname = get_wan_ifname()
            proxy.set("uci.network.interface.@wan.proto", "pppoa")
            proxy.set("uci.network.config.wan_mode", "pppoa")
            proxy.set("uci.network.interface.@lan.ifname", gsub(gsub(ifnames, wan_ifname, ""), "%s$", ""))
            os.execute("/usr/share/transformer/scripts/apply_service_modes.sh &")
            return true
        end,
    },
    {
        name = "static",
        default = false,
        description = T"Fixed IP mode",
        view = "internet-static-routed.lp",
        card = "003_internet_static_routed.lp",
        check = {
            { "uci.network.interface.@wan.proto", "^static$"},
        },
        operations = function()
            local ifnames = get_ifnames()
            local wan_ifname = get_wan_ifname()
            proxy.set("uci.network.interface.@wan.proto", "static")
            proxy.set("uci.network.config.wan_mode", "static")
            proxy.set("uci.network.interface.@lan.ifname", gsub(gsub(ifnames, wan_ifname, ""), "%s$", ""))
            os.execute("/usr/share/transformer/scripts/apply_service_modes.sh &")
            return true
        end,
    },
    {
        name = "bridge",
        default = false,
        description = T"Bridge mode",
        view = "internet-bridged.lp",
        card = "003_internet_bridged.lp",
        check = {
            { "uci.network.config.wan_mode", "^bridge$"}
        },
        operations = function()
            local ifnames = get_ifnames()
            local wan_ifname = get_wan_ifname()
            proxy.set("uci.network.interface.@wan.proto", "bridge")
            proxy.set("uci.network.config.wan_mode", "bridge")
            if not string.find(ifnames, wan_ifname) then
                proxy.set("uci.network.interface.@lan.ifname", ifnames .. ' ' .. wan_ifname)
            end
            os.execute("/usr/share/transformer/scripts/apply_service_modes.sh &")
            return true
        end,
    },
}
