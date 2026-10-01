--pretranslated: do not change this file
 
-- Localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")

local leds_columns = {
	{ --[1]
		header = T"Color",
		name = "Color",
		param = "Color",
		type = "text",
	},
	{ --[2]
		header = T"Name",
		name = "Name",
		param = "Name",
		type = "text",
	},
	{ --[3]
		header = T"Status",
		name = "Status",
		param = "Status",
		type = "text",
	},
	{ --[4]
		header = T"Brightness",
		name = "Brightness",
		param = "Brightness",
		type = "text",
	}
}

local leds_options = {
	canEdit = false,
	canAdd = false,
	canDelete = false,
	tableid = "ledstable",
	basepath = "rpc.Leds.Led.",
}

local untaint = string.untaint or function(x) return tostring(x) end

local env_data = proxy.get("uci.env.var.prod_friendly_name", "uci.env.var.prod_number", "uci.env.var.hardware_version", "uci.env.rip.board_mnemonic")
local prod_friendly = env_data and env_data[1] and untaint(env_data[1].value) or ""
local prod_number = env_data and env_data[2] and untaint(env_data[2].value) or ""
local hw_version = env_data and env_data[3] and untaint(env_data[3].value) or ""
local board_mnemonic = env_data and env_data[4] and untaint(env_data[4].value) or ""

local model_str = (prod_friendly .. " " .. prod_number .. " " .. hw_version .. " " .. board_mnemonic):upper()

local is_tg789 = model_str:match("TG789") or model_str:match("VANT%-6") or model_str:match("TG788") or model_str:match("TG799") or model_str:match("TG800")
local is_dga4132 = (not is_tg789) and (model_str:match("DGA413") or model_str:match("AGTHP") or model_str:match("AGTEF") or model_str:match("VBNT"))

local name_mapping = {}
local order_mapping = {}

if is_tg789 then
	-- Technicolor TG789vac v2 (Smart Modem): Info -> Broadband -> Internet -> Wireless 2.4 -> Wireless 5 -> WPS -> Ethernet -> TV -> Voice
	name_mapping = {
		["info"] = T"Info",
		["power"] = T"Info",
		["broadband"] = T"Broadband",
		["internet"] = T"Internet",
		["wireless"] = T"Wireless 2.4 GHz",
		["wireless_2.4GHz"] = T"Wireless 2.4 GHz",
		["wireless_5g"] = T"Wireless 5 GHz",
		["wireless_5GHz"] = T"Wireless 5 GHz",
		["wps"] = T"WPS",
		["ethernet"] = T"Ethernet",
		["iptv"] = T"TV",
		["voip"] = T"Voice",
		["dect"] = T"DECT",
	}
	order_mapping = {
		["info"] = 1, ["power"] = 1, ["Info"] = 1, ["Power"] = 1,
		["broadband"] = 2, ["Broadband"] = 2, ["Linea"] = 2, ["ADSL/FIBRA"] = 2,
		["internet"] = 3, ["Internet"] = 3, ["Web"] = 3,
		["wireless"] = 4, ["wireless_2.4GHz"] = 4, ["Wireless 2.4 GHz"] = 4, ["Wi-Fi 2,4"] = 4, ["WiFi (2.4GHz)"] = 4, ["WiFi"] = 4,
		["wireless_5g"] = 5, ["wireless_5GHz"] = 5, ["Wireless 5 GHz"] = 5, ["Wi-Fi 5"] = 5, ["WiFi (5GHz)"] = 5,
		["wps"] = 6, ["WPS"] = 6,
		["ethernet"] = 7, ["Ethernet"] = 7, ["LAN"] = 7,
		["iptv"] = 8, ["TV"] = 8, ["IPTV"] = 8,
		["voip"] = 9, ["Voice"] = 9, ["Voce"] = 9,
		["dect"] = 10, ["DECT"] = 10,
	}
elseif is_dga4132 then
	-- Technicolor DGA4132 / DGA4130 (TIM HUB / Smart Modem Plus): INFOLED -> ADSL/FIBRA -> INTERNET -> Wi-Fi 2,4 -> Wi-Fi 5 -> WPS -> Ethernet -> Voce
	name_mapping = {
		["info"] = T"INFOLED",
		["power"] = T"INFOLED",
		["broadband"] = T"ADSL/FIBRA",
		["internet"] = T"INTERNET",
		["wireless"] = T"Wi-Fi 2,4",
		["wireless_2.4GHz"] = T"Wi-Fi 2,4",
		["wireless_5g"] = T"Wi-Fi 5",
		["wireless_5GHz"] = T"Wi-Fi 5",
		["wps"] = T"WPS",
		["ethernet"] = T"Ethernet",
		["voip"] = T"Voce",
		["iptv"] = T"IPTV",
		["dect"] = T"DECT",
	}
	order_mapping = {
		["info"] = 1, ["power"] = 1, ["INFOLED"] = 1, ["Info"] = 1, ["Power"] = 1,
		["broadband"] = 2, ["ADSL/FIBRA"] = 2, ["Broadband"] = 2, ["Linea"] = 2,
		["internet"] = 3, ["INTERNET"] = 3, ["Internet"] = 3, ["Web"] = 3,
		["wireless"] = 4, ["wireless_2.4GHz"] = 4, ["Wi-Fi 2,4"] = 4, ["Wireless 2.4 GHz"] = 4, ["WiFi (2.4GHz)"] = 4, ["WiFi"] = 4,
		["wireless_5g"] = 5, ["wireless_5GHz"] = 5, ["Wi-Fi 5"] = 5, ["Wireless 5 GHz"] = 5, ["WiFi (5GHz)"] = 5,
		["wps"] = 6, ["WPS"] = 6,
		["ethernet"] = 7, ["Ethernet"] = 7, ["LAN"] = 7,
		["voip"] = 8, ["Voce"] = 8, ["Voice"] = 8,
		["iptv"] = 9, ["IPTV"] = 9, ["TV"] = 9,
		["dect"] = 10, ["DECT"] = 10,
	}
