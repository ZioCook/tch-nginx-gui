#!/usr/bin/lua
--
-- Standalone LuaSocket Emergency Rescue Server for tch-nginx-gui
-- Operates completely independently from Nginx, LuaJIT, and Transformer.
-- Provides Out-of-Band Web Management, PC archive upload, Zero-Touch USB Recovery
-- and an interactive root shell.
--
-- Target: Lua 5.1 + LuaSocket (OpenWrt / BusyBox ash). No other dependencies.
--
-- Hardening (unchanged from v2): select()-based accept loop, non-blocking header
-- collection with deadline / size / per-IP caps, strict request parser, streaming upload
-- with idle + total timeouts, /exec through temp script + `timeout`, children close
-- inherited descriptors, client socket is closed BEFORE any detached job starts.
--
-- Added in v3: LAN-only access, Host/Origin/X-Rescue checks (CSRF + DNS rebinding),
-- anti-framing headers, busy lock (one recovery at a time), background verify+extract job
-- (server stays responsive), live /status and incremental /log, tabbed console
-- (shell + live log), real progress bar, language switch that no longer wipes the shell.
--

local socket = require("socket")

------------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------------
local VERSION           = "3.0"
local DEFAULT_PORT      = 8088
local ALT_PORT          = 8089          -- used if the requested port is busy

local LOG_FILE          = "/tmp/rescue.log"
local UPLOAD_TEMP       = "/tmp/rescue_upload.tmp"
local RECOVERY_TARGET   = "/tmp/GUI_upload.tar.bz2"
local JOB_SCRIPT        = "/tmp/rescue_job.sh"
local BUSY_LOCK         = "/tmp/rescue.busy"
local USB_SCRIPT        = "/usr/bin/rescue-usb.sh"

local DOCROOT           = "/www/docroot"
-- Icon fonts / favicon are looked up in these places, in order. Copy the .woff2 files to
-- /usr/share/rescue/fonts to keep the icons even if the GUI docroot is damaged.
local FONT_DIRS         = { DOCROOT .. "/fonts", "/usr/share/rescue/fonts" }
local FAVICON_FILES     = { DOCROOT .. "/img/favicon.ico", "/usr/share/rescue/favicon.ico" }
local LOGO_FILES        = { DOCROOT .. "/img/logo.png", "/usr/share/rescue/logo.png" }

-- Access control -------------------------------------------------------------
local RESTRICT_TO_LAN       = true      -- only private / loopback / link-local clients
local CHECK_HOST_HEADER     = true      -- refuse foreign Host names (DNS rebinding)
local ENFORCE_SAME_ORIGIN   = true      -- POST: Origin (when sent) must equal Host
local REQUIRE_RESCUE_HEADER = true      -- POST must carry "X-Rescue: 1" (forces CORS preflight)
local ENABLE_SHELL          = true      -- false disables POST /exec completely

-- Connection handling --------------------------------------------------------
local LISTEN_BACKLOG    = 16            -- kernel accept queue
local MAX_PENDING       = 16            -- connections still sending their headers
local MAX_PENDING_PER_IP = 6            -- ... of which at most this many per client IP
local HEADER_DEADLINE   = 10            -- s: whole request head must arrive within this time
local SELECT_TICK       = 1             -- s: select() timeout (also deadline sweep period)

local MAX_REQ_LINE      = 8192          -- bytes per request/header line
local MAX_URI           = 2048          -- bytes
local MAX_HEADER_BYTES  = 16384         -- bytes for the whole request head
local MAX_HEADER_LINES  = 64

local IO_TIMEOUT        = 15            -- s: per socket operation once a request is dispatched
local SEND_MAX_SECS     = 120           -- s: total time allowed to send one response

-- Upload ---------------------------------------------------------------------
local UPLOAD_MAX_BYTES  = 128 * 1024 * 1024
local UPLOAD_MAX_SECS   = 1800          -- s: absolute cap for one upload
local UPLOAD_CHUNK      = 32768         -- bytes per receive()
local UPLOAD_BUFFER     = 65536         -- stdio buffer of the temp file
local VERIFY_TIMEOUT    = 600           -- s: max time for the archive integrity test
local BUSY_STALE_SECS   = 1800          -- a lock older than this is considered stale

-- Shell ----------------------------------------------------------------------
local EXEC_BODY_MAX     = 4096          -- bytes: max size of a /exec command
local EXEC_TIMEOUT      = 8             -- s
local EXEC_OUT_MAX      = 65536         -- bytes of command output returned to the browser
local EXEC_ULIMIT_BLOCKS = 16384        -- ulimit -f (512B blocks) for /exec = 8 MB

-- Files / log ----------------------------------------------------------------
local FILE_MAX          = 2 * 1024 * 1024  -- max size served by read_file() (fonts, favicon)
local LOG_MAX_BYTES     = 262144        -- rotate log above this size ...
local LOG_KEEP_BYTES    = 65536         -- ... keeping this many bytes of tail
local LOG_SERVE_MAX     = 65536         -- max bytes returned by one GET /log
local LOG_TAIL_BYTES    = 16384         -- what a freshly opened page receives

-- Descriptors 3..9 are closed in every child process (the listening socket included).
local FD_CLOSE = "3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-"

local ACTIVE_PORT = DEFAULT_PORT        -- set by main()

------------------------------------------------------------------------------
-- Small generic helpers
------------------------------------------------------------------------------

-- Run fn(f) on an open file; the file is ALWAYS closed, errors are returned, not thrown.
local function with_file(path, mode, fn)
    local f, err = io.open(path, mode)
    if not f then return nil, err end
    local ok, a, b = pcall(fn, f)
    pcall(f.close, f)
    if not ok then return nil, a end
    return a, b
end

-- os.execute() returns a number on Lua 5.1 and true/nil on 5.2+: accept both.
local function sh_ok(res)
    return res == 0 or res == true
end

-- Quote a string for safe use as a single shell word.
local function shq(s)
    return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function html_escape(s)
    return (tostring(s):gsub("[&<>\"']", {
        ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;",
    }))
end

local JSON_ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "", ["\t"] = "\\t",
                   ["\b"] = "\\b", ["\f"] = "\\f" }

-- Full JSON string escaping (control characters included, so binary command output
-- can never break JSON.parse() in the browser).
local function json_escape(s)
    return (tostring(s):gsub('[%c"\\]', function(c)
        return JSON_ESC[c] or string.format("\\u%04x", c:byte())
    end))
end

-- Flat table (strings / numbers / booleans) -> JSON object.
local function json_encode(t)
    local parts = {}
    for k, v in pairs(t) do
        local kind, enc = type(v), nil
        if kind == "number" then
            enc = string.format("%d", v)
        elseif kind == "boolean" then
            enc = v and "true" or "false"
        else
            enc = '"' .. json_escape(v) .. '"'
        end
        parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. enc
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

------------------------------------------------------------------------------
-- Files and logging (size-capped: /tmp is RAM on these routers)
------------------------------------------------------------------------------
local log_writes = 0

-- Read at most `max` bytes from the END of a file ("" if missing).
local function read_tail(path, max)
    local data = with_file(path, "rb", function(f)
        local size = f:seek("end")
        if not size then return nil end
        if size > max then f:seek("set", size - max) else f:seek("set", 0) end
        return f:read(max)
    end)
    return data or ""
end

local function rotate_log_if_needed()
    local size = with_file(LOG_FILE, "rb", function(f) return f:seek("end") end)
    if size and size > LOG_MAX_BYTES then
        local tail = read_tail(LOG_FILE, LOG_KEEP_BYTES)
        local nl = tail:find("\n", 1, true)
        if nl then tail = tail:sub(nl + 1) end        -- drop the cut first line
        with_file(LOG_FILE, "wb", function(f) f:write(tail) return true end)
    end
end

