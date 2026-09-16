--pretranslated: do not change this file

-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local post_helper = require("web.post_helper")
local content_helper = require("web.content_helper")
local eco_helper = require("eco_helper")
local untaint = string.untaint or function(x) return x end
local format = string.format

local prod_friendly_name = proxy.get("uci.env.var.prod_friendly_name")
local prod_name = prod_friendly_name and untaint(prod_friendly_name[1].value) or ""

-- Handle drop caches action
if ngx.req.get_method() == "POST" then
  local post_args = ngx.req.get_post_args()
  if post_args and post_args.action == "drop_caches" then
    eco_helper.dropCaches()
    message_helper.pushMessage(T"RAM cache emptied successfully.", "success")
  end
end

local vB = post_helper.validateBoolean
local vS = post_helper.validateNonEmptyString
local vP = post_helper.validatePositiveNum

local mapValid = {
  -- Ethernet
  eee = vB,
  autogreeen = vB,
  ethapd = vB,
  phy_down = vB,

  -- CPU
  wait = vB,
  cpuspeed = vS,
  governor = vS,
  min_freq = vS,
  max_freq = vS,
  cores = vS,

  -- VM / Memory
  swappiness = vP,
  vfs_cache_pressure = vP,

  -- LED
  ledfw_internet = vB,
  ledfw_voip = vB,
  ledfw_iptv = vB,
  eco_led_timeout = vP,
}

local mapParams = {
  eee = "uci.power.ethernet.eee",
  autogreeen = "uci.power.ethernet.autogreeen",
  ethapd = "uci.power.ethernet.ethapd",
  phy_down = "uci.power.ethernet.phy_down",

  wait = "uci.power.cpu.wait",
  cpuspeed = "uci.power.cpu.cpuspeed",
  governor = "uci.power.cpu.governor",
  min_freq = "uci.power.cpu.min_freq",
  max_freq = "uci.power.cpu.max_freq",
  cores = "uci.power.cpu.cores",

  swappiness = "uci.power.vm.swappiness",
  vfs_cache_pressure = "uci.power.vm.vfs_cache_pressure",

  ledfw_internet = "uci.ledfw.internet.check",
  ledfw_voip = "uci.ledfw.voip.check",
  ledfw_iptv = "uci.ledfw.iptv.check",
  eco_led_timeout = "uci.ledfw.timeout.ms",
}

if prod_name:match("DGA4131") then
  mapValid.ledfw_ambient = vB
  mapParams.ledfw_ambient = "uci.ledfw.ambient.active"
else
  mapValid.eco_led = vB
  mapValid.ledfw_wifinsc = vB
  mapParams.eco_led = "uci.ledfw.status_led.enable"
  mapParams.ledfw_wifinsc = "uci.ledfw.wifi.nsc_on"
end

local content, helpmsg = post_helper.handleQuery(mapParams, mapValid)

-- Trigger power init script reload on successful POST
if ngx.req.get_method() == "POST" and not helpmsg then
  local post_args = ngx.req.get_post_args()
  if post_args and post_args.action == "SAVE" then
    os.execute("/etc/init.d/power reload >/dev/null 2>&1 &")
  end
end

-- Live hardware data
local cpu_status = eco_helper.getCpuStatus()
local temperatures = eco_helper.getTemperatures()
local mem_info = eco_helper.getMemoryInfo()

local available_governors = eco_helper.getAvailableGovernors()
local available_freqs = eco_helper.getAvailableFrequencies()

-- Set defaults from live system if not in UCI
if not content["governor"] or content["governor"] == "" then
  content["governor"] = cpu_status.governor
end
if not content["min_freq"] or content["min_freq"] == "" then
  content["min_freq"] = cpu_status.min_freq
end
if not content["max_freq"] or content["max_freq"] == "" then
  content["max_freq"] = cpu_status.max_freq
end
if not content["cores"] or content["cores"] == "" then
  content["cores"] = tostring(cpu_status.cores_online)
end
if not content["swappiness"] or content["swappiness"] == "" then
  content["swappiness"] = tostring(mem_info.swappiness)
