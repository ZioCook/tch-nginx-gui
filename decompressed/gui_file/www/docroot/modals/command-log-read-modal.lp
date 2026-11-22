--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local json = require("dkjson")

local header = '<span id="header_title">'..T"Executing"..'</span><span id="show_progress"></span>'

ngx.print(ui_helper.createHeader(header, false, false))

local html = {}

html[#html + 1] = [[
<div class="modal-body update fake_console">
  <form class="form-horizontal" id="commandlogmodal" method="post" action="/modals/command-log-read-modal.lp">
<style>
  #modal-container .modal-action-close,
  #modal-container .modal-footer,
  .modal-action-close,
  .modal-footer {
    display: none !important;
  }
  .upgrade-finished .modal-action-close,
  .upgrade-finished.modal .modal-action-close,
  #modal-container.upgrade-finished .modal-action-close {
    display: block !important;
  }
  .upgrade-finished .modal-footer,
  .upgrade-finished.modal .modal-footer,
  #modal-container.upgrade-finished .modal-footer {
    display: block !important;
  }
  .upgrade-finished #close-config,
  .upgrade-finished #modal-no-change {
    display: inline-block !important;
  }
</style>
]]

html[#html + 1] = '<fieldset class="modal-body" id="upgrade-gui-bar" style="min-height: unset; margin-bottom: 15px;">'
html[#html + 1] = '<div class="alert alert-info" style="margin-bottom: 0;">'
html[#html + 1] = '<div style="display: flex; justify-content: space-between; font-weight: bold; margin-bottom: 6px;"><span id="update-text">'..T"Operation in progress... Please wait."..'</span><span id="progress-percent">0%</span></div>'
html[#html + 1] = '  <div class="progress progress-striped active" style="margin-bottom: 0;">'
html[#html + 1] = '     <div id="upgrade-progress-bar-fill" class="bar bar-warning" role="progressbar" style="width: 5%;" aria-valuenow="5" aria-valuemin="0" aria-valuemax="100"></div>'
html[#html + 1] = '</div></div>'
html[#html + 1] = '</fieldset>'
html[#html + 1] = '<fieldset>'
html[#html + 1] = '<div id="command-log-text-container" style="white-space: pre-wrap; font-family: monospace; font-size: 12px; max-height: min(280px, 35vh); overflow-y: auto; scroll-behavior: smooth; background: rgba(0,0,0,0.05); padding: 8px; border-radius: 4px;" data-bind="log_text: log">'
html[#html + 1] = '[Inizializzazione] Avvio operazione in corso...'
html[#html + 1] = '</div>'
html[#html + 1] = '</fieldset>'

local uri_cmd_action = ngx.req.get_uri_args().cmd_action
if type(uri_cmd_action) == "table" and not string.istainted(uri_cmd_action) then
  uri_cmd_action = uri_cmd_action[1]
end
local raw_cmd_action = (type(uri_cmd_action) == "string" or string.istainted(uri_cmd_action)) and string.untaint(uri_cmd_action) or ""
local safe_cmd_action = raw_cmd_action:match("^[%w_%-]+$") and raw_cmd_action or ""

local cfg_json = json.encode({
  cmdAction = tostring(safe_cmd_action or ""),
}):gsub("</", "<\\/")

html[#html + 1] = [[
  </form>
</div>
<script type="application/json" id="command-log-read-modal-cfg">]] .. cfg_json .. [[</script>
<script>window.ensureScript("/js/modals/command-log-read-modal.js",function(){return typeof window.initCommandLogReadModal==="function";},function(){window.initCommandLogReadModal();});</script>
]]

ngx.print(html)
ngx.print(ui_helper.createFooter())
