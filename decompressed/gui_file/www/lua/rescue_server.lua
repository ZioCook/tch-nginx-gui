#!/usr/bin/lua
--
-- Standalone LuaSocket Emergency Rescue Server for tch-nginx-gui
-- Operates completely independently from Nginx, LuaJIT, and Transformer.
-- Provides Out-of-Band Web Management, PC archive upload, and Zero-Touch USB Recovery.
--

local socket = require("socket")

local DEFAULT_PORT = 8088
local LOG_FILE = "/tmp/rescue.log"
local UPLOAD_TEMP = "/tmp/rescue_upload.tmp"
local RECOVERY_TARGET = "/tmp/GUI_upload.tar.bz2"

-- Append message to rescue log
local function log(msg)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local line = string.format("[%s] [RESCUE-SERVER] %s\n", timestamp, msg)
    io.stderr:write(line)
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(line)
        f:close()
    end
end

-- Read entire file contents safely
local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content or ""
end

-- Collect hardware / system status for rescue dashboard
local function get_system_summary()
    local summary = {}

    -- Board / Model
    local f_board = io.open("/proc/cpuinfo", "r")
    if f_board then
        local text = f_board:read("*a") or ""
        f_board:close()
        summary.hardware = text:match("Hardware%s*:%s*([^\r\n]+)") or text:match("model name%s*:%s*([^\r\n]+)") or "Broadcom BCM63xx/BCM4908"
    else
        summary.hardware = "Technicolor Gateway"
    end

    -- Kernel Version
    local f_ver = io.open("/proc/version", "r")
    if f_ver then
        summary.kernel = f_ver:read("*l") or "Linux"
        f_ver:close()
    else
        summary.kernel = "Linux"
    end

    -- Memory Info
    local f_mem = io.open("/proc/meminfo", "r")
    if f_mem then
        local text = f_mem:read("*a") or ""
        f_mem:close()
        local total = tonumber(text:match("MemTotal:%s*(%d+)")) or 0
        local free = tonumber(text:match("MemFree:%s*(%d+)")) or 0
        summary.mem = string.format("%d MB / %d MB", math.floor((total - free) / 1024), math.floor(total / 1024))
    else
        summary.mem = "N/A"
    end

    -- Uptime
    local f_up = io.open("/proc/uptime", "r")
    if f_up then
        local up_sec = tonumber(f_up:read("*n")) or 0
        f_up:close()
        local hours = math.floor(up_sec / 3600)
        local mins = math.floor((up_sec % 3600) / 60)
        summary.uptime = string.format("%dh %02dm", hours, mins)
    else
        summary.uptime = "N/A"
    end

    -- Check if Nginx is running
    local check_nginx = os.execute("pgrep nginx >/dev/null 2>&1")
    summary.nginx_running = (check_nginx == 0)

    -- Check if Transformer is running
    local check_trans = os.execute("pgrep transformer >/dev/null 2>&1")
    summary.trans_running = (check_trans == 0)

    return summary
end

