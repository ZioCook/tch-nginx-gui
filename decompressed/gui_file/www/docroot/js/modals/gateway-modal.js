(function () {
	"use strict";

	var NS = ".gatewayModal";
	var refreshTimeOut = 5000;
	var refreshDelay = 3000;
	var pollTimers = [];

	function getCfg() {
		var $els = $(".modal #gateway-modal-cfg");
		var el = $els.length ? $els.last()[0] : document.getElementById("gateway-modal-cfg");
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

	window.initGatewayModal = function () {
		clearTrackedTimers();
		$(document).off(NS);

		var cfg = getCfg();
		var target = $(".modal form").attr("action");

		$(".modal, #modal-container").off("hidden.bs.modal" + NS).on("hidden.bs.modal" + NS, function () {
			clearTrackedTimers();
			$(document).off(NS);
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

		function resetreboot(msg, msg_dst, action) {
			msg.removeClass("hide");
			msg[0].scrollIntoView();
			msg_dst.replaceWith(msg);
			modgui.clearKoInterval();
			$.post(
				target,
				{ action: action, CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				wait_for_webserver_down,
				"json"
			);
			return false;
		}

		function wait_for_shutdown() {
			$.ajax({ url: "/", timeout: 2000 })
			.done(function () {
				trackTimeout(wait_for_shutdown, 1500);
			})
			.fail(function () {
				tch.removeProgress();
				$("#poweroff-msg").removeClass("hide").html("<strong>" + (cfg.shutdownDoneTitle || "") + "</strong> " + (cfg.shutdownDoneDesc || ""));
			});
		}

		$("#btn-system-poweroff").off("click" + NS).on("click" + NS, function () {
			var heading = cfg.shutdownHeading || "";
			var processMsg = cfg.shutdownProcess || "";
			confirmationDialogue(cfg.shutdownConfirm || "", heading);
			$("#popUp").css({ position: "fixed", top: "50%", left: "50%", transform: "translate(-50%, -50%)", margin: "0" });
			var PopUpHeaderText = "." + $(".popUp>.header>.header-title>p").text().trim().split(" ")[0];
			$(document).off("click" + NS, PopUpHeaderText).on("click" + NS, PopUpHeaderText, function () {
				tch.removeProgress();
				tch.showProgress(processMsg);
				$("#poweroff-msg").removeClass("hide");
				$("#poweroff-msg")[0].scrollIntoView();
				$("#btn-system-poweroff").replaceWith($("#poweroff-msg"));
				modgui.clearKoInterval();
				$.post(
					target,
					{ action: "system_poweroff", CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
					wait_for_shutdown,
					"json"
				);
				return false;
			});
		});

		$("#btn-system-reboot").off("click" + NS).on("click" + NS, function () {
			var heading = cfg.restartHeading || "";
			var processMsg = cfg.rebootProcess || "";
			confirmationDialogue(cfg.confirmText || "", heading);
			var PopUpHeaderText = "." + $(".popUp>.header>.header-title>p").text().split(" ")[0];
			$(document).off("click" + NS, PopUpHeaderText).on("click" + NS, PopUpHeaderText, function () {
				tch.removeProgress();
				tch.showProgress(processMsg);
				return resetreboot($("#rebooting-msg"), $(this), "system_reboot");
			});
		});

		$("#btn-schedule-reboot").off("click" + NS).on("click" + NS, function () {
			var _date = $("#date_schedule").val();
			var _time = $("#time_schedule").val();
			var schedule_time = $("#date_schedule").val() + "T" + $("#time_schedule").val() + ":00Z";
			var temp = $("#system_time").text();
			var timeformat = temp.split(" ");
			temp = timeformat[0] + "T" + timeformat[1] + "Z";
			if (((_date && _time) != "") && (temp < schedule_time)) {
				$("#schedule-failed-msg").addClass("hide");
				$("#date_schedule").addClass("hide");
				$("#time_schedule").addClass("hide");
				$("#btn-schedule-reboot").addClass("hide");
				$(".schedule_message_get").removeClass("hide");

				$.post(
					target,
					{ action: "schedulerebootset", CSRFtoken: $("meta[name=CSRFtoken]").attr("content"), paramvalue: schedule_time },
					wait_for_webserver_down,
					"json"
				);
			} else {
				$("#schedule-failed-msg").removeClass("hide");
			}
		});

		$("#btn-system-reset").off("click" + NS).on("click" + NS, function () {
			var heading = cfg.factoryHeading || "";
			var processMsg = cfg.resetProcess || "";
			confirmationDialogue(cfg.confirmSpaceText || "", heading);
			var PopUpHeaderText = "." + $(".popUp>.header>.header-title>p").text().split(" ")[0];
			$(document).off("click" + NS, PopUpHeaderText).on("click" + NS, PopUpHeaderText, function () {
				tch.removeProgress();
				tch.showProgress(processMsg);
				return resetreboot($("#resetting-msg"), $(this), "system_reset");
			});
		});

		if (cfg.scheduleRebootGet == "1") {
			$("#date_schedule").addClass("hide");
			$("#time_schedule").addClass("hide");
			$("#btn-schedule-reboot").addClass("hide");
			$(".schedule_message_get").removeClass("hide");
		}

		$(document).on("click" + NS, "#cancel", function () {
			tch.removeProgress();
		});

		$(".export-config").off("click" + NS).on("click" + NS, function () {
			$.fileDownload(target, {
				httpMethod: "POST",
				data: [
					{ name: "action", value: "export_config" },
					{ name: "CSRFtoken", value: $("meta[name=CSRFtoken]").attr("content") }
				],
				prepareCallback: function () {
					$("#export-failed-msg").addClass("hide");
					var exporting_msg = $("#exporting-msg");
					exporting_msg.removeClass("hide");
					exporting_msg[0].scrollIntoView();
				},
				successCallback: function () {
					$("#exporting-msg").addClass("hide");
				},
				failCallback: function () {
					var export_failed_msg = $("#export-failed-msg");
					export_failed_msg.removeClass("hide");
					export_failed_msg[0].scrollIntoView();
					$("#exporting-msg").addClass("hide");
				}
			});
			return false;
		});

		$(".import-config").off("click" + NS).on("click" + NS, function () {
			var nofile_msg = $("#import-nofile-msg");
			var wrongext_msg = $("#import-wrong-ext-msg");
			var toobig_msg = $("#import-too-big-msg");
			if ($("#file-import").val() == "") {
				nofile_msg.removeClass("hide");
				nofile_msg[0].scrollIntoView();
				return false;
			}
			nofile_msg.addClass("hide");

			var validExtensions = ["bin"];
			var fileName = $("#file-import").val();
			var fileNameExt = fileName.substr(fileName.lastIndexOf(".") + 1);
			if ($.inArray(fileNameExt, validExtensions) == -1) {
				wrongext_msg.removeClass("hide");
				wrongext_msg[0].scrollIntoView();
				return false;
			}
			var fileSize = $("#file-import")[0].files[0].size;
			if (fileSize > 1048576) {
				toobig_msg.removeClass("hide");
				toobig_msg[0].scrollIntoView();
				return false;
			}

			var _this = $(this).parents(".control-group");
			$("#import-failed-msg").addClass("hide");
			var importing_msg = $("#importing-msg");
			importing_msg.removeClass("hide");
			importing_msg[0].scrollIntoView();
			$.fileUpload($("#form-import"), {
				params: { CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				completeCallback: function (form, response) {
					$("#importing-msg").addClass("hide");
					if (response.success) {
						var msg = $("#rebooting-msg");
						var msg_dst = $(_this);
						msg_dst.after(msg);
						msg.removeClass("hide");
						msg[0].scrollIntoView();
						wait_for_webserver_down();
					} else {
						$("#import-failed-msg").removeClass("hide");
						if (response.error == "buildversion") {
							$("#import-failed-msg").text(cfg.wrongBackupVersion || "");
						}
					}
				}
			});
			return false;
		});

		function wait_for_upgradefw() {
			var upgrfw_refreshTimeOut = 15000;
			var upgrfw_refreshDelay = 10000;
			var msg = $("#upgrade-busy-msg");
			var msg_dst = $(this);
			msg_dst.after(msg);
			msg.removeClass("hide");
			msg[0].scrollIntoView();
			function waitForShutdownOrError() {
				$.ajax({ url: target, data: "action=upgradefwstatus", timeout: upgrfw_refreshTimeOut, dataType: "json" })
				.done(function (data) {
					if (data.success == "true") {
						trackTimeout(waitForShutdownOrError, upgrfw_refreshDelay);
					} else {
						msg.addClass("hide");
						var failure_msg = $("#upgrade-failed-msg");
						switch (data.errorcode) {
						case "1":
							failure_msg.text(cfg.fwErrNoMem || "");
							break;
						case "10":
						case "255":
							failure_msg.text(cfg.fwErrInvalid || "");
							break;
						case "15":
							failure_msg.text(cfg.fwErrWrongKey || "");
							break;
						default:
							failure_msg.text(cfg.fwErrDefault || "");
							break;
						}
						failure_msg.text(failure_msg.text() + " (" + (cfg.fwErrCodePrefix || "") + data.errorcode + ")");
						failure_msg.removeClass("hide");
						failure_msg[0].scrollIntoView();
						tch.removeProgress();
					}
				})
				.fail(wait_for_webserver_running);
			}
			trackTimeout(waitForShutdownOrError, upgrfw_refreshDelay);
			return false;
		}

		$(".upgradefw").off("click" + NS).on("click" + NS, function () {
			var nofile_msg = $("#upgrade-nofile-msg");
			var wrongext_msg = $("#upgrade-wrong-ext-msg");
			var toobig_msg = $("#upgrade-too-big-msg");
			if ($("#file-upgradefw").val() == "") {
				nofile_msg.removeClass("hide");
				nofile_msg[0].scrollIntoView();
				return false;
			}
			nofile_msg.addClass("hide");

			var validExtensions = ["rbi", "fw"];
			var fileName = $("#file-upgradefw").val();
			var fileNameExt = fileName.substr(fileName.lastIndexOf(".") + 1);
			if ($.inArray(fileNameExt, validExtensions) == -1) {
				wrongext_msg.removeClass("hide");
				wrongext_msg[0].scrollIntoView();
				return false;
			}
			wrongext_msg.addClass("hide");
			var fileSize = $("#file-upgradefw")[0].files[0].size;

			$.ajax({ url: target, data: "action=getbanksize", timeout: refreshTimeOut, dataType: "json" })
				.done(function (data) {
					if (data.success == "true") {
						var targetBankSize = Number(data.banksize);
						if (fileSize > targetBankSize) {
							toobig_msg.removeClass("hide");
							toobig_msg[0].scrollIntoView();
							return false;
						}
					}
				});
			toobig_msg.addClass("hide");

			var _this = $(this).parents(".control-group");
			$("#upgrade-failed-msg").addClass("hide");
			var upgrading_msg = $("#upgrade-transfer-msg");
			upgrading_msg.removeClass("hide");
			upgrading_msg[0].scrollIntoView();
			tch.showProgress(cfg.upgradingText || "");
			var action = "modals/gateway-modal.lp?action=upgradefw";
			if ($("input[name='remove_conf_on_upgrade']").is(":checked")) action += "&upgrade_reset=1";
			if ($("input[name='rootonly_on_upgrade']").is(":checked")) action += "&upgrade_rootonly=1";

			$("#form-upgradefw").attr("action", action);
			$.fileUpload($("#form-upgradefw"), {
				params: { CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				completeCallback: function (form, response) {
					$("#upgrade-transfer-msg").addClass("hide");
					if (response.success) {
						wait_for_upgradefw.call(_this);
					} else {
						$("#upgrade-failed-msg").removeClass("hide");
					}
				}
			});
			return false;
		});
	};
}());
