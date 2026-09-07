--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local format = string.format
local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local session = ngx.ctx.session
local modalPath = "/modals/xdsl-low-modal.lp"
local untaint = string.untaint or function(x) return x end
local lfs = require"lfs"

local content = {
    dsl0_enabled = "uci.xdsl.xdsl.@dsl0.enabled",
    dsl0_status = "sys.class.xdsl.@line0.Status",
    xdsl_version = "rpc.xdslctl.DslFirmware",
    dslam_chipset = "rpc.xdslctl.DslamChipset",
    dslam_version = "rpc.xdslctl.DslamVersion"
}
content_helper.getExactContent(content)

local is_enabled = (untaint(content.dsl0_enabled) == "1")

if content.dslam_chipset and content.dslam_chipset:match("BDCM") then
	content.dslam_chipset = "Broadcom"
elseif content.dslam_chipset and content.dslam_chipset:match("IFTN") then
	content.dslam_chipset = "Infineon"
end

if session:hasAccess(modalPath) and lfs.attributes("/etc/config/xdsl", "mode") == "file" then

    ngx.print('\
  <div class="span3">\
      <div class="smallcard" data-aos="zoom-in" data-aos-anchor-placement="center-bottom" data-aos-easing="ease-in-back">\
         ');  ngx.print( ui_helper.createCardHeader(T"Configurazione xDSL", modalPath) ); ngx.print('\
          <div class="content card_bg" data-bg-text="&#xf2db;">\
          <div class="divtable">\
                ');  
                local html = {}
                if not is_enabled then
                    html[#html+1] = ui_helper.createSimpleLight("0", T"xDSL disabilitato", { light = { class = "off" } }, "fas fa-microchip")
                    html[#html+1] = '<p class="subinfos">'
                    html[#html+1] = '<span class="simple-desc"><i class="fas fa-network-wired" aria-hidden="true">&nbsp;</i>' .. T"Modalità: <strong>Bridge / AP</strong>" .. '</span><br/>'
                    html[#html+1] = '<span class="simple-desc"><i class="fas fa-plug" aria-hidden="true">&nbsp;</i>' .. T"Interfaccia DSL non in uso" .. '</span>'
                    html[#html+1] = '</p>'
                elseif content.dsl0_status == "Up" then
                    html[#html+1] = ui_helper.createSimpleLight("1", T"xDSL Connesso", { light = { class = "green" } }, "fas fa-microchip")
                    html[#html+1] = '<p class="subinfos">'
                    if content.xdsl_version and not content.xdsl_version:match("not found") and content.xdsl_version ~= "" then
                        html[#html+1] = format('<span class="simple-desc"><i class="fas fa-code-branch" aria-hidden="true">&nbsp;</i>' .. T"Datapump: <strong>%s</strong></span><br/>", content.xdsl_version)
                    end
                    if content.dslam_chipset and content.dslam_chipset ~= "" and not content.dslam_chipset:match("not found") then
                        html[#html+1] = format('<span class="simple-desc"><i class="fas fa-server" aria-hidden="true">&nbsp;</i>' .. T"DSLAM: <strong>%s</strong></span>", content.dslam_chipset)
                    end
                    html[#html+1] = '</p>'
                else
                    html[#html+1] = ui_helper.createSimpleLight("2", T"xDSL Disconnesso", { light = { class = "orange" } }, "fas fa-microchip")
                    html[#html+1] = '<p class="subinfos">'
                    html[#html+1] = '<span class="simple-desc"><i class="fas fa-plug" aria-hidden="true">&nbsp;</i>' .. T"Cavo DSL non collegato" .. '</span><br/>'
                    html[#html+1] = '<span class="simple-desc"><i class="fas fa-info-circle" aria-hidden="true">&nbsp;</i>' .. T"In attesa di segnale..." .. '</span>'
                    html[#html+1] = '</p>'
                end
                ngx.print(html)
                  ngx.print('\
           </div>\
           </div>\
      </div>\
  </div>\
');  
end
  ngx.print('\
\
'); 
