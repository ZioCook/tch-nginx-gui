--pretranslated: do not change this file
-- Enable localization
gettext.textdomain('webui-qos')
local format = string.format
local modal_link = nil
local session = ngx.ctx.session
if session:hasAccess("/modals/qos-queue-modal.lp") and session:hasAccess("/modals/qos-classify-modal.lp") then
 modal_link = "/modals/qos-queue-modal.lp"
end
local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local qos_enabled_res = proxy.get("uci.modgui.var.qos_enabled")
local qos_state = (qos_enabled_res and qos_enabled_res[1] and qos_enabled_res[1].value == "1") and "1" or "0"
-- Menu display information (policy classgroup name MUST match value in qos config)
local dataQoS = {
    numQueues   = "uci.qos.classNumberOfEntries",
    numClassify = "uci.qos.classifyNumberOfEntries",
}
content_helper.getExactContent(dataQoS)
local light = qos_state
local state_text = (qos_state == "1") and T"QoS enabled" or T"QoS disabled"
local transitioning = false
local sf = io.open("/var/run/toggle_qos.status", "r")
if sf then
    local sline = sf:read("*l") or ""
    sf:close()
    local phase, st, p1, p2, ts = sline:match("^(%a+):([01]):(%d+):(%d+):(%d+)")
    local pid = tonumber(p1)
    local elapsed = os.time() - (tonumber(ts) or os.time())
    if phase == "running" and elapsed < 120 then
        local is_alive = false
        if pid and pid > 0 then
            local pf = io.open("/proc/" .. pid .. "/cmdline", "r")
            if pf then
                local cmd = pf:read("*a") or ""
                pf:close()
                if cmd:find("toggle_qos") then is_alive = true end
            end
        end
        if is_alive then
            light = "2"
            state_text = T"QoS in transition..."
            transitioning = true
        end
    end
end
ngx.print('\
<div class="span3">\
    <div class="smallcard" data-aos="zoom-in" data-aos-anchor-placement="center-bottom" data-aos-easing="ease-in-back">\
        '); ngx.print( ui_helper.createCardHeader(T"QoS", modal_link, "qos_enabled", qos_state) ); ngx.print('\
        <div class="content card_bg" data-bg-text="&#xf362;">\
		<div class="divtable">\
			');
                local html = {}
                html[#html + 1] = ui_helper.createSimpleLight(light, state_text, { light = { id = "qoscard_statusled" }, span = { id = "qoscard_status" } }, "fa-tachometer-alt")
                ngx.print (html)
            ngx.print('\
        </div>\
		</div>\
    </div>\
</div>\
');
-- While a QoS transition is running, poll its status and reload the page once it has finished.
-- The script is only emitted when the card is rendered in the "transition" state.
if transitioning then
    ngx.print([==[
<script>
(function () {
  var URL = "/modals/qos-queue-modal.lp?qos_status=1";
  var INTERVAL = 2000, MAX_MS = 120000, MAX_FAILS = 5;
  var t0 = new Date().getTime(), fails = 0;
  function reloadOnce() {
    try {
      var now = new Date().getTime();
      var n = parseInt(window.sessionStorage.getItem("qosPollReloads") || "0", 10);
      var last = parseInt(window.sessionStorage.getItem("qosPollLast") || "0", 10);
      if (now - last > 60000) { n = 0; }
      if (n >= 3) { return; }
      window.sessionStorage.setItem("qosPollReloads", String(n + 1));
      window.sessionStorage.setItem("qosPollLast", String(now));
    } catch (e) {}
    window.location.reload();
  }
  function next() {
    if (fails < MAX_FAILS && new Date().getTime() - t0 < MAX_MS) { setTimeout(poll, INTERVAL); }
  }
  function poll() {
    var x = new XMLHttpRequest();
    x.open("GET", URL + "&_=" + new Date().getTime(), true);
    x.timeout = 8000;
    x.onload = function () {
      if (x.status === 200) {
        var r = null;
        try { r = JSON.parse(x.responseText); } catch (e) {}
        if (r && r.running === false) { reloadOnce(); return; }
        fails = 0;
      } else if (x.status === 401 || x.status === 403) {
        window.location = "/login.lp";
        return;
      } else {
        fails++;
      }
      next();
    };
    x.onerror = x.ontimeout = function () { fails++; next(); };
    x.send();
  }
  setTimeout(poll, INTERVAL);
})();
</script>
]==])
end
