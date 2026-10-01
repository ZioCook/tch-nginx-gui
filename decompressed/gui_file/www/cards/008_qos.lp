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
local qos_state = (qos_enabled_res and qos_enabled_res[1].value == "1") and "1" or "0"

-- Menu display information (policy classgroup name MUST match value in qos config)
local dataQoS = {
    numQueues   = "uci.qos.classNumberOfEntries",
    numClassify = "uci.qos.classifyNumberOfEntries",
}
content_helper.getExactContent(dataQoS)

local light = qos_state
local state_text = (qos_state == "1") and T"QoS enabled" or T"QoS disabled"

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
