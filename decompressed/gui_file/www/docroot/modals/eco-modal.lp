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
    message_helper.addMessage(T"Cache RAM svuotata con successo!", "success")
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
  net_down = vB,

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
  net_down = "uci.power.ethernet.net_down",

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
if ngx.req.get_method() == "POST" and not (ngx.req.get_post_args() and ngx.req.get_post_args().action == "drop_caches") then
  os.execute("/etc/init.d/power reload >/dev/null 2>&1")
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
if not content["phy_down"] or content["phy_down"] == "" then
  content["phy_down"] = "0"
end
if not content["net_down"] or content["net_down"] == "" then
  content["net_down"] = "0"
end

local cpu_step = {
  {'256', T'Auto Scaling (Dinamico)'},
  {'0', T'100% frequenza (Sincrono)'},
  {'1', T'100% frequenza (Asincrono)'},
  {'2', T'50% frequenza (Asincrono)'},
  {'4', T'25% frequenza (Asincrono)'},
  {'8', T'10% frequenza (Asincrono)'}
}

local cpu_cores_options = {
  {'2', T'Dual-Core (Entrambi i core attivi - Prestazioni standard)'},
  {'1', T'Single-Core (Core 1 spento - Massimo risparmio energetico)'}
}

ngx.print(ui_helper.createHeader(T"Eco & Risparmio Energetico", false, false))
ngx.print('<div class="modal-body update">\n')
ngx.print(ui_helper.createMessages(message_helper.popMessages()))

local basic = {
  span = { class = "span5" },
}

local info_box = {
  alert = { class = "alert alert-info" },
}

ngx.print('\
<form class="form-horizontal" method="post" action="modals/eco-modal.lp">\
  <fieldset>\
');

local html = {}

