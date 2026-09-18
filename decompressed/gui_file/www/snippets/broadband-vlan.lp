--pretranslated: do not change this file

-- NG.... to support vlan device methode

-- Enable localization
gettext.textdomain('webui-core')

local lp = require("web.lp")
local post_helper = require("web.post_helper")
local message_helper = require("web.uimessage_helper")
local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")
local proxy = require("datamodel")
local bmh = require("broadbandmode_helper")

local session = ngx.ctx.session
local role = session:getrole()
local tech = (role == "engineer" or role == "ispuser" or role == "admin")

--Support ethernet mode for devices with no eth4 port
local ethname = "eth4"
if not proxy.get("uci.ethernet.port.@eth4.") and not proxy.get("sys.eth.port.@eth4.status") then
	ethname = "eth3"
end

function getValidateNumberInRange(min, max, value)
    local helptext = T"Input must be a number"
    if min and max then
        helptext = string.format(T"Input must be a number between %d and %d included", min, max)
    elseif not min and not max then
        helptext = T"Input must be a number"
    elseif not min then
        helptext = string.format(T"Input must be a number smaller than %d included", max)
    elseif not max then
        helptext = string.format(T"Input must be a number greater than %d included", min)
    end

    local num = tonumber(value)
    if not num then
        return nil, helptext
    end
    if min and num < min then
        return nil, helptext
    end
    if max and num > max then
        return nil, helptext
    end
    return true
end

local pathifname = "uci.network.interface.@wan.ifname"
local iface = ""
local connection = ""
local path = ""
local vid = ""
local dname = ""
local difname = ""
local check = "devnot"
local b = "ptm0"
local intf_state = "disabled"

local function refresh_state()
	local ifacedata = proxy.get(pathifname)
	if ifacedata and ifacedata[1] and ifacedata[1].value then
		iface = ifacedata[1].value
	else
		iface = ""
	end

	if string.match(iface, "eth") then
		connection = ethname
		path = "uci.network.device.@waneth4."
	elseif string.match(iface, "atm") then
		connection = "atmwan"
		path = "uci.network.device.@wanatmwan."
	else
		connection = "ptm0"
		path = "uci.network.device.@wanptm0."
	end

	if string.match(iface, "%.(%d+)$") then
		check = "dotnot"
		vid = string.match(iface, "%.(%d+)$") or ""
		difname = connection
		intf_state = "connected"
	else
		local dev_ifname_data = proxy.get(path.."ifname")
		local dev_ifname = (dev_ifname_data and dev_ifname_data[1] and dev_ifname_data[1].value) or ""
		local dev_vid_data = proxy.get(path.."vid")
		local dev_vid = (dev_vid_data and dev_vid_data[1] and dev_vid_data[1].value) or ""
		local dev_name_data = proxy.get(path.."name")
		dname = (dev_name_data and dev_name_data[1] and dev_name_data[1].value) or ""

		if iface ~= "" and iface == dname and dev_ifname ~= "" then
			check = "devnot"
			vid = dev_vid
			difname = connection
			intf_state = "connected"
		else
			check = "devnot"
			vid = (dev_vid ~= "" and dev_vid) or "835"
			difname = ""
			intf_state = "disabled"
		end
	end
	b = connection
end

refresh_state()

if ngx.var.request_method == "POST" and tech then
    local content = ngx.req.get_post_args()
	if content["action"] == "SAVE" then
		local range, helpmes = getValidateNumberInRange(2, 4094, content["intf_vlanid"])
		local vlan_enabled = (content["intf_vlan"] and content["intf_vlan"] ~= "" and content["intf_vlan"] ~= "0")
		if vlan_enabled and range then
			if content["auswahlliste"] == "devnot" then
				if proxy.get(path) then
					dname = proxy.get(path.."name")[1].value
					proxy.set(path.."vid", content["intf_vlanid"])
					proxy.set(pathifname, dname)
					proxy.set(path.."ifname", connection)
				else
					proxy.add("uci.network.device.", string.format("%s%s", "wan", connection))
					proxy.set(path.."type", "8021q")
					proxy.set(path.."name", "wan"..connection)
					local eth_mac = proxy.get("uci.env.rip.eth_mac")
					if eth_mac and eth_mac[1] then
						proxy.set(path.."macaddr", eth_mac[1].value)
					end
					dname = "wan"..connection
					proxy.set(path.."vid", content["intf_vlanid"])
					proxy.set(pathifname, dname)
					proxy.set(path.."ifname", connection)
				end
				if proxy.get("uci.wansensing.global.enable") and proxy.get("uci.wansensing.global.enable")[1].value == "1" then
					proxy.set("uci.wansensing.global.enable", "0")
				end
				proxy.apply()
				os.execute("uci commit network; uci commit wansensing 2>/dev/null")
			elseif content["auswahlliste"] == "dotnot" then
				if proxy.get(path) and proxy.get(path.."ifname") and proxy.get(path.."ifname")[1].value ~= "" then
					proxy.set(path.."ifname", "")
				end
				proxy.set(pathifname, string.format("%s.%s", connection, content["intf_vlanid"]))
				if proxy.get("uci.wansensing.global.enable") and proxy.get("uci.wansensing.global.enable")[1].value == "1" then
					proxy.set("uci.wansensing.global.enable", "0")
				end
				proxy.apply()
				os.execute("uci commit network; uci commit wansensing 2>/dev/null")
			end
		elseif not vlan_enabled or content["intf_vlan"] == "0" then
			if proxy.get(path) then
				proxy.set(path.."ifname", "")
			end
			proxy.set(pathifname, connection)
			proxy.apply()
			os.execute("uci commit network")
		end
		refresh_state()
	end
end

local intf_state_map = {
    disabled = T"VLAN disabled",
    connected = T"VLAN enabled",
    disconnected = T"VLAN not connected",
}

local intf_light_map = {
  disabled = "off",
  disconnected = "red",
  connected = "green",
}

ngx.print('\
<fieldset>\
\
    '); ngx.print(ui_helper.createMessages(message_helper.popMessages())) ngx.print('\
\
  <legend>'); ngx.print( T"Internet channel" ); ngx.print('</legend>');

	liste = {	{"devnot", T"Device &nbsp;"},
				{"dotnot", T"Dot"},
			}
	
    local html = {}
    local vlanswitchclass = {
        input = {
            class = "monitor-changes"
        },
		values = {on = b, off = ""},

    }
	
    local vlanidclass = {
        group = {
            class = string.format("monitor-intf_vlan monitor-%s", b),
        },
    }
	if tech then
    html[#html + 1] = ui_helper.createSwitch(T"Using VLAN", "intf_vlan", difname, vlanswitchclass)
	html[#html + 1] = ui_helper.createInputRadio(T"Notation", "auswahlliste" , liste, check, vlanidclass)
    html[#html + 1] = ui_helper.createInputText(T"VLAN ID", "intf_vlanid", vid, vlanidclass, helpmes)
	else
	html[#html + 1] = ui_helper.createLight(T"Using VLAN", nil, intf_state_map[intf_state], { light = { class = intf_light_map[intf_state] } })
	html[#html + 1] = ui_helper.createLabel(T"VLAN ID", vid)
	end
    ngx.print(html)
	
  ngx.print('\
</fieldset>\
');
