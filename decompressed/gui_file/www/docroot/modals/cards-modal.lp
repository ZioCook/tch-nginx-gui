--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local uci = require("uci"):cursor()
local string, table, ngx = string, table, ngx

local cards_meta = {
  -- Category 1: Network & Connectivity
  gateway_card = { title = T"Modem", category = 1, order = 1 },
  boradband_card = { title = T"Broadband", category = 1, order = 2 },
  internet_card = { title = T"Internet Access", category = 1, order = 3 },
  wireless_card = { title = T"Wireless", category = 1, order = 4 },
  lan_card = { title = T"Local Network", category = 1, order = 5 },
  devices_card = { title = T"Devices", category = 1, order = 6 },
  wanservices_card = { title = T"WAN Services", category = 1, order = 7 },
  xdsl_card = { title = T"xDSL Configuration", category = 1, order = 8 },
  lte_card = { title = T"Mobile", category = 1, order = 9 },
  speedservice_card = { title = T"Speed Test", category = 1, order = 10 },

  -- Category 2: Security & Routing
  firewall_card = { title = T"Firewall", category = 2, order = 11 },
  qos_card = { title = T"QoS", category = 2, order = 12 },
  natalghelper_card = { title = T"NAT Helpers", category = 2, order = 13 },
  iproutes_card = { title = T"IP Extras", category = 2, order = 14 },
  parental_card = { title = T"Parental Controls", category = 2, order = 15 },
  tod_card = { title = T"Time of Day", category = 2, order = 16 },
  relaysetup_card = { title = T"Relay Setup", category = 2, order = 17 },

  -- Category 3: System & Services
  modgui_card = { title = T"GUI Settings", category = 3, order = 18 },
  usermgr_card = { title = T"Management", category = 3, order = 19 },
  system_card = { title = T"System Extras", category = 3, order = 20 },
  diagnostics_card = { title = T"Diagnostics", category = 3, order = 21 },
  eco_card = { title = T"Eco", category = 3, order = 22 },
  contentsharing_card = { title = T"Content Sharing", category = 3, order = 23 },
  printersharing_card = { title = T"Printer Sharing", category = 3, order = 24 },
  telephony_card = { title = T"Telephony", category = 3, order = 25 },
  extensions_card = { title = T"Extensions", category = 3, order = 26 },
  assistance_card = { title = T"Assistance", category = 3, order = 27 },
  cwmpconf_card = { title = T"CWMP", category = 3, order = 28 },
  nfc_card = { title = T"NFC", category = 3, order = 29 },
}

local categories = {
  [1] = T"Network and Connectivity",
  [2] = T"Security and Routing",
  [3] = T"System and Services",
}

local cards_list = {}
uci:foreach('web', 'card', function(s)
  local sec_name = s['.name']
  local meta = cards_meta[sec_name] or { title = s.card or sec_name, category = 3, order = 99 }
  cards_list[#cards_list + 1] = {
    sec = sec_name,
    card = s.card,
    title = meta.title,
    category = meta.category,
    order = meta.order,
    hide = s.hide or '0'
  }
end)
table.sort(cards_list, function(a, b) return a.order < b.order end)

if ngx.req.get_method() == "POST" then
  local post_args = ngx.req.get_post_args()
  if post_args.action == "SAVE" then
    for _, c in ipairs(cards_list) do
      local val = post_args["card_" .. c.sec]
      local hide_val = (val == "1") and "0" or "1"
      uci:set("web", c.sec, "hide", hide_val)
      c.hide = hide_val
    end
    uci:commit("web")
    message_helper.pushMessage(T"Card settings saved successfully", "success")
  end
end

ngx.print(ui_helper.createHeader(T"Card Settings", false, false))
ngx.print('\n<div class="modal-body update">\n  <form class="form-horizontal" method="post" action="modals/cards-modal.lp">\n')
ngx.print(ui_helper.createMessages(message_helper.popMessages()))
ngx.print(ui_helper.createAlertBlock(T"Choose which cards to display on the main dashboard. Disabling a card will hide it from the home page.", { alert = { class = "alert-info" } }))

ngx.print('\n    <div style="margin-bottom: 12px; text-align: right;">\n      <button type="button" class="btn btn-small" id="btn-show-all"><i class="icon-eye-open"></i> ')
ngx.print(T"Show all")
ngx.print('</button>\n      <button type="button" class="btn btn-small" id="btn-hide-all" style="margin-left: 8px;"><i class="icon-eye-close"></i> ')
ngx.print(T"Hide all")
ngx.print('</button>\n    </div>\n')

for cat_id = 1, 3 do
  local cat_cards = {}
  for _, c in ipairs(cards_list) do
    if c.category == cat_id then
      cat_cards[#cat_cards + 1] = c
    end
  end
  if #cat_cards > 0 then
    ngx.print('<fieldset><legend>' .. categories[cat_id] .. '</legend>')
    for _, c in ipairs(cat_cards) do
      local is_visible = (c.hide == "0") and "1" or "0"
      ngx.print(ui_helper.createSwitch(c.title, "card_" .. c.sec, is_visible))
    end
    ngx.print('</fieldset>')
  end
end

ngx.print('\n  </form>\n</div>\n<script>\n  $("#btn-show-all").on("click", function (e) {\n    e.preventDefault();\n    $(".modal-body .switch").each(function () {\n      var $sw = $(this);\n      $sw.addClass("switchOn").find(".switcher").addClass("switcherOn");\n      $sw.find("input[type=hidden]").val("1").trigger("change");\n    });\n  });\n  $("#btn-hide-all").on("click", function (e) {\n    e.preventDefault();\n    $(".modal-body .switch").each(function () {\n      var $sw = $(this);\n      $sw.removeClass("switchOn").find(".switcher").removeClass("switcherOn");\n      $sw.find("input[type=hidden]").val("0").trigger("change");\n    });\n  });\n</script>\n')
ngx.print(ui_helper.createFooter())