end
if not content["vfs_cache_pressure"] or content["vfs_cache_pressure"] == "" then
  content["vfs_cache_pressure"] = tostring(mem_info.vfs_cache_pressure)
end

local cpu_step = {
  {'256', T'Auto (Dynamic)'},
  {'0', '1/1 (100% sincrono)'},
  {'1', '1/1 (100% asincrono)'},
  {'2', '1/2 (50%)'},
  {'4', '1/4 (25%)'},
  {'8', '1/8 (12.5%)'}
}

local cpu_cores_options = {
  {'2', T'Dual-Core (2 active cores - Standard)'},
  {'1', T'Single-Core (1 active core - Saving)'}
}

ngx.print(ui_helper.createHeader(T"Eco & Energy Saving", false, false))
ngx.print('<div class="modal-body update">\n')
ngx.print(ui_helper.createMessages(message_helper.popMessages()))

local span5 = {
  span = { class = "span5" },
}

local info_box = {
  alert = { class = "alert alert-info" },
}

ngx.print('\
<form class="form-horizontal" method="post" action="modals/eco-modal.lp">\
  <fieldset>\
')

local html = {}

-- SEZIONE 1: Stato Hardware & Sensori
html[#html + 1] = '<legend>' .. T"System & Sensors Status" .. '</legend>'

-- CPU info
local cpu_display = format("<strong>%s</strong> &mdash; Governor: %s (%d core attivi)", cpu_status.cur_freq, cpu_status.governor:upper(), cpu_status.cores_online)
html[#html + 1] = ui_helper.createLabel(T"Processor (CPU)", cpu_display, span5)

-- Temperature info
local temp_parts = {}
if #temperatures > 0 then
  for _, t in ipairs(temperatures) do
    temp_parts[#temp_parts + 1] = format("%s: <strong>%d %s</strong>", t.sensor, t.temp, t.unit)
  end
end
local temp_display = (#temp_parts > 0) and table.concat(temp_parts, " &nbsp;|&nbsp; ") or T"No sensor available"
html[#html + 1] = ui_helper.createLabel(T"Temperature Radio / SoC", temp_display, span5)

-- RAM info
local ram_total_mb = math.floor(mem_info.mem_total / 1024)
local ram_free_mb = math.floor(mem_info.mem_available / 1024)
local ram_cache_mb = math.floor(mem_info.buff_cache / 1024)
local ram_display = format("<strong>%d MB liberi</strong> su %d MB (%d MB cache)", ram_free_mb, ram_total_mb, ram_cache_mb)
html[#html + 1] = ui_helper.createLabel(T"RAM Memory", ram_display, span5)

if mem_info.swap_total > 0 then
  local swap_used_mb = math.floor(mem_info.swap_used / 1024)
  local swap_total_mb = math.floor(mem_info.swap_total / 1024)
  html[#html + 1] = ui_helper.createLabel(T"Swap Memory", format("%d MB usati su %d MB", swap_used_mb, swap_total_mb), span5)
end

-- SEZIONE 2: Configurazione CPU & Prestazioni
html[#html + 1] = '<legend>' .. T"CPU & Performance Configuration" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Adjusts the frequency scaling logic and energy profiles of the ARM Broadcom processor. Conservative profiles reduce heat and consumption, but can introduce slight latency in network flows.", info_box)

html[#html + 1] = ui_helper.createInputSelect(T"Governor CPU", "governor", available_governors, content["governor"])
if #available_freqs > 0 then
  html[#html + 1] = ui_helper.createInputSelect(T"Minimum CPU Frequency", "min_freq", available_freqs, content["min_freq"])
  html[#html + 1] = ui_helper.createInputSelect(T"Maximum CPU Frequency", "max_freq", available_freqs, content["max_freq"])
end
html[#html + 1] = ui_helper.createInputSelect(T"Broadcom Clock Ratio", "cpuspeed", cpu_step, content["cpuspeed"])
html[#html + 1] = ui_helper.createSwitch(T"CPU Wait (Stato WFI)", "wait", content["wait"])
html[#html + 1] = ui_helper.createInputSelect(T"CPU Core Mode", "cores", cpu_cores_options, content["cores"])

-- SEZIONE 3: Risparmio Energetico Ethernet
html[#html + 1] = '<legend>' .. T"Ethernet Energy Saving" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Configure power saving features for the integrated Broadcom switch and physical LAN port transceivers (802.3az).", info_box)

html[#html + 1] = ui_helper.createSwitch(T"Ethernet EEE (802.3az)", "eee", content["eee"])
html[#html + 1] = ui_helper.createSwitch(T"Ethernet AutoGrEEEn", "autogreeen", content["autogreeen"])
html[#html + 1] = ui_helper.createSwitch(T"Auto Power Down (APD)", "ethapd", content["ethapd"])
html[#html + 1] = ui_helper.createSwitch(T"PHY Power Down", "phy_down", content["phy_down"])

-- SEZIONE 4: Gestione Memoria RAM & Cache
html[#html + 1] = '<legend>' .. T"RAM & Cache Memory Management" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Adjusts the virtual memory parameters of the Linux kernel. Low swappiness values keep processes active in physical RAM and avoid aggressive swapping.", info_box)

html[#html + 1] = ui_helper.createInputText(T"VM Swappiness (0-100)", "swappiness", content["swappiness"], span5, helpmsg["swappiness"])
html[#html + 1] = ui_helper.createInputText(T"VM Cache Pressure (0-200)", "vfs_cache_pressure", content["vfs_cache_pressure"], span5, helpmsg["vfs_cache_pressure"])

local drop_cache_btn = {
  button = {
    id = "btn-drop-caches"
  }
}
html[#html + 1] = ui_helper.createButton(T"Cache Memory", T"Clear RAM Cache (Drop Caches)", "icon-refresh", drop_cache_btn)

-- SEZIONE 5: Indicatori LED
html[#html + 1] = '<legend>' .. T"LED Indicator Settings" .. '</legend>'

if prod_name:match("4130") or prod_name:match("4132") or prod_name:match("TG789") then
  html[#html + 1] = ui_helper.createAlertBlock(T"Turns on the front Wi-Fi LEDs only when at least one client is connected to the radio network.", info_box)
  html[#html + 1] = ui_helper.createSwitch(T"WiFi NSC (Dynamic LEDs)", "ledfw_wifinsc", content["ledfw_wifinsc"])
end

if prod_name:match("DGA4131") then
  html[#html + 1] = ui_helper.createSwitch(T"Ambient LED", "ledfw_ambient", content["ledfw_ambient"])
else
  html[#html + 1] = ui_helper.createAlertBlock(T"Turns off all front LEDs (except the Info LED) when services are operational. Press the Info/Wi-Fi button on the modem to turn them back on temporarily.", info_box)
  html[#html + 1] = ui_helper.createSwitch(T"Eco LED Mode", "eco_led", content["eco_led"])
end

html[#html + 1] = ui_helper.createInputText(T"Timeout Spegnimento LED (ms)", "eco_led_timeout", content["eco_led_timeout"], span5, helpmsg["eco_led_timeout"])

html[#html + 1] = ui_helper.createAlertBlock(T"Select which services must be active and verified before turning off the service LEDs:", info_box)
html[#html + 1] = ui_helper.createSwitch(T"Check Telephony (VoIP)", "ledfw_voip", content["ledfw_voip"])
html[#html + 1] = ui_helper.createSwitch(T"Check IPTV", "ledfw_iptv", content["ledfw_iptv"])
html[#html + 1] = ui_helper.createSwitch(T"Check Internet Connection", "ledfw_internet", content["ledfw_internet"])

ngx.print(html)

ngx.print('\
  </fieldset>\
</form>\
</div>\
<script>\
  $("#btn-drop-caches").on("click", function() {\
    var form = $(this).closest("form");\
    $("<input type=\'hidden\' name=\'action\' value=\'drop_caches\'>").appendTo(form);\
    form.submit();\
  });\
</script>\
');

ngx.print(ui_helper.createFooter())
