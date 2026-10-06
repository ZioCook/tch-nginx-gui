--pretranslated: do not change this file
 ngx.print('	');  
		gettext.textdomain('webui-core')
                local post_helper = require("web.post_helper")
                local has_variant, variant_helper = pcall(require, "variant_helper")
                local variantHelper = nil
                if has_variant and variant_helper then
                  variantHelper = post_helper.getVariant(variant_helper, "ExtenderPage", "extenderConfig")
                end

		local ui_helper = require("web.ui_helper")
		local items = {
			{"easy-mesh-configuration.lp", T"EasyMesh Configuration"},
		}
                if post_helper.getVariantValue(variantHelper, "extenderInfo") then
                  items[#items + 1] = {"wifi-extender-status.lp", T"Extender Info"}
                end
                if post_helper.getVariantValue(variantHelper, "agentAndStationInfo") then
                  items[#items + 1] = {"agent-list.lp", T"Agent List"}
                end
                if post_helper.getVariantValue(variantHelper, "wifiDevicesList") then
                  items[#items + 1] =  {"wifi-devices-info.lp", T"WiFi Devices"}
                end
	        local uri = ngx.var.args and string.len(ngx.var.args) > 0 and ngx.var.uri.. "?" .. ngx.var.args or  ngx.var.uri
                local fileName = string.match(uri, "/%S+/(%S+)")
                if fileName and string.match(fileName, "^agent") then
                  for _, item in ipairs(items) do
                    if item[1]:match("^agent") then
                      item[1] = fileName
                      break
                    end
                  end
                end
		local tabs = {}
		local session = ngx.ctx.session
		for _, item in ipairs(items) do
			local target = "/modals/" .. item[1]
			if not session or session:hasAccess(target) then
				local active = nil
				if uri and uri:find(item[1], 1, true) then
					active = "active"
				end
				tabs[#tabs + 1] = {
					desc = item[2],
					target = target,
					active = active,
				}
			end
		end
		if #tabs > 1 then
			local html = ui_helper.createModalTabs(tabs)
			ngx.print(html)
		end
	  ngx.print('\
'); 