-- Append message to rescue log (never throws)
local function log(msg)
    pcall(function()
        local line = string.format("[%s] [RESCUE-SERVER] %s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(msg))
        io.stderr:write(line)
        log_writes = log_writes + 1
        if log_writes % 32 == 0 then rotate_log_if_needed() end
        with_file(LOG_FILE, "a", function(f) f:write(line) return true end)
    end)
end

-- Incremental log read for GET /log?pos=N.
-- Returns { data = ..., size = <file size>, reset = <true when the client must start over> }
local function read_log_chunk(pos)
    local res = with_file(LOG_FILE, "rb", function(f)
        local size = f:seek("end") or 0
        local start, reset = pos, false
        if not start or start < 0 or start > size then
            start, reset = math.max(0, size - LOG_TAIL_BYTES), true      -- first poll / log rotated
        elseif size - start > LOG_SERVE_MAX then
            start, reset = size - LOG_SERVE_MAX, true                     -- client too far behind
        end
        f:seek("set", start)
        local data = f:read(size - start) or ""
        if reset and start > 0 then
            local nl = data:find("\n", 1, true)
            if nl then data = data:sub(nl + 1) end                        -- drop the cut first line
        end
        return { data = data, size = size, reset = reset }
    end)
    return res or { data = "", size = 0, reset = true }
end

-- Read an entire (small) file in ONE allocation: size is probed with seek() and files
-- bigger than `max` are refused. Returns "" when missing / unreadable / too big.
local function read_file(path, max)
    max = max or FILE_MAX
    local data = with_file(path, "rb", function(f)
        local size = f:seek("end")
        if not size or size > max then return nil end
        if size == 0 then return "" end
        f:seek("set", 0)
        return f:read(size)
    end)
    return data or ""
end

-- Read a small text/proc file completely ("" on error)
local function slurp(path)
    return with_file(path, "r", function(f) return f:read("*a") end) or ""
end

local function file_exists(path)
    return with_file(path, "rb", function() return true end) == true
end

------------------------------------------------------------------------------
-- Process helpers
------------------------------------------------------------------------------

-- Locate a `timeout` applet once at startup (no fork on every request)
local TIMEOUT_BIN
for _, p in ipairs({ "/usr/bin/timeout", "/bin/timeout", "/usr/sbin/timeout", "/sbin/timeout" }) do
    if file_exists(p) then TIMEOUT_BIN = p; break end
end

-- Build a shell line that closes inherited fds, then runs `inner` with a hard time limit.
-- Without a timeout applet a tiny shell watchdog is used instead.
local function wrap_timeout(secs, inner)
    if TIMEOUT_BIN then
        return string.format("exec %s; %s -s KILL %d %s", FD_CLOSE, TIMEOUT_BIN, secs, inner)
    end
    return string.format(
        "exec %s; ( %s ) & P=$!; ( sleep %d; kill -9 $P ) >/dev/null 2>&1 & W=$!; " ..
        "wait $P; R=$?; kill $W >/dev/null 2>&1; exit $R",
        FD_CLOSE, inner, secs)
end

-- Start a fully detached background job. Descriptors 3..9 (listening socket included) are
-- closed in the child, stdio goes to /dev/null, so a long-lived child can never keep the
-- listening port (or an HTTP connection) alive.
local function spawn_detached(body)
    os.execute(string.format("( exec %s; %s ) </dev/null >/dev/null 2>&1 &", FD_CLOSE, body))
end

------------------------------------------------------------------------------
-- "Recovery in progress" lock (shared with the background job, which removes it)
------------------------------------------------------------------------------
local function set_busy()
    with_file(BUSY_LOCK, "w", function(f) f:write(tostring(os.time()), "\n") return true end)
end

local function is_busy()
    local ts = with_file(BUSY_LOCK, "r", function(f) return f:read("*n") or 0 end)
    if not ts then return false end
    local age = os.time() - ts
    if age > BUSY_STALE_SECS or age < -BUSY_STALE_SECS then       -- stale, or the clock jumped
        pcall(os.remove, BUSY_LOCK)
        return false
    end
    return true
end

------------------------------------------------------------------------------
-- System summary for the dashboard (raw values: escaping is done where they are used)
------------------------------------------------------------------------------
local function pid_alive(pidfile, needle)
    local pid = slurp(pidfile):match("^%s*(%d+)")
    if not pid then return false end
    local cmdline = slurp("/proc/" .. pid .. "/cmdline")
    return cmdline ~= "" and cmdline:find(needle, 1, true) ~= nil
end

local function detect_hardware()
    local env = slurp("/etc/config/env")
    local friendly = env:match("option%s+prod_friendly_name%s+['\"]([^'\"]+)['\"]")
    if friendly and #friendly > 0 then
        return friendly
    end
    local prod_name = env:match("option%s+prod_name%s+['\"]([^'\"]+)['\"]")
    local prod_num = env:match("option%s+prod_number%s+['\"]([^'\"]+)['\"]")
    if prod_name and prod_num then
        return prod_name .. " " .. prod_num
    end
    local model = slurp("/tmp/sysinfo/model"):match("^([%g ]+)")
        or slurp("/proc/device-tree/model"):match("^([%g ]+)")
    if model and #model > 2 then return model end
    local cpu = slurp("/proc/cpuinfo")
    return cpu:match("Hardware%s*:%s*([^\r\n]+)")
        or cpu:match("model name%s*:%s*([^\r\n]+)")
        or cpu:match("system type%s*:%s*([^\r\n]+)")
        or "Technicolor Gateway"
end

local function detect_kernel()
    local ver = slurp("/proc/version")
    local k = ver:match("Linux%s+version%s+([%w%._%-]+)")
    if k and #k > 0 then return k end
    local rel = slurp("/proc/sys/kernel/osrelease"):match("^([%w%._%-]+)")
    return (rel and #rel > 0) and rel or "N/A"
end

-- Installed GUI version: /etc/config/modgui first, /etc/config/env second, /etc/init.d/rootdevice fallback.
local function detect_gui_version()
    local mg = slurp("/etc/config/modgui")
    local v = mg:match("option%s+version%s+['\"]([^%s'\"]+)['\"]") or mg:match("option%s+version%s+([%w%._%-]+)")
    if v and #v > 0 then return v end
    local env = slurp("/etc/config/env")
    local gv = env:match("option%s+gui_version%s+['\"]([^%s'\"]+)['\"]") or env:match("option%s+gui_version%s+([%w%._%-]+)")
    if gv and #gv > 0 then return gv end
    local ver = with_file("/etc/init.d/rootdevice", "r", function(f)
        for l in f:lines() do
            local val = l:match("version_gui=([^%s]+)")
            if val then return val end
        end
    end)
    return ver
end

local function detect_memory()
    local mem = slurp("/proc/meminfo")
    local total = tonumber(mem:match("MemTotal:%s*(%d+)"))
    if not total then return "N/A" end
    local avail = tonumber(mem:match("MemAvailable:%s*(%d+)"))
    if not avail then                                   -- old kernels: count caches as free
        avail = (tonumber(mem:match("MemFree:%s*(%d+)")) or 0)
              + (tonumber(mem:match("Buffers:%s*(%d+)")) or 0)
              + (tonumber(mem:match("\nCached:%s*(%d+)")) or 0)
    end
    return string.format("%d MB / %d MB", math.max(0, math.floor((total - avail) / 1024)), math.floor(total / 1024))
end

local function detect_uptime()
    local secs = with_file("/proc/uptime", "r", function(f) return f:read("*n") end)
    if not secs then return "N/A" end
    local days  = math.floor(secs / 86400)
    local hours = math.floor((secs % 86400) / 3600)
    local mins  = math.floor((secs % 3600) / 60)
    if days > 0 then return string.format("%dg %dh %02dm", days, hours, mins) end
    return string.format("%dh %02dm", hours, mins)
end

-- USB stick: first sdXN partition (or bare sdX disk) in /proc/partitions + fs type from /proc/mounts
local function detect_usb()
    local usb = { present = false, name = "", fs = "" }
    local disk, part
    for name in slurp("/proc/partitions"):gmatch("%d+%s+%d+%s+%d+%s+(sd%a+%d*)") do
        if name:match("%d$") then part = part or name else disk = disk or name end
    end
    local found = part or disk
    if not found then return usb end
    usb.present, usb.name = true, found
    for dev, fstype in slurp("/proc/mounts"):gmatch("/dev/(%S+)%s+%S+%s+(%S+)") do
        if dev == found then usb.fs = fstype; break end
    end
    return usb
end

local summary_cache = { at = 0, data = nil }

local function get_system_summary()
    local now = os.time()
    local age = now - summary_cache.at
    if summary_cache.data and age >= 0 and age < 2 then
        return summary_cache.data
    end

    local s = {
        hardware    = detect_hardware(),
        kernel      = detect_kernel(),
        gui_version = detect_gui_version(),             -- nil when not found
        mem         = detect_memory(),
        uptime      = detect_uptime(),
        usb         = detect_usb(),
        busy        = is_busy(),
    }

    -- NOTE: kept as separate, plain os.execute() calls. The "[t]" trick stops pgrep -f from
    -- matching the very `sh -c` line that carries the pattern; the pid file is only trusted
    -- when the process it names is really alive (no more "running" from a stale pid file).
    s.nginx_running = sh_ok(os.execute("pgrep nginx >/dev/null 2>&1"))
    s.trans_running = sh_ok(os.execute("pgrep -f '[t]ransformer' >/dev/null 2>&1"))
                      or pid_alive("/var/run/transformer.pid", "transformer")

    summary_cache.at, summary_cache.data = now, s
    return s
end

------------------------------------------------------------------------------
-- HTML page (static template; the few dynamic values use @@NAME@@ placeholders)
------------------------------------------------------------------------------
local PAGE_TEMPLATE = [==[<!DOCTYPE HTML>

<html lang="it">

<head>

  <meta charset="utf-8">

  <meta http-equiv="X-UA-Compatible" content="IE=edge">

  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title>Technicolor Gateway - Rescue Console (@@PORT@@)</title>

  <style>

    /* Reset & Base Technicolor gw.css + Bootstrap 2.3.2 */

    *, *::before, *::after {

      box-sizing: border-box;

    }

    html, body {

      margin: 0;

      padding: 0;

      background-color: #eeeeee;

      color: #333333;

      font-family: Helvetica, Arial, sans-serif;

      font-size: 14px;

      line-height: 20px;

      -webkit-font-smoothing: antialiased;

    }

    a {

      color: #0088cc;

      text-decoration: none;

    }

    a:hover {

      color: #005580;

      text-decoration: underline;

    }



    /* Contenitore Principale */

    .rescue-container {

      max-width: 1200px;

      margin: 0 auto;

      padding: 18px 20px 30px 20px;

    }



    /* Header (Fix strutturale: header-logo chiuso correttamente) */

    .rescue-header {

      display: flex;

      justify-content: space-between;

      align-items: center;

      margin-bottom: 16px;

      min-height: 54px;

    }

    .header-logo {

      display: inline-flex;

      align-items: center;

    }

    .header-logo svg {

      display: block;

      width: 131px;

      height: 50px;

    }

    .header-actions {

      display: flex;

      align-items: center;

      gap: 10px;

    }

    #webui_language {

      appearance: auto;

      background-color: #ffffff;

      background-image: linear-gradient(to bottom, #ffffff, #e6e6e6);

      border: 1px solid #cccccc;

      border-color: rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.1) rgba(0, 0, 0, 0.25);

      border-radius: 4px;

      padding: 6px 12px;

      font-family: Helvetica, Arial, sans-serif;

      font-size: 13px;

      line-height: 18px;

      color: #333333;

      cursor: pointer;

      box-shadow: inset 0 1px 0 rgba(255,255,255,0.2), 0 1px 2px rgba(0,0,0,0.05);

    }

    #webui_language:focus {

      outline: none;

      border-color: #1e741e;

    }



    /* Alert di Emergenza (Bootstrap 2.3.2 .alert-warning) */

    .alert-warning {

      width: 100%;

      background-color: #fcf8e3;

      border: 1px solid #fbeed5;

      color: #c09853;

      border-radius: 4px;

      padding: 10px 16px;

      margin-bottom: 22px;

      text-align: center;

      font-weight: bold;

      font-size: 13.5px;

      display: flex;

      align-items: center;

      justify-content: center;

      gap: 8px;

      text-shadow: 0 1px 0 rgba(255, 255, 255, 0.5);

      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);

    }

    .alert-warning svg {

      width: 16px;

      height: 16px;

      fill: #c09853;

      flex-shrink: 0;

    }



    /* Griglia 4 Colonne Technicolor */

    .cards-grid {

      display: grid;

      grid-template-columns: repeat(4, 1fr);

      gap: 22px;

      align-items: stretch;

    }

    .card {

      background-color: #ffffff;

      border-radius: 4px;

      box-shadow: 0 2px 20px 0 rgba(56, 132, 56, 0.45);

      display: flex;

      flex-direction: column;

      overflow: hidden;

      min-height: 255px;

    }

    .card.span-3 {

      grid-column: span 3;

      min-height: 360px;

    }



    /* Intestazione Card (.sh) */

    .sh {

      background: rgb(30, 116, 30);

      background: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);

      border-bottom: 1px solid rgb(25, 95, 25);

      color: #ffffff;

      font-weight: bold;

      font-size: 16px;

      line-height: 22px;

      text-shadow: 0 1px 1px #000000;

      padding: 10px 16px;

      display: flex;

      align-items: center;

      justify-content: space-between;

      border-top-left-radius: 4px;

      border-top-right-radius: 4px;

    }

    .sh-title {

      display: inline-flex;

      align-items: center;

      gap: 8px;

    }



    /* Corpo Card */

    .card-body {

      padding: 15px 16px 16px 16px;

      flex: 1;

      display: flex;

      flex-direction: column;

      justify-content: space-between;

    }

    .card-content {

      display: flex;

      flex-direction: column;

      gap: 8px;

    }

    .card-footer-action {

      margin-top: 14px;

    }



    /* Righe Informazioni & Micro-Icone SVG */

    .info-row {

      display: flex;

      align-items: baseline;

      gap: 7px;

      font-size: 13.5px;

      line-height: 19px;

      color: #333333;

      word-break: break-word;

    }

    .info-icon {

      width: 14px;

      height: 14px;

      fill: #333333;

      flex-shrink: 0;

      position: relative;

      top: 2px;

    }

    .gui-ver {

      color: #1e741e;

      font-weight: bold;

    }

    .card-desc {

      margin: 6px 0 0 0;

      font-size: 12.5px;

      line-height: 17px;

      color: #555555;

    }



    /* Indicatori LED Technicolor */

    .led-row {

      display: flex;

      align-items: center;

      gap: 8px;

      font-size: 13.5px;

      line-height: 20px;

    }

    .led {

      display: inline-block;

      width: 10px;

      height: 10px;

      border-radius: 50%;

      background-color: #999999;

      box-shadow: 0 0 0 2px rgba(153, 153, 153, 0.25);

      flex-shrink: 0;

    }

    .led.green, .led.led-green, .led.ok, .led.active, .led.running {

      background-color: #46a546;

      box-shadow: 0 0 5px rgba(70, 165, 70, 0.75), 0 0 0 2px rgba(70, 165, 70, 0.25);

    }

    .led.red, .led.led-red, .led.err, .led.error, .led.inactive, .led.stopped {

      background-color: #d9534f;

      box-shadow: 0 0 5px rgba(217, 83, 79, 0.75), 0 0 0 2px rgba(217, 83, 79, 0.25);

    }

    .led.orange, .led.yellow, .led.warn, .led.warning, .led.busy {

      background-color: #f89406;

      box-shadow: 0 0 5px rgba(248, 148, 6, 0.75), 0 0 0 2px rgba(248, 148, 6, 0.25);

    }

    .led.gray, .led.grey, .led.off, .led.none {

      background-color: #8c8c8c;

      box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.3);

    }



    /* Pulsanti Technicolor / Bootstrap 2.3.2 */

    .btn {

      display: inline-flex;

      align-items: center;

      justify-content: center;

      gap: 6px;

      width: 100%;

      padding: 8px 14px;

      font-family: Helvetica, Arial, sans-serif;

      font-size: 13.5px;

      font-weight: bold;

      line-height: 18px;

      text-align: center;

      border-radius: 4px;

      cursor: pointer;

      transition: filter 0.15s ease, opacity 0.15s ease;

      user-select: none;

    }

    .btn:hover:not(:disabled) {

      filter: brightness(1.06);

    }

    .btn:active:not(:disabled) {

      transform: translateY(1px);

    }

    .btn:disabled {

      opacity: 0.6;

      cursor: not-allowed;

    }

    .btn svg {

      width: 13px;

      height: 13px;

      flex-shrink: 0;

    }



    /* Pulsante Grigio Technicolor (Riavvia Servizi) */

    .btn-default {

      background-color: #f5f5f5;

      background-image: linear-gradient(to bottom, #ffffff, #e6e6e6);

      border: 1px solid #cccccc;

      border-bottom-color: #b3b3b3;

      color: #1e741e;

      text-shadow: 0 1px 1px rgba(255, 255, 255, 0.75);

      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.2), 0 1px 2px rgba(0, 0, 0, 0.08);

    }

    .btn-default svg {

      fill: #1e741e;

    }



    /* Pulsante Verde Technicolor (Flash da USB, Carica & Flash, Invia) */

    .btn-tch {

      background: rgb(30, 116, 30);

      background: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);

      border: 1px solid rgb(25, 95, 25);

      color: #ffffff;

      text-shadow: 0 1px 1px #000000;

      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.15), 0 2px 4px rgba(0, 0, 0, 0.2);

    }

    .btn-tch svg {

      fill: #ffffff;

    }



    /* Pulsante Rosso Pericolo (Riavvia Modem) */

    .btn-danger {

      background-color: #da4f49;

      background-image: linear-gradient(to bottom, #ee5f5b, #bd362f);

      border: 1px solid #bd362f;

      color: #ffffff;

      text-shadow: 0 -1px 0 rgba(0, 0, 0, 0.25);

      box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.2), 0 1px 2px rgba(0, 0, 0, 0.15);

    }

    .btn-danger svg {

      fill: #ffffff;

    }



    /* Pulsante Bianco Header "Pulisci" */

    .btn-clear {

      width: auto;

      padding: 4px 12px;

      font-size: 12px;

      line-height: 16px;

      background: #ffffff;

      color: #1e741e;

      border: 1px solid rgba(0, 0, 0, 0.2);

      border-radius: 3px;

      text-shadow: none;

      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.15);

    }

    .btn-clear svg {

      width: 12px;

      height: 12px;

      fill: #1e741e;

    }



    /* Sezione Upload File & Progress Bar */

    .file-input-box {

      border: 1px solid #cccccc;

      border-radius: 4px;

      padding: 6px 8px;

      background-color: #fafafa;

      margin-top: 6px;

    }

    .file-input-box input[type="file"] {

      width: 100%;

      font-size: 12px;

      color: #333333;

      cursor: pointer;

    }

    .upload-meta {

      font-size: 11px;

      color: #777777;

      margin-top: 2px;

    }

    .progress-wrap {

      display: none;

      width: 100%;

      height: 18px;

      background-color: #f5f5f5;

      border-radius: 4px;

      box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.1);

      overflow: hidden;

      margin-top: 6px;

      border: 1px solid #dddddd;

    }

    .progress-bar {

      width: 0%;

      height: 100%;

      background-color: #1e741e;

      background-image: linear-gradient(to bottom, #2b942b, #185c18);

      color: #ffffff;

      font-size: 11px;

      font-weight: bold;

      line-height: 18px;

      text-align: center;

      transition: width 0.2s ease;

    }

    .status-feedback {

      font-size: 12px;

      line-height: 16px;

      min-height: 16px;

      margin-top: 4px;

      font-weight: bold;

    }

    .status-feedback.ok { color: #1e741e; }

    .status-feedback.err { color: #bd362f; }

    .status-feedback.warn { color: #c09853; }



    /* Console Rescue & Tabs */

    .console-tabs {

      display: flex;

      gap: 6px;

      margin-bottom: 10px;

    }

    .tab-btn {

      padding: 6px 14px;

      font-family: Helvetica, Arial, sans-serif;

      font-size: 13px;

      font-weight: bold;

      border-radius: 4px;

      cursor: pointer;

      border: 1px solid #cccccc;

      background-color: #ffffff;

      color: #1e741e;

      transition: all 0.15s ease;

    }

    .tab-btn.active {

      background: rgb(30, 116, 30);

      background: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);

      border-color: rgb(25, 95, 25);

      color: #ffffff;

      text-shadow: 0 1px 1px #000000;

    }



    /* Terminale Nero Monospace */

    .terminal-box {

      background-color: #0c0c0c;

      color: #e8e8e8;

      font-family: Consolas, "Liberation Mono", Menlo, Courier, monospace;

      font-size: 12.5px;

      line-height: 18px;

      height: 225px;

      padding: 12px 14px;

      border-radius: 4px;

      border: 1px solid #222222;

      overflow-y: auto;

      white-space: pre-wrap;

      word-break: break-word;

      margin: 0 0 12px 0;

      box-shadow: inset 0 2px 6px rgba(0, 0, 0, 0.6);

    }

    .terminal-box .cmd-echo {

      color: #58d68d;

      font-weight: bold;

    }

    .terminal-box .cmd-err {

      color: #ff6b6b;

    }



    /* Barra Input Comandi */

    .cmd-bar {

      display: flex;

      align-items: center;

      gap: 10px;

    }

    .cmd-prompt {

      font-family: Consolas, "Liberation Mono", Menlo, Courier, monospace;

      font-size: 13px;

      font-weight: bold;

      color: #2e8b36;

      white-space: nowrap;

      user-select: none;

    }

    .cmd-input {

      flex: 1;

      background-color: #111111;

      color: #ffffff;

      border: 1px solid #333333;

      border-radius: 4px;

      padding: 8px 12px;

      font-family: Consolas, "Liberation Mono", Menlo, Courier, monospace;

      font-size: 13px;

      line-height: 18px;

      outline: none;

    }

    .cmd-input:focus {

      border-color: #1e741e;

      box-shadow: 0 0 4px rgba(30, 116, 30, 0.5);

    }

    .cmd-input::placeholder {

      color: #777777;

    }

    .btn-send {

      width: auto;

      min-width: 86px;

      padding: 8px 16px;

    }



    /* Footer Technicolor */

    .rescue-footer {

      margin-top: 28px;

      text-align: center;

      font-size: 12px;

      line-height: 19px;

      color: #777777;

    }

    .rescue-footer p {

      margin: 2px 0;

    }

    .rescue-footer .gh-green {

      color: #1e741e;

      font-weight: bold;

    }



    /* Responsività Tablet (2 colonne) & Mobile (1 colonna) */

    @media (max-width: 992px) {

      .cards-grid {

        grid-template-columns: repeat(2, 1fr);

      }

      .card.span-3 {

        grid-column: span 2;

      }

    }

    @media (max-width: 600px) {

      .rescue-container {

        padding: 12px;

      }

      .cards-grid {

        grid-template-columns: 1fr;

      }

      .card.span-3 {

        grid-column: span 1;

      }

      .cmd-bar {

        flex-wrap: wrap;

      }

      .cmd-input {

        width: 100%;

        flex: 1 1 100%;

      }

      .btn-send {

        width: 100%;

      }

    }

  </style>

</head>

<body data-rescue-version="@@VERSION@@" data-upload-max="@@UPLOAD_MAX@@">



  <div class="rescue-container">

    <!-- HEADER -->

    <header class="rescue-header">

      <div class="header-logo" title="Technicolor Gateway">

        <svg xmlns="http://www.w3.org/2000/svg" width="131" height="50" viewBox="0 0 600.29283 228.46002">

          <path d="M237.78 42.8c3.25-.01 6.51-.01 9.77-.01.05 15.17-.05 30.34.04 45.52 4.2-3.26 8.57-6.59 13.88-7.74 6.97-1.65 15.14.41 19.61 6.26 2.71 4.15 3.17 9.3 3.13 14.13-.08 10.58.05 21.15-.07 31.73-3.24.04-6.47.02-9.7.03.02-10.58 0-21.15.03-31.73-.01-3.35-.36-7.08-2.83-9.6-3.69-4.1-10.17-3.76-14.76-1.5-3.39 1.75-7.15 3.57-9.21 6.9-.28 11.96-.03 23.95-.1 35.92-3.27.01-6.53.01-9.79.01-.03-29.97-.02-59.95 0-89.92zM496.82 42.8c3.24-.01 6.48-.01 9.73-.03.12 29.98.01 59.96.05 89.95h-9.76c-.04-29.97-.01-59.95-.02-89.92zM361.46 57.67c3.47-1.47 7.85.54 8.53 4.36 1.36 4.81-4.62 9.67-8.96 6.88-4.47-2.19-4.3-9.51.43-11.24zM91.71 71.63c3.14-2.53 6.35-4.98 9.59-7.4.04 5.64.03 11.29.01 16.93 5.07.04 10.14.02 15.22.04-.01 2.78-.01 5.55-.01 8.33-5.06.01-10.12.01-15.18 0-.03 9.18-.01 18.35-.03 27.53-.05 2.5.28 5.55 2.68 6.95 2.97 1.45 6.41.8 9.58.77.4 2.64.83 5.27 1.26 7.9-5.29.93-11.07 1.8-16.14-.48-5.14-2.62-6.91-8.8-6.95-14.17-.06-9.5.03-18.99-.03-28.48-2.93.02-5.85 0-8.76-.25 2.68-3.13 5.68-5.97 8.7-8.77.08-2.97.1-5.93.06-8.9zM129.06 90.99c6.77-11.08 23.26-14.47 33.78-6.81 8.08 5.54 9.95 16.41 9.08 25.54-12.65.07-25.31-.01-37.97.04.41 5.82 3.81 11.64 9.43 13.78 7.76 2.9 16.35 1.46 23.99-1.13.61 2.7 1.28 5.39 2 8.06-10.31 3.52-22.48 5.09-32.4-.42-5.96-2.98-10.09-8.97-11.75-15.31-1.35-8-1.05-16.91 3.84-23.75m9.49 1.54c-2.62 2.67-3.58 6.41-4.5 9.91 9.74.07 19.47.05 29.21.02-.82-3.85-1.57-8.24-4.93-10.76-5.39-4.98-14.83-4.6-19.78.83zM202.06 80.96c8.37-2.45 17.4.12 24.63 4.57-1.37 2.37-2.65 4.77-3.88 7.21-6.84-3.47-15.25-6.29-22.54-2.43-10.42 4.56-12.36 19.58-5.9 28.15 3.17 3.66 7.74 6.31 12.65 6.58 5.78.64 11.36-1.42 16.4-4.03 1.05 2.49 2.15 4.97 3.33 7.4-7.65 4.56-16.91 6.59-25.64 4.31-6.23-1.94-12.31-5.49-15.72-11.22-5.14-8.03-5.4-18.8-.95-27.18 3.42-6.85 10.28-11.58 17.62-13.36zM319.86 80.88c6.43-1.92 14.21-.67 18.9 4.4 3.35 3.27 3.93 8.23 3.98 12.69.01 11.58 0 23.17-.01 34.75h-9.6c-.04-10.58.06-21.17-.03-31.75-.31-3.45-.01-7.61-2.97-10.05-3.06-3.31-8.16-3.04-12.12-1.86-4.1 1.79-8.42 4.08-10.95 7.88-.32 11.91-.02 23.85-.13 35.78h-9.69c-.01-17.18-.02-34.36 0-51.53 3.03-.01 6.06-.01 9.1-.01 0 2.56.02 5.11.01 7.67 3.95-3.47 8.37-6.59 13.51-7.97zM386.2 91.3c4.02-5.98 10.9-9.5 17.84-10.84 7.65-1.49 15.44 1.01 22.11 4.68-.85 2.61-1.92 5.14-3.26 7.54-6.59-2.88-14.1-6.03-21.23-3.04-10.42 3.43-14.21 17.43-8.85 26.46 3.41 6.47 11.14 9.88 18.27 8.91 4.41-.19 8.37-2.25 12.31-4.04 1.2 2.49 2.12 5.12 2.77 7.82-9.28 5.17-21.13 6.93-30.77 1.69-7.3-3.38-12.36-10.61-13.96-18.38-1.53-7.2.48-14.9 4.77-20.8zM454.48 80.57c8.65-1.82 18.3 1.07 24.31 7.62 9.41 10.08 9.34 27.43-.07 37.5-10.15 11.27-30.51 10.52-39.52-1.8-8.85-11.08-7.19-29.03 3.85-38.05 3.36-2.57 7.27-4.42 11.43-5.27m.88 7.97c-3.89 1.15-7.56 3.64-9.4 7.35-2.96 4.79-3.05 10.7-2.29 16.11 1.12 5.37 4.52 10.69 9.91 12.55 5.17 2.23 11.42 1.31 15.89-2.04 9.43-7.82 9.16-24.85-1.01-31.93-3.74-2.78-8.71-2.73-13.1-2.04zM539.26 80.38c7.3-1.32 15.13.85 20.9 5.46 12.28 9.88 12.56 30.83.94 41.33-9.23 8.39-24.46 8.66-34.11.83-12.33-9.88-12.72-30.56-1.21-41.23 3.8-3.32 8.52-5.5 13.48-6.39m-.75 8.34c-3.8 1.47-7.45 4-9.09 7.86-3.4 7.12-3.12 16.2 1.28 22.85 5.48 7.68 17.95 8.5 24.33 1.49 7.8-8.47 6.82-24.39-3.27-30.7-3.86-2.58-8.9-2.36-13.25-1.5zM589.49 89.52c4.38-5.66 11.2-9.15 18.32-9.66.04 3.23.04 6.46.06 9.7-5.81.47-12.07 1.65-16.38 5.89-1.65 1.35-1.39 3.59-1.43 5.48.06 10.59.03 21.19.02 31.79h-9.94c-.01-17.18 0-34.36 0-51.53 3.12-.01 6.25-.01 9.38-.01.02 2.78.02 5.56-.03 8.34zM359.06 81.18c3.21 0 6.41 0 9.62.01v51.53h-9.55c.03-17.18-.04-34.36-.07-51.54z" style="opacity:1;fill:#6d6e72" transform="translate(-42.86705 -42.77001)"/>

          <path d="M42.87 185.92c10.03-7.06 19.74-14.67 30.13-21.18 12.51-.42 25.08-.09 37.61-.14-7.74 7.75-16.78 14.03-24.91 21.36-14.27-.02-28.55.05-42.83-.04z" style="opacity:1;fill:#81dcf9" transform="translate(-42.86705 -42.77001)"/>

          <path d="M110.61 164.6c12.95-.08 25.9-.07 38.84 0-6.6 7.44-13.96 14.18-20.83 21.37-14.3-.01-28.61.01-42.92-.01 8.13-7.33 17.17-13.61 24.91-21.36z" style="opacity:1;fill:#81c7eb" transform="translate(-42.86705 -42.77001)"/>

          <path d="M149.45 164.6c12.93-.07 25.87-.02 38.8-.03-5.26 7.31-11.27 14.05-16.47 21.39h-.43c-14.25.02-28.49 0-42.73.01 6.87-7.19 14.23-13.93 20.83-21.37z" style="opacity:1;fill:#81a6d0" transform="translate(-42.86705 -42.77001)"/>

          <path d="M188.25 164.57c12.74-.01 25.47-.02 38.21.01-3.54 7.35-8.05 14.18-11.88 21.38-14.27.01-28.53 0-42.8 0 5.2-7.34 11.21-14.08 16.47-21.39z" style="opacity:1;fill:#b296c7" transform="translate(-42.86705 -42.77001)"/>

          <path d="M226.46 164.58c12.94-.02 25.88-.03 38.83 0-2.31 7.27-5.24 14.31-8.04 21.39-14.22.01-28.44.01-42.67-.01 3.83-7.2 8.34-14.03 11.88-21.38z" style="opacity:1;fill:#c894bb" transform="translate(-42.86705 -42.77001)"/>

          <path d="M265.29 164.58c12.93-.03 25.87 0 38.8-.01-1.15 7.17-2.47 14.31-3.99 21.4-14.29.01-28.57 0-42.85 0 2.8-7.08 5.73-14.12 8.04-21.39z" style="opacity:1;fill:#de92ae" transform="translate(-42.86705 -42.77001)"/>

          <path d="M304.09 164.57c12.98-.03 25.96-.02 38.94 0-.04 7.14-.02 14.27-.03 21.41-14.3-.02-28.6-.02-42.9-.01 1.52-7.09 2.84-14.23 3.99-21.4z" style="opacity:1;fill:#f78d97" transform="translate(-42.86705 -42.77001)"/>

          <path d="M343.03 164.57c12.68.02 25.36.01 38.04.01 2.01 7.05 3.4 14.25 5.09 21.39-14.39.02-28.77.01-43.16.01.01-7.14-.01-14.27.03-21.41z" style="opacity:1;fill:#f9b292" transform="translate(-42.86705 -42.77001)"/>

          <path d="M381.07 164.58c12.94-.04 25.89-.01 38.84-.02 3.08 7.09 6.08 14.21 8.93 21.41-14.23-.01-28.45 0-42.68 0-1.69-7.14-3.08-14.34-5.09-21.39z" style="opacity:1;fill:#ffe086" transform="translate(-42.86705 -42.77001)"/>

          <path d="M419.91 164.56c12.91-.01 25.83-.04 38.75.01 3.96 7.28 9.23 13.8 12.65 21.37-14.16.05-28.32.02-42.47.03-2.85-7.2-5.85-14.32-8.93-21.41z" style="opacity:1;fill:#fff681" transform="translate(-42.86705 -42.77001)"/>

          <path d="M458.66 164.57c13.02-.01 26.04-.05 39.06.02 5.51 7.31 11.44 14.3 17.23 21.39-14.41-.04-28.83.03-43.24-.04h-.4c-3.42-7.57-8.69-14.09-12.65-21.37z" style="opacity:1;fill:#e5ee95" transform="translate(-42.86705 -42.77001)"/>

          <path d="M497.72 164.59c12.8-.04 25.6-.05 38.4 0 6.77 7.37 14.51 13.8 21.07 21.38-14.08.01-28.16-.01-42.24.01-5.79-7.09-11.72-14.08-17.23-21.39z" style="opacity:1;fill:#c7e29f" transform="translate(-42.86705 -42.77001)"/>

          <path d="M536.12 164.59c13.11-.04 26.22-.05 39.33.01 7.46 8.02 16.55 14.26 24.82 21.37-14.21-.01-28.42 0-42.63 0h-.45c-6.56-7.58-14.3-14.01-21.07-21.38z" style="opacity:1;fill:#80d39f" transform="translate(-42.86705 -42.77001)"/>

          <path d="M575.45 164.6c11.85-.1 23.7-.01 35.56-.05 2.05-.22 3.85.87 5.44 2.05 8.83 6.52 17.98 12.61 26.71 19.29-14.3.18-28.59.02-42.89.08-8.27-7.11-17.36-13.35-24.82-21.37z" style="opacity:1;fill:#80c5a6" transform="translate(-42.86705 -42.77001)"/>

          <path d="M42.87 185.92c14.28.09 28.56.02 42.83.04.06 19.86.03 39.72.03 59.57-14.27.02-28.53-.03-42.8.03-.13-19.88-.01-39.76-.06-59.64z" style="opacity:1;fill:#00b9f2" transform="translate(-42.86705 -42.77001)"/>

          <path d="M85.7 185.96c14.31.02 28.62 0 42.92.01-.06 17.41-.07 34.81.01 52.22.02 11.01.05 22.03-.02 33.04-14.3-.06-28.59.01-42.88-.04v-25.66c0-19.85.03-39.71-.03-59.57z" style="opacity:1;fill:#008fd5" transform="translate(-42.86705 -42.77001)"/>

          <path d="M128.62 185.97c14.24-.01 28.48.01 42.73-.01.14 17.41.02 34.82.06 52.22-14.26.01-28.52 0-42.78.01-.08-17.41-.07-34.81-.01-52.22z" style="opacity:1;fill:#034da2" transform="translate(-42.86705 -42.77001)"/>

          <path d="M171.35 185.96h.43c14.27 0 28.53.01 42.8 0 .06 21.15.04 42.3.02 63.45-14.39.05-28.78 0-43.16.03-.03-3.75-.03-7.51-.03-11.26-.04-17.4.08-34.81-.06-52.22z" style="opacity:1;fill:#662e91" transform="translate(-42.86705 -42.77001)"/>

          <path d="M214.58 185.96c14.23.02 28.45.02 42.67.01.2 24.77-.03 49.55.12 74.32.02 2.9.01 5.79.01 8.69-14.26.04-28.52.01-42.78.02-.01-6.53-.02-13.06 0-19.59.02-21.15.04-42.3-.02-63.45z" style="opacity:1;fill:#942977" transform="translate(-42.86705 -42.77001)"/>

          <path d="M257.25 185.97c14.28 0 28.56.01 42.85 0-.02 19.42-.06 38.84.01 58.25.03 5.36.01 10.71.01 16.07-14.25.02-28.5.01-42.75 0-.15-24.77.08-49.55-.12-74.32z" style="opacity:1;fill:#bf245e" transform="translate(-42.86705 -42.77001)"/>

          <path d="M300.1 185.97c14.3-.01 28.6-.01 42.9.01-.01 19.41.01 38.82-.01 58.23-14.29.03-28.59.01-42.88.01-.07-19.41-.03-38.83-.01-58.25z" style="opacity:1;fill:#ec1b30" transform="translate(-42.86705 -42.77001)"/>

          <path d="M343 185.98c14.39 0 28.77.01 43.16-.01.07 18.22-.03 36.45.05 54.68.03 6.97 0 13.93.03 20.89-14.41.12-28.82.01-43.23.06-.02-5.79-.01-11.59-.02-17.39.02-19.41 0-38.82.01-58.23z" style="opacity:1;fill:#f36523" transform="translate(-42.86705 -42.77001)"/>

          <path d="M386.16 185.97c14.23 0 28.45-.01 42.68 0-.18 18.23 0 36.46-.09 54.7-14.18-.04-28.36-.01-42.54-.02-.08-18.23.02-36.46-.05-54.68z" style="opacity:1;fill:#ffc20f" transform="translate(-42.86705 -42.77001)"/>

          <path d="M428.84 185.97c14.15-.01 28.31.02 42.47-.03h.4c-.25 16.2-.1 32.4-.08 48.6.04 6.53-.01 13.07.03 19.6-14.32-.13-28.66.34-42.97-.25.1-4.41.07-8.81.06-13.22.09-18.24-.09-36.47.09-54.7z" style="opacity:1;fill:#ffec01" transform="translate(-42.86705 -42.77001)"/>

          <path d="M471.71 185.94c14.41.07 28.83 0 43.24.04-.06 13.25 0 26.5-.03 39.75-.01 2.94-.01 5.87-.01 8.81-14.43-.01-28.86-.01-43.28 0-.02-16.2-.17-32.4.08-48.6z" style="opacity:1;fill:#cadb2a" transform="translate(-42.86705 -42.77001)"/>

          <path d="M514.95 185.98c14.08-.02 28.16 0 42.24-.01h.45c-.11 13.25-.01 26.5-.06 39.76-14.22.01-28.44 0-42.66 0 .03-13.25-.03-26.5.03-39.75z" style="opacity:1;fill:#8ec63f" transform="translate(-42.86705 -42.77001)"/>

          <path d="M557.64 185.97c14.21 0 28.42-.01 42.63 0 .09 20.25-.01 40.5.09 60.74-14.26.01-28.52.01-42.77 0 .01-6.99.01-13.99-.01-20.98.05-13.26-.05-26.51.06-39.76z" style="opacity:1;fill:#00a640" transform="translate(-42.86705 -42.77001)"/>

          <path d="M600.27 185.97c14.3-.06 28.59.1 42.89-.08-.08 25.64-.01 51.28-.04 76.92-14.25-.01-28.5 0-42.75-.01.01-5.36.02-10.73-.01-16.09-.1-20.24 0-40.49-.09-60.74z" style="opacity:1;fill:#008a4c" transform="translate(-42.86705 -42.77001)"/>

        </svg>

      </div>

      <div class="header-actions">

        <select id="webui_language" aria-label="Language">

          <option value="it">Italiano</option>

          <option value="en">English</option>

        </select>

      </div>

    </header>



    <!-- ALERT MODALITA' DI EMERGENZA -->

    <div class="alert-warning" role="alert">

      <svg viewBox="0 0 16 16" aria-hidden="true">

        <path d="M8.982 1.566a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>

      </svg>

      <span data-i18n="emergency_active">Modalità di Emergenza Attiva</span>

    </div>



    <!-- GRIGLIA PRINCIPALE (RIGA 1 + RIGA 2) -->

    <main class="cards-grid">



      <!-- CARD 1: STATO DEL SISTEMA -->

      <section class="card">

        <div class="sh">

          <span class="sh-title" data-i18n="card_sys_status">Stato del Sistema</span>

        </div>

        <div class="card-body">

          <div class="card-content">

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M5 0v2H3a1 1 0 0 0-1 1v2H0v2h2v2H0v2h2v2a1 1 0 0 0 1 1h2v2h2v-2h2v2h2v-2h2a1 1 0 0 0 1-1v-2h2V9h-2V7h2V5h-2V3a1 1 0 0 0-1-1h-2V0H9v2H7V0H5zm-1 4h8v8H4V4zm2 2v4h4V6H6z"/></svg>

              <span><strong data-i18n="lbl_model">Modello:</strong> <span id="hw-val">@@HARDWARE@@</span></span>

            </div>

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M2 2a2 2 0 0 1 2-2h5.586a1 1 0 0 1 .707.293l4.414 4.414a1 1 0 0 1 .293.707V14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2zm3.5 2a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z"/></svg>

              <span><strong data-i18n="lbl_guiver">Versione GUI:</strong> <span class="gui-ver" id="guiver-val">@@GUIVER@@</span></span>

            </div>

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M1 3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h4v-2h2v2h2v-2h2v2h4a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H1zm2 3h2v4H3V6zm4 0h2v4H7V6zm4 0h2v4h-2V6z"/></svg>

              <span><strong data-i18n="lbl_ram">RAM:</strong> <span id="mem-val">@@MEM@@</span></span>

            </div>

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M8 16A8 8 0 1 0 8 0a8 8 0 0 0 0 16zm.5-13v4.793l2.854 2.853-.708.708L7.5 8.207V3h1z"/></svg>

              <span><strong data-i18n="lbl_uptime">Uptime:</strong> <span id="uptime-val">@@UPTIME@@</span></span>

            </div>

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M8 0c-.69 0-1.843.265-2.928.56-1.11.3-2.229.655-2.887.87a1.54 1.54 0 0 0-1.044 1.262c-.596 4.477.787 7.795 2.465 9.99a11.777 11.777 0 0 0 2.517 2.453c.386.273.744.482 1.048.625.28.132.581.24.829.24s.548-.108.829-.24a7.159 7.159 0 0 0 1.048-.625 11.775 11.775 0 0 0 2.517-2.453c1.678-2.195 3.061-5.513 2.465-9.99a1.541 1.541 0 0 0-1.044-1.263 62.467 62.467 0 0 0-2.887-.87C9.843.266 8.69 0 8 0z"/></svg>

              <span><strong data-i18n="lbl_kernel">Kernel:</strong> <span id="kernel-val">@@KERNEL@@</span></span>

            </div>

          </div>

        </div>

      </section>



      <!-- CARD 2: SERVIZI WEB -->

      <section class="card">

        <div class="sh">

          <span class="sh-title" data-i18n="card_web_services">Servizi Web</span>

        </div>

        <div class="card-body">

          <div class="card-content">

            <div class="led-row">

              <span id="nginx-led" class="led @@NGINX_LED@@"></span>

              <span><strong>Nginx:</strong> <span id="nginx-txt" data-state="@@NGINX_STATE@@">@@NGINX_TXT@@</span></span>

            </div>

            <div class="led-row">

              <span id="trans-led" class="led @@TRANS_LED@@"></span>

              <span><strong>Transformer:</strong> <span id="trans-txt" data-state="@@TRANS_STATE@@">@@TRANS_TXT@@</span></span>

            </div>

            <p class="card-desc" data-i18n="web_services_desc">

              Nginx e Transformer gestiscono l'accesso web primario (porta 80).

            </p>

            <div id="srv-feedback" class="status-feedback"></div>

          </div>

          <div class="card-footer-action">

            <button type="button" class="btn btn-default" id="btn-restart-srv" onclick="restartServices()">

              <svg viewBox="0 0 16 16"><path d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z"/><path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z"/></svg>

              <span data-i18n="btn_restart_srv">Riavvia Servizi</span>

            </button>

          </div>

        </div>

      </section>



      <!-- CARD 3: RIPRISTINO USB -->

      <section class="card">

        <div class="sh">

          <span class="sh-title" data-i18n="card_usb_recovery">Ripristino USB</span>

        </div>

        <div class="card-body">

          <div class="card-content">

            <div class="led-row">

              <span id="usb-led" class="led @@USB_LED@@"></span>

              <span id="usb-txt">@@USB_TXT@@</span>

            </div>

            <p class="card-desc" data-i18n="usb_recovery_desc">

              Inserisci una chiavetta USB con il pacchetto di ripristino della GUI per avviare il flashing automatico.

            </p>

            <div id="usb-feedback" class="status-feedback"></div>

          </div>

          <div class="card-footer-action">

            <button type="button" class="btn btn-tch" id="btn-usb-flash" onclick="usbRecovery()">

              <svg viewBox="0 0 16 16"><path d="m11.596 8.697-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393z"/></svg>

              <span data-i18n="btn_usb_flash">Flash da USB</span>

            </button>

          </div>

        </div>

      </section>



      <!-- CARD 4: CARICA PACCHETTO -->

      <section class="card">

        <div class="sh">

          <span class="sh-title" data-i18n="card_pkg_upload">Carica Pacchetto</span>

        </div>

        <div class="card-body">

          <div class="card-content">

            <p class="card-desc" style="margin-top:0;" data-i18n="pkg_upload_desc">

              Seleziona il pacchetto di ripristino dal computer:

            </p>

            <div class="file-input-box">

              <input type="file" id="pkg-file" accept=".tar.bz2,.bz2,.tar.gz,.tgz,.ipk">

            </div>

            <div class="upload-meta">

              <span data-i18n="lbl_max_size">Max:</span> <span id="upload-max-val">@@UPLOAD_MAX@@</span>

            </div>

            <div class="progress-wrap" id="upload-prog-wrap">

              <div class="progress-bar" id="upload-prog-bar">0%</div>

            </div>

            <div id="upload-feedback" class="status-feedback"></div>

          </div>

          <div class="card-footer-action">

            <button type="button" class="btn btn-tch" id="btn-upload-flash" onclick="uploadPackage()">

              <svg viewBox="0 0 16 16"><path d="M.5 9.9a.5.5 0 0 1 .5.5v2.5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2.5a.5.5 0 0 1 1 0v2.5a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2v-2.5a.5.5 0 0 1 .5-.5z"/><path d="M7.646 1.146a.5.5 0 0 1 .708 0l3 3a.5.5 0 0 1-.708.708L8.5 2.707V11.5a.5.5 0 0 1-1 0V2.707L5.354 4.854a.5.5 0 1 1-.708-.708l3-3z"/></svg>

              <span data-i18n="btn_upload_flash">Carica &amp; Flash</span>

            </button>

          </div>

        </div>

      </section>



      <!-- CARD 5: GESTIONE MODEM (1 Colonna) -->

      <section class="card">

        <div class="sh">

          <span class="sh-title" data-i18n="card_modem_mgmt">Gestione Modem</span>

        </div>

        <div class="card-body">

          <div class="card-content">

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M2 2a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2H2zm1 3h2v2H3V5zm4 0h2v2H7V5zm4 0h2v2h-2V5z"/></svg>

              <span><strong data-i18n="lbl_port">Porta rescue:</strong> <span id="port-val">@@PORT@@</span></span>

            </div>

            <div class="info-row">

              <svg class="info-icon" viewBox="0 0 16 16"><path d="M4 0h5.5L14 4.5V14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V2a2 2 0 0 1 2-2zm5.5 1.5V5H13L9.5 1.5z"/></svg>

              <span><strong data-i18n="lbl_log">Log:</strong> <span id="logfile-val">@@LOGFILE@@</span></span>

            </div>

            <p class="card-desc" data-i18n="modem_reboot_desc">

              Riavvio hardware a basso livello del gateway.

            </p>

            <div id="reboot-feedback" class="status-feedback"></div>

          </div>

          <div class="card-footer-action">

            <button type="button" class="btn btn-danger" id="btn-reboot" onclick="rebootModem()">

              <svg viewBox="0 0 16 16"><path d="M7.5 1v7h1V1h-1z"/><path d="M3 8.812a4.999 4.999 0 0 1 2.578-4.375l-.485-.874A6 6 0 1 0 11 3.616l-.501.865A5 5 0 1 1 3 8.812z"/></svg>

              <span data-i18n="btn_reboot">Riavvia Modem</span>

            </button>

          </div>

        </div>

      </section>



      <!-- CARD 6: CONSOLE RESCUE & ROOT SHELL (Spanna 3 Colonne) -->

      <section class="card span-3">

        <div class="sh">

          <span class="sh-title">

            <svg width="16" height="16" viewBox="0 0 16 16" fill="#ffffff">

              <path d="M6 9a.5.5 0 0 1 .5-.5h3a.5.5 0 0 1 0 1h-3A.5.5 0 0 1 6 9zM3.854 4.146a.5.5 0 1 0-.708.708L4.793 6.5 3.146 8.146a.5.5 0 1 0 .708.708l2-2a.5.5 0 0 0 0-.708l-2-2z"/>

              <path d="M2 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2H2zm12 1a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1h12z"/>

            </svg>

            <span data-i18n="card_rescue_console">Console Rescue</span>

          </span>

          <button type="button" class="btn btn-clear" id="btn-clear-console" onclick="clearConsole()">

            <span data-i18n="btn_clear">Pulisci</span>

          </button>

        </div>

        <div class="card-body">

          <div>

            <!-- Tab Interattivi -->

            <div class="console-tabs">

              <button type="button" class="tab-btn active" id="tab-btn-shell" onclick="switchTab('shell')" data-i18n="tab_shell">Shell Root</button>

              <button type="button" class="tab-btn" id="tab-btn-log" onclick="switchTab('log')" data-i18n="tab_log">Log</button>

            </div>



            <!-- Box Terminale Nero: Vista Shell Root -->

            <pre class="terminal-box" id="shell-output"></pre>



            <!-- Box Terminale Nero: Vista Log Operativo -->

            <pre class="terminal-box" id="log-output" style="display:none;"></pre>

          </div>



          <!-- Barra Input Comandi -->

          <div class="cmd-bar" id="cmd-bar">

            <span class="cmd-prompt" id="cmd-prompt">root@rescue:/#</span>

            <input type="text" id="cmd-input" class="cmd-input" placeholder="Comando shell root (es. ls -la, ifconfig, df -h)..." data-i18n-placeholder="cmd_placeholder" autocomplete="off" spellcheck="false">

            <button type="button" class="btn btn-tch btn-send" id="btn-send-cmd" onclick="execCommand()">

              <svg viewBox="0 0 16 16"><path d="m11.596 8.697-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393z"/></svg>

              <span data-i18n="btn_send">Invia</span>

            </button>

          </div>

        </div>

      </section>



    </main>



    <!-- FOOTER TECHNICOLOR -->

    <footer class="rescue-footer">

      <p>&copy; Technicolor 2026 &bull; Rescue Console (<span data-i18n="footer_port">Porta</span> @@PORT@@) &bull; v@@VERSION@@</p>

      <p><span data-i18n="footer_guiver">Versione GUI:</span> <span class="gui-ver" id="footer-guiver">@@GUIVER@@</span></p>

      <p>

        <span data-i18n="footer_credits_1">Fork &amp; modifiche di</span>

        <a href="https://github.com/ziocook" target="_blank" rel="noopener">ZioCook</a> &bull;

        <span data-i18n="footer_credits_2">Codice originale di</span>

        <a href="https://github.com/Ansuel" target="_blank" rel="noopener">Ansuel</a>

        <span data-i18n="footer_credits_3">e</span>

        <a href="https://github.com/Ansuel/tch-nginx-gui/graphs/contributors" target="_blank" rel="noopener" class="gh-green" data-i18n="footer_credits_4">questi utenti GitHub.</a>

      </p>

      <p>

        <span data-i18n="footer_credits_5">Utility di sblocco di</span>

        <a href="https://github.com/ADeltaX" target="_blank" rel="noopener">ADeltaX</a> -

        <span data-i18n="footer_credits_6">Traduzione GUI di</span>

        <a href="https://github.com/DarkNiko" target="_blank" rel="noopener">DarkNiko</a>,

        <a href="https://github.com/bovirus" target="_blank" rel="noopener">bovirus</a>

      </p>

    </footer>

  </div>



  <!-- LOGICA JAVASCRIPT STANDALONE -->

  <script>
    (function () {
      "use strict";

      var I18N = {
        it: {
          emergency_active: "Modalità di Emergenza Attiva",
          card_sys_status: "Stato del Sistema",
          lbl_model: "Modello:",
          lbl_guiver: "Versione GUI:",
          lbl_ram: "RAM:",
          lbl_uptime: "Uptime:",
          lbl_kernel: "Kernel:",
          card_web_services: "Servizi Web",
          web_services_desc: "Nginx e Transformer gestiscono l'accesso web primario (porta 80).",
          btn_restart_srv: "Riavvia Servizi",
          card_usb_recovery: "Ripristino USB",
          usb_recovery_desc: "Inserisci una chiavetta USB con il pacchetto di ripristino della GUI per avviare il flashing automatico.",
          btn_usb_flash: "Flash da USB",
          card_pkg_upload: "Carica Pacchetto",
          pkg_upload_desc: "Seleziona il pacchetto di ripristino dal computer:",
          lbl_max_size: "Max:",
          btn_upload_flash: "Carica & Flash",
          card_modem_mgmt: "Gestione Modem",
          lbl_port: "Porta rescue:",
          lbl_log: "Log:",
          modem_reboot_desc: "Riavvio hardware a basso livello del gateway.",
          btn_reboot: "Riavvia Modem",
          card_rescue_console: "Console Rescue",
          btn_clear: "Pulisci",
          tab_shell: "Shell Root",
          tab_log: "Log",
          cmd_placeholder: "Comando shell root (es. ls -la, ifconfig, df -h)...",
          btn_send: "Invia",
          footer_port: "Porta",
          footer_guiver: "Versione GUI:",
          footer_credits_1: "Fork & modifiche di",
          footer_credits_2: "Codice originale di",
          footer_credits_3: "e",
          footer_credits_4: "questi utenti GitHub.",
          footer_credits_5: "Utility di sblocco di",
          footer_credits_6: "Traduzione GUI di",
          state_active: "Attivo",
          state_inactive: "Inattivo",
          usb_none: "Nessuna chiavetta rilevata",
          usb_detected_prefix: "Chiavetta rilevata",
          shell_banner: "Technicolor Emergency Root Shell\nDigita un comando root (es. ls -la, ps, df -h, free -m) e premi Invio.\nOgni comando gira in una shell separata; 'cd' viene ricordato dalla console.\n",
          msg_restarting_srv: "Riavvio servizi in corso...",
          msg_restarted_srv: "Servizi riavviati correttamente.",
          msg_usb_starting: "Avvio ripristino da USB in corso...",
          msg_usb_done: "Procedura USB avviata. Controlla il tab Log.",
          msg_select_file: "Seleziona prima un file .tar.bz2 valido.",
          msg_uploading: "Caricamento e flash in corso...",
          msg_upload_ok: "Pacchetto caricato e installato con successo!",
          msg_upload_err: "Errore durante il caricamento del pacchetto.",
          msg_reboot_confirm: "Sei sicuro di voler riavviare il modem?",
          msg_rebooting: "Riavvio hardware del modem inviato...",
          msg_log_cleared: "[Log svuotato]\n"
        },
        en: {
          emergency_active: "Emergency Mode Active",
          card_sys_status: "System Status",
          lbl_model: "Model:",
          lbl_guiver: "GUI Version:",
          lbl_ram: "RAM:",
          lbl_uptime: "Uptime:",
          lbl_kernel: "Kernel:",
          card_web_services: "Web Services",
          web_services_desc: "Nginx and Transformer manage primary web access (port 80).",
          btn_restart_srv: "Restart Services",
          card_usb_recovery: "USB Recovery",
          usb_recovery_desc: "Insert a USB drive containing the GUI recovery package to start automatic flashing.",
          btn_usb_flash: "Flash from USB",
          card_pkg_upload: "Upload Package",
          pkg_upload_desc: "Select the recovery package from your computer:",
          lbl_max_size: "Max:",
          btn_upload_flash: "Upload & Flash",
          card_modem_mgmt: "Modem Management",
          lbl_port: "Rescue port:",
          lbl_log: "Log:",
          modem_reboot_desc: "Low-level hardware reboot of the gateway.",
          btn_reboot: "Reboot Modem",
          card_rescue_console: "Rescue Console",
          btn_clear: "Clear",
          tab_shell: "Root Shell",
          tab_log: "Log",
          cmd_placeholder: "Root shell command (e.g. ls -la, ifconfig, df -h)...",
          btn_send: "Send",
          footer_port: "Port",
          footer_guiver: "GUI Version:",
          footer_credits_1: "Fork & modifications by",
          footer_credits_2: "Original code by",
          footer_credits_3: "and",
          footer_credits_4: "these GitHub users.",
          footer_credits_5: "Unlock utility by",
          footer_credits_6: "GUI translation by",
          state_active: "Active",
          state_inactive: "Inactive",
          usb_none: "No USB drive detected",
          usb_detected_prefix: "USB drive detected",
          shell_banner: "Technicolor Emergency Root Shell\nType a root command (e.g. ls -la, ps, df -h, free -m) and press Enter.\nEach command runs in a separate shell; 'cd' is remembered by the console.\n",
          msg_restarting_srv: "Restarting web services...",
          msg_restarted_srv: "Services restarted successfully.",
          msg_usb_starting: "Starting USB recovery...",
          msg_usb_done: "USB recovery triggered. Check the Log tab.",
          msg_select_file: "Please select a valid .tar.bz2 file first.",
          msg_uploading: "Uploading and flashing package...",
          msg_upload_ok: "Package uploaded and flashed successfully!",
          msg_upload_err: "Error uploading package.",
          msg_reboot_confirm: "Are you sure you want to reboot the modem?",
          msg_rebooting: "Hardware reboot command sent...",
          msg_log_cleared: "[Log cleared]\n"
        }
      };

      var currentLang = "it";
      try {
        currentLang = localStorage.getItem("rescue_lang") || "it";
      } catch (e) {}
      if (!I18N[currentLang]) currentLang = "it";

      var activeTab = "shell";
      var logPos = 0;
      var cmdHistory = [];
      var historyIdx = -1;
      var currentCwd = "/";
      var shellTouched = false;
      var uploading = false;

      function t(key) {
        return (I18N[currentLang] && I18N[currentLang][key]) || I18N.it[key] || key;
      }

      function translateServiceState(el) {
        if (!el) return;
        var st = (el.getAttribute("data-state") || "").toLowerCase();
        if (st === "active" || st === "running" || st === "1" || st === "ok") {
          el.textContent = t("state_active");
        } else if (st === "inactive" || st === "stopped" || st === "0" || st === "err") {
          el.textContent = t("state_inactive");
        }
      }

      function applyLanguage(lang) {
        if (!I18N[lang]) lang = "it";
        currentLang = lang;
        try {
          localStorage.setItem("rescue_lang", lang);
        } catch (e) {}

        var sel = document.getElementById("webui_language");
        if (sel && sel.value !== lang) sel.value = lang;
        document.documentElement.lang = lang;

        var nodes = document.querySelectorAll("[data-i18n]");
        for (var i = 0; i < nodes.length; i++) {
          var key = nodes[i].getAttribute("data-i18n");
          if (key) nodes[i].textContent = t(key);
        }

        var inputs = document.querySelectorAll("[data-i18n-placeholder]");
        for (var j = 0; j < inputs.length; j++) {
          var pKey = inputs[j].getAttribute("data-i18n-placeholder");
          if (pKey) inputs[j].setAttribute("placeholder", t(pKey));
        }

        translateServiceState(document.getElementById("nginx-txt"));
        translateServiceState(document.getElementById("trans-txt"));

        var ut = document.getElementById("usb-txt");
        if (ut && (ut.textContent === "Nessuna chiavetta rilevata" || ut.textContent === "No USB drive detected")) {
          ut.textContent = t("usb_none");
        }

        var shellEl = document.getElementById("shell-output");
        if (shellEl && !shellTouched) {
          shellEl.textContent = t("shell_banner");
        }
      }

      window.switchTab = function (tab) {
        activeTab = tab === "log" ? "log" : "shell";
        var btnShell = document.getElementById("tab-btn-shell");
        var btnLog = document.getElementById("tab-btn-log");
        var outShell = document.getElementById("shell-output");
        var outLog = document.getElementById("log-output");

        if (activeTab === "shell") {
          btnShell.classList.add("active");
          btnLog.classList.remove("active");
          outShell.style.display = "block";
          outLog.style.display = "none";
          outShell.scrollTop = outShell.scrollHeight;
        } else {
          btnLog.classList.add("active");
          btnShell.classList.remove("active");
          outLog.style.display = "block";
          outShell.style.display = "none";
          outLog.scrollTop = outLog.scrollHeight;
        }
      };

      function rescuePost(url, body, contentType, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("X-Rescue", "1");
        if (contentType) {
          xhr.setRequestHeader("Content-Type", contentType);
        }
        xhr.onreadystatechange = function () {
          if (xhr.readyState === 4) {
            var data = null;
            try {
              data = JSON.parse(xhr.responseText);
            } catch (e) {
              data = { raw: xhr.responseText };
            }
            callback(xhr.status >= 200 && xhr.status < 300, data, xhr);
          }
        };
        xhr.send(body !== undefined && body !== null ? body : "");
      }

      function setFeedback(id, msg, type) {
        var el = document.getElementById(id);
        if (!el) return;
        el.className = "status-feedback " + (type || "");
        el.textContent = msg || "";
      }

      function pollStatus() {
        if (document.hidden || uploading) return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "/status?_=" + new Date().getTime(), true);
        xhr.onreadystatechange = function () {
          if (xhr.readyState === 4 && xhr.status === 200) {
            try {
              var d = JSON.parse(xhr.responseText);
              if (d.mem) document.getElementById("mem-val").textContent = d.mem;
              if (d.uptime) document.getElementById("uptime-val").textContent = d.uptime;
              if (d.hardware) document.getElementById("hw-val").textContent = d.hardware;
              if (d.kernel) document.getElementById("kernel-val").textContent = d.kernel;
              var gv = d.gui_version || d.guiver || d.gui_ver;
              if (gv) {
                document.getElementById("guiver-val").textContent = gv;
                var fgv = document.getElementById("footer-guiver");
                if (fgv) fgv.textContent = gv;
              }

              var nginxOk = !!d.nginx;
              var nLed = document.getElementById("nginx-led");
              if (nLed) nLed.className = "led " + (nginxOk ? "green" : "red");
              var nTxt = document.getElementById("nginx-txt");
              if (nTxt) {
                nTxt.setAttribute("data-state", nginxOk ? "active" : "inactive");
                nTxt.textContent = nginxOk ? t("state_active") : t("state_inactive");
              }

              var transOk = !!d.transformer;
              var tLed = document.getElementById("trans-led");
              if (tLed) tLed.className = "led " + (transOk ? "green" : "red");
              var tTxt = document.getElementById("trans-txt");
              if (tTxt) {
                tTxt.setAttribute("data-state", transOk ? "active" : "inactive");
                tTxt.textContent = transOk ? t("state_active") : t("state_inactive");
              }

              var usbOk = !!d.usb;
              var uLed = document.getElementById("usb-led");
              if (uLed) uLed.className = "led " + (usbOk ? "green" : "");
              var uTxt = document.getElementById("usb-txt");
              if (uTxt) {
                if (usbOk) {
                  var label = (d.usb_name || "") + (d.usb_fs ? " (" + d.usb_fs + ")" : "");
                  uTxt.textContent = t("usb_detected_prefix") + (label ? ": " + label : "");
                } else {
                  uTxt.textContent = t("usb_none");
                }
              }
            } catch (e) {}
          }
        };
        xhr.send();
      }

      function pollLog() {
        if (document.hidden || uploading) return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "/log?pos=" + encodeURIComponent(logPos) + "&_=" + new Date().getTime(), true);
        xhr.onreadystatechange = function () {
          if (xhr.readyState === 4 && xhr.status === 200) {
            var logEl = document.getElementById("log-output");
            var reset = xhr.getResponseHeader("X-Log-Reset");
            if (reset === "1") {
              logEl.textContent = "";
            }
            var posHeader = xhr.getResponseHeader("X-Log-Pos");
            var pos = parseInt(posHeader, 10);
            if (!isNaN(pos)) {
              logPos = pos;
            }
            if (xhr.responseText) {
              logEl.textContent += xhr.responseText;
              logEl.scrollTop = logEl.scrollHeight;
            }
          }
        };
        xhr.send();
      }

      window.execCommand = function () {
        var input = document.getElementById("cmd-input");
        var shellOut = document.getElementById("shell-output");
        var promptEl = document.getElementById("cmd-prompt");
        var btn = document.getElementById("btn-shell-send");
        var cmd = (input.value || "").trim();
        if (!cmd) return;

        if (activeTab !== "shell") {
          window.switchTab("shell");
        }

        shellTouched = true;
        if (cmdHistory.length === 0 || cmdHistory[cmdHistory.length - 1] !== cmd) {
          cmdHistory.push(cmd);
        }
        historyIdx = cmdHistory.length;
        input.value = "";

        shellOut.textContent += (shellOut.textContent ? "\n" : "") + promptEl.textContent + " " + cmd + "\n";
        shellOut.scrollTop = shellOut.scrollHeight;

        var cd = /^cd(?:\s+(.*))?$/.exec(cmd);
        var qCwd = "'" + currentCwd.replace(/'/g, "'\\''") + "'";
        var body = 'cd ' + qCwd + ' 2>/dev/null\n' + (cd ? 'cd ' + (cd[1] || '') + ' && pwd' : cmd);

        if (btn) btn.disabled = true;
        rescuePost("/exec", body, "text/plain; charset=utf-8", function (ok, d, xhr) {
          if (btn) btn.disabled = false;
          input.focus();
          if (d && d.status === "ok") {
            var out = d.output || "";
            if (cd) {
              var m = /^(\/[^\n]*)\n*$/.exec(out);
              if (m) {
                currentCwd = m[1];
                promptEl.textContent = "root@rescue:" + currentCwd + "#";
                shellOut.scrollTop = shellOut.scrollHeight;
                return;
              }
            }
            if (out) {
              shellOut.textContent += out + (out.slice(-1) === "\n" ? "" : "\n");
            }
          } else {
            var err = (d && (d.output || d.error || d.message || d.raw)) || ("HTTP Error " + xhr.status);
            shellOut.textContent += err + (err.slice(-1) === "\n" ? "" : "\n");
          }
          shellOut.scrollTop = shellOut.scrollHeight;
        });
      };

      window.uploadPackage = function () {
        var fileInput = document.getElementById("pkg-file");
        var progWrap = document.getElementById("upload-prog-wrap");
        var progBar = document.getElementById("upload-prog-bar");
        var btn = document.getElementById("btn-upload-flash");

        if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
          setFeedback("upload-feedback", t("msg_select_file"), "err");
          return;
        }

        var file = fileInput.files[0];
        uploading = true;
        btn.disabled = true;
        progWrap.style.display = "block";
        progBar.style.width = "0%";
        progBar.textContent = "0%";
        setFeedback("upload-feedback", t("msg_uploading"), "warn");

        var xhr = new XMLHttpRequest();
        xhr.open("POST", "/upload", true);
        xhr.setRequestHeader("X-Rescue", "1");
        xhr.setRequestHeader("Content-Type", "application/octet-stream");

        if (xhr.upload) {
          xhr.upload.onprogress = function (ev) {
            if (ev.lengthComputable) {
              var pct = Math.round((ev.loaded / ev.total) * 100);
              progBar.style.width = pct + "%";
              progBar.textContent = pct + "%";
            }
          };
        }

        xhr.onreadystatechange = function () {
          if (xhr.readyState === 4) {
            uploading = false;
            btn.disabled = false;
            var res = null;
            try { res = JSON.parse(xhr.responseText); } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300 && (!res || res.status !== "error")) {
              progBar.style.width = "100%";
              progBar.textContent = "100%";
              setFeedback("upload-feedback", (res && (res.message || res.msg)) ? (res.message || res.msg) : t("msg_upload_ok"), "ok");
              pollStatus();
              pollLog();
            } else {
              setFeedback("upload-feedback", (res && (res.message || res.error || res.msg)) ? (res.message || res.error || res.msg) : t("msg_upload_err"), "err");
            }
          }
        };
        xhr.send(file);
      };

      window.usbRecovery = function () {
        var btn = document.getElementById("btn-usb-flash");
        btn.disabled = true;
        setFeedback("usb-feedback", t("msg_usb_starting"), "warn");
        rescuePost("/usb_recovery", "", "application/x-www-form-urlencoded", function (ok, d) {
          btn.disabled = false;
          if (ok && (!d || d.status !== "error")) {
            setFeedback("usb-feedback", (d && (d.message || d.msg)) ? (d.message || d.msg) : t("msg_usb_done"), "ok");
            window.switchTab("log");
          } else {
            setFeedback("usb-feedback", (d && (d.message || d.error || d.msg)) ? (d.message || d.error || d.msg) : "USB Recovery Error", "err");
          }
          pollStatus();
          pollLog();
        });
      };

      window.restartServices = function () {
        var btn = document.getElementById("btn-restart-srv");
        btn.disabled = true;
        setFeedback("srv-feedback", t("msg_restarting_srv"), "warn");
        rescuePost("/restart_services", "", "application/x-www-form-urlencoded", function (ok, d) {
          btn.disabled = false;
          if (ok && (!d || d.status !== "error")) {
            setFeedback("srv-feedback", (d && (d.message || d.msg)) ? (d.message || d.msg) : t("msg_restarted_srv"), "ok");
          } else {
            setFeedback("srv-feedback", (d && (d.message || d.error || d.msg)) ? (d.message || d.error || d.msg) : "Error", "err");
          }
          pollStatus();
          pollLog();
        });
      };

      window.rebootModem = function () {
        if (!window.confirm(t("msg_reboot_confirm"))) return;
        var btn = document.getElementById("btn-reboot");
        btn.disabled = true;
        setFeedback("reboot-feedback", t("msg_rebooting"), "warn");
        rescuePost("/reboot", "", "application/x-www-form-urlencoded", function () {
          setTimeout(function () { btn.disabled = false; }, 10000);
        });
      };

      window.clearConsole = function () {
        if (activeTab === "shell") {
          shellTouched = false;
          document.getElementById("shell-output").textContent = t("shell_banner");
        }
        rescuePost("/clear_log", "", "application/x-www-form-urlencoded", function () {
          logPos = 0;
          document.getElementById("log-output").textContent = t("msg_log_cleared");
        });
      };

      document.addEventListener("DOMContentLoaded", function () {
        var langSelect = document.getElementById("webui_language");
        if (langSelect) {
          langSelect.addEventListener("change", function () {
            applyLanguage(this.value);
          });
        }

        var cmdInput = document.getElementById("cmd-input");
        if (cmdInput) {
          cmdInput.addEventListener("keydown", function (e) {
            if (e.key === "Enter") {
              e.preventDefault();
              window.execCommand();
            } else if (e.key === "ArrowUp") {
              if (cmdHistory.length > 0 && historyIdx > 0) {
                e.preventDefault();
                historyIdx--;
                cmdInput.value = cmdHistory[historyIdx];
              }
            } else if (e.key === "ArrowDown") {
              if (historyIdx < cmdHistory.length - 1) {
                e.preventDefault();
                historyIdx++;
                cmdInput.value = cmdHistory[historyIdx];
              } else {
                historyIdx = cmdHistory.length;
                cmdInput.value = "";
              }
            }
          });
        }

        var maxEl = document.getElementById("upload-max-val");
        if (maxEl) {
          var b = parseInt(maxEl.textContent, 10);
          if (!isNaN(b) && b > 0) {
            maxEl.textContent = Math.round(b / (1024 * 1024)) + " MB";
          }
        }

        applyLanguage(currentLang);
        pollStatus();
        pollLog();
        setInterval(pollStatus, 4000);
        setInterval(pollLog, 1500);
      });
    })();
  </script>

