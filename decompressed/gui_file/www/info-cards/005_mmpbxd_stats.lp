--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")
local proxy = require("datamodel")

local session = ngx.ctx.session
if session and session.getLanguage then
    gettext.language(session:getLanguage())
elseif ngx.header['Content-Language'] then
    gettext.language(ngx.header['Content-Language'])
end

local mmpbx_state = "0"
local mmpbx_state_uci = proxy.get("uci.mmpbx.mmpbx.@global.enabled")
if not mmpbx_state_uci or not mmpbx_state_uci[1] or mmpbx_state_uci[1].value == "" then
    mmpbx_state_uci = proxy.get("uci.mmpbx.global.enabled")
end
if mmpbx_state_uci and mmpbx_state_uci[1] and mmpbx_state_uci[1].value == "1" then
    local rpc_state = proxy.get("rpc.mmpbx.state")
    if not rpc_state or not rpc_state[1] or rpc_state[1].value ~= "NA" then
        mmpbx_state = "1"
    end
end

local mmpbx_info = (mmpbx_state == "1") and T"Telephony enabled" or T"Telephony disabled"

ngx.print('\
\
<div class="infocard" id="infommpbxdtab">\
  <div class="smallcard">\
    ');  ngx.print( ui_helper.createCardHeader(T"Telephony Info", nil, nil, nil, nil) ); ngx.print('\
    <div class="content card_bg" data-bg-text="&#xf095;" style="min-height: 80px; padding: 15px 0;">\
	<div class="divtable">\
	<form class="form-horizontal">\
	<fieldset>\
')

local basic = {
  span = {
    class = "span3"
  },
}

local html = {}
html[#html + 1] = '<span data-bind="html: mmpbx_status">'
html[#html + 1] = ui_helper.createLabel(T"Service", ui_helper.createSimpleLight(mmpbx_state, mmpbx_info), basic)
html[#html + 1] = '</span>'

html[#html + 1] = '<span data-bind="html: mmpbx_table">'
if mmpbx_state == "0" then
    html[#html + 1] = ''
else
    html[#html + 1] = '<div class="spinner3"><div class="rect1"></div><div class="rect2"></div><div class="rect3"></div><div class="rect4"></div><div class="rect5"></div></div>'
end
html[#html + 1] = '</span>'

ngx.print(html)
ngx.print('\
	  </fieldset>\
	</form>\
	</div>\
    </div>\
  </div>\
</div>\
<script>\
$(document).ready(function () {\
	new modgui.createAjaxUpdateCard("infommpbxdtab","/ajax/mmpbx_status.lua","InfoMmpbxCardInterval",4000);\
})\
</script>\
');
