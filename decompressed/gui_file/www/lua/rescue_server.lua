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

-- Render the Standalone Recovery HTML Webpage
local function render_html()
    local s = get_system_summary()
    local nginx_badge = s.nginx_running and '<span class="badge badge-ok">Attivo</span>' or '<span class="badge badge-fail">Non attivo</span>'
    local trans_badge = s.trans_running and '<span class="badge badge-ok">Attivo</span>' or '<span class="badge badge-fail">Non attivo</span>'

    return [[<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rescue Console &#8212; Technicolor Gateway</title>
  <style>
    :root {
      --navy:   #003087;
      --blue:   #005DAA;
      --blue-h: #004d92;
      --red:    #CC0000;
      --red-h:  #aa0000;
      --green:  #007A3D;
      --bg:     #F2F4F7;
      --white:  #FFFFFF;
      --border: #D8DCE6;
      --text:   #1A1A2E;
      --muted:  #6B7280;
      --shadow: 0 1px 4px rgba(0,0,0,.10);
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; font-size: 14px; background: var(--bg); color: var(--text); }
    .header { background: var(--navy); padding: 0 32px; height: 56px; display: flex; align-items: center; justify-content: space-between; }
    .header-brand { display: flex; align-items: center; gap: 14px; }
    .header-logo { font-size: 1.25rem; font-weight: 700; letter-spacing: -0.5px; color: #FFFFFF; }
    .header-logo span { color: #78B9E7; }
    .header-sep { width: 1px; height: 22px; background: rgba(255,255,255,.25); }
    .header-subtitle { font-size: 0.75rem; color: rgba(255,255,255,.70); letter-spacing: 0.5px; text-transform: uppercase; }
    .badge { display: inline-flex; align-items: center; gap: 5px; font-size: 0.68rem; font-weight: 700; letter-spacing: 0.5px; padding: 3px 10px; border-radius: 3px; text-transform: uppercase; }
    .badge-rescue { background: var(--red); color: #fff; }
    .badge-ok { background: #D1FAE5; color: var(--green); }
    .badge-fail { background: #FEE2E2; color: var(--red); }
    .page { max-width: 1020px; margin: 28px auto; padding: 0 20px 40px; }
    .section-title { font-size: 0.7rem; font-weight: 700; letter-spacing: 1px; text-transform: uppercase; color: var(--muted); margin-bottom: 12px; padding-bottom: 6px; border-bottom: 1px solid var(--border); }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin-bottom: 28px; }
    .card { background: var(--white); border: 1px solid var(--border); border-radius: 8px; padding: 22px; box-shadow: var(--shadow); }
    .card-title { display: flex; align-items: center; gap: 8px; font-size: 0.9rem; font-weight: 700; color: var(--text); margin-bottom: 8px; }
    .card-title svg { flex-shrink: 0; }
    .card-desc { font-size: 0.82rem; color: var(--muted); margin-bottom: 16px; line-height: 1.5; }
    .card-desc code { font-size: 0.78rem; background: var(--bg); border: 1px solid var(--border); border-radius: 3px; padding: 1px 5px; }
    .info-list { list-style: none; margin-bottom: 16px; }
    .info-list li { display: flex; justify-content: space-between; align-items: center; padding: 7px 0; border-bottom: 1px solid var(--border); font-size: 0.82rem; }
    .info-list li:last-child { border-bottom: none; }
    .info-list .label { color: var(--muted); }
    .info-list .value { font-weight: 600; color: var(--text); }
    .btn { display: inline-block; width: 100%; padding: 9px 16px; font-size: 0.82rem; font-weight: 700; text-align: center; border: none; border-radius: 5px; cursor: pointer; transition: background .15s, opacity .15s; }
    .btn-blue { background: var(--blue); color: #fff; }
    .btn-blue:hover { background: var(--blue-h); }
    .btn-red { background: var(--red); color: #fff; }
    .btn-red:hover { background: var(--red-h); }
    .btn-outline { background: transparent; color: var(--blue); border: 1.5px solid var(--blue); }
    .btn-outline:hover { background: #EBF2FB; }
    .btn:disabled { opacity: .45; cursor: not-allowed; }
    .btn-row { display: flex; gap: 10px; }
    .btn-row .btn { width: auto; flex: 1; }
    .file-wrap { margin-bottom: 12px; }
    input[type="file"] { width: 100%; padding: 7px 10px; background: var(--bg); border: 1.5px dashed var(--border); border-radius: 5px; color: var(--text); font-size: 0.8rem; }
    .terminal-wrap { background: #0D1117; border: 1px solid #30363D; border-radius: 8px; overflow: hidden; box-shadow: var(--shadow); }
    .terminal-bar { display: flex; align-items: center; justify-content: space-between; padding: 8px 16px; background: #161B22; border-bottom: 1px solid #30363D; }
    .terminal-bar-dots { display: flex; gap: 6px; }
    .terminal-bar-dots span { width: 11px; height: 11px; border-radius: 50%; }
    .dot-r { background: #FF5F57; } .dot-y { background: #FFBD2E; } .dot-g { background: #28C840; }
    .terminal-label { font-size: 0.72rem; color: #8B949E; letter-spacing: 0.5px; }
    .terminal-clear { background: none; border: none; color: #58A6FF; font-size: 0.75rem; cursor: pointer; }
    .terminal-clear:hover { text-decoration: underline; }
    pre#logBox { padding: 14px 18px; margin: 0; background: transparent; color: #3FB950; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 0.78rem; line-height: 1.6; height: 240px; overflow-y: auto; white-space: pre-wrap; word-break: break-all; }
  </style>
</head>
<body>
  <div class="header">
    <div class="header-brand">
      <div class="header-logo">Techni<span>color</span></div>
      <div class="header-sep"></div>
      <div class="header-subtitle">Gateway Recovery Console</div>
    </div>
    <span class="badge badge-rescue">&#9888; Modalit&agrave; Emergenza</span>
  </div>
  <div class="page">
    <p class="section-title">Strumenti di Ripristino</p>
    <div class="grid">
      <div class="card">
        <div class="card-title">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#005DAA" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v8M8 6l4-4 4 4"/><rect x="7" y="10" width="10" height="8" rx="2"/><path d="M9 18v2M15 18v2M9 20h6"/></svg>
          Ripristino Zero-Touch USB
        </div>
        <p class="card-desc">Inserisci una chiavetta USB con il file <code>ziocook-gui-recovery.tar.bz2</code> o <code>GUI.tar.bz2</code> nella porta USB del gateway e avvia la scansione automatica.</p>
        <button id="btnUsb" class="btn btn-blue" onclick="triggerUsbRecovery()">Avvia Scansione &amp; Flash USB</button>
      </div>
      <div class="card">
        <div class="card-title">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#005DAA" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
          Caricamento Pacchetto da PC
        </div>
        <p class="card-desc">Seleziona un pacchetto <code>GUI.tar.bz2</code> salvato sul tuo computer per eseguire il ripristino manuale.</p>
        <div class="file-wrap"><input type="file" id="guiFile" accept=".tar.bz2,.bz2"></div>
        <button id="btnUpload" class="btn btn-blue" onclick="uploadPackage()">Carica &amp; Ripristina</button>
      </div>
      <div class="card">
        <div class="card-title">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#005DAA" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
          Stato del Sistema
        </div>
        <ul class="info-list">
          <li><span class="label">Hardware</span><span class="value">]] .. s.hardware .. [[</span></li>
          <li><span class="label">Nginx</span>]] .. nginx_badge .. [[</li>
          <li><span class="label">Transformer</span>]] .. trans_badge .. [[</li>
          <li><span class="label">Memoria RAM</span><span class="value">]] .. s.mem .. [[</span></li>
          <li><span class="label">Uptime</span><span class="value">]] .. s.uptime .. [[</span></li>
        </ul>
        <div class="btn-row">
          <button class="btn btn-outline" onclick="restartServices()">Riavvia Servizi</button>
          <button class="btn btn-red" onclick="rebootRouter()">Riavvia Modem</button>
        </div>
      </div>
    </div>
    <p class="section-title">Log Operativo</p>
    <div class="terminal-wrap">
      <div class="terminal-bar">
        <div class="terminal-bar-dots">
          <span class="dot-r"></span><span class="dot-y"></span><span class="dot-g"></span>
        </div>
        <span class="terminal-label">rescue.log -- live</span>
        <button class="terminal-clear" onclick="clearLogBox()">Pulisci</button>
      </div>
      <pre id="logBox">In attesa di istruzioni...</pre>
    </div>
  </div>
  <script>
    var pollInterval = null;
    function appendLog(msg) {
      var box = document.getElementById('logBox');
      box.textContent += '\n' + msg;
      box.scrollTop = box.scrollHeight;
    }
    function clearLogBox() { document.getElementById('logBox').textContent = ''; }
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
      if (!pollInterval) { pollLogs(); pollInterval = setInterval(pollLogs, 1500); }
    }
    function triggerUsbRecovery() {
      var btn = document.getElementById('btnUsb');
      btn.disabled = true; btn.textContent = 'Scansione USB in corso...';
      appendLog('--> Avviata richiesta ripristino Zero-Touch da USB...');
      startPolling();
      var xhr = new XMLHttpRequest();
      xhr.open('POST', '/usb_recovery', true);
      xhr.onload = function() {
        try { var j = JSON.parse(xhr.responseText); appendLog('[SERVER] ' + (j.message || 'Richiesta accettata')); } catch(e) {}
        setTimeout(function() { btn.disabled = false; btn.textContent = 'Avvia Scansione & Flash USB'; }, 5000);
      };
      xhr.onerror = function() { appendLog('[ERRORE] Impossibile contattare il server.'); btn.disabled = false; btn.textContent = 'Avvia Scansione & Flash USB'; };
      xhr.send();
    }
    function uploadPackage() {
      var fi = document.getElementById('guiFile');
      if (!fi.files || fi.files.length === 0) { alert('Seleziona prima un file .tar.bz2.'); return; }
      var file = fi.files[0];
      var btn = document.getElementById('btnUpload');
      btn.disabled = true; btn.textContent = 'Caricamento (' + (file.size/1024/1024).toFixed(1) + ' MB)...';
      appendLog('--> Caricamento: ' + file.name + ' (' + file.size + ' bytes)...');
      startPolling();
      var xhr = new XMLHttpRequest();
      xhr.open('POST', '/upload', true);
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');
      xhr.setRequestHeader('X-Filename', file.name);
      xhr.onload = function() {
        try { var j = JSON.parse(xhr.responseText); appendLog('[RISULTATO] ' + (j.message || 'Completato')); } catch(e) {}
        btn.disabled = false; btn.textContent = 'Carica & Ripristina';
      };
      xhr.onerror = function() { appendLog('[ERRORE UPLOAD] Errore di rete.'); btn.disabled = false; btn.textContent = 'Carica & Ripristina'; };
      xhr.send(file);
    }
    function restartServices() {
      if (!confirm('Vuoi riavviare i demoni Transformer e Nginx?')) return;
      appendLog('--> Richiesta riavvio dei servizi web...'); startPolling();
      var xhr = new XMLHttpRequest(); xhr.open('POST', '/restart_services', true); xhr.send();
    }
    function rebootRouter() {
      if (!confirm('Confermi il riavvio completo del router?')) return;
      appendLog('--> Richiesta riavvio modem inviata...');
      var xhr = new XMLHttpRequest(); xhr.open('POST', '/reboot', true); xhr.send();
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