-- Render the Standalone Recovery HTML Webpage (Faithful Technicolor GUI Theme)
local function render_html()
    local s = get_system_summary()
    local nginx_led = s.nginx_running and '<span class="led green"></span>Nginx: <b>Attivo</b>' or '<span class="led red"></span>Nginx: <b>Non attivo</b>'
    local trans_led = s.trans_running and '<span class="led green"></span>Transformer: <b>Attivo</b>' or '<span class="led red"></span>Transformer: <b>Non attivo</b>'

    return [[<!doctype html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rescue Console &#8211; Technicolor Gateway</title>
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
    body { margin: 0; padding: 0; background-color: #eee; font: 14px/20px Helvetica,Arial,sans-serif; color: #333; }
    .pg { position: relative; overflow: hidden; min-height: 100vh; background: #eee; }
    .gb { position: absolute; background: rgba(151,187,151,.4); pointer-events: none; }
    .fa { font-family: "Font Awesome 5 Free", sans-serif; font-weight: 900; font-style: normal; }
    .fb { font-family: "Font Awesome 5 Brands", sans-serif; font-weight: 400; font-style: normal; }

    /* Header */
    .hdr { position: relative; z-index: 2; display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 14px; padding: 30px 2rem 0; margin-bottom: 30px; }
    .hdr-logo-block { display: flex; flex-direction: column; }
    .hdr-logo-text { font-size: 26px; line-height: 30px; color: #555; font-weight: 400; letter-spacing: -0.5px; }
    .hdr-palette { display: flex; align-items: flex-end; gap: 2px; margin-top: 6px; }
    .hdr-palette span { display: inline-block; }
    .hdr-actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 8px; max-width: 580px; }
    .hbtn { display: inline-flex; align-items: center; gap: 7px; box-sizing: border-box; height: 36px; padding: 7px 18px; font: 500 14px/20px Helvetica,Arial,sans-serif; color: #333; background: #fff; border: 1px solid #c6bec9; border-radius: 4px; box-shadow: inset 0 -1px 0 #fff, 0 1px 2px rgba(0,0,0,.08); text-decoration: none; cursor: default; }
    .hbtn-badge { background: #fcf0d0; border-color: #e0a030; color: #6b4000; font-weight: 700; }
    .hbtn i { font-size: 13px; }

    /* Cards Grid */
    .cards { position: relative; z-index: 2; display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; padding: 0 38px; margin-bottom: 20px; }
    .sc { position: relative; display: flex; flex-direction: column; background: #fff; overflow: hidden; font-size: 15px; box-shadow: 0 2px 20px 0 rgba(56,132,56,.65); }
    .sh { padding: 10px; height: 20px; font-size: 18px; line-height: 20px; color: #fff; text-shadow: 0 1px 1px #000; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; background: linear-gradient(to bottom, rgb(30,116,30) 20%, rgb(29,36,29) 100%); border: 1px solid rgb(30,116,30); box-shadow: inset 0 1px 1px rgba(255,255,255,.2); }
    .ct { position: relative; z-index: 1; flex: 1; box-sizing: border-box; min-height: 172px; padding: 10px; font-weight: 500; overflow: hidden; }
    .bgi { position: absolute; right: 8px; top: 10px; z-index: 0; font-size: 130px; line-height: 1; color: rgba(151,187,151,.4); pointer-events: none; }
    .li { position: relative; z-index: 1; line-height: 20px; margin-bottom: 4px; font-size: 14px; }
    .li i { display: inline-block; width: 22px; color: #555; font-size: 14px; text-align: center; }
    .sub { position: relative; z-index: 1; margin: 6px 0 10px 0; font-size: 13px; line-height: 18px; font-weight: 300; }

    /* LEDs */
    .led { display: inline-block; width: 7px; height: 7px; margin: 0 10px 0 4px; border-radius: 50%; vertical-align: 1px; }
    .led.red { background: #cd3535; border: 1px solid #912424; box-shadow: inset 0 1px 3px rgba(255,255,255,.5), 0 0 4px rgba(255,0,0,1); }
    .led.green { background: #69c469; border: 1px solid #3fa13f; box-shadow: inset 0 1px 3px rgba(255,255,255,.5), 0 0 4px rgba(0,220,0,1); }

    /* Buttons */
    .btn { position: relative; z-index: 1; display: inline-block; padding: 8px 14px; font: 14px/20px Helvetica,Arial,sans-serif; text-align: center; cursor: pointer; color: rgb(30,116,30); background: linear-gradient(to bottom, #fff, #e6e6e6); border: 1px solid #c6bec9; border-bottom-color: #aea2b2; border-radius: 4px; box-shadow: inset 0 -1px 0 #fff, 0 1px 2px rgba(0,0,0,.1); transition: opacity .15s; }
    .btn:hover { background: #e6e6e6; }
    .btn:disabled { opacity: .55; cursor: not-allowed; }
    .pri { color: #ededed; text-shadow: 0 1px 0 #000; background: linear-gradient(to bottom, rgb(30,116,30) 20%, rgb(29,36,29) 100%); border: 1px solid rgb(30,116,30); border-radius: 3px; box-shadow: inset 0 1px 0 rgba(255,255,255,.3), 0 2px 4px rgba(0,0,0,.5); }
    .pri:hover { background: linear-gradient(to bottom, rgb(38,140,38) 20%, rgb(20,28,20) 100%); color: #fff; }
    .dan { color: #fff; text-shadow: 0 -1px 0 rgba(0,0,0,.25); background: linear-gradient(to bottom, #ee5f5b, #bd362f); border: 1px solid #bd362f; box-shadow: inset 0 1px 0 rgba(255,255,255,.2), 0 1px 2px rgba(0,0,0,.05); border-radius: 4px; }
    .dan:hover { background: linear-gradient(to bottom, #bd362f, #942a25); }

    /* Log Card (Terminal) */
    .logt { grid-column: span 3; }
    .fk { position: relative; z-index: 1; height: 190px; overflow: hidden; box-sizing: border-box; padding: 12px 16px; background: #0c0c0c; color: #ccc; font: 500 13px/21px monospace; }
    pre#logBox { margin: 0; padding: 0; background: transparent; color: #3FB950; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 13px; line-height: 21px; height: 165px; overflow-y: auto; white-space: pre-wrap; word-break: break-all; }

    /* Footer & Copyright */
    .copyright { position: relative; z-index: 2; margin: 30px 0 20px; text-align: center; color: #999; text-shadow: 0 1px 0 #fff; font: 300 12px/20px Helvetica,Arial,sans-serif; }
    .copyright p { margin: 5px 0 0; }
    a { color: #0a74c8; text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* Responsive */
    @media (max-width: 1000px) { .cards { grid-template-columns: repeat(2, 1fr); } .logt { grid-column: 1 / -1; } }
    @media (max-width: 600px) { .cards { grid-template-columns: 1fr; padding: 0 10px; } .hdr { padding: 20px 1rem 0; } }
  </style>
</head>
<body>
<div class="pg">
  <!-- Geometric Technicolor background shapes -->
  <div class="gb" style="left:0;top:0;width:272px;height:134px;border-radius:0 0 70px 0"></div>
  <div class="gb" style="left:330px;top:0;width:240px;height:134px;border-radius:0 0 120px 70px"></div>
  <div class="gb" style="left:-780px;top:380px;width:800px;height:800px;border-radius:50%;opacity:.5"></div>

  <!-- Header -->
  <div class="hdr">
    <div class="hdr-logo-block">
      <div class="hdr-logo-text">technicolor</div>
      <div class="hdr-palette">
        <span style="width:17px;height:12px;background:#1f5fc9"></span>
        <span style="width:17px;height:17px;background:#5b3a9e"></span>
        <span style="width:17px;height:11px;background:#c8137a"></span>
        <span style="width:17px;height:18px;background:#dd2a1b"></span>
        <span style="width:17px;height:13px;background:#f08a00"></span>
        <span style="width:17px;height:10px;background:#f6d200"></span>
        <span style="width:17px;height:15px;background:#2e9e46"></span>
      </div>
    </div>
    <div class="hdr-actions">
      <div class="hbtn hbtn-badge"><i class="fa">&#xf071;</i>&nbsp;Modalit&agrave; Emergenza</div>
      <button class="hbtn" type="button"><i class="fa">&#xf0ad;</i>&nbsp;Gateway Recovery Console</button>
    </div>
  </div>

  <!-- Cards Grid -->
  <div class="cards">

    <!-- Card 1: Stato del Sistema -->
    <div class="sc">
      <div class="sh">Stato del Sistema</div>
      <div class="ct">
        <span class="bgi fa" aria-hidden="true">&#xf129;</span>
        <div class="li"><i class="fa">&#xf071;</i>&nbsp;<b>Modalit&agrave; Emergenza attiva</b></div>
        <div class="li"><i class="fa">&#xf2db;</i>&nbsp;<b>]] .. s.hardware .. [[</b></div>
        <div class="li"><i class="fa">&#xf538;</i>&nbsp;RAM: <b>]] .. s.mem .. [[</b></div>
        <div class="li"><i class="fa">&#xf017;</i>&nbsp;Uptime: <b>]] .. s.uptime .. [[</b></div>
      </div>
    </div>

    <!-- Card 2: Servizi Web -->
    <div class="sc">
      <div class="sh">Servizi Web</div>
      <div class="ct">
        <span class="bgi fa" aria-hidden="true">&#xf233;</span>
        <div class="li">]] .. nginx_led .. [[</div>
        <div class="li">]] .. trans_led .. [[</div>
        <div class="sub" style="margin-top:22px">
          <button class="btn" type="button" onclick="restartServices()">Riavvia Servizi</button>
        </div>
      </div>
    </div>

    <!-- Card 3: Ripristino Zero-Touch USB -->
    <div class="sc">
      <div class="sh">Ripristino Zero-Touch USB</div>
      <div class="ct">
        <span class="bgi fb" aria-hidden="true">&#xf287;</span>
        <div class="sub" style="margin-top:0;width:75%">
          Cerca <b>ziocook-gui-recovery.tar.bz2</b> o <b>GUI.tar.bz2</b> nella chiavetta USB.
        </div>
        <button id="btnUsb" class="btn pri" type="button" onclick="triggerUsbRecovery()">
          Avvia Scansione &amp; Flash USB
        </button>
      </div>
    </div>

    <!-- Card 4: Caricamento Pacchetto da PC -->
    <div class="sc">
      <div class="sh">Caricamento Pacchetto da PC</div>
      <div class="ct">
        <span class="bgi fa" aria-hidden="true">&#xf093;</span>
        <div class="sub" style="margin-top:0;width:75%">
          Seleziona un pacchetto <b>GUI.tar.bz2</b> dal tuo computer.
        </div>
        <label for="guiFile" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)">Pacchetto di ripristino</label>
        <input id="guiFile" type="file" accept=".tar.bz2,.bz2" style="position:relative;z-index:1;display:block;width:100%;box-sizing:border-box;margin-bottom:10px;padding:4px;font:13px Helvetica,Arial,sans-serif;background:#fff;border:1px solid #ccc;border-radius:4px">
        <button id="btnUpload" class="btn pri" type="button" onclick="uploadPackage()">
          Carica &amp; Ripristina
        </button>
      </div>
    </div>

    <!-- Card 5: Gestione Modem -->
    <div class="sc">
      <div class="sh">Gestione Modem</div>
      <div class="ct">
        <span class="bgi fa" aria-hidden="true">&#xf011;</span>
        <div class="li"><i class="fa">&#xf233;</i>&nbsp;Porta rescue: <b>8088</b></div>
        <div class="li"><i class="fa">&#xf15c;</i>&nbsp;<b>/tmp/rescue.log</b></div>
        <div class="sub" style="margin-top:22px">
          <button class="btn dan" type="button" onclick="rebootRouter()">Riavvia Modem</button>
        </div>
      </div>
    </div>

    <!-- Card 6: Log Operativo (Span 3 colonne) -->
    <div class="sc logt">
      <div class="sh">Log Operativo</div>
      <div class="ct" style="min-height:0;padding:10px;font-weight:300">
        <div style="position:relative;z-index:1;display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">
          <span><i class="fa">&#xf120;</i>&nbsp; rescue.log -- live</span>
          <button class="btn" type="button" onclick="clearLogBox()">Pulisci</button>
        </div>
        <div class="fk">
          <pre id="logBox">In attesa di istruzioni...</pre>
          <span class="fa" aria-hidden="true" style="position:absolute;right:14px;bottom:6px;font-size:100px;line-height:1;color:rgba(151,187,151,.14);pointer-events:none">&#xf120;</span>
        </div>
      </div>
    </div>

  </div><!-- /cards -->

  <!-- Footer -->
  <div class="copyright">
    <p>&copy; Technicolor 2026</p>
    <p>Rescue Server MediaAccess &bull; <span style="color:#7a7a00">Porta 8088</span></p>
    <p>Fork e modifiche di <a href="https://github.com/ZioCook/tch-nginx-gui" target="_blank">ZioCook</a> &bull; Codice originale di <a href="https://github.com/Ansuel/tch-nginx-gui" target="_blank">Ansuel</a> e della community.</p>
  </div>

</div><!-- /pg -->

<script>
  var pollInterval = null;

  function appendLog(msg) {
    var box = document.getElementById('logBox');
    box.textContent += '\n' + msg;
    box.scrollTop = box.scrollHeight;
  }

  function clearLogBox() {
    document.getElementById('logBox').textContent = '';
  }

  function pollLogs() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/log', true);
    xhr.onload = function() {
      if (xhr.status === 200 && xhr.responseText) {
        var box = document.getElementById('logBox');
        box.textContent = xhr.responseText;
        box.scrollTop = box.scrollHeight;
      }
    };
    xhr.send();
  }

  function startPolling() {
    if (!pollInterval) {
      pollLogs();
      pollInterval = setInterval(pollLogs, 1500);
    }
  }

  function triggerUsbRecovery() {
    var btn = document.getElementById('btnUsb');
    btn.disabled = true;
    btn.textContent = 'Scansione USB in corso...';
    appendLog('--> Avviata richiesta ripristino Zero-Touch da USB...');
    startPolling();
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/usb_recovery', true);
    xhr.onload = function() {
      try {
        var j = JSON.parse(xhr.responseText);
        appendLog('[SERVER] ' + (j.message || 'Richiesta accettata'));
      } catch(e) {}
      setTimeout(function() {
        btn.disabled = false;
        btn.textContent = 'Avvia Scansione & Flash USB';
      }, 5000);
    };
    xhr.onerror = function() {
      appendLog('[ERRORE] Impossibile contattare il server.');
      btn.disabled = false;
      btn.textContent = 'Avvia Scansione & Flash USB';
    };
    xhr.send();
  }

  function uploadPackage() {
    var fi = document.getElementById('guiFile');
    if (!fi.files || fi.files.length === 0) {
      alert('Seleziona prima un file .tar.bz2 valido dal tuo computer.');
      return;
    }
    var file = fi.files[0];
    var btn = document.getElementById('btnUpload');
    btn.disabled = true;
    btn.textContent = 'Caricamento (' + (file.size / 1024 / 1024).toFixed(1) + ' MB)...';
    appendLog('--> Caricamento del pacchetto: ' + file.name + ' (' + file.size + ' bytes)...');
    startPolling();
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload', true);
    xhr.setRequestHeader('Content-Type', 'application/octet-stream');
    xhr.setRequestHeader('X-Filename', file.name);
    xhr.onload = function() {
      try {
        var j = JSON.parse(xhr.responseText);
        appendLog('[RISULTATO] ' + (j.message || 'Operazione completata'));
      } catch(e) {}
      btn.disabled = false;
      btn.textContent = 'Carica & Ripristina';
    };
    xhr.onerror = function() {
      appendLog('[ERRORE UPLOAD] Errore durante il trasferimento.');
      btn.disabled = false;
      btn.textContent = 'Carica & Ripristina';
    };
    xhr.send(file);
  }

  function restartServices() {
    if (!confirm('Vuoi riavviare i demoni Transformer e Nginx?')) return;
    appendLog('--> Richiesta riavvio dei servizi web...');
    startPolling();
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/restart_services', true);
    xhr.send();
  }

  function rebootRouter() {
    if (!confirm('Confermi il riavvio completo del router?')) return;
    appendLog('--> Richiesta riavvio modem inviata...');
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/reboot', true);
    xhr.send();
  }

  startPolling();
</script>
</body>
</html>
]]
end

-- Read request headers
local function parse_headers(client)
    local headers = {}
    while true do
        local line, err = client:receive("*l")
        if not line or line == "" or line == "\r" then break end
        local k, v = line:match("^([^:]+):%s*(.*)")
        if k and v then
            headers[k:lower()] = v:gsub("[\r\n]", "")
        end
    end
    return headers
end

-- Send HTTP response
local function send_response(client, status_code, content_type, body)
    local status_text = "OK"
    if status_code == 404 then status_text = "Not Found"
    elseif status_code == 400 then status_text = "Bad Request"
    elseif status_code == 500 then status_text = "Internal Server Error"
    end

    local resp = string.format("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
        status_code, status_text, content_type, #body, body)
    client:send(resp)
end

-- Stream and extract uploaded recovery package
local function handle_upload(client, headers)
    local content_length = tonumber(headers["content-length"] or 0)
    if content_length <= 0 then
        return send_response(client, 400, "application/json", '{"status":"error","message":"Dimensione file non valida"}')
    end

    log(string.format("Ricezione upload pacchetto di emergenza: %d bytes...", content_length))

    local out_f, err = io.open(UPLOAD_TEMP, "wb")
    if not out_f then
        log("Errore apertura file temporaneo: " .. tostring(err))
        return send_response(client, 500, "application/json", '{"status":"error","message":"Errore apertura storage temporaneo"}')
    end

    local remaining = content_length
    local chunk_size = 65536
    while remaining > 0 do
        local to_read = math.min(chunk_size, remaining)
        local chunk, rerr = client:receive(to_read)
        if not chunk then
            out_f:close()
            os.remove(UPLOAD_TEMP)
            log("Errore lettura chunk upload: " .. tostring(rerr))
            return send_response(client, 400, "application/json", '{"status":"error","message":"Trasferimento interrotto"}')
        end
        out_f:write(chunk)
        remaining = remaining - #chunk
    end
    out_f:close()

    log("Upload completato con successo. Validazione integrità bzcat...")
    local test_res = os.execute("bzcat " .. UPLOAD_TEMP .. " >/dev/null 2>&1")
    if test_res ~= 0 then
        os.remove(UPLOAD_TEMP)
        log("ERRORE: Il file caricato non è un archivio .tar.bz2 integro!")
        return send_response(client, 400, "application/json", '{"status":"error","message":"Archivio corrotto o non valido"}')
    end

    -- Rename to permanent target
    os.remove(RECOVERY_TARGET)
    os.rename(UPLOAD_TEMP, RECOVERY_TARGET)
    log("Archivio convalidato. Inizio estrazione su filesystem principale (/).")

    -- Run extraction and postreq asynchronously
    local cmd = string.format("bzcat %s | tar -C / -xf - >> %s 2>&1 && /etc/init.d/rootdevice force >> %s 2>&1 &",
        RECOVERY_TARGET, LOG_FILE, LOG_FILE)
    os.execute(cmd)

    return send_response(client, 200, "application/json", '{"status":"ok","message":"Estrazione avviata con successo! Segui il log per i dettagli."}')
end

-- Process incoming connection
local function handle_client(client)
    client:settimeout(15) -- 15s timeout for operations
    local req_line, err = client:receive("*l")
    if not req_line then
        client:close()
        return
    end

    local method, uri = req_line:match("^(%a+)%s+(%S+)")
    if not method or not uri then
        client:close()
        return
    end

    local headers = parse_headers(client)

    if (method == "GET" or method == "HEAD") and (uri == "/" or uri == "/index.html") then
        send_response(client, 200, "text/html; charset=utf-8", render_html())
    elseif (method == "GET" or method == "HEAD") and uri == "/log" then
        local log_data = read_file(LOG_FILE)
        send_response(client, 200, "text/plain; charset=utf-8", log_data)
    elseif (method == "GET" or method == "HEAD") and uri:match("^/fonts/") then
        local font_name = uri:match("^/fonts/([%w%._%-]+)$")
        local font_path = font_name and ("/www/docroot/fonts/" .. font_name)
        local font_data = font_path and read_file(font_path)
        if font_data and #font_data > 0 then
            local mime = uri:match("%.woff2$") and "font/woff2" or "font/woff"
            send_response(client, 200, mime, font_data)
        else
            send_response(client, 404, "text/plain", "Font Not Found")
        end
        local log_data = read_file(LOG_FILE)
        send_response(client, 200, "text/plain; charset=utf-8", log_data)
    elseif method == "POST" and uri == "/usb_recovery" then
        log("Avvio del motore di ripristino Zero-Touch USB...")
        os.execute("/usr/bin/rescue-usb.sh &")
        send_response(client, 200, "application/json", '{"status":"started","message":"Scansione periferiche USB avviata."}')
    elseif method == "POST" and uri == "/upload" then
        handle_upload(client, headers)
    elseif method == "POST" and uri == "/restart_services" then
        log("Richiesta riavvio servizi web ricevuta.")
        os.execute("/etc/init.d/transformer restart >/dev/null 2>&1; /etc/init.d/nginx restart >/dev/null 2>&1 &")
        send_response(client, 200, "application/json", '{"status":"ok","message":"Servizi web riavviati."}')
    elseif method == "POST" and uri == "/reboot" then
        log("Richiesta riavvio router ricevuta. Riavvio tra 1 secondo.")
        os.execute("sleep 1 && /sbin/reboot &")
        send_response(client, 200, "application/json", '{"status":"ok","message":"Riavvio del router in corso..."}')
    else
        send_response(client, 404, "text/plain", "Not Found")
    end

    client:close()
end

-- Server entry point
local function main()
    local port = tonumber(arg[1]) or DEFAULT_PORT

    log("Inizializzazione Standalone Rescue Server...")
    local server, err = socket.bind("0.0.0.0", port)
    if not server then
        log(string.format("Impossibile associare alla porta %d: %s. Tentativo su porta alternativa %d...", port, tostring(err), DEFAULT_PORT))
        server, err = socket.bind("0.0.0.0", DEFAULT_PORT)
        if not server then
            log("FATALE: Impossibile avviare il rescue server: " .. tostring(err))
            os.exit(1)
        end
        port = DEFAULT_PORT
    end

    server:settimeout(1)
    log(string.format("Rescue Server attivo e in ascolto su http://0.0.0.0:%d", port))

    while true do
        local client, accept_err = server:accept()
        if client then
            local ok, client_err = pcall(handle_client, client)
            if not ok then
                log("Errore gestione client: " .. tostring(client_err))
                pcall(function() client:close() end)
            end
        end
    end
end

main()
