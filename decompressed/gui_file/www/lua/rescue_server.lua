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
    local nginx_badge = s.nginx_running and '<span class="badge badge-ok">Attivo (Porta 80)</span>' or '<span class="badge badge-fail">NON ATTIVO (In Crash/Down)</span>'
    local trans_badge = s.trans_running and '<span class="badge badge-ok">Attivo</span>' or '<span class="badge badge-fail">NON ATTIVO</span>'

    return [[<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Console di Emergenza & Recovery - ZioCook GUI</title>
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --border: #334155;
      --text: #f8fafc;
      --muted: #94a3b8;
      --primary: #38bdf8;
      --primary-hover: #0284c7;
      --danger: #ef4444;
      --danger-hover: #dc2626;
      --success: #22c55e;
      --warning: #f59e0b;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
    body { background-color: var(--bg); color: var(--text); padding: 20px; line-height: 1.5; }
    .container { max-width: 960px; margin: 0 auto; }
    .header { display: flex; align-items: center; justify-content: space-between; border-bottom: 2px solid var(--border); padding-bottom: 16px; margin-bottom: 24px; }
    .header h1 { font-size: 1.6rem; color: var(--primary); display: flex; align-items: center; gap: 10px; }
    .badge { font-size: 0.75rem; font-weight: 700; padding: 4px 10px; border-radius: 9999px; text-transform: uppercase; }
    .badge-ok { background: rgba(34, 197, 94, 0.2); color: var(--success); border: 1px solid var(--success); }
    .badge-fail { background: rgba(239, 68, 68, 0.2); color: var(--danger); border: 1px solid var(--danger); }
    .badge-rescue { background: rgba(245, 158, 11, 0.2); color: var(--warning); border: 1px solid var(--warning); }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin-bottom: 24px; }
    .card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }
    .card h2 { font-size: 1.15rem; margin-bottom: 12px; color: var(--primary); display: flex; align-items: center; gap: 8px; }
    .card p { font-size: 0.9rem; color: var(--muted); margin-bottom: 16px; }
    .info-list { list-style: none; font-size: 0.85rem; }
    .info-list li { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }
    .info-list li span:first-child { color: var(--muted); }
    .btn { display: inline-block; width: 100%; padding: 10px 16px; font-size: 0.9rem; font-weight: 600; text-align: center; border: none; border-radius: 8px; cursor: pointer; transition: 0.2s; }
    .btn-primary { background: var(--primary); color: #000; }
    .btn-primary:hover { background: var(--primary-hover); }
    .btn-danger { background: var(--danger); color: #fff; }
    .btn-danger:hover { background: var(--danger-hover); }
    .btn-secondary { background: var(--border); color: var(--text); }
    .btn-secondary:hover { background: #475569; }
    .btn:disabled { opacity: 0.5; cursor: not-allowed; }
    .file-input-wrapper { margin-bottom: 12px; }
    input[type="file"] { width: 100%; padding: 8px; background: #0f172a; border: 1px dashed var(--border); border-radius: 6px; color: var(--text); font-size: 0.85rem; }
    .console-wrapper { background: #000; border: 1px solid var(--border); border-radius: 12px; padding: 16px; margin-top: 16px; }
    .console-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; font-size: 0.85rem; color: var(--muted); }
    pre#logBox { background: transparent; color: #4ade80; font-family: monospace; font-size: 0.8rem; height: 260px; overflow-y: auto; white-space: pre-wrap; word-break: break-all; padding: 4px; }
    .actions-bar { display: flex; gap: 12px; margin-top: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div>
        <h1>Rescue Console (Out-of-Band)</h1>
        <p style="font-size: 0.85rem; color: var(--muted); margin-top: 4px;">Server di Ripristino autonomo LuaSocket (Immune a crash di Nginx/Transformer)</p>
      </div>
      <div>
        <span class="badge badge-rescue">Modalit&agrave; Emergenza</span>
      </div>
    </div>

    <div class="grid">
      <!-- Card 1: Ripristino da USB -->
      <div class="card">
        <h2>&#128190; Ripristino Zero-Touch USB</h2>
        <p>Inserisci una chiavetta USB con il file <code>ziocook-gui-recovery.tar.bz2</code> o <code>GUI.tar.bz2</code> nella porta USB del modem.</p>
        <button id="btnUsb" class="btn btn-primary" onclick="triggerUsbRecovery()">Avvia Scansione & Flash USB</button>
      </div>

      <!-- Card 2: Upload Manuale da PC -->
      <div class="card">
        <h2>&#128228; Caricamento Manuale da PC</h2>
        <p>Seleziona un pacchetto <code>GUI.tar.bz2</code> salvato sul tuo computer da ripristinare.</p>
        <div class="file-input-wrapper">
          <input type="file" id="guiFile" accept=".tar.bz2,.bz2">
        </div>
        <button id="btnUpload" class="btn btn-primary" onclick="uploadPackage()">Carica & Esegui Ripristino</button>
      </div>

      <!-- Card 3: Stato Sistema -->
      <div class="card">
        <h2>&#9881; Stato del Sistema</h2>
        <ul class="info-list">
          <li><span>Hardware:</span> <strong>]] .. s.hardware .. [[</strong></li>
          <li><span>Stato Nginx:</span> ]] .. nginx_badge .. [[</li>
          <li><span>Stato Transformer:</span> ]] .. trans_badge .. [[</li>
          <li><span>Memoria RAM:</span> <strong>]] .. s.mem .. [[</strong></li>
          <li><span>Uptime:</span> <strong>]] .. s.uptime .. [[</strong></li>
        </ul>
        <div class="actions-bar">
          <button class="btn btn-secondary" onclick="restartServices()">Riavvia Servizi</button>
          <button class="btn btn-danger" onclick="rebootRouter()">Riavvia Modem</button>
        </div>
      </div>
    </div>

    <!-- Live Console Output Box -->
    <div class="console-wrapper">
      <div class="console-header">
        <span>Log Operativo in Tempo Reale (/tmp/rescue.log)</span>
        <button style="background: none; border: none; color: var(--primary); cursor: pointer;" onclick="clearLogBox()">Pulisci Schermo</button>
      </div>
      <pre id="logBox">In attesa di istruzioni...</pre>
    </div>
  </div>

  <script>
    let pollInterval = null;

    function appendLog(msg) {
      const box = document.getElementById('logBox');
      box.textContent += "\n" + msg;
      box.scrollTop = box.scrollHeight;
    }

    function clearLogBox() {
      document.getElementById('logBox').textContent = "";
    }

    async function pollLogs() {
      try {
        const res = await fetch('/log');
        if (res.ok) {
          const text = await res.text();
          if (text) {
            const box = document.getElementById('logBox');
            box.textContent = text;
            box.scrollTop = box.scrollHeight;
          }
        }
      } catch (e) {
        // server might be restarting
      }
    }

    function startPolling() {
      if (!pollInterval) {
        pollLogs();
        pollInterval = setInterval(pollLogs, 1500);
      }
    }

    async function triggerUsbRecovery() {
      const btn = document.getElementById('btnUsb');
      btn.disabled = true;
      btn.textContent = "Scansione USB in corso...";
      appendLog("--> Avviata richiesta ripristino Zero-Touch da USB...");
      startPolling();

      try {
        const res = await fetch('/usb_recovery', { method: 'POST' });
        const json = await res.json();
        appendLog("[SERVER] " + (json.message || "Richiesta accettata"));
      } catch (e) {
        appendLog("[ERRORE] Impossibile contattare il server: " + e.message);
      } finally {
        setTimeout(() => { btn.disabled = false; btn.textContent = "Avvia Scansione & Flash USB"; }, 5000);
      }
    }

    async function uploadPackage() {
      const fileInput = document.getElementById('guiFile');
      if (!fileInput.files || fileInput.files.length === 0) {
        alert("Seleziona prima un file .tar.bz2 valido dal tuo computer.");
        return;
      }
      const file = fileInput.files[0];
      const btn = document.getElementById('btnUpload');
      btn.disabled = true;
      btn.textContent = "Caricamento (" + (file.size / 1024 / 1024).toFixed(1) + " MB)...";
      appendLog("--> Caricamento del pacchetto: " + file.name + " (" + file.size + " bytes)...");
      startPolling();

      try {
        const res = await fetch('/upload', {
          method: 'POST',
          headers: { 'Content-Type': 'application/octet-stream', 'X-Filename': file.name },
          body: file
        });
        const json = await res.json();
        appendLog("[RISULTATO] " + (json.message || "Operazione completata"));
      } catch (e) {
        appendLog("[ERRORE UPLOAD] " + e.message);
      } finally {
        btn.disabled = false;
        btn.textContent = "Carica & Esegui Ripristino";
      }
    }

    async function restartServices() {
      if (!confirm("Vuoi riavviare i demoni Transformer e Nginx?")) return;
      appendLog("--> Richiesta riavvio dei servizi web...");
      startPolling();
      try {
        await fetch('/restart_services', { method: 'POST' });
      } catch(e) {}
    }

    async function rebootRouter() {
      if (!confirm("Confermi il riavvio completo del router?")) return;
      appendLog("--> Richiesta riavvio modem inviata...");
      try {
        await fetch('/reboot', { method: 'POST' });
      } catch(e) {}
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
