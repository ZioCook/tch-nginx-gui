-- .luacheckrc  (configurazione luacheck per tch-nginx-gui)
--
-- Obiettivo: trovare globali create per errore (W111/W112), globali lette ma mai
-- definite (W113), assegnazioni a globali del framework (W121/W122) e shadowing
-- dei `local` appena aggiunti (4xx). Tutto il resto (variabili inutilizzate,
-- formattazione, ecc.) è escluso per non coprire il segnale.
--
-- I .lp sono già Lua puro (--pretranslated), ma luacheck dalle directory prende
-- solo i *.lua: passa i .lp come argomenti espliciti, ad esempio
--   luacheck --config .luacheckrc $(find . -name '*.lp' -o -name '*.lua')

std = "lua51"

-- solo globali (1xx) e shadowing (4xx)
only = { "1..", "4.." }

-- niente codice minificato/di build
exclude_files = {
  "**/node_modules/**",
  "**/dist/**",
  "**/build/**",
  "**/*.min.lua",
  "**/*-min.lua",
}

-- Globali fornite dal runtime a livello base (Nginx Lua C core e modulo C gettext)
read_globals = {
  "ngx",
  "gettext",
}

-- Funzioni di traduzione T e N: iniettate esclusivamente nei template .lp da insertGettext (web.lua)
files["**/*.lp"] = {
  read_globals = {
    "T",
    "N",
  }
}

-- Globali legittimi del framework LuCI CBI (sottopacchetto luci_wireless)
files["decompressed/luci_wireless/**"] = {
  read_globals = {
    "SimpleForm",
    "translate",
    "ListValue",
    "Value",
    "DummyValue",
    "SimpleSection",
    "FORM_VALID",
    "bit",
    "luci",
    "nixio",
    "uci",
  }
}

-- Globali legittimi iniettati dal loader ledfw in stateMachines.lua
files["decompressed/ledfw_support-specific*/**"] = {
  read_globals = {
    "timerLed",
    "staticLed",
    "netdevLed",
    "netdevLedOWRT",
    "runFunc",
    "patternLed",
    "uci",
    "ubus",
    "get_depending_led",
    "is_WiFi_LED_on_if_NSC",
    "is_show_remote_mgmt",
    "xdsl_status",
    "get_wl1_ifname",
  },
  globals = {
    "patterns",
    "stateMachines",
  }
}

-- Non dichiarare qui le globali "sospette" (mapParam, remove, s, ...): devono
-- continuare a comparire nel report.
globals = {}
