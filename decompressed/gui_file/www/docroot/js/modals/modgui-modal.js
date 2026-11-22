(function () {
	"use strict";

	var NS = ".modguiModal";
	var pollTimers = [];

	function getCfg() {
		var $els = $(".modal #modgui-modal-cfg");
		var el = $els.length ? $els.last()[0] : document.getElementById("modgui-modal-cfg");
		if (!el) return {};
		try {
			return JSON.parse(el.textContent || "{}") || {};
		} catch (e) {
			return {};
		}
	}

	function trackTimeout(fn, delay) {
		var id = window.setTimeout(fn, delay);
		pollTimers.push(id);
		return id;
	}

	function clearTrackedTimers() {
		while (pollTimers.length) {
			window.clearTimeout(pollTimers.pop());
		}
	}

	window.initModguiModal = function () {
		clearTrackedTimers();
		$(document).off(NS);

		var cfg = getCfg();
		var refreshTimeOut = 5000;
		var refreshDelay = 3000;
		var target = $(".modal form").attr("action");

		$(".modal, #modal-container").off("hidden.bs.modal" + NS).on("hidden.bs.modal" + NS, function () {
			clearTrackedTimers();
			$(document).off(NS);
		});

		var timescroll_opt = {
			theme: "android-ics light",
			display: "bubble",
			mode: "scroller",
			headerText: false,
			timeFormat: "HH:ii",
			stepMinute: 5
		};

		$("#update_autoupgrade_hour").mobiscroll().time(timescroll_opt);
		$("#update_autoupgrade_hour").off("change" + NS).on("change" + NS, function () {
			$("#modal-no-change").fadeOut(300);
			$("#modal-changes").delay(350).fadeIn(300);
		});

		function wait_for_webserver_running() {
			$.ajax({ url: "/", timeout: refreshTimeOut })
			.done(function () {
				window.location.href = "/";
			})
			.fail(function () {
				trackTimeout(wait_for_webserver_running, refreshDelay);
			});
		}

		function wait_for_webserver_down() {
			$.ajax({ url: target, timeout: refreshTimeOut })
			.done(function () {
				trackTimeout(wait_for_webserver_down, refreshDelay);
			})
			.fail(function () {
				trackTimeout(wait_for_webserver_running, refreshDelay);
			});
		}

		function resetreboot(msg, msg_dst, action, customCallbackfunc) {
			msg.removeClass("hide");
			msg[0].scrollIntoView();
			msg_dst.replaceWith(msg);
			var callbackfunc = (typeof customCallbackfunc === "function") && customCallbackfunc || wait_for_webserver_down;
			if (callbackfunc == wait_for_webserver_down) modgui.clearKoInterval();
			$.post(target, { action: action, CSRFtoken: $("meta[name=CSRFtoken]").attr("content") }, callbackfunc, "json");
			return false;
		}

		function genericButtonFunction(headingText, processMsgText, ConfirmationDialogueText, resetIDName, btnID, callFunctionName, customCallBack) {
			var heading = headingText;
			var processMsg = processMsgText;
			confirmationDialogue(ConfirmationDialogueText, heading);
			var PopUpHeaderText = "." + $(".popUp>.header>.header-title>p").text().split(" ")[0];
			$(document).off("click" + NS, PopUpHeaderText).on("click" + NS, PopUpHeaderText, function () {
				tch.removeProgress();
				tch.showProgress(processMsg);
				return resetreboot($(resetIDName), $(btnID), callFunctionName, customCallBack);
			});
		}

		$("#btn-reset-gui").off("click" + NS).on("click" + NS, function () {
			return genericButtonFunction(
				cfg.restoreGuiTitle || "",
				cfg.restoringText || "",
				cfg.continuePrompt || "",
				"#resetting-msg",
				"#btn-reset-gui",
				"system_reset_gui"
			);
		});
		$("#btn-remove-root").off("click" + NS).on("click" + NS, function () {
			return genericButtonFunction(
				cfg.removeRootTitle || "",
				cfg.resettingText || "",
				cfg.removeRootPrompt || "",
				"#unrooting-msg",
				"#btn-remove-root",
				"system_remove_root"
			);
		});
		$("#btn-remove-config").off("click" + NS).on("click" + NS, function () {
			return genericButtonFunction(
				cfg.resetConfigTitle || "",
				cfg.resettingText || "",
				cfg.resetConfigPrompt || "",
				"#config-resetting-msg",
				"#btn-remove-config",
				"system_reset_config"
			);
		});
		$("#btn-reset-cwmp").off("click" + NS).on("click" + NS, function () {
			return genericButtonFunction(
				cfg.resetCwmpTitle || "",
				cfg.resettingText || "",
				cfg.resetCwmpPrompt || "",
				"#btn-reset-cwmp",
				"#btn-reset-cwmp",
				"system_reset_cwmp",
				tch.removeProgress
			);
		});

		var schedulReload = false;

		$("#gui_skin").on("change", function () {
			var theme = $(this).val();
			if (theme.indexOf("Fritz") === -1) {
				var restyled = theme + "/style.css";
				modgui.freshStyle(restyled);
			}
			if (theme.indexOf("Fritz") != -1 || theme.indexOf("unified") != -1) {
				if ($('#gui_skin_firstpage option[value="cards"]').is(":selected")) $("#gui_skin_firstpage").val("stats");
				$('#gui_skin_firstpage option[value="cards"]').attr("disabled", "disabled");
			} else {
				$('#gui_skin_firstpage option[value="cards"]').removeAttr("disabled");
			}
			schedulReload = true;
		});

		$("#btn-gen-backup").off("click" + NS).on("click" + NS, function () {
			$.fileDownload(target, {
				httpMethod: "POST",
				data: [
					{ name: "action", value: "system_genBackup" },
					{ name: "CSRFtoken", value: $("meta[name=CSRFtoken]").attr("content") }
				],
				prepareCallback: function () {
					tch.showProgress(cfg.generatingBackupText || "");
				},
				successCallback: function () {
					tch.removeProgress();
				}
			});
			return false;
		});

		$("#gui_forcehttps,#gui_alwaysadvanced").off("change" + NS).on("change" + NS, function () {
			schedulReload = true;
		});

		$("#save-config").off("click" + NS).on("click" + NS, function () {
			if (schedulReload) {
				schedulReload = true;
				setTimeout(function () { window.location.reload(true); }, 1000);
			}
		});

		$(document).on("click" + NS, "#cancel", function () {
			tch.removeProgress();
		});

		$("#btn-upgrade-gui").off("click" + NS).on("click" + NS, function () {
			modgui.postAction("system_upgrade_gui", 1);
		});

		$(".import-gui").off("click" + NS).on("click" + NS, function () {
			var nofile_msg = $("#upgrade-gui-fail");
			var wrongext_msg = $("#upgrade-gui-fail");
			nofile_msg.addClass("hide");
			if ($("#file-upgradegui").val() == "") {
				nofile_msg.removeClass("hide");
				nofile_msg[0].scrollIntoView();
				return false;
			}

			var validExtensions = ["bz2"];
			var fileName = $("#file-upgradegui").val();

			var fileNameExt = fileName.substr(fileName.lastIndexOf(".") + 1);
			if ($.inArray(fileNameExt, validExtensions) == -1) {
				wrongext_msg.removeClass("hide");
				wrongext_msg[0].scrollIntoView();
				return false;
			}
			var importing_msg = $("#upload-gui-alert");
			importing_msg.removeClass("hide");
			importing_msg[0].scrollIntoView();

			$.fileUpload($("#form-import-gui"), {
				params: { CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				completeCallback: function (form, response) {
					var res = response;
					if (typeof res === "string") {
						try {
							res = JSON.parse(res.replace(/<[^>]*>/g, "").trim());
						} catch (e) {
							if (res.indexOf("success") !== -1 && res.indexOf("true") !== -1) {
								res = { success: true };
							}
						}
					}
					if (res && (res.success === true || res.success === "true")) {
						modgui.postAction("system_upgrade_gui", 1);
					} else {
						importing_msg.addClass("hide");
						if (res && res.error) {
							$("#upgrade-gui-fail").text(res.error);
						}
						$("#upgrade-gui-fail").removeClass("hide");
					}
				}
			});
			return false;
		});

		$("#btn-install-specificapp").off("click" + NS).on("click" + NS, function () {
			modgui.postAction("system_install_specificapp", 1);
		});

		$(".import-specificapp").off("click" + NS).on("click" + NS, function () {
			var nofile_msg = $("#upgrade-specificapp-fail");
			var wrongext_msg = $("#upgrade-specificapp-fail");
			nofile_msg.addClass("hide");
			if ($("#file-specificapp").val() == "") {
				nofile_msg.removeClass("hide");
				nofile_msg[0].scrollIntoView();
				return false;
			}

			var validExtensions = ["bz2"];
			var fileName = $("#file-specificapp").val();

			var fileNameExt = fileName.substr(fileName.lastIndexOf(".") + 1);
			if ($.inArray(fileNameExt, validExtensions) == -1) {
				wrongext_msg.removeClass("hide");
				wrongext_msg[0].scrollIntoView();
				return false;
			}
			var importing_msg = $("#upload-specificapp-alert");
			importing_msg.removeClass("hide");
			importing_msg[0].scrollIntoView();

			$.fileUpload($("#form-import-specificapp"), {
				params: { CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				completeCallback: function (form, response) {
					var res = response;
					if (typeof res === "string") {
						try {
							res = JSON.parse(res.replace(/<[^>]*>/g, "").trim());
						} catch (e) {
							if (res.indexOf("success") !== -1 && res.indexOf("true") !== -1) {
								res = { success: true };
							}
						}
					}
					if (res && (res.success === true || res.success === "true")) {
						modgui.postAction("system_install_specificapp", 1);
					} else {
						importing_msg.addClass("hide");
						if (res && res.error) {
							$("#upgrade-specificapp-fail").text(res.error);
						}
						$("#upgrade-specificapp-fail").removeClass("hide");
					}
				}
			});
			return false;
		});

		$(".import-backup").off("click" + NS).on("click" + NS, function () {
			var nofile_msg = $("#restore-fail");
			var wrongext_msg = $("#restore-fail");
			nofile_msg.addClass("hide");
			if ($("#file-restore").val() == "") {
				nofile_msg.removeClass("hide");
				nofile_msg[0].scrollIntoView();
				return false;
			}

			var validExtensions = ["gz"];
			var fileName = $("#file-restore").val();

			var fileNameExt = fileName.substr(fileName.lastIndexOf(".") + 1);
			if ($.inArray(fileNameExt, validExtensions) == -1) {
				wrongext_msg.removeClass("hide");
				wrongext_msg[0].scrollIntoView();
				return false;
			}
			var importing_msg = $("#upload-backup-alert");
			importing_msg.removeClass("hide");
			importing_msg[0].scrollIntoView();

			$.fileUpload($("#form-import-backup"), {
				params: { CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				completeCallback: function (form, response) {
					var res = response;
					if (typeof res === "string") {
						try {
							res = JSON.parse(res.replace(/<[^>]*>/g, "").trim());
						} catch (e) {
							if (res.indexOf("success") !== -1 && res.indexOf("true") !== -1) {
								res = { success: true };
							}
						}
					}
					if (res && (res.success === true || res.success === "true")) {
						importing_msg.addClass("hide");
						tch.showProgress((cfg.rebootingText || "") + "...");
						modgui.clearKoInterval();
						wait_for_webserver_down();
					} else {
						importing_msg.addClass("hide");
						$("#restore-fail").removeClass("hide");
					}
				}
			});
			return false;
		});

		$("#btn-system-debug-report").off("click" + NS).on("click" + NS, function () {
			$.fileDownload(target, {
				httpMethod: "POST",
				data: [
					{ name: "action", value: "debug_report" },
					{ name: "CSRFtoken", value: $("meta[name=CSRFtoken]").attr("content") }
				],
				prepareCallback: function () {
					tch.showProgress(cfg.generatingReportText || "");
				},
				successCallback: function () {
					location.reload();
				}
			});
			return false;
		});

		var fwversion_real = cfg.fwversionReal || "";
		$("#version_spoof_mode").off("change" + NS).on("change" + NS, function () {
			if ($(this).val() == "manual") {
				$("#fwversion_override").prop("disabled", false);
			} else {
				if ($(this).val() == "disabled") {
					$("#fwversion_override").val(fwversion_real);
				}
				$("#fwversion_override").prop("disabled", true);
			}
		});
		if ($("#version_spoof_mode").val() == "manual") {
			$("#fwversion_override").prop("disabled", false);
		} else {
			$("#fwversion_override").prop("disabled", true);
		}

		if (cfg.scrollManualUpgrade && $("#GUI_Upgrade_Legend").length) {
			$("#GUI_Upgrade_Legend")[0].scrollIntoView();
		}
	};
}());