</body>

</html>
]==]

-- Fill the template. Values are escaped HERE (the summary itself stays raw).
local function render_html()
    local s = get_system_summary()
    local usb_label = s.usb.name .. (s.usb.fs ~= "" and (" (" .. s.usb.fs .. ")") or "")
    local vars = {
        PORT        = tostring(ACTIVE_PORT),
        VERSION     = VERSION,
        UPLOAD_MAX  = string.format("%d", UPLOAD_MAX_BYTES),
        LOGFILE     = html_escape(LOG_FILE),
        HARDWARE    = html_escape(s.hardware),
        KERNEL      = html_escape(s.kernel),
        MEM         = html_escape(s.mem),
        UPTIME      = html_escape(s.uptime),
        GUIVER      = s.gui_version and html_escape(s.gui_version)
                      or '<span data-i18n="gui_unknown">Non rilevata / Corrotta</span>',
        NGINX_LED   = s.nginx_running and "green" or "red",
        NGINX_STATE = s.nginx_running and "active" or "inactive",
        NGINX_TXT   = s.nginx_running and "Attivo" or "Non attivo",
        TRANS_LED   = s.trans_running and "green" or "red",
        TRANS_STATE = s.trans_running and "active" or "inactive",
        TRANS_TXT   = s.trans_running and "Attivo" or "Non attivo",
        USB_LED     = s.usb.present and "green" or "",
        USB_TXT     = s.usb.present and html_escape("Chiavetta rilevata: " .. usb_label) or "Nessuna chiavetta rilevata",
    }
    return (PAGE_TEMPLATE:gsub("@@([%w_]+)@@", function(key) return vars[key] end))
