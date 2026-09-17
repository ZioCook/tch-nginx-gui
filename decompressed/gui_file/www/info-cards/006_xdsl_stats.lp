--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")

local find, sub, format, floor = string.find, string.sub, string.format, math.floor

local content = {
  status = "sys.class.xdsl.@line0.LinkStatus",
  version = "rpc.xdsl.dslversion",
  dsl_linerate_up_max = "sys.class.xdsl.@line0.UpstreamMaxRate",
  dsl_linerate_down_max = "sys.class.xdsl.@line0.DownstreamMaxRate",
  dsl_linerate_up = "sys.class.xdsl.@line0.UpstreamCurrRate",
  dsl_linerate_down = "sys.class.xdsl.@line0.DownstreamCurrRate",
  dsl_margin_up = "sys.class.xdsl.@line0.UpstreamNoiseMargin",
  dsl_margin_down = "sys.class.xdsl.@line0.DownstreamNoiseMargin",
  dsl_attenuation_up = "sys.class.xdsl.@line0.UpstreamAttenuation",
  dsl_attenuation_down = "sys.class.xdsl.@line0.DownstreamAttenuation",
  dsl_power_up = "sys.class.xdsl.@line0.UpstreamPower",
  dsl_power_down = "sys.class.xdsl.@line0.DownstreamPower",
  dsl_type = "sys.class.xdsl.@line0.ModulationType",
  dsl_margin_SNRM_up = "sys.class.xdsl.@line0.UpstreamSNRMpb",
  dsl_margin_SNRM_down = "sys.class.xdsl.@line0.DownstreamSNRMpb",
  dslam_chipset = "rpc.xdslctl.DslamChipset",
  dslam_version = "rpc.xdslctl.DslamVersion",
  dslam_version_raw = "rpc.xdslctl.DslamVersionRaw",
  dsl_profile = "rpc.xdslctl.DslProfile",
  dsl_port = "rpc.xdslctl.DslamPort",
  dsl_serial = "rpc.xdslctl.DslamSerial",
}

content_helper.getExactContent(content)

local function format_rate(rate)
    local num = tonumber(rate)
    if num then
        return floor(num / 10) / 100 .. " Mbps"
    end
    return "0 Mbps"
end

if content.dsl_linerate_down and content.dsl_linerate_down ~= "0" and content.dsl_linerate_down ~= "" then
    content.max_upstream = nil
    content.dsl_linerate_up = format_rate(content.dsl_linerate_up)
    content.dsl_linerate_down = format_rate(content.dsl_linerate_down)
    content.dsl_linerate_up_max = format_rate(content.dsl_linerate_up_max)
    content.dsl_linerate_down_max = format_rate(content.dsl_linerate_down_max)
else
    content.dsl_linerate_up = "0 Mbps"
    content.dsl_linerate_down = "0 Mbps"
    content.dsl_linerate_up_max = "0 Mbps"
    content.dsl_linerate_down_max = "0 Mbps"
end

if content.dsl_type and content.dsl_type ~= "" and not content.dsl_type:match("ADSL") then
	content.dsl_margin_down = content.dsl_margin_SNRM_down
	content.dsl_margin_up = content.dsl_margin_SNRM_up
end

if content.dslam_chipset and content.dslam_chipset:match("BDCM") then
	content.dslam_chipset = "Broadcom" .. " ( " .. content.dslam_chipset .. " )"
elseif content.dslam_chipset and content.dslam_chipset:match("IFTN") then
	content.dslam_chipset = "Infineon" .. " ( " .. content.dslam_chipset .. " )"
end

local dsl_status = content["status"] or ""
if dsl_status:match("Showtime") then
	content["status"] = T"Connected"
elseif dsl_status == "" then
	content["status"] = T"Disconnected"
else
	content["status"] = T(dsl_status)
