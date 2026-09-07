--pretranslated: do not change this file

-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local post_helper = require("web.post_helper")
local content_helper = require("web.content_helper")
local format = string.format
local tinsert = table.insert
local untaint = string.untaint or function(x) return x end

local content = {
  dsl0_enabled = "uci.xdsl.xdsl.@dsl0.enabled",
  dsl0_status = "sys.class.xdsl.@line0.Status",
  dsl0_xdsl_FirmwareVersion = "rpc.xdslctl.DslFirmwareVersion",
  dsl0_mode = "rpc.xdslctl.ModulationType",
  dsl0_profile = "rpc.xdslctl.Profile",
  dsl0_linkencapsulation = "rpc.xdslctl.LinkEncapsulationUsed",
  dsl0_port = "rpc.xdslctl.VdslDslamPort",
  dsl0_handshake_switch_timeout = "uci.xdsl.xdsl.@dsl0.handshake_switch_timeout",
  dsl0_demod_cap_value = "uci.xdsl.xdsl.@dsl0.demod_cap_value",
  dsl0_demod_cap_mask = "uci.xdsl.xdsl.@dsl0.demod_cap_mask",
  dsl0_demod_cap2_value = "uci.xdsl.xdsl.@dsl0.demod_cap2_value",
  dsl0_demod_cap2_mask = "uci.xdsl.xdsl.@dsl0.demod_cap2_mask",
  dsl0_aux_features_value = "uci.xdsl.xdsl.@dsl0.aux_features_value",
  dsl0_aux_features_mask = "uci.xdsl.xdsl.@dsl0.aux_features_mask",
  dsl0_vdsl_cfg_flags_value = "uci.xdsl.xdsl.@dsl0.vdsl_cfg_flags_value",
  dsl0_vdsl_cfg_flags_mask = "uci.xdsl.xdsl.@dsl0.vdsl_cfg_flags_mask",
  dsl0_xdsl_cfg1_value = "uci.xdsl.xdsl.@dsl0.xdsl_cfg1_value",
  dsl0_xdsl_cfg1_mask = "uci.xdsl.xdsl.@dsl0.xdsl_cfg1_mask",
  dsl0_eoc_vendor_id = "rpc.xdslctl.EocVendorId",
  dsl0_eoc_serial_number = "rpc.xdslctl.EocSerialNumber",
  dslam_chipset = "rpc.xdslctl.DslamChipset",
  dslam_version = "rpc.xdslctl.DslamVersion",
  dslam_version_raw = "rpc.xdslctl.DslamVersionRaw",
  dslam_serial = "rpc.xdslctl.VdslDslamSerial",
}

content_helper.getExactContent(content)

local all_modes = {
  "adsl2",
  "adsl2annexl",
  "adsl2annexm",
  "adsl2plus",
  "gdmt",
  "glite",
  "t1413",
  "vdsl2"
}

local modes_content = proxy.get("uci.xdsl.xdsl.@dsl0.multimode.")
if not modes_content then
  modes_content = {}
end

local vB = post_helper.validateBoolean
local vNES = post_helper.validateNonEmptyString

local driver_valid = {
  dsl0_enabled = vB,
  ds10_sra = vB,
  ds10_bitswap = vB,
  ds10_snr = post_helper.validateStringIsNumber,
}

local driver_Params = {
  dsl0_enabled = "uci.xdsl.xdsl.@dsl0.enabled",
  ds10_sra = "uci.xdsl.xdsl.@dsl0.sra",
  ds10_bitswap = "uci.xdsl.xdsl.@dsl0.bitswap",
  ds10_snr = "uci.xdsl.xdsl.@dsl0.snrmargin_offset",
}

local profile_list = ""
local profiles = proxy.get("uci.xdsl.xdsl.@dsl0.profile.")
if profiles then
  for _, v in pairs(profiles) do
    profile_list = profile_list .. v.value .. ", "
  end
  profile_list = profile_list:sub(1, -3)
end

if ngx.var.request_method == "POST" then
  local vars = ngx.req.get_post_args()
  if vars["modes"] then
    local path = "uci.xdsl.xdsl.@dsl0.multimode."
    for _, v in pairs(modes_content) do
      proxy.del(v.path:sub(1, -7))
    end
    if type(vars["modes"]) == "table" then
      for _, v in pairs(vars["modes"]) do
        local index = proxy.add(path)
        proxy.set(path .. "@" .. index .. ".value", v)
      end
    else
      local index = proxy.add(path)
      proxy.set(path .. "@" .. index .. ".value", vars["modes"])
    end
    proxy.apply()
  end
