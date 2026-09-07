--pretranslated: do not change this file

-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local eco_helper = require("eco_helper")
local untaint = string.untaint or function(x) return x end
local format = string.format

local prod_friendly_name = proxy.get("uci.env.var.prod_friendly_name")
local prod_name = prod_friendly_name and untaint(prod_friendly_name[1].value) or ""

local content = {
	cpuspeed = "uci.power.cpu.cpuspeed",
	eee = "uci.power.ethernet.eee",
}
if prod_name:match("DGA4131") then
	content.eco_led = "uci.ledfw.ambient.active"
else
	content.eco_led = "uci.ledfw.status_led.enable"
end

content_helper.getExactContent(content)

if prod_name:match("DGA4131") then
	if content.eco_led == "1" then
		content.eco_led_text = T"Ambient LED abilitato"
	else
		content.eco_led_text = T"Ambient LED disabilitato"
	end
else
	if content.eco_led == "1" then
		content.eco_led_text = T"Eco LED abilitato"
	else
		content.eco_led_text = T"Eco LED disattivato"
	end
end

if content.eee == "1" then
	content.eee_text = T"Ethernet EEE abilitato"
else
	content.eee_text = T"Ethernet EEE disattivato"
end

local cpu_status = eco_helper.getCpuStatus()
local cpu_label = format("CPU: %s (%s, %d core)", cpu_status.governor:upper(), cpu_status.cur_freq, cpu_status.cores_online)

local temps = eco_helper.getTemperatures()
local temp_text = nil
local temp_status = 1
if #temps > 0 then
	local parts = {}
	for _, t in ipairs(temps) do
		if t.chip == "wl0" then
			parts[#parts+1] = format("2.4G: %d°C", t.temp)
		elseif t.chip == "qtn-rfic" or t.chip == "wl1" then
			parts[#parts+1] = format("5G: %d°C", t.temp)
		end
		if t.temp >= 80 then
			temp_status = 0
		end
	end
	if #parts > 0 then
		temp_text = "Temp: " .. table.concat(parts, " | ")
	else
		temp_text = format("Temp: %d°C", temps[1].temp)
	end
end

local modalPath = nil
local switchName = nil
local session = ngx.ctx.session
if session:hasAccess("/modals/eco-modal.lp") then
	modalPath = "/modals/eco-modal.lp"
end

ngx.print('\
<div class="span3">\
  <div class="smallcard" data-aos="zoom-in" data-aos-anchor-placement="center-bottom" data-aos-easing="ease-in-back">\
\
    ');  ngx.print( ui_helper.createCardHeader(T"Eco & Hardware", modalPath, switchName, nil) ); ngx.print('\
\
    <div class="content card_bg" data-bg-text="&#xf06c;">\
	  <div class="divtable">\
\
      ');
local html = {}

	html[#html + 1] = ui_helper.createSimpleLight(1, cpu_label, nil, "fas fa-microchip"  )
	if temp_text then
		html[#html + 1] = ui_helper.createSimpleLight(temp_status, temp_text, nil, "fas fa-thermometer-half"  )
	end
	html[#html + 1] = ui_helper.createSimpleLight(content.eee, content.eee_text, nil, "fas fa-exchange-alt"  )
	html[#html + 1] = ui_helper.createSimpleLight(content.eco_led, content.eco_led_text, nil, "fas fa-leaf"  )

ngx.print(html)
ngx.print('\
\
	  </div>\
    </div>\
  </div>\
</div>\
'); 
