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

-- Globali fornite dal framework, in SOLA LETTURA: scrivervi dentro darà W121.
read_globals = {
  "ngx",
  "proxy",
  "ui_helper",
  "post_helper",
  "content_helper",
  "T",
  "N",
  "session",
  "gettext",
}

-- Non dichiarare qui le globali "sospette" (mapParam, remove, s, ...): devono
-- continuare a comparire nel report.
globals = {}
