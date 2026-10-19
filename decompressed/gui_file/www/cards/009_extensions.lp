--pretranslated: do not change this file

-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local insert, format = table.insert, string.format

local marketing_version = proxy.get("uci.version.version.@version[0].marketing_version")
local cputype = proxy.get("rpc.system.modgui.CPUtype")[1].value

local extension_supported = 0

local function kernel_has_tun()
	if _G.__kernel_has_tun ~= nil then
		return _G.__kernel_has_tun
	end
	local f = io.open("/dev/net/tun", "r")
	if f then
		f:close()
		_G.__kernel_has_tun = true
		return true
	end
	local command = io.popen("zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_TUN=y$'; echo $?", "r")
	if not command then
		_G.__kernel_has_tun = false
		return false
	end
	local result = command:read("*line")
	command:close()
	_G.__kernel_has_tun = (result == "0")
	return _G.__kernel_has_tun
end

local function tun_install_supported()
	if kernel_has_tun() then return true end
	if _G.__tun_install_supported ~= nil then
		return _G.__tun_install_supported
	end
	local command = io.popen("[ \"$(uname -m)\" = armv7l ] && [ \"$(uname -r)\" = 4.1.52 ]; echo $?", "r")
	if not command then
		_G.__tun_install_supported = false
		return false
	end
	local result = command:read("*line")
	command:close()
	_G.__tun_install_supported = (result == "0")
	return _G.__tun_install_supported
end

local m_ver = 0
if marketing_version and marketing_version[1] and marketing_version[1].value then
	local v_str = marketing_version[1].value
	local maj, min = v_str:match("^(%d+)%.(%d+)")
	if maj and min then
		m_ver = tonumber(maj .. "." .. min) or 0
	else
		m_ver = tonumber(v_str:match("^(%d+)")) or 0
	end
end

local mapParams = {
	telstra_webui = "uci.modgui.app.telstra_webui"
}

if m_ver >= 16.3 or (m_ver >= 2.0 and m_ver < 10.0) then
	mapParams.luci_webui = "uci.modgui.app.luci_webui"
	mapParams.blacklist_application = "uci.modgui.app.blacklist_app"
end
mapParams.voipblock_for_mmpbx = "uci.modgui.app.voipblock_for_mmpbx"
mapParams.voipblock_for_asterisk = "uci.modgui.app.voipblock_for_asterisk"
if cputype:match("mips") then
	mapParams.amule_webui = "uci.modgui.app.amule_webui"
end
mapParams.aria2_webui = "uci.modgui.app.aria2_webui"
mapParams.transmission_webui = "uci.modgui.app.transmission_webui"
mapParams.adblock_application = "uci.modgui.app.adblock_app"
mapParams.rsyncd_application = "uci.modgui.app.rsyncd_app"
mapParams.openspeedtest_application = "uci.modgui.app.openspeedtest_app"
if cputype:match("^armv7") or cputype:match("^mips") then
	mapParams.l2tpipsec_application = "uci.modgui.app.l2tpipsec_app"
end
if cputype:match("^armv7") or cputype:match("^mips") then
	if tun_install_supported() then
		mapParams.openvpn_application = "uci.modgui.app.openvpn_app"
	end
end
if cputype:match("^armv7") or cputype == "aarch64" or cputype == "arm64" then
	mapParams.speedtest_application = "uci.modgui.app.speedtest_app"
	mapParams.adguardhome_application = "uci.modgui.app.adguardhome_app"
	if tun_install_supported() then
		mapParams.wireguard_application = "uci.modgui.app.wireguard_app"
	end
	if tun_install_supported() then
		mapParams.tailscale_application = "uci.modgui.app.tailscale_app"
	end
end
if cputype:match("^armv7") then
	mapParams.dumaos_application = "uci.modgui.app.dumaos_app"
end
if m_ver >= 17.3 or (m_ver >= 2.0 and m_ver < 10.0) then
	mapParams.xupnp_application = "uci.modgui.app.xupnp_app"
end

content_helper.getExactContent(mapParams)

