--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local ui_helper = require("web.ui_helper")
local post_helper = require("web.post_helper")

local function sendcmd(cmd,name)
	proxy.set("rpc.system.init."..cmd, name)
	ngx.header.content_type = "application/json"
	ngx.print('{ "success":"true" }')
	ngx.timer.at(0, function()
		proxy.apply()
	end)
	ngx.exit(ngx.HTTP_OK)
end

if ngx.req.get_method() == "POST" then
	local action = string.untaint(ngx.req.get_post_args().action)
	if action:match("restart") then
		local name = action:gsub("restart_","")
		sendcmd("restart",name)
	elseif action:match("start") then
		local name = action:gsub("start_","")
		sendcmd("start",name)
	elseif action:match("stop") then
		local name = action:gsub("stop_","")
		sendcmd("stop",name)
	elseif action:match("enable") then
		local name = action:gsub("enable_","")
		sendcmd("enable",name)
	elseif action:match("disable") then
		local name = action:gsub("disable_","")
		sendcmd("disable",name)
	end
end

local init_columns = {
	{ --[1]
		header = T"Enabled",
		name = "active",
		param = "active",
		type = "light",
	},
	{ --[2]
		header = T"Name",
		name = "name",
		param = "name",
		type = "text",
	},
	{ --[3]
		header = T"Start Order",
		name = "start_order",
		param = "start_order",
		type = "text",
	},
	{ --[4]
		header = T"Stop Order",
		name = "stop_order",
		param = "stop_order",
		type = "text",
	},
	{ --[5]
		header = T"Toggle",
		name = "toggle",
		param = "toggle",
		type = "text",
	},
	{ --[6]
		header = T"Start",
		name = "start",
		param = "start",
		type = "text",
	},
	{ --[7]
		header = T"Stop",
		name = "stop",
		param = "stop",
		type = "text",
	},
	{ --[8]
		header = T"Restart",
		name = "restart",
		param = "restart",
		type = "text",
	}
}

local init_options = {
	canEdit = false,
	canAdd = false,
	canDelete = false,
	tableid = "inittable",
	basepath = "rpc.system.init.files.",
	sorted = "start_order",
}

local init_filter = function(data)

	if data.start_order == "" then
		return false
	end

	local function genAttrib(type)
		return {
			button = {
			  class = "btn-"..type,
			  ["data-name"] = data.name
			}
		}
	end

	if data.active == "1" then
		data.toggle = ui_helper.createSimpleButton(T"Disable","refresh",genAttrib("disable"))
	else
		data.toggle = ui_helper.createSimpleButton(T"Enable","refresh",genAttrib("enable"))
	end
	data.restart = ui_helper.createSimpleButton(T"Restart","refresh",genAttrib("restart"))
	data.start = ui_helper.createSimpleButton(T"Start","refresh",genAttrib("start"))
	data.stop = ui_helper.createSimpleButton(T"Stop","refresh",genAttrib("stop"))

	return true
end

local init_data, sipnet_helpmsg = post_helper.handleTableQuery(init_columns, init_options, init_filter)

  ngx.print('\
');  ngx.print(ui_helper.createHeader(T"Management", false, false) ); ngx.print('\
<div class="modal-body update">\
');
  local lp = require("web.lp")
  lp.setpath("/www/snippets/")
  lp.include("tabs-management.lp")
  ngx.print('\
');
-- dummy form so that refresh button knows which page to reload, keep it
  ngx.print('\
  <form class="form-horizontal" method="post" action="modals/system-init-modal.lp">\
  </form>\
  <fieldset id="system-init-tab">\
	<fieldset>\
	<legend>');  ngx.print( T"Init Management" ); ngx.print('</legend>')

	local alert_warn = {
		alert = {
			class = "alert alert-warn"
		},
	}

	ngx.print(ui_helper.createAlertBlock(T"Don't randomly disable or restart Init Process. Some Init are crucial for the correct boot of the device.",alert_warn))
	ngx.print(ui_helper.createTable(init_columns, init_data, init_options))

	ngx.print('\
	</fieldset>\
  </fieldset>\
  </div>\
  <script>\
	function handleInitAction(btn, action) {\
		var $btn = $(btn);\
		var originalHtml = $btn.html();\
		$btn.prop("disabled", true).html("<i class=\\"fas fa-spinner fa-spin\\"></i>");\
		$.post("/modals/system-init-modal.lp", {\
			action: action,\
			CSRFtoken: $("meta[name=CSRFtoken]").attr("content")\
		}, function(res) {\
			setTimeout(function() {\
				tch.loadModal("/modals/system-init-modal.lp");\
			}, 1200);\
		}, "json").fail(function() {\
			$btn.prop("disabled", false).html(originalHtml);\
		});\
	}\
\
	$(document).off("click", ".btn-disable").on("click", ".btn-disable", function(e){\
		e.preventDefault();\
		handleInitAction(this, "disable_" + $(this).data("name"));\
	});\
	$(document).off("click", ".btn-enable").on("click", ".btn-enable", function(e){\
		e.preventDefault();\
		handleInitAction(this, "enable_" + $(this).data("name"));\
	});\
	$(document).off("click", ".btn-start").on("click", ".btn-start", function(e){\
		e.preventDefault();\
		handleInitAction(this, "start_" + $(this).data("name"));\
	});\
	$(document).off("click", ".btn-stop").on("click", ".btn-stop", function(e){\
		e.preventDefault();\
		handleInitAction(this, "stop_" + $(this).data("name"));\
	});\
	$(document).off("click", ".btn-restart").on("click", ".btn-restart", function(e){\
		e.preventDefault();\
		handleInitAction(this, "restart_" + $(this).data("name"));\
	});\
  </script>\
');  ngx.print(ui_helper.createFooter() ); ngx.print('\
');