-- SECTION 1: Monitoraggio Termico e Hardware
html[#html + 1] = '<legend>' .. T"Monitoraggio Termico e Hardware" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Rilevazione in tempo reale delle temperature e dello stato operativo dei chip di bordo.", info_box)

html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Frequenza CPU Attuale" .. '</label><div class="controls">'
html[#html + 1] = format('<span class="badge badge-info" style="font-size:14px; padding:6px 12px;"><i class="fas fa-microchip"></i> %s (Governor: %s, Core attivi: %d/2)</span>', cpu_status.cur_freq, cpu_status.governor:upper(), cpu_status.cores_online)
html[#html + 1] = '</div></div>'

if #temperatures > 0 then
  html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Temperature Sensori" .. '</label><div class="controls">'
  for _, t in ipairs(temperatures) do
    local badge_class = "badge-success"
    if t.temp >= 80 then
      badge_class = "badge-important"
    elseif t.temp >= 65 then
      badge_class = "badge-warning"
    end
    html[#html + 1] = format('<span class="badge %s" style="font-size:13px; padding:5px 10px; margin-right:8px; margin-bottom:6px; display:inline-block;"><i class="fas fa-thermometer-half"></i> %s: <strong>%d %s</strong></span>', badge_class, t.sensor, t.temp, t.unit)
  end
  html[#html + 1] = '</div></div>'
end

-- SECTION 2: Prestazioni & Governor CPU
html[#html + 1] = '<legend>' .. T"Prestazioni & Risparmio Energetico CPU" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Configura la logica di scalabilità della frequenza e i consumi del processore ARM. L'attivazione di profili molto conservativi può aumentare la latenza di elaborazione.", info_box)

html[#html + 1] = ui_helper.createInputSelect(T"Governor CPU", "governor", available_governors, content["governor"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Strategia di clock: 'Interactive' reagisce istantaneamente ai picchi di carico (consigliato); 'Ondemand' scala gradualmente in base al carico medio; 'Userspace' mantiene un clock fisso." .. '</small></div></div>'

if #available_freqs > 0 then
  html[#html + 1] = ui_helper.createInputSelect(T"Frequenza Minima CPU", "min_freq", available_freqs, content["min_freq"])
  html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Limite inferiore di clock a riposo (ad es. 200 MHz per consumi minimi)." .. '</small></div></div>'

  html[#html + 1] = ui_helper.createInputSelect(T"Frequenza Massima CPU", "max_freq", available_freqs, content["max_freq"])
  html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Limite superiore di clock sotto carico (1.0 GHz garantisce le massime prestazioni di routing/Wi-Fi)." .. '</small></div></div>'
end

html[#html + 1] = ui_helper.createInputSelect(T"Rapporto Clock Broadcom", "cpuspeed", cpu_step, content["cpuspeed"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Regolatore hardware integrato Broadcom. Lasciare su 'Auto' per consentire al governor Linux il pieno controllo dinamico." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"CPU Wait (Stato WFI)", "wait", content["wait"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Abilita l'istruzione ARM 'Wait-For-Interrupt' (WFI) che arresta i cicli di clock della CPU quando non ci sono task in coda, riducendo calore e consumi." .. '</small></div></div>'

html[#html + 1] = ui_helper.createInputSelect(T"Modalità Core CPU", "cores", cpu_cores_options, content["cores"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Permette di disattivare il secondo core (CPU1) per il massimo risparmio energetico possibile nei carichi leggeri." .. '</small></div></div>'

-- SECTION 3: Risparmio Energetico Ethernet & Switch
html[#html + 1] = '<legend>' .. T"Risparmio Energetico Ethernet & Switch" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Opzioni di riduzione consumi per lo switch Broadcom e i transceiver delle porte LAN fisiche.", info_box)

html[#html + 1] = ui_helper.createSwitch(T"Ethernet EEE (802.3az)", "eee", content["eee"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Energy Efficient Ethernet: riduce l'energia trasmessa sui cavi di rete durante i periodi di inattività del flusso dati." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"AutoGrEEEn (Deep Green Mode)", "autogreeen", content["autogreeen"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Attiva la modalità a bassissimo consumo energetico (DGM) nello switch hardware Broadcom SF2." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"Auto Power Down (APD)", "ethapd", content["ethapd"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Disalimenta i circuiti delle porte LAN quando nessun cavo Ethernet è fisicamente inserito." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"PHY Power Down", "phy_down", content["phy_down"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Spegne i transceiver PHY delle interfacce quando il link è assente o disconnesso." .. '</small></div></div>'

-- SECTION 4: Gestione Memoria RAM & Parametri VM
html[#html + 1] = '<legend>' .. T"Gestione Memoria RAM & Parametri VM" .. '</legend>'
html[#html + 1] = ui_helper.createAlertBlock(T"Regola la politica di allocazione memoria e cache del kernel Linux.", info_box)

html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Stato Memoria" .. '</label><div class="controls">'
html[#html + 1] = format('<span class="badge badge-info" style="font-size:13px; padding:5px 10px; margin-right:6px;">RAM Totale: %d MB</span>', math.floor(mem_info.mem_total / 1024))
html[#html + 1] = format('<span class="badge badge-success" style="font-size:13px; padding:5px 10px; margin-right:6px;">RAM Libera: %d MB</span>', math.floor(mem_info.mem_available / 1024))
html[#html + 1] = format('<span class="badge badge-inverse" style="font-size:13px; padding:5px 10px; margin-right:6px;">Buffer/Cache: %d MB</span>', math.floor(mem_info.buff_cache / 1024))
if mem_info.swap_total > 0 then
  html[#html + 1] = format('<span class="badge badge-warning" style="font-size:13px; padding:5px 10px;">Swap: %d / %d MB</span>', math.floor(mem_info.swap_used / 1024), math.floor(mem_info.swap_total / 1024))
else
  html[#html + 1] = '<span class="badge" style="font-size:13px; padding:5px 10px;">Swap: Non presente / Non configurato</span>'
end
html[#html + 1] = '</div></div>'

html[#html + 1] = ui_helper.createInputText(T"VM Swappiness (0-100)", "swappiness", content["swappiness"], basic, helpmsg["swappiness"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Preferenza del kernel tra rilascio della cache e uso dell'eventuale swap (default: 60). Valori bassi (es. 10-20) mantengono i processi attivi in RAM ed evitano swap aggressivo." .. '</small></div></div>'

html[#html + 1] = ui_helper.createInputText(T"VM Cache Pressure (0-200)", "vfs_cache_pressure", content["vfs_cache_pressure"], basic, helpmsg["vfs_cache_pressure"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Frequenza con cui il kernel reclama le memorie cache di directory e inode (default: 100). Valori più alti liberano memoria cache più rapidamente a fronte di letture disco." .. '</small></div></div>'

html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Libera Memoria" .. '</label><div class="controls">'
html[#html + 1] = '<button type="submit" name="action" value="drop_caches" class="btn btn-warning"><i class="fas fa-broom"></i> ' .. T"Svuota Cache RAM (Drop Caches)" .. '</button>'
html[#html + 1] = '<span class="help-inline" style="margin-left:10px;">' .. T"Forza il rilascio istantaneo di buffer e memorie di cache non utilizzate." .. '</span></div></div>'

-- SECTION 5: Gestione LED
html[#html + 1] = '<legend>' .. T"Gestione Indicatori LED" .. '</legend>'

if prod_name:match("4130") or prod_name:match("4132") or prod_name:match("TG789") then
  html[#html + 1] = ui_helper.createSwitch(T"WiFi NSC (LED Wi-Fi dinamici)", "ledfw_wifinsc", content["ledfw_wifinsc"])
  html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Accende i LED Wi-Fi sul frontale solo quando almeno un dispositivo client è effettivamente connesso alla rete." .. '</small></div></div>'
end

if prod_name:match("DGA4131") then
  html[#html + 1] = ui_helper.createSwitch(T"LED Ambientale", "ledfw_ambient", content["ledfw_ambient"])
  html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Attiva o disattiva l'illuminazione a LED ambientale integrata nel telaio." .. '</small></div></div>'
else
  html[#html + 1] = ui_helper.createSwitch(T"Modalità Eco LED", "eco_led", content["eco_led"])
  html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Spegne tutti i LED del frontale (ad eccezione del LED di stato 'Info') una volta che i servizi sono operativi. Premere il tasto fisico sul modem per mostrare temporaneamente i LED." .. '</small></div></div>'
end

html[#html + 1] = ui_helper.createInputText(T"Timeout Spegnimento LED (ms)", "eco_led_timeout", content["eco_led_timeout"], basic, helpmsg["eco_led_timeout"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"Tempo di attesa (in millisecondi) prima di applicare lo spegnimento dei LED dopo l'avvio o la riattivazione temporanea." .. '</small></div></div>'

html[#html + 1] = ui_helper.createAlertBlock(T"Seleziona quali servizi devono essere necessariamente attivi e funzionanti prima di spegnere i LED dei servizi e mantenere solo il LED Info verde.", info_box)

html[#html + 1] = ui_helper.createSwitch(T"Verifica Telefonia (VoIP)", "ledfw_voip", content["ledfw_voip"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"I LED non si spegneranno finché la registrazione dell'account telefonico VoIP non sarà completata con successo." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"Verifica IPTV", "ledfw_iptv", content["ledfw_iptv"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"I LED non si spegneranno finché il flusso del servizio televisivo IPTV non risulterà agganciato e attivo." .. '</small></div></div>'

html[#html + 1] = ui_helper.createSwitch(T"Verifica Connessione Internet", "ledfw_internet", content["ledfw_internet"])
html[#html + 1] = '<div class="control-group" style="margin-top:-10px; margin-bottom:15px;"><div class="controls"><small class="text-muted"><i class="fas fa-info-circle"></i> ' .. T"I LED non si spegneranno finché la sessione Internet (WAN/PPP) non sarà stabilita con un indirizzo IP valido." .. '</small></div></div>'

ngx.print(html)

ngx.print('\
  </fieldset>\
</form>\
</div>\
');

ngx.print(ui_helper.createFooter())
