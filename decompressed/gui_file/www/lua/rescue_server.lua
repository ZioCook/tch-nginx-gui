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
    local model = slurp("/proc/device-tree/model"):match("^([%g ]+)")      -- stops at the NUL
    if model and #model > 2 then return model end
    local cpu = slurp("/proc/cpuinfo")
    return cpu:match("Hardware%s*:%s*([^\r\n]+)")
        or cpu:match("model name%s*:%s*([^\r\n]+)")
        or cpu:match("system type%s*:%s*([^\r\n]+)")
        or "Technicolor Gateway"
end

-- Installed GUI version: /etc/init.d/rootdevice first, /etc/config/modgui as fallback.
local function detect_gui_version()
    local ver = with_file("/etc/init.d/rootdevice", "r", function(f)
        for l in f:lines() do
            local v = l:match("version_gui=([^%s]+)")
            if v then return v end
        end
    end)
    if ver then return ver end
    local mg = slurp("/etc/config/modgui")
    return mg:match("option%s+version%s+['\"]([^%s'\"]+)") or mg:match("option%s+version%s+([%w%._%-]+)")
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

    local kernel = slurp("/proc/version"):match("Linux%s+version%s+([%w%._%-]+)")
    local s = {
        hardware    = detect_hardware(),
        kernel      = kernel or "N/A",
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
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rescue Console &mdash; Technicolor Gateway</title>
  <link rel="icon" type="image/x-icon" href="/favicon.ico">
  <style>
    @font-face {
      font-family: "Font Awesome 5 Free";
      font-style: normal;
      font-weight: 900;
      src: url("/fonts/fa-solid-900.woff2") format("woff2"),
           url("/fonts/fa-solid-900.woff") format("woff");
    }
    @font-face {
      font-family: "Font Awesome 5 Brands";
      font-style: normal;
      font-weight: 400;
      src: url("/fonts/fa-brands-400.woff2") format("woff2"),
           url("/fonts/fa-brands-400.woff") format("woff");
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      color: #333;
      background-color: #eee;
      font: 14px/20px Helvetica,Arial,sans-serif;
      min-height: 100vh;
      -webkit-font-smoothing: antialiased;
      overflow-x: hidden;
    }
    
    /* Font Awesome Classes */
    .fa { font-family: "Font Awesome 5 Free", sans-serif; font-weight: 900; font-style: normal; display: inline-block; }
    .fb { font-family: "Font Awesome 5 Brands", sans-serif; font-weight: 400; font-style: normal; display: inline-block; }
    .fa-microchip:before { content: "\f2db"; }
    .fa-code-branch:before { content: "\f126"; }
    .fa-memory:before { content: "\f538"; }
    .fa-clock:before { content: "\f017"; }
    .fa-shield-alt:before { content: "\f3ed"; }
    .fa-exclamation-triangle:before { content: "\f071"; }
    .fa-server:before { content: "\f233"; }
    .fa-wrench:before { content: "\f0ad"; }
    .fa-sync-alt:before { content: "\f021"; }
    .fa-power-off:before { content: "\f011"; }
    .fa-network-wired:before { content: "\f6ff"; }
    .fa-file-alt:before { content: "\f15c"; }
    .fa-terminal:before { content: "\f120"; }
    .fa-upload:before { content: "\f093"; }
    .fa-play:before { content: "\f04b"; }
    .fa-eraser:before { content: "\f12d"; }
    .fa-spinner:before { content: "\f110"; }
    .fa-cogs:before { content: "\f085"; }
    .fa-spin { animation: fa-spin 1s infinite linear; }
    @keyframes fa-spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }

    /* Technicolor Green Theme Gateway Background Globe Watermark */
    .gateway_bg {
      position: fixed;
      left: 0;
      top: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
      z-index: 1;
      overflow: hidden;
    }
    .gateway_bg:after {
      font-family: "Font Awesome 5 Free";
      font-weight: 900;
      color: rgba(151, 187, 151, 0.30);
      content: "\f0ac";
      display: block;
      position: fixed;
      left: -380px;
      top: 90px;
      font-size: 1000px;
      z-index: -1;
      line-height: 1;
    }

    /* Main Container */
    .container {
      max-width: 1240px;
      margin: 0 auto;
      padding: 0 20px 40px;
      position: relative;
      z-index: 2;
    }

    /* Header */
    .header {
      padding: 26px 0 18px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .header-logo img {
      width: 131px;
      height: 50px;
      display: block;
      border: 0;
    }
    .header-lang {
      display: flex;
      align-items: center;
      position: relative;
      z-index: 10;
    }
    #webui_language {
      height: 36px;
      padding: 6px 14px;
      font-size: 13px;
      font-weight: bold;
      font-family: Helvetica, Arial, sans-serif;
      color: #333;
      background-color: #ffffff;
      background-image: linear-gradient(to bottom, #fff, #f5f5f5);
      border: 1px solid #c6bec9;
      border-radius: 4px;
      box-shadow: inset 0 1px 1px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.05);
      cursor: pointer;
      outline: none;
      transition: all .15s ease-in-out;
    }
    #webui_language:hover {
      border-color: rgb(30, 116, 30);
      box-shadow: 0 0 6px rgba(92, 247, 65, 0.45);
    }
    #webui_language:focus {
      border-color: rgb(30, 116, 30);
      box-shadow: 0 0 8px rgba(92, 247, 65, 0.6);
    }

    /* Warning Alert Banner */
    .alert {
      padding: 10px 20px;
      margin-bottom: 24px;
      text-shadow: 0 1px 0 rgba(255,255,255,0.5);
      background-color: #fcf8e3;
      border: 1px solid #fbeed5;
      border-radius: 4px;
      color: #c09853;
      font-size: 14px;
      line-height: 20px;
      text-align: center;
      box-shadow: 0 1px 2px rgba(0,0,0,0.05);
    }

    /* Balanced 4-Column Grid Layout */
    .cards-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 20px;
    }

    /* Card Styling - Pixel Perfect Replica of Technicolor .smallcard */
    .sc {
      position: relative;
      display: flex;
      flex-direction: column;
      background: #fff;
      overflow: hidden;
      font-family: Helvetica,Arial,sans-serif;
      font-size: 14px;
      border-radius: 0;
      border: none;
      -webkit-box-shadow: 0 2px 20px 0px rgba(56, 132, 56, 0.65);
      -moz-box-shadow: 0 2px 20px 0px rgba(56, 132, 56, 0.65);
      box-shadow: 0 2px 20px 0px rgba(56, 132, 56, 0.65);
      height: 100%;
      z-index: 2;
    }

    /* Card Header - Thick, Bold Technicolor Green Gradient (Identical to Original GUI) */
    .sh {
      min-height: 44px;
      height: 44px;
      padding: 10px 14px;
      font-size: 18px;
      line-height: 22px;
      font-weight: bold;
      color: #fff;
      text-shadow: 0 1px 1px #000;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      background-color: rgb(30, 116, 30);
      background-image: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);
      border: 1px solid rgb(30, 116, 30);
      border-bottom: 1px solid rgb(25, 95, 25);
      box-shadow: inset 0 1px 1px rgba(255,255,255,.2);
      display: flex;
      align-items: center;
      justify-content: space-between;
      box-sizing: border-box;
    }

    /* Card Body */
    .ct {
      position: relative;
      z-index: 1;
      flex: 1;
      box-sizing: border-box;
      min-height: 180px;
      padding: 14px 15px;
      font-weight: 500;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }

    /* Discreet Watermarks (Non-overlapping, Solid Glyph without cutouts) */
    .bgi {
      position: absolute;
      right: 8px;
      bottom: 30px;
      z-index: 0;
      font-size: 110px;
      line-height: 1;
      color: rgba(151, 187, 151, 0.18);
      pointer-events: none;
      user-select: none;
    }

    .li {
      position: relative;
      z-index: 1;
      line-height: 22px;
      margin-bottom: 5px;
      color: #333;
    }
    .li i {
      display: inline-block;
      width: 20px;
      color: #555;
      font-size: 13px;
      text-align: center;
    }
    .sub {
      position: relative;
      z-index: 1;
      margin-bottom: 12px;
      font-size: 13px;
      line-height: 18px;
      font-weight: 300;
      color: #666;
    }

    /* Status LEDs */
    .light {
      width: 8px;
      height: 8px;
      display: inline-block;
      border-radius: 10px;
      margin-right: 8px;
      vertical-align: 1px;
    }
    .light.red {
      background-color: #cd3535;
      border: 1px solid #912424;
      box-shadow: inset 0 1px 3px rgba(255,255,255,.5), 0 0 4px rgba(255,0,0,1);
    }
    .light.green {
      background-color: #69c469;
      border: 1px solid #3fa13f;
      box-shadow: inset 0 1px 3px rgba(255,255,255,.5), 0 0 4px rgba(0,220,0,1);
    }

    /* Buttons */
    .btn-action {
      position: relative;
      z-index: 2;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      width: 100%;
      padding: 8px 14px;
      font-size: 14px;
      line-height: 20px;
      font-weight: bold;
      font-family: inherit;
      text-align: center;
      vertical-align: middle;
      border-radius: 4px;
      cursor: pointer;
      box-sizing: border-box;
      transition: all .15s ease-in-out;
    }
    .btn-default {
      color: rgb(30, 116, 30);
      background-color: #f5f5f5;
      background-image: linear-gradient(to bottom, #fff, #e6e6e6);
      border: 1px solid #c6bec9;
      border-bottom-color: #aea2b2;
      box-shadow: inset 0 -1px 0 rgba(255,255,255,1), 0 1px 2px rgba(0,0,0,.1);
    }
    .btn-default:hover {
      color: #ffffff;
      background-color: rgb(30, 116, 30);
      background-image: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);
      border-color: rgb(30, 116, 30);
      box-shadow: inset 0 1px 0 rgba(255,255,255,.5), 0 0 6px rgb(92, 247, 65);
      text-shadow: 0 1px 0 #000;
    }
    .btn-primary {
      color: #ffffff;
      text-shadow: 0 1px 0 #000;
      background-color: rgb(30, 116, 30);
      background-image: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);
      border: 1px solid rgb(30, 116, 30);
      border-radius: 3px;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.3), 0 2px 4px rgba(0,0,0,.5);
    }
    .btn-primary:hover {
      background-image: linear-gradient(to bottom, rgb(45, 145, 45) 20%, rgb(25, 40, 25) 100%);
      border-color: rgb(45, 145, 45);
      box-shadow: inset 0 1px 0 rgba(255,255,255,.4), 0 0 8px rgba(92, 247, 65, 0.75);
    }
    .btn-danger {
      color: #fff;
      text-shadow: 0 -1px 0 rgba(0,0,0,0.25);
      background-color: #da4f49;
      background-image: linear-gradient(to bottom, #ee5f5b, #bd362f);
      border: 1px solid #bd362f;
      border-radius: 4px;
      box-shadow: inset 0 1px 0 rgba(255,255,255,.2), 0 1px 2px rgba(0,0,0,.05);
    }
    .btn-danger:hover {
      background-color: #bd362f;
      background-image: linear-gradient(to bottom, #bd362f, #a9302a);
      border-color: #802420;
    }
    .btn-action:disabled {
      opacity: .55;
      cursor: not-allowed;
      background: #e6e6e6 !important;
      color: #888 !important;
      border-color: #ccc !important;
      box-shadow: none !important;
      text-shadow: none !important;
    }

    /* Card 6: Log Operativo & Root Shell (Spans 3 Columns on Row 2) */
    .logt {
      grid-column: span 3;
    }
    .btn-clear {
      padding: 3px 10px;
      font-size: 11px;
      line-height: 16px;
      border-radius: 3px;
      background: #fff;
      border: 1px solid #c6bec9;
      color: rgb(30, 116, 30);
      font-weight: bold;
      cursor: pointer;
    }
    .btn-clear:hover {
      background: rgb(30, 116, 30);
      color: #fff;
    }

    /* Pure White Monospace Console */
    .fake_console {
      background-color: #0c0c0c;
      border: 1px solid #222;
      border-radius: 3px;
      padding: 10px 14px;
      box-sizing: border-box;
      height: 200px;
      position: relative;
      z-index: 1;
    }
    pre.con {
      margin: 0;
      padding: 0;
      background: transparent;
      color: #ffffff;
      font-family: Consolas, "SFMono-Regular", "Liberation Mono", Menlo, monospace;
      font-size: 13px;
      line-height: 20px;
      height: 180px;
      overflow-y: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }

    /* Root Shell Interactive Command Bar */
    .shell-bar {
      display: flex;
      gap: 8px;
      margin-top: 10px;
      align-items: center;
      position: relative;
      z-index: 2;
    }
    .shell-prompt {
      color: #69c469;
      font-family: Consolas, monospace;
      font-size: 13px;
      font-weight: bold;
      white-space: nowrap;
      user-select: none;
    }
    .shell-input {
      flex: 1;
      height: 36px;
      padding: 6px 10px;
      font-family: Consolas, monospace;
      font-size: 13px;
      background: #141414;
      color: #fff;
      border: 1px solid #333;
      border-radius: 3px;
      box-sizing: border-box;
    }
    .shell-input:focus {
      outline: none;
      border-color: rgb(30, 116, 30);
      box-shadow: 0 0 5px rgba(92, 247, 65, 0.5);
    }
    .shell-btn {
      width: auto !important;
      height: 36px;
      padding: 6px 18px !important;
      margin: 0 !important;
    }

    /* Styled File Upload Container */
    .file-wrap {
      position: relative;
      z-index: 2;
      margin-bottom: 14px;
    }
    .file-wrap input[type="file"] {
      display: block;
      width: 100%;
      box-sizing: border-box;
      padding: 7px 8px;
      font-size: 12px;
      font-family: inherit;
      background: #fafafa;
      border: 1px solid #c6bec9;
      border-radius: 4px;
      color: #333;
      cursor: pointer;
    }
    .file-wrap input[type="file"]:hover {
      background: #fff;
      border-color: rgb(30, 116, 30);
    }

    /* Clean Footer showing GUI Version */
    .copyright {
      margin-top: 35px;
      margin-bottom: 20px;
      text-align: center;
      font: 300 13px/20px Helvetica,Arial,sans-serif;
      color: #666;
      position: relative;
      z-index: 2;
    }
    .copyright p { margin: 4px 0 0; }
    .copyright strong { color: rgb(30, 116, 30); font-weight: 700; }

    /* Responsive Breakpoints: Desktop (default 4 cols), Tablet (2 cols), Smartphone (1 col) */
    @media (max-width: 1024px) {
      .container {
        padding: 0 16px 30px;
      }
      .cards-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 16px;
      }
      .logt {
        grid-column: 1 / -1;
      }
    }
    @media (max-width: 680px) {
      .container {
        padding: 0 10px 25px;
      }
      .header {
        flex-direction: column;
        align-items: center;
        text-align: center;
        gap: 12px;
        padding: 16px 0 12px;
      }
      .header-lang {
        width: 100%;
        justify-content: center;
      }
      #webui_language {
        width: 100%;
        max-width: 280px;
      }
      .alert {
        word-break: break-word;
        padding: 10px 12px;
      }
      .cards-grid {
        grid-template-columns: minmax(0, 1fr);
        gap: 14px;
        min-width: 0;
        width: 100%;
      }
      .sc {
        min-width: 0;
        max-width: 100%;
        width: 100%;
      }
      .ct {
        min-width: 0;
      }
      .shell-input {
        min-width: 0;
        width: 100%;
      }
      .sh {
        font-size: 16px;
        padding: 10px 12px;
      }
      .logt {
        grid-column: 1;
      }
      .logt .sh {
        flex-wrap: wrap;
        gap: 6px;
      }
      .shell-bar {
        flex-direction: column;
        align-items: stretch;
        gap: 8px;
      }
      .shell-btn {
        width: 100% !important;
        justify-content: center;
      }
    }

    /* ---- v3 additions ---- */
    .light { background-color: #999; border: 1px solid #737373; box-shadow: inset 0 1px 3px rgba(255,255,255,.5); }
    .guiver { color: rgb(30, 116, 30); font-weight: bold; }
    .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
    .btn-clear { min-height: 32px; padding: 5px 12px; font-size: 12px; line-height: 20px; }
    .tabs { position: relative; z-index: 2; display: flex; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; }
    .tab { padding: 6px 16px; font: inherit; font-weight: bold; color: rgb(30, 116, 30); background: #fff;
           border: 1px solid #c6bec9; border-radius: 4px; cursor: pointer; }
    .tab:hover { border-color: rgb(30, 116, 30); }
    .tab.on { color: #fff; border-color: rgb(30, 116, 30);
              background: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%); }
    .pill { display: none; margin-left: 8px; padding: 2px 10px; font-size: 12px; font-weight: bold; color: #6b4000;
            background: #fcf0d0; border: 1px solid #e0a030; border-radius: 10px; }
    pre.con { display: none; }
    pre.con.on { display: block; }
    .prog { position: relative; z-index: 2; display: none; height: 14px; margin-bottom: 14px; overflow: hidden;
            background: linear-gradient(to bottom, #f5f5f5, #f9f9f9); border-radius: 4px;
            box-shadow: inset 0 1px 2px rgba(0,0,0,.1); }
    .prog i { display: block; width: 0; height: 100%; transition: width .3s ease;
              background: linear-gradient(to bottom, #62c462, #57a957); }
    .tab:focus-visible, .btn-clear:focus-visible, .btn-action:focus-visible { outline: 2px solid rgb(92,247,65); outline-offset: 2px; }
  </style>
</head>
<body>

<!-- Technicolor Green Globe Watermark -->
<div class="gateway_bg"></div>

<div class="container">

  <!-- Header with Technicolor Logo and language selector -->
  <div class="header">
    <div class="header-logo">
      <a href="https://www.technicolor.com" target="_blank" rel="noopener noreferrer" title="Technicolor Gateway">
        <img width="131px" height="50px" alt="Technicolor" src="data:image/png;base64,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">
      </a>
    </div>
    <div class="header-lang">
      <select id="webui_language" name="webui_language" aria-label="Language">
        <option value="it">Italiano</option>
        <option value="en">English</option>
      </select>
    </div>
  </div>

  <!-- Warning Alert Banner -->
  <div class="alert">
    <i class="fa fa-exclamation-triangle" style="margin-right: 6px;"></i>
    <strong data-i18n="alert_title">Modalit&agrave; di Emergenza Attiva</strong>
  </div>

  <!-- 4-column grid: 4 cards on row 1, 1 card + 3-column console on row 2 -->
  <div class="cards-grid">

    <!-- Card 1: Stato del Sistema -->
    <div class="sc">
      <div class="sh" data-i18n="c1_title">Stato del Sistema</div>
      <div class="ct">
        <span class="bgi fa">&#xf129;</span>
        <div>
          <div class="li"><i class="fa fa-microchip"></i> <strong data-i18n="c1_model">Modello:</strong> <span id="v-model">@@HARDWARE@@</span></div>
          <div class="li"><i class="fa fa-code-branch"></i> <strong data-i18n="c1_guiver">Versione GUI:</strong> <span id="v-gui" class="guiver">@@GUIVER@@</span></div>
          <div class="li"><i class="fa fa-memory"></i> <strong data-i18n="c1_ram">RAM:</strong> <span id="v-ram">@@MEM@@</span></div>
          <div class="li"><i class="fa fa-clock"></i> <strong data-i18n="c1_uptime">Uptime:</strong> <span id="v-uptime">@@UPTIME@@</span></div>
          <div class="li"><i class="fa fa-shield-alt"></i> <strong data-i18n="c1_kernel">Kernel:</strong> <span id="v-kernel">@@KERNEL@@</span></div>
        </div>
      </div>
    </div>

    <!-- Card 2: Servizi Web -->
    <div class="sc">
      <div class="sh" data-i18n="c2_title">Servizi Web</div>
      <div class="ct">
        <span class="bgi fa">&#xf085;</span>
        <div>
          <div class="li"><span id="led-nginx" class="light @@NGINX_LED@@"></span><strong data-i18n="c2_nginx">Nginx:</strong> <span id="st-nginx" data-state="@@NGINX_STATE@@">@@NGINX_TXT@@</span></div>
          <div class="li"><span id="led-trans" class="light @@TRANS_LED@@"></span><strong data-i18n="c2_trans">Transformer:</strong> <span id="st-trans" data-state="@@TRANS_STATE@@">@@TRANS_TXT@@</span></div>
          <div class="sub" data-i18n="c2_desc" style="margin-top: 10px; margin-bottom: 14px;">Nginx e Transformer gestiscono l'accesso web primario (porta 80).</div>
        </div>
        <div>
          <button id="btnRestart" class="btn-action btn-default" type="button">
            <i class="fa fa-sync-alt"></i> <span data-i18n="btn_restart">Riavvia Servizi</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Card 3: Ripristino Zero-Touch USB -->
    <div class="sc">
      <div class="sh" data-i18n="c3_title">Ripristino USB</div>
      <div class="ct">
        <span class="bgi fb">&#xf287;</span>
        <div class="li"><span id="led-usb" class="light @@USB_LED@@"></span><span id="st-usb">@@USB_TXT@@</span></div>
        <div class="sub" data-i18n="c3_desc" style="margin: 8px 0 16px;">
          Inserisci una chiavetta USB con il pacchetto di ripristino della GUI per avviare il flashing automatico.
        </div>
        <div>
          <button id="btnUsb" class="btn-action btn-primary" type="button">
            <i class="fa fa-play"></i> <span data-i18n="btn_usb">Flash da USB</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Card 4: Caricamento Pacchetto da PC -->
    <div class="sc">
      <div class="sh" data-i18n="c4_title">Carica Pacchetto</div>
      <div class="ct">
        <span class="bgi fa">&#xf093;</span>
        <div class="sub" data-i18n="c4_desc" style="margin-bottom: 8px;">
          Seleziona il pacchetto di ripristino dal computer:
        </div>
        <div class="file-wrap">
          <label for="guiFile" class="sr-only">Package</label>
          <input id="guiFile" type="file" accept=".tar.bz2,.bz2">
        </div>
        <div id="upProg" class="prog" role="progressbar" aria-valuemin="0" aria-valuemax="100"><i id="upFill"></i></div>
        <div>
          <button id="btnUpload" class="btn-action btn-primary" type="button">
            <i class="fa fa-upload"></i> <span data-i18n="btn_upload">Carica &amp; Flash</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Card 5: Gestione Modem -->
    <div class="sc">
      <div class="sh" data-i18n="c5_title">Gestione Modem</div>
      <div class="ct">
        <span class="bgi fa">&#xf011;</span>
        <div>
          <div class="li"><i class="fa fa-network-wired"></i> <strong data-i18n="c5_port">Porta rescue:</strong> @@PORT@@</div>
          <div class="li"><i class="fa fa-file-alt"></i> <strong data-i18n="c5_log">Log:</strong> @@LOGFILE@@</div>
          <div class="sub" data-i18n="c5_desc" style="margin-top: 10px; margin-bottom: 14px;">Riavvio hardware a basso livello del gateway.</div>
        </div>
        <div>
          <button id="btnReboot" class="btn-action btn-danger" type="button">
            <i class="fa fa-power-off"></i> <span data-i18n="btn_reboot">Riavvia Modem</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Card 6: Console (root shell + live log), spans 3 columns -->
    <div class="sc logt">
      <div class="sh">
        <span><i class="fa fa-terminal"></i> <span data-i18n="c6_title">Console Rescue</span></span>
        <button id="btnClear" class="btn-clear" type="button"><i class="fa fa-eraser"></i> <span data-i18n="btn_clear">Pulisci</span></button>
      </div>
      <div class="ct" style="min-height: auto; padding: 14px;">
        <div class="tabs" role="tablist">
          <button id="tabShell" class="tab on" type="button" role="tab" aria-selected="true" data-i18n="tab_shell">Shell Root</button>
          <button id="tabLog" class="tab" type="button" role="tab" aria-selected="false" data-i18n="tab_log">Log</button>
          <span id="busyNote" class="pill" data-i18n="busy_note">Operazione in corso</span>
        </div>
        <div class="fake_console">
          <pre id="shellBox" class="con on"></pre>
          <pre id="logBox" class="con" aria-live="off"></pre>
        </div>
        <!-- Interactive Root Shell Command Bar -->
        <form id="shellForm" class="shell-bar">
          <span id="shellPrompt" class="shell-prompt">root@rescue:/#</span>
          <input type="text" id="shellInput" class="shell-input" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" aria-label="Shell">
          <button type="submit" id="btnShell" class="btn-action btn-primary shell-btn">
            <i class="fa fa-play"></i> <span data-i18n="btn_send">Invia</span>
          </button>
        </form>
      </div>
    </div>

  </div><!-- /cards-grid -->

  <!-- Footer showing current GUI version -->
  <div class="copyright">
    <p><span data-i18n="footer_copy">&copy; Technicolor &bull; Rescue Console</span> (<span data-i18n="footer_port">Porta</span> @@PORT@@) &bull; v@@VERSION@@</p>
    <p><span data-i18n="footer_guiver">Versione GUI rilevata sul router:</span> <strong id="f-gui">@@GUIVER@@</strong></p>
  </div>

</div><!-- /container -->

<script>
(function () {
  'use strict';

  var UPLOAD_MAX = @@UPLOAD_MAX@@;

  var I18N = {
    it: {
      page_title: "Rescue Console \u2014 Technicolor Gateway",
      alert_title: "Modalit\u00e0 di Emergenza Attiva",
      c1_title: "Stato del Sistema", c1_model: "Modello:", c1_guiver: "Versione GUI:", c1_ram: "RAM:",
      c1_uptime: "Uptime:", c1_kernel: "Kernel:",
      c2_title: "Servizi Web", c2_nginx: "Nginx:", c2_trans: "Transformer:",
      c2_desc: "Nginx e Transformer gestiscono l'accesso web primario (porta 80).",
      btn_restart: "Riavvia Servizi",
      c3_title: "Ripristino USB",
      c3_desc: "Inserisci una chiavetta USB con il pacchetto di ripristino della GUI per avviare il flashing automatico.",
      btn_usb: "Flash da USB", usb_scanning: "Scansione USB...",
      usb_found: "Chiavetta rilevata: {0}", usb_none: "Nessuna chiavetta rilevata",
      c4_title: "Carica Pacchetto", c4_desc: "Seleziona il pacchetto di ripristino dal computer:",
      btn_upload: "Carica & Flash", upload_btn_loading: "Caricamento",
      c5_title: "Gestione Modem", c5_port: "Porta rescue:", c5_log: "Log:",
      c5_desc: "Riavvio hardware a basso livello del gateway.", btn_reboot: "Riavvia Modem",
      c6_title: "Console Rescue", tab_shell: "Shell Root", tab_log: "Log", btn_clear: "Pulisci", btn_send: "Invia",
      busy_note: "Operazione in corso",
      shell_placeholder: "Comando shell root (es. ls -la, ifconfig, df -h)...",
      welcome_text: "Technicolor Emergency Root Shell\nDigita un comando root (es. ls -la, ps, df -h, free -m) e premi Invio.\nOgni comando gira in una shell separata; 'cd' viene ricordato dalla console.",
      footer_copy: "\u00a9 Technicolor \u2022 Rescue Console", footer_port: "Porta",
      footer_guiver: "Versione GUI rilevata sul router:", gui_unknown: "Non rilevata / Corrotta",
      st_on: "Attivo", st_off: "Non attivo",
      confirm_restart: "Vuoi riavviare i demoni Transformer e Nginx?",
      confirm_reboot: "Confermi il riavvio completo del router?",
      confirm_upload: "Il pacchetto \"{0}\" verr\u00e0 estratto sul filesystem principale e sovrascriver\u00e0 i file esistenti. Procedere?",
      m_nofile: "Seleziona prima un file .tar.bz2 valido dal tuo computer.",
      m_toobig: "File troppo grande (massimo {0} MB).",
      m_usb_req: "--> [USB] Avvio scansione periferiche USB per il ripristino...",
      m_upload_req: "--> [UPLOAD] Invio pacchetto GUI: {0} ({1} MB)...",
      m_restart_req: "--> [SERVIZI] Richiesta riavvio di Nginx e Transformer...",
      m_reboot_req: "--> [MODEM] Invio comando di reboot del gateway...",
      m_neterr: "[ERRORE] Server non raggiungibile.",
      m_http: "[ERRORE] Risposta HTTP {0}",
      m_shell_err: "[ERRORE] Impossibile contattare la shell."
    },
    en: {
      page_title: "Rescue Console \u2014 Technicolor Gateway",
      alert_title: "Emergency Recovery Mode Active",
      c1_title: "System Status", c1_model: "Model:", c1_guiver: "GUI Version:", c1_ram: "RAM:",
      c1_uptime: "Uptime:", c1_kernel: "Kernel:",
      c2_title: "Web Services", c2_nginx: "Nginx:", c2_trans: "Transformer:",
      c2_desc: "Nginx and Transformer handle primary web access (port 80).",
      btn_restart: "Restart Services",
      c3_title: "USB Recovery",
      c3_desc: "Insert a USB drive containing the GUI recovery package to start automatic flashing.",
      btn_usb: "Flash from USB", usb_scanning: "Scanning USB...",
      usb_found: "USB drive detected: {0}", usb_none: "No USB drive detected",
      c4_title: "Upload Package", c4_desc: "Select the recovery package from your computer:",
      btn_upload: "Upload & Flash", upload_btn_loading: "Uploading",
      c5_title: "Modem Management", c5_port: "Rescue port:", c5_log: "Log:",
      c5_desc: "Low-level hardware reboot of the gateway.", btn_reboot: "Reboot Gateway",
      c6_title: "Rescue Console", tab_shell: "Root Shell", tab_log: "Log", btn_clear: "Clear", btn_send: "Send",
      busy_note: "Operation in progress",
      shell_placeholder: "Root shell command (e.g. ls -la, ifconfig, df -h)...",
      welcome_text: "Technicolor Emergency Root Shell\nType a root command (e.g. ls -la, ps, df -h, free -m) and press Enter.\nEach command runs in a separate shell; 'cd' is remembered by the console.",
      footer_copy: "\u00a9 Technicolor \u2022 Rescue Console", footer_port: "Port",
      footer_guiver: "Detected router GUI version:", gui_unknown: "Not detected / Corrupted",
      st_on: "Active", st_off: "Inactive",
      confirm_restart: "Do you want to restart Transformer and Nginx?",
      confirm_reboot: "Are you sure you want to reboot the gateway?",
      confirm_upload: "The package \"{0}\" will be extracted onto the main filesystem and will overwrite existing files. Continue?",
      m_nofile: "Please select a valid .tar.bz2 file from your computer first.",
      m_toobig: "File too large (maximum {0} MB).",
      m_usb_req: "--> [USB] Starting USB device scan for recovery...",
      m_upload_req: "--> [UPLOAD] Sending GUI package: {0} ({1} MB)...",
      m_restart_req: "--> [SERVICES] Restart of Nginx and Transformer requested...",
      m_reboot_req: "--> [MODEM] Sending gateway reboot command...",
      m_neterr: "[ERROR] Server unreachable.",
      m_http: "[ERROR] HTTP response {0}",
      m_shell_err: "[ERROR] Unable to reach the shell."
    }
  };

  var lang = 'it';
  var cwd = '/';
  var cmdHistory = [], histIdx = -1;
  var logPos = -1, lastStatus = null;
  var busy = false, uploading = false, shellDirty = false;

  function $(id) { return document.getElementById(id); }

  function t(key, args) {
    var s = (I18N[lang] && I18N[lang][key]) || I18N.it[key] || key;
    if (args) { s = s.replace(/\{(\d+)\}/g, function (m, i) { return args[i]; }); }
    return s;
  }

  // ---------- HTTP ----------
  function request(method, url, body, done, fail, setup) {
    var x = new XMLHttpRequest();
    x.open(method, url, true);
    if (method === 'POST') { x.setRequestHeader('X-Rescue', '1'); }
    if (setup) { setup(x); }
    x.onload = function () { if (done) { done(x); } };
    x.onerror = function () { if (fail) { fail(x); } };
    x.send(body === undefined ? null : body);
    return x;
  }
  function parse(x) {
    try { return JSON.parse(x.responseText); } catch (e) { return null; }
  }

  // ---------- console panes ----------
  var shellBox = $('shellBox'), logBox = $('logBox');

  function append(box, text) {
    var near = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    box.textContent += text;
    if (box.textContent.length > 200000) { box.textContent = box.textContent.slice(-150000); }
    if (near) { box.scrollTop = box.scrollHeight; }
  }
  function line(box, text) {
    var cur = box.textContent;
    append(box, (cur && cur.slice(-1) !== '\n' ? '\n' : '') + text + '\n');
  }
  function showTab(name) {
    var shell = (name === 'shell');
    shellBox.className = 'con' + (shell ? ' on' : '');
    logBox.className = 'con' + (shell ? '' : ' on');
    $('tabShell').className = 'tab' + (shell ? ' on' : '');
    $('tabLog').className = 'tab' + (shell ? '' : ' on');
    $('tabShell').setAttribute('aria-selected', shell ? 'true' : 'false');
    $('tabLog').setAttribute('aria-selected', shell ? 'false' : 'true');
    $('shellForm').style.display = shell ? 'flex' : 'none';
    if (shell) { $('shellInput').focus(); }
  }
  function isShellTab() { return shellBox.classList.contains('on'); }
  // Action feedback goes to the log tab, which is switched to automatically.
  function note(msg) { line(logBox, msg); showTab('log'); }

  // ---------- i18n ----------
  function paintStates() {
    var els = document.querySelectorAll('[data-state]');
    for (var i = 0; i < els.length; i++) {
      els[i].textContent = t(els[i].getAttribute('data-state') === 'active' ? 'st_on' : 'st_off');
    }
  }
  function paintUsb(s) {
    if (!s) { return; }
    var label = s.usb_name + (s.usb_fs ? ' (' + s.usb_fs + ')' : '');
    $('st-usb').textContent = s.usb ? t('usb_found', [label]) : t('usb_none');
  }
  function applyLang(l) {
    if (!I18N[l]) { l = 'it'; }
    lang = l;
    try { localStorage.setItem('rescue_lang', l); } catch (e) {}
    document.documentElement.lang = l;
    document.title = t('page_title');
    var els = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < els.length; i++) {
      var key = els[i].getAttribute('data-i18n');
      if (I18N[l][key] !== undefined) { els[i].innerHTML = I18N[l][key]; }
    }
    paintStates();
    paintUsb(lastStatus);
    $('shellInput').placeholder = t('shell_placeholder');
    $('webui_language').value = l;
    if (!shellDirty) { shellBox.textContent = t('welcome_text'); }   // only the untouched banner
  }

  // ---------- live status ----------
  function paintGui(v) {
    ['v-gui', 'f-gui'].forEach(function (id) {
      var el = $(id);
      if (v) { el.removeAttribute('data-i18n'); el.textContent = v; }
      else { el.setAttribute('data-i18n', 'gui_unknown'); el.textContent = t('gui_unknown'); }
    });
  }
  function paintService(name, active) {
    $('led-' + name).className = 'light ' + (active ? 'green' : 'red');
    $('st-' + name).setAttribute('data-state', active ? 'active' : 'inactive');
  }
  function applyBusy() {
    var off = busy || uploading;
    ['btnUsb', 'btnUpload', 'btnRestart'].forEach(function (id) { $(id).disabled = off; });
    $('busyNote').style.display = off ? 'inline-block' : 'none';
  }
  function pollStatus() {
    if (document.hidden || uploading) { return; }
    request('GET', '/status', undefined, function (x) {
      var s = (x.status === 200) ? parse(x) : null;
      if (!s) { return; }
      lastStatus = s;
      $('v-model').textContent = s.hardware;
      $('v-kernel').textContent = s.kernel;
      $('v-ram').textContent = s.mem;
      $('v-uptime').textContent = s.uptime;
      paintGui(s.gui_version);
      paintService('nginx', s.nginx);
      paintService('trans', s.transformer);
      $('led-usb').className = 'light' + (s.usb ? ' green' : '');
      paintStates();
      paintUsb(s);
      busy = !!s.busy;
      applyBusy();
    });
  }
  function pollLog() {
    if (document.hidden || uploading) { return; }
    request('GET', '/log?pos=' + logPos, undefined, function (x) {
      if (x.status !== 200) { return; }
      var pos = parseInt(x.getResponseHeader('X-Log-Pos'), 10);
      if (x.getResponseHeader('X-Log-Reset') === '1') { logBox.textContent = ''; }
      if (x.responseText) { append(logBox, x.responseText); }
      if (!isNaN(pos)) { logPos = pos; }
    });
  }

  // ---------- button helpers ----------
  function btnState(id, icon, key, raw) {
    var b = $(id), i = b.querySelector('i'), s = b.querySelector('span');
    i.className = 'fa ' + icon;
    if (key) { s.setAttribute('data-i18n', key); s.textContent = t(key); }
    else { s.removeAttribute('data-i18n'); s.textContent = raw; }
  }
  function report(x, tag) {
    var j = parse(x);
    note(tag + ' ' + (j && j.message ? j.message : t('m_http', [x.status])));
  }

  // ---------- shell ----------
  function shellQuote(s) { return "'" + s.replace(/'/g, "'\\''") + "'"; }
  function setPrompt() { $('shellPrompt').textContent = 'root@rescue:' + cwd + '#'; }

  function runShell(ev) {
    ev.preventDefault();
    var inp = $('shellInput'), btn = $('btnShell'), cmd = inp.value.trim();
    if (!cmd) { return; }
    if (!cmdHistory.length || cmdHistory[cmdHistory.length - 1] !== cmd) { cmdHistory.push(cmd); }
    histIdx = -1;
    inp.value = '';
    shellDirty = true;
    if (cmd === 'clear') { shellBox.textContent = ''; return; }

    var cd = /^cd(?:\s+(.*))?$/.exec(cmd);
    var body = 'cd ' + shellQuote(cwd) + ' 2>/dev/null\n' + (cd ? 'cd ' + (cd[1] || '') + ' && pwd' : cmd);
    line(shellBox, 'root@rescue:' + cwd + '# ' + cmd);
    btn.disabled = true;
    request('POST', '/exec', body, function (x) {
      var j = parse(x), out = (j && j.output) ? j.output : '';
      btn.disabled = false;
      inp.focus();
      if (!j) { line(shellBox, t('m_http', [x.status])); return; }
      if (cd) {
        var m = /^(\/[^\n]*)\n*$/.exec(out);
        if (m) { cwd = m[1]; setPrompt(); return; }        // cd succeeded: stay silent like a real shell
      }
      if (out) { line(shellBox, out.replace(/\n+$/, '')); }
    }, function () {
      btn.disabled = false;
      inp.focus();
      line(shellBox, t('m_shell_err'));
    }, function (x) { x.setRequestHeader('Content-Type', 'text/plain; charset=utf-8'); });
  }

  // ---------- actions ----------
  function onUsb() {
    note(t('m_usb_req'));
    btnState('btnUsb', 'fa-spinner fa-spin', 'usb_scanning');
    $('btnUsb').disabled = true;
    function restore() { btnState('btnUsb', 'fa-play', 'btn_usb'); pollStatus(); }
    request('POST', '/usb_recovery', undefined, function (x) {
      report(x, '[USB]');
      setTimeout(restore, 3000);
    }, function () { note(t('m_neterr')); restore(); });
  }

  function startUpload(file) {
    var fill = $('upFill'), prog = $('upProg');
    uploading = true;
    applyBusy();
    prog.style.display = 'block';
    fill.style.width = '0%';
    btnState('btnUpload', 'fa-spinner fa-spin', null, t('upload_btn_loading') + ' (' + (file.size / 1048576).toFixed(1) + ' MB)...');
    note(t('m_upload_req', [file.name, (file.size / 1048576).toFixed(2)]));
    function finish() {
      uploading = false;
      btnState('btnUpload', 'fa-upload', 'btn_upload');
      applyBusy();
      setTimeout(function () { pollStatus(); pollLog(); }, 500);
    }
    request('POST', '/upload', file, function (x) {
      if (x.status === 200) { fill.style.width = '100%'; }
      report(x, '[UPLOAD]');
      finish();
    }, function () { note(t('m_neterr')); finish(); }, function (x) {
      x.setRequestHeader('Content-Type', 'application/octet-stream');
      x.upload.onprogress = function (e) {
        if (!e.lengthComputable) { return; }
        var p = Math.round(e.loaded * 100 / e.total);
        fill.style.width = p + '%';
        prog.setAttribute('aria-valuenow', p);
        btnState('btnUpload', 'fa-spinner fa-spin', null, t('upload_btn_loading') + ' ' + p + '%...');
      };
    });
  }
  function onUpload() {
    var fi = $('guiFile'), file = fi.files && fi.files[0];
    if (!file) { note(t('m_nofile')); return; }
    if (file.size > UPLOAD_MAX) { note(t('m_toobig', [Math.floor(UPLOAD_MAX / 1048576)])); return; }
    if (!/\.bz2$/i.test(file.name)) { note(t('m_nofile')); return; }
    if (confirm(t('confirm_upload', [file.name]))) { startUpload(file); }
  }

  function simplePost(url, confirmKey, reqKey, tag) {
    if (!confirm(t(confirmKey))) { return; }
    note(t(reqKey));
    request('POST', url, undefined, function (x) { report(x, tag); setTimeout(pollStatus, 3000); },
            function () { note(t('m_neterr')); });
  }

  function onClear() {
    if (isShellTab()) { shellBox.textContent = ''; shellDirty = true; $('shellInput').focus(); return; }
    request('POST', '/clear_log', undefined, function () { logBox.textContent = ''; logPos = -1; pollLog(); });
  }

  // ---------- init ----------
  $('btnUsb').addEventListener('click', onUsb);
  $('btnUpload').addEventListener('click', onUpload);
  $('btnRestart').addEventListener('click', function () { simplePost('/restart_services', 'confirm_restart', 'm_restart_req', '[SERVIZI]'); });
  $('btnReboot').addEventListener('click', function () { simplePost('/reboot', 'confirm_reboot', 'm_reboot_req', '[MODEM]'); });
  $('btnClear').addEventListener('click', onClear);
  $('tabShell').addEventListener('click', function () { showTab('shell'); });
  $('tabLog').addEventListener('click', function () { showTab('log'); });
  $('shellForm').addEventListener('submit', runShell);
  $('webui_language').addEventListener('change', function () { applyLang(this.value); });
  $('shellInput').addEventListener('keydown', function (e) {
    var inp = this;
    if (e.key === 'ArrowUp') {
      if (cmdHistory.length) {
        histIdx = (histIdx === -1) ? cmdHistory.length - 1 : Math.max(0, histIdx - 1);
        inp.value = cmdHistory[histIdx];
      }
      e.preventDefault();
    } else if (e.key === 'ArrowDown' && histIdx !== -1) {
      histIdx++;
      if (histIdx >= cmdHistory.length) { histIdx = -1; inp.value = ''; } else { inp.value = cmdHistory[histIdx]; }
      e.preventDefault();
    }
  });

  var initial = 'it';
  try {
    var q = new URLSearchParams(window.location.search).get('lang');
    initial = q || localStorage.getItem('rescue_lang') || '';
  } catch (e) {}
  if (!initial) {
    var nav = (navigator.language || 'it').substring(0, 2).toLowerCase();
    initial = (nav === 'en') ? 'en' : 'it';
  }
  applyLang(initial);
  setPrompt();
  applyBusy();
  pollLog();
  pollStatus();
  setInterval(pollLog, 1500);
  setInterval(pollStatus, 4000);
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
