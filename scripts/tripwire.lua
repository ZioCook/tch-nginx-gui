-- tripwire.lua — SOLO SVILUPPO (Lua 5.1 PUC-Rio)
--
-- Scrive in /tmp/global-tripwire.log una riga per evento (deduplicata):
--   READ  nome  file:riga   lettura di una globale inesistente (nil)
--   WRITE nome  file:riga   creazione di una NUOVA globale
-- (una scrittura su una globale già esistente non scatta: conta solo la prima)
--
-- Si attiva solo se esiste /tmp/tripwire.on. /tmp si svuota al riavvio, quindi se
-- il file finisse per errore in un firmware di produzione resterebbe inerte.
--
-- Uso:
--   touch /tmp/tripwire.on && /etc/init.d/nginx restart
--   ... navigare la GUI (anche i POST, e ogni pagina come PRIMA richiesta) ...
--   cat /tmp/global-tripwire.log
--   rm /tmp/tripwire.on /tmp/global-tripwire.log && /etc/init.d/nginx restart

local LOG   = "/tmp/global-tripwire.log"
local FLAG  = "/tmp/tripwire.on"
local MAXEV = 1000                       -- tetto di righe, per non riempire la RAM

local open = io.open
local flag = open(FLAG, "r")
if not flag then return end
flag:close()

-- tutto ciò che serve dentro i metamethod è catturato qui come upvalue, così il
-- tripwire non si innesca da solo cercando globali
local type, pcall, rawset, setmetatable = type, pcall, rawset, setmetatable
local getmetatable, pairs, tostring = getmetatable, pairs, tostring
local getinfo = debug and debug.getinfo or function() return nil end

local prev = getmetatable(_G)
if prev and prev.__tripwire then return end   -- già installato (idempotente)

local seen, n = {}, 0

-- livello 3 = chi ha toccato la globale (1 = note, 2 = il metamethod)
local function note(kind, name)
  if type(name) ~= "string" then return end
  local info = getinfo(3, "Sl")
  local where = info and (info.short_src .. ":" .. (info.currentline or 0)) or "?"
  local key = kind .. " " .. name .. " " .. where
  if seen[key] or n >= MAXEV then return end
  seen[key] = true
  n = n + 1
  local f = open(LOG, "a")
  if f then
    f:write(kind, " ", name, " ", where, "\n")
    f:close()
  end
end

-- conserva eventuali handler già presenti su _G (modulo Lua di Nginx, strict.lua, ...)
local mt = {}
if prev then
  for k, v in pairs(prev) do mt[k] = v end
end
mt.__tripwire = true

mt.__index = function(t, k)
  local v
  local h = prev and prev.__index
  if h ~= nil then
    if type(h) == "function" then v = h(t, k) else v = h[k] end
  end
  if v == nil then note("READ", k) end
  return v
end

mt.__newindex = function(t, k, v)
  note("WRITE", k)
  local h = prev and prev.__newindex
  if h ~= nil then
    if type(h) == "function" then return h(t, k, v) end
    h[k] = v
    return
  end
  rawset(t, k, v)
end

local ok, err = pcall(setmetatable, _G, mt)
if not ok then
  local f = open(LOG, "a")
  if f then
    f:write("TRIPWIRE-NON-INSTALLATO ", tostring(err), "\n")
    f:close()
  end
end