end

local driver_option = {}
if content.dsl0_xdsl_FirmwareVersion and content.dsl0_xdsl_FirmwareVersion:match(".*H045") then
  tinsert(driver_option, {"A2pvfbH045d", "A2pvfbH045d (AGTEF 1.0.3)"})
  tinsert(driver_option, {"A2pvfbH045j", "A2pvfbH045j (DGA4130 1.0.3)"})
  tinsert(driver_option, {"A2pvfbH045k", "A2pvfbH045k (SmartRG SR516ac)"})
  tinsert(driver_option, {"A2pvfbH045m", "A2pvfbH045m (DGA4132 1.0.1)"})
  tinsert(driver_option, {"A2pvfbH045o1", "A2pvfbH045o1 (Zyxel VMG4005-B50A_5.15(ABQA.0)C0)"})
  tinsert(driver_option, {"A2pvfbH045p", "A2pvfbH045p (DGA4131FWB 18.3.n)"})
  tinsert(driver_option, {"A2pvfbH045q", "A2pvfbH045q (iopsys 5.1.0RC4)"})
  tinsert(driver_option, {"A2pvfbH045r", "A2pvfbH045r (AGTHP_2.2.2_001)"})
  tinsert(driver_option, {"A2pvfbH045s", "A2pvfbH045s (AGTHF_1.0.2)"})
  tinsert(driver_option, {"A2pvfbH046w", "A2pvfbH046w (FRITZ!Box 7582 7.13-84683)"})
  tinsert(driver_option, {"A2pvfbH046u", "A2pvfbH046u (vbnt-v_20.3.c.0329-MR19-RA)"})
  tinsert(driver_option, {"A2pvfbH046y", "A2pvfbH046y (FRITZ!Box 7582 7.14-88881)"})
  driver_Params.driver_ver = "rpc.xdslctl.DslFirmwareVersion"
  driver_valid.driver_ver = post_helper.getValidateInEnumSelect(driver_option)
elseif content.dsl0_xdsl_FirmwareVersion and content.dsl0_xdsl_FirmwareVersion:match(".*F039") then
  tinsert(driver_option, {"B2pv6F039k", "B2pv6F039k (TP-Link Archer VR900vV1)"})
  tinsert(driver_option, {"B2pv6F039v", "B2pv6F039v (789vacV2 UNO.uk 17.1/Tiscali 16.3 Backup)"})
  tinsert(driver_option, {"A2pv6F038f2", "A2pv6F038f2 (Comtrend VR-3032u)"})
  tinsert(driver_option, {"A2pv6F039e", "A2pv6F039e (Huawei HG635)"})
  tinsert(driver_option, {"A2pv6F039f1", "A2pv6F039f1 (Indeno D301)"})
  tinsert(driver_option, {"A2pv6F039m1", "A2pv6F039m1 (Sky NR701-NR801)"})
  tinsert(driver_option, {"A2pv6F039o1", "A2pv6F039o1 (Telstra TG799vac)"})
  tinsert(driver_option, {"A2pv6F039t", "A2pv6F039t (Netgear D6400)"})
  tinsert(driver_option, {"A2pv6F039u", "A2pv6F039u (Netgear D6220 v1.0.0.48/Sercomm VD625)"})
  tinsert(driver_option, {"A2pv6F039v", "A2pv6F039v (SmartRG sr516ac/Tp-link Archer VR600V1)"})
  tinsert(driver_option, {"A2pv6F039v2", "A2pv6F039v2 (789vacV2 UNO.uk 17.1/Tiscali 16.3)"})
  tinsert(driver_option, {"A2pv6F039v4", "A2pv6F039v4 (Inteno D301)"})
  tinsert(driver_option, {"A2pv6F039x1", "A2pv6F039x1 (Zyxel VMG3926)"})
  tinsert(driver_option, {"A2pv6F039x5", "A2pv6F039x5 (SmartRG SR505N/SR515AC 2.6.1.9)"})
  tinsert(driver_option, {"A2pv6F039x6", "A2pv6F039x6 (Zyxel VMG3926-B10B)"})
  driver_Params.driver_ver = "rpc.xdslctl.DslFirmwareVersion"
  driver_valid.driver_ver = post_helper.getValidateInEnumSelect(driver_option)
end

local driver_content, helpmsg = post_helper.handleQuery(driver_Params, driver_valid)

ngx.print(ui_helper.createHeader(T"Configurazione xDSL", false, false))
ngx.print('<div class="modal-body update">\n')
ngx.print(ui_helper.createMessages(message_helper.popMessages()))