else
	-- DGA4331 (TIM HUB+) and default: Power -> Linea -> Web -> LAN -> WiFi -> WPS -> Voce
	name_mapping = {
		["power"] = T"Power",
		["info"] = T"Power",
		["broadband"] = T"Linea",
		["internet"] = T"Web",
		["ethernet"] = T"LAN",
		["wireless"] = T"WiFi",
		["wireless_2.4GHz"] = T"WiFi (2.4GHz)",
		["wireless_5g"] = T"WiFi (5GHz)",
		["wireless_5GHz"] = T"WiFi (5GHz)",
		["wps"] = T"WPS",
		["voip"] = T"Voce",
		["iptv"] = T"IPTV",
		["dect"] = T"DECT",
	}
	order_mapping = {
		["power"] = 1, ["Power"] = 1, ["info"] = 1, ["Info"] = 1,
		["broadband"] = 2, ["Linea"] = 2, ["Broadband"] = 2, ["ADSL/FIBRA"] = 2,
		["internet"] = 3, ["Web"] = 3, ["Internet"] = 3, ["INTERNET"] = 3,
		["ethernet"] = 4, ["LAN"] = 4, ["Ethernet"] = 4,
		["wireless"] = 5, ["WiFi"] = 5,
		["wireless_2.4GHz"] = 5.1, ["WiFi (2.4GHz)"] = 5.1, ["Wi-Fi 2,4"] = 5.1,
		["wireless_5g"] = 5.2, ["wireless_5GHz"] = 5.2, ["WiFi (5GHz)"] = 5.2, ["Wi-Fi 5"] = 5.2,
		["wps"] = 6, ["WPS"] = 6,
		["voip"] = 7, ["Voce"] = 7, ["Voice"] = 7,
		["iptv"] = 8, ["IPTV"] = 8, ["TV"] = 8,
		["dect"] = 9, ["DECT"] = 9,
	}
end

for k, v in pairs(name_mapping) do
	local ord = order_mapping[k]
	if ord then
		order_mapping[v] = ord
		order_mapping[tostring(v)] = ord
		order_mapping[untaint(v)] = ord
	end
end

local leds_filter = function(data)
	local raw_name = untaint(data.Name)
	data.raw_name = raw_name
	data.Name = name_mapping[raw_name] or raw_name

	local raw_color = untaint(data.Color)
	local color, label
	if not raw_color or raw_color == "None" or raw_color == "" or raw_color == "Off" then
		color = "grey"
		label = "Off"
	else
		color = raw_color:lower()
		label = raw_color
	end
	
	data.Color = ui_helper.createSimpleLight(nil, T(label), { light = { style = "background-color:"..color } })
	
	if data.Status then
		data.Status = T(untaint(data.Status))
	end
	if data.Brightness then
		data.Brightness = untaint(data.Brightness)
	end
	
	return true
end

local leds_data, leds_index = content_helper.loadTableData(leds_options.basepath, leds_columns, leds_filter)

table.sort(leds_data, function(a, b)
	local key_a = untaint(a[2])
	local key_b = untaint(b[2])
	local order_a = order_mapping[key_a] or order_mapping[a[2]] or order_mapping[tostring(key_a)] or 99
	local order_b = order_mapping[key_b] or order_mapping[b[2]] or order_mapping[tostring(key_b)] or 99
	return order_a < order_b
end)

  ngx.print('\
');  ngx.print(ui_helper.createHeader(T"Diagnostics", false, false, 1) ); ngx.print('\
<div class="modal-body update">\
');  
  local lp = require("web.lp")
  lp.setpath("/www/snippets/")
  lp.include("tabs-diagnostics.lp")
  ngx.print('\
');  
-- dummy form so that refresh button knows which page to reload, keep it
  ngx.print('\
  <form class="form-horizontal" method="post" action="modals/diagnostics-leds-modal.lp">\
  </form>\
  <fieldset id="diagnostics-network-tab">\
	<fieldset>\
	<legend>');  ngx.print( T"Leds State" ); ngx.print('</legend>')
	
	ngx.print(ui_helper.createTable(leds_columns, leds_data, leds_options))
	
	ngx.print('\
	</fieldset>\
  </fiedlset>\
  </div>\
');  ngx.print(ui_helper.createFooter() ); ngx.print('\
'); 