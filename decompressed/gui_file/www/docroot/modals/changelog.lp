--pretranslated: do not change this file

local ui_helper = require("web.ui_helper")
local format = string.format

local function get_local_changelog()
	local local_paths = { "/www/docroot/CHANGELOG.md", "/etc/CHANGELOG.md", "/root/CHANGELOG.md" }
	for _, path in ipairs(local_paths) do
		local f = io.open(path, "r")
		if f then
			local result = f:read("*a") or ""
			f:close()
			if #result > 50 then
				return result, "Locale (Copia installata)"
			end
		end
	end
	return "Impossibile caricare il changelog locale.", "Non disponibile"
end

local changelog_text, changelog_source = get_local_changelog()

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
html[#html + 1] = '  <i class="fa fa-info-circle"></i> Origine dati: <strong id="changelog-source">' .. html_escape(changelog_source) .. '</strong> &bull; '
html[#html + 1] = '  <span id="changelog-status" style="color: #888;"></span> &bull; '
html[#html + 1] = '  <a href="https://github.com/ZioCook/tch-nginx-gui/blob/master/CHANGELOG.md" target="_blank" rel="noopener noreferrer" style="color: rgb(30, 116, 30); font-weight: bold;">Apri su GitHub</a>'
html[#html + 1] = '</div>'
html[#html + 1] = '<div class="fake_console" style="background: #0c0c0c; border: 1px solid #222; border-radius: 4px; padding: 12px; max-height: 480px; overflow-y: auto;">'
html[#html + 1] = '  <pre id="changelog-pre" style="margin: 0; padding: 0; background: transparent; border: none; color: #4af626; font-family: Consolas, Menlo, Monaco, Lucida Console, Liberation Mono, DejaVu Sans Mono, Bitstream Vera Sans Mono, Courier New, monospace, serif; font-size: 12px; line-height: 1.5; white-space: pre-wrap; word-break: break-word;">'
html[#html + 1] = html_escape(changelog_text)
html[#html + 1] = '  </pre>'
html[#html + 1] = '</div>'
html[#html + 1] = [[
<script type="text/javascript">
(function() {
  if (typeof window.fetch !== "function") return;
  var statusEl = document.getElementById("changelog-status");
  var sourceEl = document.getElementById("changelog-source");
  var preEl = document.getElementById("changelog-pre");
  if (!preEl) return;
  if (statusEl) statusEl.textContent = "Controllo aggiornamenti online...";
  var controller = typeof AbortController === "function" ? new AbortController() : null;
  var timer = controller ? setTimeout(function() { controller.abort(); }, 5000) : null;
  var fetchOpts = { method: "GET", cache: "no-cache" };
  if (controller) fetchOpts.signal = controller.signal;
  fetch("https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/CHANGELOG.md", fetchOpts)
    .then(function(res) {
      if (timer) clearTimeout(timer);
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.text();
    })
    .then(function(text) {
      if (text && text.length > 50) {
        preEl.textContent = text;
        if (sourceEl) sourceEl.textContent = "Online (GitHub master)";
        if (statusEl) statusEl.textContent = "Aggiornato";
      }
    })
    .catch(function(err) {
      if (timer) clearTimeout(timer);
      if (statusEl) statusEl.textContent = "Uso copia locale";
    });
})();
</script>
]]

ngx.print(table.concat(html))

ngx.print('\
    </form>\
  </fieldset>\
</div>\
')
ngx.print(ui_helper.createFooter())