end

------------------------------------------------------------------------------
-- HTTP layer
------------------------------------------------------------------------------
local STATUS_TEXT = {
    [100] = "Continue", [200] = "OK", [400] = "Bad Request", [403] = "Forbidden",
    [404] = "Not Found", [405] = "Method Not Allowed", [408] = "Request Timeout",
    [409] = "Conflict", [411] = "Length Required", [413] = "Payload Too Large",
    [414] = "URI Too Long", [431] = "Request Header Fields Too Large",
    [500] = "Internal Server Error",
}

local ALLOWED_METHODS = { GET = true, HEAD = true, POST = true }
local TOKEN_PAT = "^[%w!#%$%%&'%*%+%-%.%^_`|~]+$"

-- Sent with every response: no framing (clickjacking on a root shell), no foreign content.
local SECURITY_HEADERS =
    "X-Content-Type-Options: nosniff\r\n" ..
    "X-Frame-Options: DENY\r\n" ..
    "Referrer-Policy: no-referrer\r\n" ..
    "Content-Security-Policy: default-src 'none'; img-src 'self' data:; font-src 'self'; " ..
    "style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; " ..
    "form-action 'self'; base-uri 'none'; frame-ancestors 'none'\r\n"

-- Send a whole buffer, coping with partial writes and enforcing a total deadline.
local function send_all(client, data, deadline)
    local i, n = 1, #data
    while i <= n do
        if deadline and socket.gettime() > deadline then return nil, "timeout" end
        local sent, err, last = client:send(data, i, n)
        if sent then return true end
        if err == "timeout" and last and last >= i then
            i = last + 1                      -- some progress: keep going
        else
            return nil, err
        end
    end
    return true