local function webui_url(port, path)
	local address = ngx.var.host
	if address:find(":", 1, true) and address:sub(1, 1) ~= "[" then
		address = "[" .. address .. "]"
	end
	return format("http://%s:%s%s", address, port, path or "/")
end

local adguard_port = "3000"
if mapParams.adguardhome_application == "1" then
	local config = io.open("/opt/AdGuardHome/AdGuardHome.yaml", "r")
	if config then
		local in_http = false
		for line in config:lines() do
			if line:match("^http:%s*$") then
				in_http = true
			elseif line:match("^%S") then
				in_http = false
			elseif in_http then
				local port = line:match("address:%s*.*:(%d+)%s*$")
				if port then
					adguard_port = port
					break
				end
			end
		end
		config:close()
	end
end

local StateParams = {}

for Params in pairs(mapParams) do
	extension_supported = extension_supported + 1
	if mapParams[Params] and mapParams[Params] == "1" then
		StateParams[Params] = "1"
	else
		StateParams[Params] = "0"
	end
end

local extension_items = {
	{ key = "luci_webui", title = T"LuCI", url = webui_url("9080") },
	{ key = "aria2_webui", title = T"Aria2", url = "/aria" },
	{ key = "transmission_webui", title = T"Transmission", url = webui_url("9091", "/transmission") },
	{ key = "voipblock_for_mmpbx", title = T"Voipblock MMPBX" },
	{ key = "voipblock_for_asterisk", title = T"Voipblock Asterisk" },
	{ key = "blacklist_application", title = T"Blacklist" },
	{ key = "xupnp_application", title = T"XUPnP", url = webui_url("4044", "/ui/") },
	{ key = "telstra_webui", title = T"Telstra GUI", url = "/telstra-gui.lp" },
	{ key = "amule_webui", title = T"aMule", url = webui_url("4711") },
	{ key = "adblock_application", title = T"Adblock" },
	{ key = "rsyncd_application", title = T"Rsync" },
	{ key = "speedtest_application", title = T"Speedtest" },
	{ key = "adguardhome_application", title = T"AdGuard Home", url = webui_url(adguard_port) },
	{ key = "openspeedtest_application", title = T"OpenSpeedTest", url = webui_url("5678") },
	{ key = "wireguard_application", title = T"WireGuard" },
	{ key = "l2tpipsec_application", title = T"L2TP/IPsec" },
	{ key = "openvpn_application", title = T"OpenVPN" },
	{ key = "tailscale_application", title = T"Tailscale" },
	{ key = "dumaos_application", title = T"DumaOS", url = "/desktop/" },
}

local modalPath = nil
local switchName = nil
local session = ngx.ctx.session
if session:hasAccess("/modals/applications-modal.lp") and extension_supported > 0 then
	modalPath = "/modals/applications-modal.lp"
end
ngx.print('\
<div class="span3">\
  <div class="smallcard extensions-card" data-aos="zoom-in" data-aos-anchor-placement="center-bottom" data-aos-easing="ease-in-back">\
\
    ');  ngx.print( ui_helper.createCardHeader(T"Extensions", modalPath, switchName, nil) ); ngx.print('\
\
    <div class="content card_bg" data-bg-text="&#xf015;">\
	  <div class="divtable extensions-status-grid">\
\
      ');
local html = {}

local active_count = 0
for _, item in ipairs(extension_items) do
	if StateParams[item.key] == "1" then
		active_count = active_count + 1
	end
end

if extension_supported == 0 then
	html[#html + 1] = ui_helper.createSimpleLight("0", T"Not supported", { span = { class = "simple-desc extension-status" } }, nil)
else
    local status_light = active_count > 0 and "1" or "0"
    local status_text = active_count > 0 and format(N("%d extension active", "%d extensions active", active_count), active_count) or T"No extensions active"
    html[#html + 1] = ui_helper.createSimpleLight(status_light, status_text, { span = { class = "simple-desc extension-status" } }, "fa-puzzle-piece")
end

ngx.print(html)
ngx.print('\
\
	  </div>\
    </div>\
  </div>\
</div>\
');
