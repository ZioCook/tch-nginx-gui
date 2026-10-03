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

    -- Short Kernel Version
    local f_ver = io.open("/proc/version", "r")
    if f_ver then
        local line = f_ver:read("*l") or "Linux"
        f_ver:close()
        summary.kernel = line:match("Linux%s+version%s+([%w%._%-]+)") or line:match("^(Linux%s+[%w%._%-]+)") or "Linux 4.1.52"
    else
        summary.kernel = "Linux"
    end

    -- Real Installed GUI Version (matches the real GUI from /etc/init.d/rootdevice)
    summary.gui_version = "Non rilevata / Corrotta"
    local f_rootdev = io.open("/etc/init.d/rootdevice", "r")
    if f_rootdev then
        for l in f_rootdev:lines() do
            local ver = l:match("version_gui=([^%s]+)")
            if ver and ver ~= "" then
                summary.gui_version = ver
                break
            end
        end
        f_rootdev:close()
    end
    if summary.gui_version == "Non rilevata / Corrotta" then
        local f_modgui = io.open("/etc/config/modgui", "r")
        if f_modgui then
            local text = f_modgui:read("*a") or ""
            f_modgui:close()
            local ver_match = text:match('option%s+version%s+[\'"]([^%s\'"]+)') or text:match('option%s+version%s+([%w%._%-]+)')
            if ver_match and ver_match ~= "" then
                summary.gui_version = ver_match
            end
        end
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

