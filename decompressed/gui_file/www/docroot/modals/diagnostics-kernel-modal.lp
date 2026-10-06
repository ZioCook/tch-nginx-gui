--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local string, tonumber, io = string, tonumber, io
local format = string.format

local function trim_val(s)
  local res = (s or ""):match("^%s*(.-)%s*$")
  return res or ""
end

-- Read TCP & Kernel network metrics
local cc_algo = trim_val(content_helper.readfile("/proc/sys/net/ipv4/tcp_congestion_control"))
if cc_algo == "" then cc_algo = "N/A" end

local ct_count = trim_val(content_helper.readfile("/proc/sys/net/netfilter/nf_conntrack_count"))
if ct_count == "" then
  ct_count = trim_val(content_helper.readfile("/proc/sys/net/ipv4/netfilter/ip_conntrack_count"))
end
local ct_max = trim_val(content_helper.readfile("/proc/sys/net/netfilter/nf_conntrack_max"))
if ct_max == "" then
  ct_max = trim_val(content_helper.readfile("/proc/sys/net/ipv4/netfilter/ip_conntrack_max"))
end
if ct_count == "" then ct_count = "0" end
if ct_max == "" then ct_max = "N/A" end

local rmem_max = tonumber(trim_val(content_helper.readfile("/proc/sys/net/core/rmem_max"))) or 0
local wmem_max = tonumber(trim_val(content_helper.readfile("/proc/sys/net/core/wmem_max"))) or 0
local rmem_mb = (rmem_max > 0) and format("%.0f MB", rmem_max / (1024 * 1024)) or "N/A"
local wmem_mb = (wmem_max > 0) and format("%.0f MB", wmem_max / (1024 * 1024)) or "N/A"

local tfo = trim_val(content_helper.readfile("/proc/sys/net/ipv4/tcp_fastopen"))
local tfo_str
if tfo == "3" then
  tfo_str = T"Enabled (Client & Server)"
elseif tfo == "1" then
  tfo_str = T"Enabled (Client only)"
elseif tfo == "2" then
  tfo_str = T"Enabled (Server only)"
elseif tfo == "0" then
  tfo_str = T"Disabled"
else
  tfo_str = T"Not supported on this kernel"
end

local qdisc = trim_val(content_helper.readfile("/proc/sys/net/core/default_qdisc"))
if qdisc == "" then
  qdisc = "pfifo_fast (Default)"
end

-- Dynamic Wi-Fi IRQ affinity detection from /proc/interrupts
local irq_str = "N/A"
local f_irq = io.open("/proc/interrupts", "r")
if f_irq then
  local wifi_irq = nil
  for line in f_irq:lines() do
    local num = line:match("^%s*(%d+):.*wl0")
    if num then
      wifi_irq = num
      break
    end
  end
  f_irq:close()

  if wifi_irq then
    local aff_raw = trim_val(content_helper.readfile("/proc/irq/" .. wifi_irq .. "/smp_affinity"))
    if aff_raw == "1" then
      irq_str = T"Core 0 (Default)"
    elseif aff_raw == "2" then
      irq_str = T"Core 1 (Offloaded)"
    elseif aff_raw == "3" then
      irq_str = T"Core 0 & Core 1 (Shared)"
    elseif aff_raw ~= "" then
      irq_str = "Mask: " .. aff_raw
    end
  end
end

local basic = {
  span = { class = "span5" },
}

ngx.print(ui_helper.createHeader(T"Diagnostics", false, false, 2))
ngx.print('<div class="modal-body update">\n')

local lp = require("web.lp")
lp.setpath("/www/snippets/")
lp.include("tabs-diagnostics.lp")

ngx.print('\
  <form class="form-horizontal" method="post" action="modals/diagnostics-kernel-modal.lp">\
  <fieldset id="diagnostics-kernel-tab">\
    <fieldset>\
      <legend>' .. T"TCP Stack & Socket Buffers" .. '</legend>\
')

local html = {}
html[#html + 1] = ui_helper.createLabel(T"TCP Congestion Algorithm", cc_algo:upper(), basic)
html[#html + 1] = ui_helper.createLabel(T"TCP Max Socket Buffers", rmem_mb .. " (RX) / " .. wmem_mb .. " (TX)", basic)
html[#html + 1] = ui_helper.createLabel(T"TCP Fast Open", tfo_str, basic)

html[#html + 1] = '    </fieldset>\
    <fieldset>\
      <legend>' .. T"Routing & Network Offload" .. '</legend>\
'

html[#html + 1] = ui_helper.createLabel(T"NAT Conntrack Connections", ct_count .. " / " .. ct_max .. " (Max)", basic)
html[#html + 1] = ui_helper.createLabel(T"Queue Discipline (Bufferbloat)", qdisc, basic)
html[#html + 1] = ui_helper.createLabel(T"Wi-Fi IRQ Core Affinity", irq_str, basic)

html[#html + 1] = '    </fieldset>\
  </fieldset>\
  </form>\
</div>\
'

ngx.print(html)
ngx.print(ui_helper.createFooter())
