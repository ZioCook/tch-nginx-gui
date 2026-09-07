--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local uci = require("uci"):cursor()
local lfs = require("lfs")
local string, table, ngx = string, table, ngx

-- Cards meta: friendly names and categories for known cards
local cards_meta = {
  -- Category 1: Network & Connectivity
  gateway_card      = { title = T"Modem",              category = 1, order = 1  },
  modgui_card       = { title = T"GUI Settings",        category = 1, order = 2  },
  boradband_card    = { title = T"Broadband",           category = 1, order = 3  },
  internet_card     = { title = T"Internet Access",     category = 1, order = 4  },
  wireless_card     = { title = T"Wireless",            category = 1, order = 5  },
  lan_card          = { title = T"Local Network",       category = 1, order = 6  },
  devices_card      = { title = T"Devices",             category = 1, order = 7  },
  wanservices_card  = { title = T"WAN Services",        category = 1, order = 8  },
  xdsl_card         = { title = T"xDSL Configuration", category = 1, order = 9  },
  lte_card          = { title = T"Mobile",              category = 1, order = 10 },
  speedservice_card = { title = T"Speed Test",          category = 1, order = 11 },
  -- Category 2: Security & Routing
  firewall_card     = { title = T"Firewall",            category = 2, order = 12 },
  qos_card          = { title = T"QoS",                 category = 2, order = 13 },
  natalghelper_card = { title = T"NAT Helpers",         category = 2, order = 14 },
  iproutes_card     = { title = T"IP Extras",           category = 2, order = 15 },
  parental_card     = { title = T"Parental Controls",   category = 2, order = 16 },
  tod_card          = { title = T"Time of Day",         category = 2, order = 17 },
  relaysetup_card   = { title = T"Relay Setup",         category = 2, order = 18 },
  -- Category 3: System & Services
  usermgr_card      = { title = T"Management",          category = 3, order = 19 },
  system_card       = { title = T"System Extras",       category = 3, order = 20 },
  diagnostics_card  = { title = T"Diagnostics",         category = 3, order = 21 },
  eco_card          = { title = T"Eco",                 category = 3, order = 22 },
  contentsharing_card  = { title = T"Content Sharing",  category = 3, order = 23 },
  printersharing_card  = { title = T"Printer Sharing",  category = 3, order = 24 },
  telephony_card    = { title = T"Telephony",           category = 3, order = 25 },
  extensions_card   = { title = T"Extensions",          category = 3, order = 26 },
  assistance_card   = { title = T"Assistance",          category = 3, order = 27 },
  cwmpconf_card     = { title = T"CWMP",                category = 3, order = 28 },
  nfc_card          = { title = T"NFC",                 category = 3, order = 29 },
}

local categories = {
  [1] = T"Network and Connectivity",
  [2] = T"Security and Routing",
  [3] = T"System and Services",
}

-- Build card list from UCI, only include cards whose .lp file actually exists on disk
local cards_path = "/www/cards"
local cards_list = {}
local prod_name = uci:get("env", "var", "prod_friendly_name") or ""
uci:foreach('web', 'card', function(s)
  local sec_name = s['.name']
  local card_file = s.card
  if sec_name == "nfc_card" and prod_name ~= "DJN2130" and prod_name ~= "Technicolor TG800vac" then
    return
  end
  if card_file and lfs.attributes(cards_path .. "/" .. card_file, 'mode') == 'file' then
    local meta = cards_meta[sec_name] or {
      title    = card_file:gsub("^%d+_", ""):gsub("%.lp$", ""),
      category = 3,
      order    = 99
    }
    cards_list[#cards_list + 1] = {
      sec      = sec_name,
      card     = card_file,
      title    = meta.title,
      category = meta.category,
      order    = meta.order,
      hide     = s.hide or '0'
    }
  end
end)
uci:unload('web')
table.sort(cards_list, function(a, b) return a.order < b.order end)

-- Handle POST save: re-open cursor
if ngx.req.get_method() == "POST" then
  local post_args = ngx.req.get_post_args()
  local action = post_args.action
  if type(action) == "table" then action = action[1] end
  if action and string.untaint(action) == "SAVE" then
    local uci2 = require("uci"):cursor()
    for _, c in ipairs(cards_list) do
      local val = post_args["card_" .. c.sec]
      if type(val) == "table" then val = val[1] end
      if val then
        val = string.untaint(val)
        -- val=="1" means switch ON (visible), hide=0; val=="0" means hide=1
        local hide_val = (val == "1") and "0" or "1"
        uci2:set("web", string.untaint(c.sec), "hide", hide_val)
        c.hide = hide_val
      end
    end
    uci2:commit("web")
    uci2:unload("web")
    pcall(function() require("web.lp").flush() end)
    message_helper.pushMessage(T"Card settings saved successfully", "success")
  end
end

ngx.print(ui_helper.createHeader(T"Card Settings", false, false))
ngx.print('\n<div class="modal-body update">\n  <form class="form-horizontal" method="post" action="modals/cards-modal.lp">\n')
ngx.print(ui_helper.createMessages(message_helper.popMessages()))
ngx.print(ui_helper.createAlertBlock(T"Choose which cards to display on the main dashboard. Disabling a card will hide it from the home page.", { alert = { class = "alert-info" } }))

ngx.print('\n    <div style="margin-bottom: 12px; text-align: right;">\n')
ngx.print('      <button type="button" class="btn btn-small" id="btn-show-all"><i class="icon-eye-open"></i> ')
ngx.print(T"Show all")
ngx.print('</button>\n      <button type="button" class="btn btn-small" id="btn-hide-all" style="margin-left: 8px;"><i class="icon-eye-close"></i> ')
ngx.print(T"Hide all")
ngx.print('</button>\n    </div>\n')

-- Switch attributes: add monitor-changes so the Save button appears in the footer
local sw_attr = { input = { class = "monitor-changes" } }

for cat_id = 1, 3 do
  local cat_cards = {}
  for _, c in ipairs(cards_list) do
    if c.category == cat_id then cat_cards[#cat_cards + 1] = c end
  end
  if #cat_cards > 0 then
    ngx.print('<fieldset><legend>' .. categories[cat_id] .. '</legend>')
    for _, c in ipairs(cat_cards) do
      local is_visible = (c.hide == "0") and "1" or "0"
      ngx.print(ui_helper.createSwitch(c.title, "card_" .. c.sec, is_visible, sw_attr))
    end
    ngx.print('</fieldset>')
  end
end

ngx.print('\n  </form>\n</div>\n')
ngx.print([[
<script>
  $("#btn-show-all").on("click", function (e) {
    e.preventDefault();
    $(".modal-body .switch").each(function () {
      var $sw = $(this);
      if (!$sw.hasClass("switchOn")) {
        $sw.addClass("switchOn").find(".switcher").addClass("switcherOn");
        $sw.find("input[type=hidden]").val("1").trigger("change");
      }
    });
    $("#modal-no-change").fadeOut(300);
    $("#modal-changes").delay(350).fadeIn(300);
  });
  $("#btn-hide-all").on("click", function (e) {
    e.preventDefault();
    $(".modal-body .switch").each(function () {
      var $sw = $(this);
      if ($sw.hasClass("switchOn")) {
        $sw.removeClass("switchOn").find(".switcher").removeClass("switcherOn");
        $sw.find("input[type=hidden]").val("0").trigger("change");
      }
    });
    $("#modal-no-change").fadeOut(300);
    $("#modal-changes").delay(350).fadeIn(300);
  });
</script>
]])
ngx.print(ui_helper.createFooter())