local span5 = {span = {class = "span5"}}
local alertinfo = {alert = {class = "alert alert-info"}}
local is_disabled = (untaint(content.dsl0_enabled) == "0")
local html = {}

ngx.print('\
<form class="form-horizontal" method="post" action="modals/xdsl-low-modal.lp">\
  <fieldset>\
')

-- SECTION 1: Impostazioni di Base
html[#html + 1] = '<legend>' .. T"Impostazioni di Base" .. '</legend>'

if is_disabled then
  html[#html + 1] = ui_helper.createAlertBlock(
    T"L'interfaccia xDSL è attualmente disattivata. Questa configurazione è ottimale quando il modem opera in modalità Bridge o Access Point (la connessione Internet proviene dalla porta WAN Ethernet). Abilitare l'interruttore sottostante solo se si desidera allineare il modem sulla linea telefonica DSL.",
    alertinfo
  )
end

html[#html + 1] = ui_helper.createSwitch(T"Interfaccia xDSL", "dsl0_enabled", driver_content["dsl0_enabled"])

local conn_status_text
if is_disabled then
  conn_status_text = T"Disattivato (Circuito DSL spento)"
elseif content.dsl0_status == "Up" then
  conn_status_text = T"Connesso (Allineato)"
else
  conn_status_text = T(content.dsl0_status or "Inizializzazione...")
end
html[#html + 1] = ui_helper.createLabel(T"Stato Connessione DSL", conn_status_text, span5)

local datapump_text
if is_disabled or not content.dsl0_xdsl_FirmwareVersion or content.dsl0_xdsl_FirmwareVersion == "" or content.dsl0_xdsl_FirmwareVersion:match("not found") then
  datapump_text = is_disabled and T"Non disponibile (interfaccia disattivata)" or T"In rilevamento..."
else
  datapump_text = content.dsl0_xdsl_FirmwareVersion
end
html[#html + 1] = ui_helper.createLabel(T"Versione Datapump", datapump_text, span5)

if not driver_Params.driver_ver then
  html[#html + 1] = ui_helper.createLabel(
    T"Driver xDSL",
    T"Versione originale di sistema",
    span5
  )
else
  html[#html + 1] = ui_helper.createInputSelect(T"Driver xDSL", "driver_ver", driver_option, driver_content["driver_ver"])
end

local reset_driver = {
  button = {
    id = "btn-reset-driver"
  }
}
html[#html + 1] = ui_helper.createButton(T"Ripristina Driver", T"Ripristina driver originale", "icon-refresh", reset_driver)

-- SECTION 2: Parametri di Linea
html[#html + 1] = '<legend>' .. T"Parametri di Linea" .. '</legend>'

html[#html + 1] = ui_helper.createSwitch(T"SRA (Rate Adaptation)", "ds10_sra", driver_content["ds10_sra"])
html[#html + 1] = ui_helper.createSwitch(T"Bitswap", "ds10_bitswap", driver_content["ds10_bitswap"])

html[#html + 1] = ui_helper.createAlertBlock(
  T"La modifica dell'offset SNR ha effetto solo con connessioni ADSL / ADSL2+. Su linee VDSL2 questo valore viene ignorato dal DSLAM.",
  alertinfo
)
html[#html + 1] = ui_helper.createInputText(T"Offset Margine SNR", "ds10_snr", driver_content["ds10_snr"], span5, helpmsg["ds10_snr"])

local mode_labels = {
  adsl2 = "ADSL2 (G.992.3)",
  adsl2annexl = "ADSL2 Annex L (RE-ADSL)",
  adsl2annexm = "ADSL2 Annex M",
  adsl2plus = "ADSL2+ (G.992.5)",
  gdmt = "G.Dmt (ADSL G.992.1)",
  glite = "G.Lite (G.992.2)",
  t1413 = "ANSI T1.413",
  vdsl2 = "VDSL2 (G.993.2)"
}

html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Modalità Supportate" .. '</label><div class="controls"><select multiple="multiple" class="span5" size="6" name="modes">'
for i = 1, #all_modes do
  local selected = ""
  for _, w in pairs(modes_content) do
    if all_modes[i] == w.value then
      selected = "selected"
    end
  end
  local lbl = mode_labels[all_modes[i]] or all_modes[i]
  html[#html + 1] = format('<option value="%s" %s>%s</option>', all_modes[i], selected, lbl)
end
html[#html + 1] = '</select></div></div>'

html[#html + 1] = ui_helper.createLabel(T"Profili VDSL", profile_list or T"Nessuno", span5)

-- SECTION 3: Dettagli DSLAM (solo se connesso Up)
if (content.dsl0_status == "Up") then
  html[#html + 1] = '<legend>' .. T"Dettagli DSLAM & Connessione" .. '</legend>'
  html[#html + 1] = ui_helper.createLabel(T"Modalità DSL", content.dsl0_mode .. " (" .. content.dsl0_linkencapsulation .. ")", span5)
  if (content.dsl0_profile ~= "Not Found") then
    html[#html + 1] = ui_helper.createLabel(T"Profilo VDSL", content.dsl0_profile, span5)
  end
  if (content.dsl0_port ~= "") then
    html[#html + 1] = ui_helper.createLabel(T"Porta DSLAM VDSL", content.dsl0_port, span5)
  end
  if (content.dslam_serial ~= "") then
    html[#html + 1] = ui_helper.createLabel(T"Seriale DSLAM", content.dslam_serial, span5)
  end
  html[#html + 1] = ui_helper.createLabel(T"Chipset DSLAM", content.dslam_chipset, span5)
  if content.dslam_version_raw:sub(0, 2) == "0x" then
    html[#html + 1] = ui_helper.createLabel(
      T"Firmware DSLAM",
      format("%s ( %s )", content.dslam_version, content.dslam_version_raw),
      span5
    )
  elseif content.dslam_version_raw == "" then
    html[#html + 1] = ui_helper.createLabel(T"Firmware DSLAM", T"Versione non rilevata", span5)
  else
    html[#html + 1] = ui_helper.createLabel(
      T"Firmware DSLAM",
      format(T"Valore grezzo: %s", content.dslam_version_raw),
      span5
    )
  end
end

-- SECTION 4: Identificativi EOC & Registri PHY
html[#html + 1] = '<legend>' .. T"Registri Demod & PHY" .. '</legend>'

html[#html + 1] = ui_helper.createLabel(T"Vendor ID EOC", content.dsl0_eoc_vendor_id or "-", span5)
html[#html + 1] = ui_helper.createLabel(T"Numero Seriale EOC", content.dsl0_eoc_serial_number or "-", span5)
html[#html + 1] = ui_helper.createLabel(T"Timeout Switch HS", format("%s s", content.dsl0_handshake_switch_timeout or "0"), span5)

html[#html + 1] = '<div class="control-group"><label class="control-label">' .. T"Registri Demod / PHY" .. '</label><div class="controls">'
html[#html + 1] = format([[
<table class="table table-bordered table-striped table-condensed span5" style="margin-left:0; margin-bottom:0;">
  <thead>
    <tr>
      <th>%s</th>
      <th>%s</th>
      <th>%s</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Cap Demod 1</td><td><code>%s</code></td><td><code>%s</code></td></tr>
    <tr><td>Cap Demod 2</td><td><code>%s</code></td><td><code>%s</code></td></tr>
    <tr><td>Aux Features</td><td><code>%s</code></td><td><code>%s</code></td></tr>
    <tr><td>VDSL Cfg Flags</td><td><code>%s</code></td><td><code>%s</code></td></tr>
    <tr><td>Phy Extra</td><td><code>%s</code></td><td><code>%s</code></td></tr>
  </tbody>
</table>
</div></div>
]],
  T"Registro", T"Valore", T"Maschera",
  content.dsl0_demod_cap_value or "-", content.dsl0_demod_cap_mask or "-",
  content.dsl0_demod_cap2_value or "-", content.dsl0_demod_cap2_mask or "-",
  content.dsl0_aux_features_value or "-", content.dsl0_aux_features_mask or "-",
  content.dsl0_vdsl_cfg_flags_value or "-", content.dsl0_vdsl_cfg_flags_mask or "-",
  content.dsl0_xdsl_cfg1_value or "-", content.dsl0_xdsl_cfg1_mask or "-"
)

ngx.print(html)

ngx.print('\
  </fieldset>\
</form>\
</div>\
<script>\
  $("#save-config").on("click", function() {\
    var installed = $("[id=\'Datapump Version\']").text();\
    if ($("#driver_ver") && $("#driver_ver").val() != installed.substring(0, installed.indexOf("."))) {\
      window.setTimeout(function () { modgui.postAction("installdriver", 1); }, 1000);\
    }\
  });\
  $("#btn-reset-driver").on("click", function () {\
    modgui.postAction("resetdriver", 1);\
  });\
</script>\
');

ngx.print(ui_helper.createFooter())