end

-- Send an HTTP response. HEAD (opts.head_only) gets the headers incl. Content-Length, no body.
-- The body is sent separately from the headers: no big concatenated copy of the page.
local function send_response(client, status_code, content_type, body, opts)
    opts = opts or {}
    body = body or ""
    local head = table.concat({
        string.format("HTTP/1.1 %d %s\r\n", status_code, STATUS_TEXT[status_code] or "Unknown"),
        "Content-Type: ", content_type, "\r\n",
        "Content-Length: ", tostring(#body), "\r\n",
        "Connection: close\r\n",
        SECURITY_HEADERS,
        opts.cache or "Cache-Control: no-store\r\n",
        opts.extra or "",
        "\r\n",
    })
    local deadline = socket.gettime() + SEND_MAX_SECS
    local ok, err = send_all(client, head, deadline)
    if ok and not opts.head_only and #body > 0 then
        ok, err = send_all(client, body, deadline)
    end
    return ok, err
end

local function send_json(client, status_code, tbl, opts)
    return send_response(client, status_code, "application/json; charset=utf-8", json_encode(tbl), opts)
end

-- {"status": ..., "message": ...} reply used by every action endpoint
local function reply(client, status_code, status, message)
    return send_json(client, status_code, { status = status, message = message })
end

-- Parse the request head (request line + headers, WITHOUT the final blank line).
-- Returns method, uri, headers   or   nil, http_status, message
local function parse_request(head)
    local headers, count = {}, 0
    local method, uri
    local first = true

    for line in (head .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        if #line > MAX_REQ_LINE then
            return nil, first and 414 or 431, "Line too long"
        end

        if first then
            first = false
            local m, u, major = line:match("^(%u+) (%S+) HTTP/(%d)%.%d$")
            if not m or major ~= "1" then return nil, 400, "Bad Request" end
            if #u > MAX_URI then return nil, 414, "URI Too Long" end
            if u:sub(1, 1) ~= "/" or u:find("[%c\127]") then return nil, 400, "Bad Request" end
            if not ALLOWED_METHODS[m] then
                return nil, 405, "Method Not Allowed"
            end
            method, uri = m, u
        else
            local c1 = line:sub(1, 1)
            if c1 == " " or c1 == "\t" then return nil, 400, "Bad Request" end   -- no obs-fold
            count = count + 1
            if count > MAX_HEADER_LINES then return nil, 431, "Too many headers" end

            local k, v = line:match("^([^:]+):[ \t]*(.-)[ \t]*$")
            if not k or not k:match(TOKEN_PAT) then return nil, 400, "Bad Request" end
            if (v:gsub("\t", " ")):find("[%c\127]") then return nil, 400, "Bad Request" end
            k = k:lower()
            if k == "content-length" and headers[k] and headers[k] ~= v then
                return nil, 400, "Bad Request"            -- conflicting lengths
            end
            headers[k] = v
        end
    end

    if not method then return nil, 400, "Bad Request" end
    return method, uri, headers
end

-- Read a SMALL request body (the part already received after the head is `rest`).
-- Returns body   or   nil, http_status
local function read_small_body(client, headers, rest, max)
    local cl = headers["content-length"]
    if not cl then return "" end
    if not cl:match("^%d+$") then return nil, 400 end
    local n = tonumber(cl)
    if n > max then return nil, 413 end
    if n == 0 then return "" end

    local body = rest:sub(1, n)
    local need = n - #body
    if need > 0 then
        client:settimeout(IO_TIMEOUT, "t")
        local chunk = client:receive(need)
        client:settimeout(IO_TIMEOUT, "b")
        if not chunk then return nil, 408 end
        body = body .. chunk
    end
    return body
end

------------------------------------------------------------------------------
-- Access control
------------------------------------------------------------------------------
-- RFC1918, loopback and link-local IPv4 peers only.
local function is_private_ip(ip)
    if not ip then return false end
    local a, b = ip:match("^(%d+)%.(%d+)%.%d+%.%d+$")
    a, b = tonumber(a), tonumber(b)
    if not a then return false end
    return a == 10 or a == 127
        or (a == 192 and b == 168)
        or (a == 169 and b == 254)
        or (a == 172 and b >= 16 and b <= 31)
end

-- DNS-rebinding guard: accept IP literals, localhost, single-label names and the usual
-- local suffixes; anything else (a public domain pointing at the router) is refused.
local function host_allowed(headers)
    if not CHECK_HOST_HEADER then return true end
    local host = headers["host"]
    if not host then return true end                        -- HTTP/1.0 client
    local h = host:lower():gsub(":%d+$", "")
    if h:sub(1, 1) == "[" or h:match("^%d+%.%d+%.%d+%.%d+$") then return true end
    if h == "localhost" or not h:find(".", 1, true) then return true end
    return h:match("%.lan$") ~= nil or h:match("%.local$") ~= nil
        or h:match("%.home%.arpa$") ~= nil or h:match("%.localdomain$") ~= nil
end

-- CSRF guard for state-changing requests
local function same_origin(headers)
    if not ENFORCE_SAME_ORIGIN then return true end
    local origin = headers["origin"]
    if not origin then return true end
    local o_host = origin:match("^%a[%w+.-]*://([^/]+)$")
    local host = headers["host"]
    return (o_host ~= nil and host ~= nil and o_host:lower() == host:lower())
end

local function close_client(client)
    pcall(client.shutdown, client, "send")   -- FIN now, even if a child still holds the fd
    pcall(client.close, client)
end

------------------------------------------------------------------------------
-- /exec : run a shell command with a hard timeout
------------------------------------------------------------------------------
-- The command goes into a temp script, stdout+stderr go into a temp FILE (not a pipe):
-- if the command leaves background grandchildren behind they cannot keep a pipe open and
-- stall the server. `timeout -s KILL` ends the script itself after EXEC_TIMEOUT seconds.
local function run_shell(cmd)
    local script = os.tmpname()
    if not script or script == "" then script = "/tmp/rescue_exec." .. tostring(os.time()) end
    local outf = script .. ".out"
    local output, timed_out = "", false

    local ok, perr = pcall(function()
        local written = with_file(script, "wb", function(f)
            f:write("#!/bin/sh\n",
                    "exec ", FD_CLOSE, "\n",
                    "ulimit -f ", tostring(EXEC_ULIMIT_BLOCKS), " 2>/dev/null\n",
                    cmd, "\n")
            return true
        end)
        if not written then error("impossibile scrivere lo script temporaneo") end

        local inner = string.format("/bin/sh %s >%s 2>&1 </dev/null", shq(script), shq(outf))
        local t0 = socket.gettime()
        local status = os.execute(wrap_timeout(EXEC_TIMEOUT, inner))
        timed_out = (not sh_ok(status)) and (socket.gettime() - t0) >= (EXEC_TIMEOUT - 0.5)

        output = with_file(outf, "rb", function(f) return f:read(EXEC_OUT_MAX + 1) end) or ""
    end)

    pcall(os.remove, script)      -- always cleaned up, whatever happened above
    pcall(os.remove, outf)

    if not ok then output = "[ERRORE] " .. tostring(perr) .. "\n" end
    if #output > EXEC_OUT_MAX then
        output = output:sub(1, EXEC_OUT_MAX) .. "\n[... output troncato ...]\n"
    end
    if timed_out then
        output = output .. string.format("\n[TIMEOUT] Comando terminato dopo %d s\n", EXEC_TIMEOUT)
    end
    if output == "" then
        output = "(Comando completato senza output)\n"
    end
    return output
end

------------------------------------------------------------------------------
-- Background jobs (verify + extract, USB flash, service restart)
------------------------------------------------------------------------------
-- Every job is a small shell script: it logs its progress to the rescue log and ALWAYS
-- removes the busy lock (and itself) on exit, so the web UI can follow what is happening.
local JOB_HELPERS = [==[
say() { printf '[%s] [RESCUE-SERVER] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }
trap 'rm -f "$LOCK" "$0"' EXIT
]==]

-- Writes the job script and returns the function that starts it (to be run AFTER the
-- HTTP connection is closed), or nil + error.
local function prepare_job(body)
    local script = "#!/bin/sh\nLOG=" .. shq(LOG_FILE) .. "\nLOCK=" .. shq(BUSY_LOCK) .. "\n"
        .. JOB_HELPERS .. body .. "\n"
    local written = with_file(JOB_SCRIPT, "wb", function(f) f:write(script) return true end)
    if not written then return nil, "impossibile preparare il job in background" end
    set_busy()
    return function() spawn_detached("/bin/sh " .. shq(JOB_SCRIPT)) end
end

local function package_job()
    local limit = TIMEOUT_BIN and (TIMEOUT_BIN .. " -s KILL " .. VERIFY_TIMEOUT .. " ") or ""
    return table.concat({
        "PKG=", shq(RECOVERY_TARGET), "\n",
        "say \"Validazione integrita archivio (bzcat + tar)...\"\n",
        "if ! command -v bzcat >/dev/null 2>&1; then\n",
        "  say \"ERRORE: bzcat non disponibile su questo sistema.\"; rm -f \"$PKG\"; exit 1\n",
        "fi\n",
        "if ! ", limit, "sh -c 'bzcat \"$1\" | tar -tf - >/dev/null 2>&1' sh \"$PKG\"; then\n",
        "  say \"ERRORE: il file caricato non e un archivio .tar.bz2 integro.\"; rm -f \"$PKG\"; exit 1\n",
        "fi\n",
        "say \"Archivio convalidato. Inizio estrazione su filesystem principale (/).\"\n",
        "if bzcat \"$PKG\" | tar -C / -xf - >> \"$LOG\" 2>&1; then\n",
        "  say \"Estrazione completata. Applicazione modifiche (rootdevice force)...\"\n",
        "  /etc/init.d/rootdevice force >> \"$LOG\" 2>&1\n",
        "  say \"Ripristino terminato.\"\n",
        "else\n",
        "  say \"ERRORE: estrazione del pacchetto fallita.\"\n",
        "fi\n",
        "rm -f \"$PKG\"\n",
    })
end

local USB_JOB = table.concat({
    "say \"Avvio script di ripristino USB...\"\n",
    shq(USB_SCRIPT), " >/dev/null 2>&1\n",
    "say \"Script di ripristino USB terminato (codice $?).\"\n",
})

local SERVICES_JOB = table.concat({
    "say \"Riavvio di Transformer...\"\n",
    "/etc/init.d/transformer restart >/dev/null 2>&1\n",
    "say \"Riavvio di Nginx...\"\n",
    "/etc/init.d/nginx restart >/dev/null 2>&1\n",
    "say \"Servizi web riavviati.\"\n",
})

------------------------------------------------------------------------------
-- /upload : stream a .tar.bz2 straight to disk
------------------------------------------------------------------------------
-- Copies `total` body bytes (first `rest`, already buffered, then the socket) into out_f.
-- Returns true   or   nil, reason
local function stream_to_file(client, out_f, total, rest)
    local remaining = total
    local deadline = socket.gettime() + UPLOAD_MAX_SECS

    if rest and #rest > 0 then
        if #rest > remaining then rest = rest:sub(1, remaining) end
        local ok, werr = out_f:write(rest)
        if not ok then return nil, "scrittura su disco fallita: " .. tostring(werr) end
        remaining = remaining - #rest
    end

    -- "t" = total time per receive() call: a stalled client is cut after IO_TIMEOUT seconds
    -- without ANY byte, while a slow-but-alive one keeps making progress.
    client:settimeout(IO_TIMEOUT, "t")
    while remaining > 0 do
        if socket.gettime() > deadline then return nil, "tempo massimo di upload superato" end
        local want = remaining < UPLOAD_CHUNK and remaining or UPLOAD_CHUNK
        local chunk, err, partial = client:receive(want)
        local data
        if chunk then
            data = chunk
        elseif err == "timeout" and partial and #partial > 0 then
            data = partial                    -- progress was made, keep going
        else
            return nil, (err == "timeout") and "client inattivo (timeout)" or "connessione interrotta dal client"
        end
        local ok, werr = out_f:write(data)
        if not ok then return nil, "scrittura su disco fallita: " .. tostring(werr) end
        remaining = remaining - #data
    end
    return true
end

local function handle_upload(client, headers, rest)
    if is_busy() then
        return reply(client, 409, "error", "Un ripristino e' gia' in corso")
    end
    if headers["transfer-encoding"] then
        return reply(client, 411, "error", "Transfer-Encoding non supportato: serve Content-Length")
    end
    local cl = headers["content-length"]
    if not cl or not cl:match("^%d+$") or tonumber(cl) <= 0 then
        return reply(client, 400, "error", "Dimensione file non valida")
    end
    local content_length = tonumber(cl)
    if content_length > UPLOAD_MAX_BYTES then
        log(string.format("Upload rifiutato: %d bytes oltre il limite di %d", content_length, UPLOAD_MAX_BYTES))
        return reply(client, 413, "error", "File troppo grande")
    end

    if (headers["expect"] or ""):lower() == "100-continue" then
        send_all(client, "HTTP/1.1 100 Continue\r\n\r\n", socket.gettime() + IO_TIMEOUT)
    end

    log(string.format("Ricezione upload pacchetto di emergenza: %d bytes...", content_length))

    pcall(os.remove, UPLOAD_TEMP)             -- stale leftovers from a previous crash
    collectgarbage("collect")                 -- start streaming with a clean heap
    local out_f, err = io.open(UPLOAD_TEMP, "wb")
    if not out_f then
        log("Errore apertura file temporaneo: " .. tostring(err))
        return reply(client, 500, "error", "Errore apertura storage temporaneo")
    end
    pcall(out_f.setvbuf, out_f, "full", UPLOAD_BUFFER)

    -- Receive; pcall guarantees we get control back for cleanup even on an internal error.
    local pok, rok, rerr = pcall(stream_to_file, client, out_f, content_length, rest)
    local cok, cres = pcall(out_f.close, out_f)          -- close ALWAYS, check flush errors
    client:settimeout(IO_TIMEOUT, "b")
    collectgarbage("collect")

    if not pok then
        pcall(os.remove, UPLOAD_TEMP)
        log("Errore interno durante l'upload: " .. tostring(rok))
        return reply(client, 500, "error", "Errore interno durante l'upload")
    end
    if not rok then
        pcall(os.remove, UPLOAD_TEMP)
        log("Errore lettura upload: " .. tostring(rerr))
        return reply(client, 400, "error", "Trasferimento interrotto")
    end
    if not (cok and cres) then
        pcall(os.remove, UPLOAD_TEMP)
        log("Errore chiusura/flush file temporaneo (spazio esaurito?)")
        return reply(client, 500, "error", "Scrittura su storage temporaneo fallita (spazio insufficiente?)")
    end

    -- Rename to permanent target; verification + extraction continue in the background job.
    pcall(os.remove, RECOVERY_TARGET)
    local mv_ok, mv_err = os.rename(UPLOAD_TEMP, RECOVERY_TARGET)
    if not mv_ok then
        pcall(os.remove, UPLOAD_TEMP)
        log("Errore rename archivio: " .. tostring(mv_err))
        return reply(client, 500, "error", "Impossibile salvare l'archivio")
    end

    local after, jerr = prepare_job(package_job())
    if not after then
        pcall(os.remove, RECOVERY_TARGET)
        log("Errore avvio job: " .. tostring(jerr))
        return reply(client, 500, "error", jerr)
    end
    log("Upload completato con successo. Verifica ed estrazione avviate in background.")
    reply(client, 200, "ok", "Pacchetto ricevuto. Verifica ed estrazione avviate: segui il log.")
    return after
end

------------------------------------------------------------------------------
-- Routing
------------------------------------------------------------------------------
local FONT_MIME = { woff2 = "font/woff2", woff = "font/woff", ttf = "font/ttf", otf = "font/otf" }
local STATIC_CACHE = "Cache-Control: public, max-age=86400\r\n"

-- First non-empty file found for `name` inside `dirs` ("" when none).
local function find_in_dirs(dirs, name)
    for _, dir in ipairs(dirs) do
        local data = read_file(dir .. "/" .. name)
        if #data > 0 then return data end
    end
    return ""
end

-- Each POST handler returns nil or a function to run after the client has been closed.
local POST_ROUTES = {}

POST_ROUTES["/clear_log"] = function(client)
    with_file(LOG_FILE, "w", function() return true end)
    log("Log della rescue console azzerato dall'operatore.")
    reply(client, 200, "ok", "Log azzerato")
end

POST_ROUTES["/exec"] = function(client, headers, rest)
    if not ENABLE_SHELL then
        return send_json(client, 403, { status = "error", output = "Shell disabilitata in configurazione" })
    end
    local body, bad = read_small_body(client, headers, rest, EXEC_BODY_MAX)
    if not body then
        return send_json(client, bad, { status = "error", output = "Comando non valido (mancante o troppo lungo)" })
    end
    -- drop control characters except newline / tab
    local cmd = body:gsub("%c", function(c) return (c == "\n" or c == "\t") and c or "" end)
    cmd = cmd:match("^%s*(.-)%s*$")
    if not cmd or cmd == "" then
        return send_json(client, 400, { status = "error", output = "Comando vuoto" })
    end

    log(string.format("[SHELL] # %s", (cmd:gsub("\n", " \\n "))))

    -- Auto-add count limit to ping if not specified, preventing endless blocking
    if cmd:match("^ping%s+") and not cmd:match("%-c%s*%d+") then
        cmd = (cmd:gsub("^ping%s+", "ping -c 4 ", 1))
    end

    send_json(client, 200, { status = "ok", output = run_shell(cmd) })
end

POST_ROUTES["/usb_recovery"] = function(client)
    if is_busy() then return reply(client, 409, "error", "Un ripristino e' gia' in corso") end
    if not file_exists(USB_SCRIPT) then
        log("ERRORE: " .. USB_SCRIPT .. " non trovato.")
        return reply(client, 500, "error", "Script di ripristino USB non trovato")
    end
    local after, err = prepare_job(USB_JOB)
    if not after then return reply(client, 500, "error", err) end
    log("Avvio del motore di ripristino Zero-Touch USB...")
    reply(client, 200, "started", "Scansione periferiche USB avviata.")
    return after
end

POST_ROUTES["/upload"] = handle_upload

POST_ROUTES["/restart_services"] = function(client)
    if is_busy() then return reply(client, 409, "error", "Un'operazione e' gia' in corso") end
    local after, err = prepare_job(SERVICES_JOB)
    if not after then return reply(client, 500, "error", err) end
    log("Richiesta riavvio servizi web ricevuta.")
    reply(client, 200, "ok", "Riavvio dei servizi web avviato.")
    return after
end

POST_ROUTES["/reboot"] = function(client)
    log("Richiesta riavvio router ricevuta. Riavvio tra 1 secondo.")
    reply(client, 200, "ok", "Riavvio del router in corso...")
    return function() spawn_detached("sleep 1 && /sbin/reboot") end
end

-- GET endpoints. Return true when the path was handled.
local function handle_get(client, path, query, head_only)
    local ropts = { head_only = head_only }
    local sopts = { head_only = head_only, cache = STATIC_CACHE }

    if path == "/" or path == "/index.html" then
        send_response(client, 200, "text/html; charset=utf-8", render_html(), ropts)

    elseif path == "/log" then
        local chunk = read_log_chunk(tonumber(query:match("pos=(%-?%d+)")))
        ropts.extra = string.format("X-Log-Pos: %d\r\nX-Log-Reset: %d\r\n", chunk.size, chunk.reset and 1 or 0)
        send_response(client, 200, "text/plain; charset=utf-8", chunk.data, ropts)

    elseif path == "/status" then
        local s = get_system_summary()
        send_json(client, 200, {
            hardware = s.hardware, kernel = s.kernel, gui_version = s.gui_version or "",
            mem = s.mem, uptime = s.uptime,
            nginx = s.nginx_running, transformer = s.trans_running,
            usb = s.usb.present, usb_name = s.usb.name, usb_fs = s.usb.fs,
            busy = s.busy,
        }, ropts)

    elseif path:match("^/fonts/") then
        local name, ext = path:match("^/fonts/([%w%._%-]+%.(%w+))$")
        local mime = ext and FONT_MIME[ext:lower()]
        local data = (mime and not name:find("..", 1, true)) and find_in_dirs(FONT_DIRS, name) or ""
        if #data > 0 then
            send_response(client, 200, mime, data, sopts)
        else
            send_response(client, 404, "text/plain; charset=utf-8", "Font Not Found", ropts)
        end

    elseif path == "/favicon.ico" or path == "/img/favicon.ico" then
        local data = ""
        for _, file in ipairs(FAVICON_FILES) do
            data = read_file(file)
            if #data > 0 then break end
        end
        if #data > 0 then
            send_response(client, 200, "image/x-icon", data, sopts)
        else
            send_response(client, 404, "text/plain; charset=utf-8", "Favicon Not Found", ropts)
        end

    elseif path == "/img/logo.png" or path == "/logo.png" then
        local data = ""
        for _, file in ipairs(LOGO_FILES) do
            data = read_file(file)
            if #data > 0 then break end
        end
        if #data > 0 then
            send_response(client, 200, "image/png", data, sopts)
        else
            send_response(client, 404, "text/plain; charset=utf-8", "Logo Not Found", ropts)
        end

    else
        send_response(client, 404, "text/plain; charset=utf-8", "Not Found", ropts)
    end
end

-- Handle one complete request. Returns an optional "after close" function.
local function handle_request(client, head, rest)
    local method, uri, headers = parse_request(head)
    if not method then
        local code, msg = uri, headers            -- parse_request(nil, status, message)
        return send_response(client, code, "text/plain; charset=utf-8", msg,
            { extra = (code == 405) and "Allow: GET, HEAD, POST\r\n" or nil })
    end

    if not host_allowed(headers) then
        log("Richiesta rifiutata (Host non ammesso): " .. tostring(headers["host"]))
        send_response(client, 403, "text/plain; charset=utf-8", "Forbidden")
        return nil
    end

    local path = uri:match("^([^?#]*)")
    local query = uri:match("%?([^#]*)") or ""

    if method == "GET" or method == "HEAD" then
        handle_get(client, path, query, method == "HEAD")
        return nil
    end

    -- POST
    if not same_origin(headers) then
        log("POST rifiutato (Origin non coincidente con Host): " .. tostring(headers["origin"]))
        send_response(client, 403, "text/plain; charset=utf-8", "Forbidden")
        return nil
    end
    if REQUIRE_RESCUE_HEADER and headers["x-rescue"] ~= "1" then
        log("POST rifiutato (header X-Rescue mancante) su " .. path)
        send_response(client, 403, "text/plain; charset=utf-8", "Forbidden (missing X-Rescue header)")
        return nil
    end
    local route = POST_ROUTES[path]
    if not route then
        send_response(client, 404, "text/plain; charset=utf-8", "Not Found")
        return nil
    end
    return route(client, headers, rest)
end

------------------------------------------------------------------------------
-- Connection management / main loop
------------------------------------------------------------------------------
local pending = {}        -- connections still sending their request head (non-blocking)
local last_denied_log = 0

local function remove_pending(conn)
    for i = #pending, 1, -1 do
        if pending[i] == conn then table.remove(pending, i) return end
    end
end

-- Best-effort short reply (2 s cap) then close
local function reject(sock, code, msg)
    pcall(function()
        sock:settimeout(2)
        send_response(sock, code, "text/plain; charset=utf-8", msg)
    end)
    close_client(sock)
end

-- Run a complete request: blocking I/O with timeouts, always closes the socket.
local function dispatch(client, head, rest)
    client:settimeout(IO_TIMEOUT, "b")
    local ok, after = pcall(handle_request, client, head, rest)
    if not ok then
        log("Errore gestione client: " .. tostring(after))
        pcall(send_response, client, 500, "text/plain; charset=utf-8", "Internal Server Error")
        after = nil
    end
    close_client(client)                      -- connection is finished BEFORE any detached job starts
    if type(after) == "function" then
        local aok, aerr = pcall(after)
        if not aok then log("Errore avvio job in background: " .. tostring(aerr)) end
    end
end

local function accept_clients(server)
    for _ = 1, 8 do
        local c = server:accept()             -- listener is non-blocking
        if not c then return end
        c:settimeout(0)
        pcall(c.setoption, c, "tcp-nodelay", true)

        local ip = c:getpeername() or "?"
        local same = 0
        for _, p in ipairs(pending) do if p.ip == ip then same = same + 1 end end

        if RESTRICT_TO_LAN and not is_private_ip(ip) then
            local now = socket.gettime()
            if now - last_denied_log > 30 then      -- do not let scanners flood the log
                last_denied_log = now
                log("Connessione rifiutata da indirizzo non locale: " .. tostring(ip))
            end
            close_client(c)
        elseif same >= MAX_PENDING_PER_IP then
            close_client(c)                   -- one host may not hog the slots
        else
            if #pending >= MAX_PENDING then   -- full: evict the oldest (most likely stalled)
                local old = table.remove(pending, 1)
                close_client(old.sock)
            end
            pending[#pending + 1] = { sock = c, buf = "", ip = ip, deadline = socket.gettime() + HEADER_DEADLINE }
        end
    end
end

-- Non-blocking read of the request head for one connection.
local function pump(conn)
    local chunk, err, partial = conn.sock:receive(2048)
    local data = chunk or partial
    if data and #data > 0 then conn.buf = conn.buf .. data end

    local buf = conn.buf
    local s, e = buf:find("\r\n\r\n", 1, true)
    local s2, e2 = buf:find("\n\n", 1, true)
    if s2 and (not s or s2 < s) then s, e = s2, e2 end
    if s then return "complete", buf:sub(1, s - 1), buf:sub(e + 1) end

    if #buf > MAX_HEADER_BYTES then return "toolarge" end
    if err and err ~= "timeout" then return "closed" end
    return "more"
end

local function open_listener(port)
    local srv, err = socket.tcp()
    if not srv then return nil, err end
    -- Restart immediately even with sockets in TIME_WAIT
    pcall(srv.setoption, srv, "reuseaddr", true)
    local ok, berr = srv:bind("0.0.0.0", port)
    if not ok then srv:close() return nil, berr end
    local lok, lerr = srv:listen(LISTEN_BACKLOG)
    if not lok then srv:close() return nil, lerr end
    srv:settimeout(0)
    return srv
end

local function loop_once(server)
    local readset = { server }
    for i = 1, #pending do readset[#readset + 1] = pending[i].sock end

    local ready, _, serr = socket.select(readset, nil, SELECT_TICK)
    if not ready then
        log("select() fallita: " .. tostring(serr))
        socket.sleep(0.2)
        ready = {}
    end

    for _, s in ipairs(ready) do
        if s == server then
            accept_clients(server)
        else
            local conn
            for i = 1, #pending do if pending[i].sock == s then conn = pending[i] break end end
            if conn then
                local state, head, rest = pump(conn)
                if state == "complete" then
                    remove_pending(conn)
                    dispatch(conn.sock, head, rest)
                elseif state == "toolarge" then
                    remove_pending(conn)
                    reject(conn.sock, 431, "Request Header Fields Too Large")
                elseif state == "closed" then
                    remove_pending(conn)
                    close_client(conn.sock)
                end
            end
        end
    end

    -- Deadline sweep: drop clients that did not finish their headers in time (slowloris)
    local now = socket.gettime()
    for i = #pending, 1, -1 do
        local conn = pending[i]
        if now > conn.deadline then
            table.remove(pending, i)
            reject(conn.sock, 408, "Request Timeout")
        end
    end
end

-- Server entry point
local function main()
    local port = tonumber(arg and arg[1]) or DEFAULT_PORT

    log("Inizializzazione Standalone Rescue Server v" .. VERSION .. "...")
    pcall(os.remove, UPLOAD_TEMP)             -- leftovers of a previous crashed run
    pcall(os.remove, BUSY_LOCK)

    local server, err = open_listener(port)
    if not server then
        local alt = (port == ALT_PORT) and DEFAULT_PORT or ALT_PORT
        log(string.format("Impossibile associare alla porta %d: %s. Tentativo su porta alternativa %d...", port, tostring(err), alt))
        server, err = open_listener(alt)
        if not server then
            log("FATALE: Impossibile avviare il rescue server: " .. tostring(err))
            os.exit(1)
        end
        port = alt
    end
    ACTIVE_PORT = port

    local lfd = tonumber(server:getfd())
    if lfd and lfd > 9 then
        log(string.format("ATTENZIONE: listening socket su fd %d (>9): i processi figli non possono chiuderlo via shell.", lfd))
    end
    if not TIMEOUT_BIN then
        log("Nota: 'timeout' non trovato, uso il watchdog di shell integrato.")
    end
    if not RESTRICT_TO_LAN then
        log("ATTENZIONE: RESTRICT_TO_LAN disattivato - la console (shell root inclusa) accetta connessioni da ovunque.")
    end

    log(string.format("Rescue Server attivo e in ascolto su http://0.0.0.0:%d", port))

    while true do
        local ok, lerr = pcall(loop_once, server)
        if not ok then
            log("Errore nel ciclo principale: " .. tostring(lerr))
            socket.sleep(0.2)                 -- never spin on a persistent error
        end
    end
end

main()