end

  ngx.print('\
\
<div class="infocard" id="xdsltab">\
  <div class="smallcard">\
    ');  ngx.print( ui_helper.createCardHeader(T"xDSL Info", nil, nil, nil, nil) ); ngx.print('\
    <div class="content card_bg" data-bg-text="&#xf022;">\
	<div class="divtable">\
	<form class="form-horizontal">\
	<fieldset>');
	
	local basic = {
      span = {
        class = "span3"
      },
    }
	
	local html = {}
	
	basic.span["data-bind"] = "text: status"
	html[#html + 1] = ui_helper.createLabel(T"Status", content["status"], basic)
	basic.span["data-bind"] = nil
	html[#html + 1] = ui_helper.createLabel(T"xDSL Version", content["version"], basic)
	basic.span["data-bind"] = "text: dslam_chipset"
	html[#html + 1] = ui_helper.createLabel(T"DSLAM Chipset",content.dslam_chipset, basic )
	basic.span["data-bind"] = "text: dslam_version"
	local dslam_raw = content.dslam_version_raw or ""
	if dslam_raw:sub(0,2) == "0x" then
		html[#html + 1] = ui_helper.createLabel(T"DSLAM Firmware",format("%s ( %s )", content.dslam_version , dslam_raw) , basic )
	elseif dslam_raw == "" then
		html[#html + 1] = ui_helper.createLabel(T"DSLAM Firmware",T"Can't recover DSLAM version." , basic )
	else
		html[#html + 1] = ui_helper.createLabel(T"DSLAM Firmware",format(T"Invalid version, can't convert. Raw value: %s", dslam_raw) , basic )
	end
	if (content.dsl_profile ~= "Not Found") then
		basic.span["data-bind"] = "text: dsl_profile"
		html[#html + 1] = ui_helper.createLabel(T"VDSL Profile", content.dsl_profile, basic )
	end
	if ( content.dsl_port ~= "" ) then
		basic.span["data-bind"] = "text: dsl_port"
		html[#html + 1] = ui_helper.createLabel(T"VDSL DSLAM Port", content.dsl_port, basic )
	end
	if ( content.dsl_serial ~= "" ) then
		basic.span["data-bind"] = "text: dsl_serial"
		html[#html + 1] = ui_helper.createLabel(T"VDSL DSLAM Serial", content.dsl_serial, basic )
	end

	html[#html + 1] = '<div class="control-group">'
	html[#html + 1] =   '<label class="control-label">' .. T("Max Rate") .. '</label>'
	html[#html + 1] =   '<div class="controls">'
	html[#html + 1] =     '<span id="Rate" class=" simple-desc span3">'
	html[#html + 1] =		format('<i class="icon-download icon-small gray"></i> <span data-bind="text: dsl_linerate_down_max">%s</span>',content["dsl_linerate_down_max"])
	html[#html + 1] =		'<br/>'
	html[#html + 1] =		format('<i class="icon-upload icon-small gray"></i> <span data-bind="text: dsl_linerate_up_max">%s</span>', content["dsl_linerate_up_max"])
	html[#html + 1] =	  '</span>'
	html[#html + 1] =   '</div>'
	html[#html + 1] = '</div>'
	
	html[#html + 1] = '<div class="control-group">'
	html[#html + 1] =   '<label class="control-label">' .. T("Rate") .. '</label>'
	html[#html + 1] =   '<div class="controls">'
	html[#html + 1] =     '<span id="Rate" class=" simple-desc span3">'
	html[#html + 1] =		format('<i class="icon-download icon-small gray"></i> <span data-bind="text: dsl_linerate_down">%s</span>',content["dsl_linerate_down"])
	html[#html + 1] =		'<br/>'
	html[#html + 1] =		format('<i class="icon-upload icon-small gray"></i> <span data-bind="text: dsl_linerate_up">%s</span>', content["dsl_linerate_up"])
	html[#html + 1] =	  '</span>'
	html[#html + 1] =   '</div>'
	html[#html + 1] = '</div>'
	
	html[#html + 1] = '<div class="control-group">'
	html[#html + 1] =   '<label class="control-label">' .. T("Noise Margin") .. '</label>'
	html[#html + 1] =   '<div class="controls">'
	html[#html + 1] =     '<span id="Rate" class=" simple-desc span3">'
	html[#html + 1] =		format('<i class="icon-download icon-small gray"></i> <span data-bind="text: dsl_margin_down">%s</span> dB',content["dsl_margin_down"])
	html[#html + 1] =		'<br/>'
	html[#html + 1] =		format('<i class="icon-upload icon-small gray"></i> <span data-bind="text: dsl_margin_up">%s</span> dB', content["dsl_margin_up"])
	html[#html + 1] =	  '</span>'
	html[#html + 1] =   '</div>'
	html[#html + 1] = '</div>'
	
	html[#html + 1] = '<div class="control-group">'
	html[#html + 1] =   '<label class="control-label">' .. T("Attenuation") .. '</label>'
	html[#html + 1] =   '<div class="controls">'
	html[#html + 1] =     '<span id="Rate" class=" simple-desc span3">'
	html[#html + 1] =		format('<i class="icon-download icon-small gray"></i> <span data-bind="text: dsl_attenuation_down">%s</span> dB',content["dsl_attenuation_down"])
	html[#html + 1] =		'<br/>'
	html[#html + 1] =		format('<i class="icon-upload icon-small gray"></i> <span data-bind="text: dsl_attenuation_up">%s</span> dB', content["dsl_attenuation_up"])
	html[#html + 1] =	  '</span>'
	html[#html + 1] =   '</div>'
	html[#html + 1] = '</div>'
	
	html[#html + 1] = '<div class="control-group">'
	html[#html + 1] =   '<label class="control-label">' .. T("Power") .. '</label>'
	html[#html + 1] =   '<div class="controls">'
	html[#html + 1] =     '<span id="Rate" class=" simple-desc span3">'
	html[#html + 1] =		format('<i class="icon-download icon-small gray"></i> <span data-bind="text: dsl_power_down">%s</span> dBm',content["dsl_power_down"])
	html[#html + 1] =		'<br/>'
	html[#html + 1] =		format('<i class="icon-upload icon-small gray"></i> <span data-bind="text: dsl_power_up">%s</span> dBm', content["dsl_power_up"])
	html[#html + 1] =	  '</span>'
	html[#html + 1] =   '</div>'
	html[#html + 1] = '</div>'
	
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
	new modgui.createAjaxUpdateCard("xdsltab","/ajax/internet.lua?datatype=xdsl","InfoXdslCardInterval",5000);\
})\
</script>\
'); 
end