-- Render the Standalone Recovery HTML Webpage (Theme Green - Authentic Height & Interactive Root Shell)
local function render_html()
    local s = get_system_summary()
    local nginx_status = s.nginx_running and '<span class="light green"></span><strong>Nginx:</strong> Attivo (Porta 80)' or '<span class="light red"></span><strong>Nginx:</strong> Non attivo'
    local trans_status = s.trans_running and '<span class="light green"></span><strong>Transformer:</strong> Attivo' or '<span class="light red"></span><strong>Transformer:</strong> Non attivo'

    return [[<!DOCTYPE HTML>
<html lang="it">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>Rescue Console &mdash; Technicolor Gateway</title>
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
    .header-button {
      display: flex;
      flex-wrap: wrap;
      justify-content: flex-end;
      align-items: center;
      gap: 10px;
    }
    .header .btn {
      background: #fff;
      padding: 7px 18px;
      box-shadow: none;
      border: 1px solid #c6bec9;
      border-radius: 4px;
      color: #333;
      font-weight: 500;
      text-shadow: none;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      height: 36px;
      box-sizing: border-box;
      font-size: 14px;
      cursor: default;
    }
    .header .btn:hover {
      background: #f5f5f5;
      border: 1px solid #c6bec9;
      color: #333;
    }
    .header-btn-badge {
      background: #fcf0d0 !important;
      border-color: #e0a030 !important;
      color: #6b4000 !important;
      font-weight: 700 !important;
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

    /* Card Styling */
    .sc {
      position: relative;
      display: flex;
      flex-direction: column;
      background: #fff;
      overflow: hidden;
      font-size: 14px;
      border-radius: 2px;
      border: 1px solid #c6bec9;
      box-shadow: 0 2px 20px 0px rgba(56, 132, 56, 0.65);
      height: 100%;
    }

    /* Card Header - Thick, Bold Technicolor Green Gradient (Identical to Original GUI) */
    .sh {
      min-height: 46px;
      padding: 10px 16px;
      font-size: 18px;
      line-height: 24px;
      font-weight: bold;
      color: #fff;
      text-shadow: 0 1px 1px #000;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      background-color: rgb(30, 116, 30);
      background-image: linear-gradient(to bottom, rgb(30, 116, 30) 20%, rgb(29, 36, 29) 100%);
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
      min-height: 175px;
      padding: 16px;
      font-weight: 500;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }

    /* Discreet Watermarks (Non-overlapping) */
    .bgi {
      position: absolute;
      right: 6px;
      bottom: 40px;
      z-index: 0;
      font-size: 110px;
      line-height: 1;
      color: rgba(151, 187, 151, 0.16);
      pointer-events: none;
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
      display: inline-block;
      width: 100%;
      padding: 8px 14px;
      font-size: 14px;
      line-height: 20px;
      font-weight: bold;
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
    pre#logBox {
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
      height: 34px;
      padding: 4px 10px;
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
      height: 34px;
      padding: 6px 16px !important;
      margin: 0 !important;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }

    /* Clean Styled File Input */
    input[type="file"] {
      display: block;
      width: 100%;
      box-sizing: border-box;
      margin-bottom: 12px;
      padding: 6px 8px;
      font-size: 12px;
      background: #fafafa;
      border: 1px solid #c6bec9;
      border-radius: 4px;
      color: #333;
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

    /* Responsive Breakpoints */
    @media (max-width: 1050px) {
      .cards-grid { grid-template-columns: repeat(2, 1fr); }
      .logt { grid-column: 1 / -1; }
    }
    @media (max-width: 620px) {
      .cards-grid { grid-template-columns: 1fr; }
      .header { flex-direction: column; align-items: flex-start; gap: 14px; }
      .container { padding: 0 12px 30px; }
    }
  </style>
</head>
<body>

<!-- Technicolor Green Globe Watermark -->
<div class="gateway_bg"></div>

<div class="container">

  <!-- Header with Technicolor Logo and Status Badge -->
  <div class="header">
    <div class="header-logo">
      <a href="https://www.technicolor.com" target="_blank" title="Technicolor Gateway">
        <img width="131px" height="50px" alt="Technicolor" src="data:image/png;base64,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">
      </a>
    </div>
    <div class="header-button">
      <div class="btn header-btn-badge">
        <i class="fa fa-exclamation-triangle"></i> Modalit&agrave; Emergenza
      </div>
      <div class="btn">
        <i class="fa fa-wrench"></i> Gateway Recovery Console
      </div>
    </div>
  </div>

  <!-- Warning Alert Banner -->
  <div class="alert">
    <i class="fa fa-exclamation-triangle" style="margin-right: 6px;"></i>
    <strong>Modalit&agrave; di Emergenza Attiva:</strong> Console di gestione Out-of-Band attiva sulla porta <strong>8088</strong> &bull; Operativa indipendentemente dallo stato di Nginx e Transformer.
  </div>

  <!-- Perfectly Balanced 4-Column Grid: 4 cards on row 1, 1 card + 3-col terminal on row 2 -->
  <div class="cards-grid">

    <!-- Card 1: Stato del Sistema -->
    <div class="sc">
      <div class="sh">Stato del Sistema</div>
      <div class="ct">
        <span class="bgi fa">&#xf129;</span>
        <div>
          <div class="li"><i class="fa fa-microchip"></i> <strong>Modello:</strong> ]] .. s.hardware .. [[</div>
          <div class="li"><i class="fa fa-code-branch"></i> <strong>Versione GUI:</strong> <span style="color:rgb(30,116,30);font-weight:bold;">]] .. s.gui_version .. [[</span></div>
          <div class="li"><i class="fa fa-memory"></i> <strong>RAM:</strong> ]] .. s.mem .. [[</div>
          <div class="li"><i class="fa fa-clock"></i> <strong>Uptime:</strong> ]] .. s.uptime .. [[</div>
        </div>
        <div class="sub" style="margin-top: 10px; margin-bottom: 0;">
          <i class="fa fa-shield-alt"></i> Kernel: ]] .. s.kernel .. [[
        </div>
      </div>
    </div>

    <!-- Card 2: Servizi Web -->
    <div class="sc">
      <div class="sh">Servizi Web</div>
      <div class="ct">
        <span class="bgi fa">&#xf233;</span>
        <div>
          <div class="li">]] .. nginx_status .. [[</div>
          <div class="li">]] .. trans_status .. [[</div>
          <div class="sub" style="margin-top: 10px; margin-bottom: 14px;">Nginx e Transformer gestiscono l'accesso web primario (porta 80).</div>
        </div>
        <div>
          <button class="btn-action btn-default" type="button" onclick="restartServices()">
            <i class="fa fa-sync-alt"></i> Riavvia Servizi
          </button>
        </div>
      </div>
    </div>

    <!-- Card 3: Ripristino Zero-Touch USB -->
    <div class="sc">
      <div class="sh">Ripristino USB</div>
      <div class="ct">
        <span class="bgi fb">&#xf287;</span>
        <div class="sub" style="margin-bottom: 16px;">
          Inserisci una chiavetta USB con il pacchetto di ripristino della GUI per avviare il flashing automatico.
        </div>
        <div>
          <button id="btnUsb" class="btn-action btn-primary" type="button" onclick="triggerUsbRecovery()">
            <i class="fa fa-play"></i> Flash da USB
          </button>
        </div>
      </div>
    </div>

    <!-- Card 4: Caricamento Pacchetto da PC -->
    <div class="sc">
      <div class="sh">Carica Pacchetto</div>
      <div class="ct">
        <span class="bgi fa">&#xf093;</span>
        <div class="sub" style="margin-bottom: 8px;">
          Seleziona il pacchetto di ripristino dal computer:
        </div>
        <input id="guiFile" type="file" accept=".tar.bz2,.bz2">
        <div>
          <button id="btnUpload" class="btn-action btn-primary" type="button" onclick="uploadPackage()">
            <i class="fa fa-upload"></i> Carica &amp; Flash
          </button>
        </div>
      </div>
    </div>

    <!-- Card 5: Gestione Modem (Row 2, Column 1) -->
    <div class="sc">
      <div class="sh">Gestione Modem</div>
      <div class="ct">
        <span class="bgi fa">&#xf011;</span>
        <div>
          <div class="li"><i class="fa fa-network-wired"></i> <strong>Porta rescue:</strong> 8088</div>
          <div class="li"><i class="fa fa-file-alt"></i> <strong>Log:</strong> /tmp/rescue.log</div>
          <div class="sub" style="margin-top: 10px; margin-bottom: 14px;">Riavvio hardware a basso livello del gateway.</div>
        </div>
        <div>
          <button class="btn-action btn-danger" type="button" onclick="rebootRouter()">
            <i class="fa fa-power-off"></i> Riavvia Modem
          </button>
        </div>
      </div>
    </div>

    <!-- Card 6: Log Operativo & Shell Root Interattiva (Row 2, Columns 2, 3, 4 - Spans 3 Columns) -->
    <div class="sc logt">
      <div class="sh">
        <span><i class="fa fa-terminal"></i> Log Operativo Live &amp; Shell Root (/tmp/rescue.log)</span>
        <button class="btn-clear" type="button" onclick="clearLogBox()"><i class="fa fa-eraser"></i> Pulisci Schermo</button>
      </div>
      <div class="ct" style="min-height: auto; padding: 14px;">
        <div class="fake_console">
          <pre id="logBox">In attesa di istruzioni...</pre>
        </div>
        <!-- Interactive Root Shell Command Bar -->
        <form class="shell-bar" onsubmit="execShellCommand(event)">
          <span class="shell-prompt">root@rescue:~#</span>
          <input type="text" id="shellInput" class="shell-input" placeholder="Esegui comando shell root (es. ls -la, df -h, free -m, /etc/init.d/nginx restart)..." autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">
          <button type="submit" id="btnShell" class="btn-action btn-primary shell-btn">
            <i class="fa fa-play"></i> Invia
          </button>
        </form>
      </div>
    </div>

  </div><!-- /cards-grid -->

  <!-- Footer showing current GUI version -->
  <div class="copyright">
    <p>&copy; Technicolor &bull; MediaAccess DGA4331 Rescue Console (Porta 8088)</p>
    <p>Versione GUI rilevata sul router: <strong>]] .. s.gui_version .. [[</strong></p>
  </div>

</div><!-- /container -->

<script>
  var pollInterval = null;

  function appendLog(msg) {
    var box = document.getElementById('logBox');
    box.textContent += '\n' + msg;
    box.scrollTop = box.scrollHeight;
  }

  function clearLogBox() {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/clear_log', true);
    xhr.onload = function() {
      document.getElementById('logBox').textContent = '[LOG RESETTATO]';
    };
    xhr.send();
  }

  function pollLogs() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/log', true);
    xhr.onload = function() {
      if (xhr.status === 200 && xhr.responseText !== null) {
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

  function execShellCommand(event) {
    event.preventDefault();
    var inp = document.getElementById('shellInput');
    var btn = document.getElementById('btnShell');
    var cmd = inp.value.trim();
    if (!cmd) return;

    btn.disabled = true;
    appendLog('root@rescue:~# ' + cmd);
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/exec', true);
    xhr.setRequestHeader('Content-Type', 'text/plain; charset=utf-8');
    xhr.onload = function() {
      btn.disabled = false;
      inp.value = '';
      inp.focus();
      try {
        var j = JSON.parse(xhr.responseText);
        if (j.output) {
          appendLog(j.output);
        }
      } catch(e) {
        pollLogs();
      }
    };
    xhr.onerror = function() {
      btn.disabled = false;
      appendLog('[ERRORE] Impossibile eseguire il comando.');
    };
    xhr.send(cmd);
  }

  function triggerUsbRecovery() {
    var btn = document.getElementById('btnUsb');
    btn.disabled = true;
    btn.innerHTML = '<i class="fa fa-spinner fa-spin"></i> Scansione USB...';
    appendLog('--> Avviata richiesta ripristino da USB...');
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
        btn.innerHTML = '<i class="fa fa-play"></i> Flash da USB';
      }, 5000);
    };
    xhr.onerror = function() {
      appendLog('[ERRORE] Impossibile contattare il server.');
      btn.disabled = false;
      btn.innerHTML = '<i class="fa fa-play"></i> Flash da USB';
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
    btn.innerHTML = '<i class="fa fa-spinner fa-spin"></i> Caricamento (' + (file.size / 1024 / 1024).toFixed(1) + ' MB)...';
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
      btn.innerHTML = '<i class="fa fa-upload"></i> Carica &amp; Flash';
    };
    xhr.onerror = function() {
      appendLog('[ERRORE UPLOAD] Errore durante il trasferimento.');
      btn.disabled = false;
      btn.innerHTML = '<i class="fa fa-upload"></i> Carica &amp; Flash';
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
    elseif method == "POST" and uri == "/clear_log" then
        local f = io.open(LOG_FILE, "w")
        if f then f:close() end
        log("Log della rescue console azzerato dall'operatore.")
        send_response(client, 200, "application/json", '{"status":"ok","message":"Log azzerato"}')
    elseif method == "POST" and uri == "/exec" then
        local content_length = tonumber(headers["content-length"] or 0)
        local cmd = ""
        if content_length > 0 then
            cmd = client:receive(content_length) or ""
        end
        cmd = cmd:match("^%s*(.-)%s*$")
        if not cmd or cmd == "" then
            send_response(client, 400, "application/json", '{"status":"error","message":"Comando vuoto"}')
        else
            log(string.format("[SHELL] # %s", cmd))
            local pipe = io.popen(cmd .. " 2>&1")
            local output = ""
            if pipe then
                output = pipe:read("*a") or ""
                pipe:close()
            end
            if output ~= "" then
                log(string.format("%s", output))
            else
                log("(Nessun output restituito)")
            end
            -- JSON escape
            local escaped_out = output:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", ""):gsub("\n", "\\n")
            send_response(client, 200, "application/json", string.format('{"status":"ok","output":"%s"}', escaped_out))
        end
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
