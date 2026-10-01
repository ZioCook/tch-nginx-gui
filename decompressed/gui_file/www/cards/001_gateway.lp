--pretranslated: do not change this file
 
-- Enable localization
-- NG-92675/TCOMITAGW-2102 implement changes required from the customer
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")
local model_helper = require("model_helper")

local content = {
	version = "uci.version.version.@version[0].marketing_version",
	name = "uci.version.version.@version[0].marketing_name",
	model = "uci.env.var.prod_friendly_name",
	cpuusage = "sys.proc.CPUUsage",
}

content_helper.getExactContent(content)
content.model = model_helper[string.untaint(content.model)] or content.model
local readfile = content_helper.readfile
local initial_load = readfile("/proc/loadavg", "string")
local initial_loadavg = initial_load and initial_load:sub(1, 14) or ""
local initial_cpu = (content.cpuusage and content.cpuusage ~= "") and (content.cpuusage .. "%") or ""

local modalPath = nil
local switchName = nil
local session = ngx.ctx.session

if session:hasAccess("/modals/gateway-modal.lp") then
   modalPath = "/modals/gateway-modal.lp"
   switchName = nil
end

ngx.print('\
\
<div class="span3" id="gateway-card">\
  <div class="smallcard" data-aos="zoom-in" data-aos-anchor-placement="center-bottom" data-aos-easing="ease-in-back">\
    ');  ngx.print( ui_helper.createCardHeader(T"Modem", modalPath, switchName, nil, nil) ); ngx.print('\
    <div class="content card_bg" data-bg-text="&#xf129;">\
	<div class="divtable">\
	  <p>\
      <i class="fa fa-info" id="Gateway_=LED_Id"></i>\
      <strong id = "Version_Id">');  ngx.print(string.format(T"Version %s (%s)", content.name, content.version)); ngx.print('</strong><br/>');
	  ngx.print('<span class="subinfos" id="cpu-info-wrap" rel="tooltip" data-placement="top" data-original-title="' .. string.format(T"Load average (1m, 5m, 15m): %s", initial_loadavg) .. '" style="cursor: help;">' ..  T"CPU Usage"..": " ); ngx.print('\
					<strong data-bind="text: cpuusage">'); ngx.print(initial_cpu); ngx.print('</strong></span>\
      <div data-remote="/modals/gateway-modal.lp" data-id="gateway-modal" style="text-align: center;">\
	    <picture>\
		    <source srcset="/img/gateway_'); ngx.print(content.model); ngx.print('.webp" type="image/webp">\
		    <source srcset="/img/gateway_'); ngx.print(content.model); ngx.print('.png" type="image/png">\
        <img class="someInfos" href="#" rel="tooltip" data-placement="top" data-original-title="');  ngx.print( T"Your Gateway" ); ngx.print('" src="/img/gateway_'); ngx.print(content.model); ngx.print('.png" alt="'); ngx.print(content.model); ngx.print('">\
		</picture>\
		</div>\
      </div>\
    </div>\
  </div>\
</div>\
<script>\
$(document).ready(function () {\
	new modgui.createAjaxUpdateCard("gateway-card","/ajax/cpuload.lua","GatewayCardInterval",5000);\
	$("#cpu-info-wrap").tooltip();\
	$(document).ajaxSuccess(function(event, xhr, settings) {\
		if (settings.url && settings.url.indexOf("/ajax/cpuload.lua") !== -1) {\
			try {\
				var d = JSON.parse(xhr.responseText);\
				if (d && d.cpuload) {\
					$("#cpu-info-wrap").attr("data-original-title", "'); ngx.print(T"Load average (1m, 5m, 15m):"); ngx.print(' " + d.cpuload);\
				}\
			} catch(e) {}\
		}\
	});\
})\
</script>\
');
