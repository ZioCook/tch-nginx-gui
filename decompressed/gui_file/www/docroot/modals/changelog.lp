--pretranslated: do not change this file

local ui_helper = require("web.ui_helper")
local format = string.format

local function get_changelog()
	local cmd = "curl -k -s -m 4 https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/CHANGELOG.md 2>/dev/null"
	local handle = io.popen(cmd)
	local result = ""
	if handle then
		result = handle:read("*a") or ""
		handle:close()
	end

	if not result or #result < 50 then
		local wcmd = "wget --no-check-certificate -q -T 4 -O- https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/CHANGELOG.md 2>/dev/null"
		local whandle = io.popen(wcmd)
		if whandle then
			result = whandle:read("*a") or ""
			whandle:close()
		end
	end

	local source = "Online (GitHub master)"
	if not result or #result < 50 then
		local local_paths = { "/www/docroot/CHANGELOG.md", "/etc/CHANGELOG.md", "/root/CHANGELOG.md" }
		for _, path in ipairs(local_paths) do
			local f = io.open(path, "r")
			if f then
				result = f:read("*a") or ""
				f:close()
				if #result > 50 then
					source = "Locale (Copia installata offline)"
					break
				end
			end
		end
	end

	if not result or #result < 10 then
		result = "Impossibile caricare il changelog (dispositivo offline e changelog locale non trovato)."
		source = "Non disponibile"
	end

	return result, source
end

local changelog_text, changelog_source = get_changelog()

-- Escape HTML special characters
local function html_escape(s)
	return (tostring(s):gsub("[&<>\"]", {
		["&"] = "&amp;",
		["<"] = "&lt;",
		[">"] = "&gt;",
		['"'] = "&quot;",
	}))
end

ngx.print(ui_helper.createHeader("Changelog", false, false))

ngx.print('\
<div class="modal-body no-save">\
  <fieldset>\
    <form class="form-horizontal" method="post" action="modals/changelog.lp">\
')

local html = {}
html[#html + 1] = '<div style="margin-bottom: 8px; font-size: 12px; color: #666;">'
html[#html + 1] = '  <i class="fa fa-info-circle"></i> Origine dati: <strong>' .. html_escape(changelog_source) .. '</strong> &bull; '
html[#html + 1] = '  <a href="https://github.com/ZioCook/tch-nginx-gui/blob/master/CHANGELOG.md" target="_blank" rel="noopener noreferrer" style="color: rgb(30, 116, 30); font-weight: bold;">Apri su GitHub</a>'
html[#html + 1] = '</div>'
html[#html + 1] = '<div class="fake_console" style="background: #0c0c0c; border: 1px solid #222; border-radius: 4px; padding: 12px; max-height: 480px; overflow-y: auto;">'
html[#html + 1] = '  <pre style="margin: 0; padding: 0; background: transparent; border: none; color: #4af626; font-family: Consolas, Menlo, Monaco, Lucida Console, Liberation Mono, DejaVu Sans Mono, Bitstream Vera Sans Mono, Courier New, monospace, serif; font-size: 12px; line-height: 1.5; white-space: pre-wrap; word-break: break-word;">'
html[#html + 1] = html_escape(changelog_text)
html[#html + 1] = '  </pre>'
html[#html + 1] = '</div>'

ngx.print(table.concat(html))

ngx.print('\
    </form>\
  </fieldset>\
</div>\
')
ngx.print(ui_helper.createFooter())
