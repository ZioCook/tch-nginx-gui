(function () {
	"use strict";

	var NS = ".wirelessModal";
	var BS_NS = ".wirelessModalBS";
	var aclStatusTimer = null;

	function getCfg() {
		var $els = $(".modal #wireless-modal-cfg");
		var el = $els.length ? $els.last()[0] : document.getElementById("wireless-modal-cfg");
		if (!el) return {};
		try {
			return JSON.parse(el.textContent || "{}") || {};
		} catch (e) {
			return {};
		}
	}

	function clearAclTimer() {
		if (aclStatusTimer !== null) {
			window.clearTimeout(aclStatusTimer);
			aclStatusTimer = null;
		}
	}

	window.initWirelessModal = function () {
		clearAclTimer();
		$("#save-config").off(BS_NS);

		var cfg = getCfg();

		$(".modal, #modal-container").off("hidden.bs.modal" + NS).on("hidden.bs.modal" + NS, function () {
			clearAclTimer();
			$("#save-config").off(BS_NS);
		});

		if (cfg.hasAnalyzer) {
			var maximum = -20;
			var minimum = -105;
			var range = 320;
			var bittarget40 = 10;
			var ctx;

			function get_random_color() {
				var letters = "0123456789ABCDEF".split("");
				var color = "#";
				for (var i = 0; i < 6; i++) {
					color += letters[Math.round(Math.random() * 15)];
				}
				return color;
			}

			function get_y_from_sig(max, min, rng, sig) {
				return ((sig - max) / ((min - max) / rng)) + 30;
			}

			function get_curve_y_from_sig(max, min, rng, sig) {
				var line = 350 - get_y_from_sig(max, min, rng, sig);
				line = 350 - (line * 2);
				return line;
			}

			function initializeAnalyzer() {
				var c = document.getElementById("wrapper");
				if (!c) return;
				ctx = c.getContext("2d");
				ctx.lineStyle = "#FF0000";

				ctx.moveTo(30, 30);
				ctx.lineTo(30, 350);
				ctx.stroke();

				var line10 = get_y_from_sig(maximum, minimum, range, -10);
				ctx.moveTo(30, line10);
				ctx.lineTo(25, line10);
				ctx.stroke();
				ctx.font = "9px Arial";
				ctx.fillText("-10", 7, line10 + 3);

				var line30 = get_y_from_sig(maximum, minimum, range, -30);
				ctx.moveTo(30, line30);
				ctx.lineTo(25, line30);
				ctx.stroke();
				ctx.font = "9px Arial";
				ctx.fillText("-30", 7, line30 + 3);

				var line60 = get_y_from_sig(maximum, minimum, range, -60);
				ctx.moveTo(30, line60);
				ctx.lineTo(25, line60);
				ctx.stroke();
				ctx.font = "9px Arial";
				ctx.fillText("-60", 7, line60 + 3);

				var line90 = get_y_from_sig(maximum, minimum, range, -90);
				ctx.moveTo(30, line90);
				ctx.lineTo(25, line90);
				ctx.stroke();
				ctx.font = "9px Arial";
				ctx.fillText("-90", 7, line90 + 3);

				ctx.moveTo(30, 350);
				if (cfg.is2G) {
					ctx.lineTo(690, 350);
				} else {
					ctx.lineTo(870, 350);
				}
				ctx.stroke();
				ctx.font = "9px Arial";
				ctx.fillText("Channel", 310, 390);
				ctx.save();
				ctx.translate(0, 0);
				ctx.textAlign = "center";
				ctx.fillText("Signal Strength (-dBm)", 60, 25);
				ctx.restore();

				if (cfg.is2G) {
					ctx.moveTo(120, 350);
					ctx.lineTo(120, 355);
					ctx.stroke();
					ctx.font = "9px Arial";
					ctx.fillText("1", 117, 370);
					ctx.moveTo(320, 350);
					ctx.lineTo(320, 355);
					ctx.stroke();
					ctx.font = "9px Arial";
					ctx.fillText("6", 317, 370);
					ctx.moveTo(520, 350);
					ctx.lineTo(520, 355);
					ctx.stroke();
					ctx.font = "9px Arial";
					ctx.fillText("11", 517, 370);
				} else {
					var chn_diff = 30;
					var chnl = 0;
					var i;
					for (i = 0; i <= 7; i++) {
						ctx.moveTo(60 + (chn_diff * i), 350);
						ctx.lineTo(60 + (chn_diff * i), 355);
						ctx.stroke();
						ctx.font = "9px Arial";
						chnl = 36 + (i * 4);
						ctx.fillText(chnl.toString(), 60 + (chn_diff * i) - 4, 370);
					}
					for (i = 10; i <= 27; i++) {
						ctx.moveTo(60 + (chn_diff * i), 350);
						ctx.lineTo(60 + (chn_diff * i), 355);
						ctx.stroke();
						ctx.font = "9px Arial";
						chnl = 60 + (i * 4);
						ctx.fillText(chnl.toString(), 60 + (chn_diff * i) - 6, 370);
					}
				}

				var headerCols = [
					$("<br/>"),
					$("<div>").addClass("col_ssid").text(cfg.tSsid || ""),
					$("<div>").addClass("col_channel").text(cfg.tChannel || ""),
					$("<div>").addClass("col_str").text(cfg.t40Mhz || "")
				];
				if (!cfg.is2G) {
					headerCols.push($("<div>").addClass("col_str").text(cfg.t80Mhz || ""));
				}
				headerCols.push($("<div>").addClass("col_rssi").text(cfg.tRssi || ""));
				headerCols.push($("<br/>"));
				$("#key").empty().append.apply($("#key"), headerCols);
			}

			function generateGraph(ssid, channel, rssi, capRaw) {
				var color = get_random_color();
				var Mhz = 1;
				var Str = "";
				var cap = parseInt(capRaw, 16).toString(2);
				while (cap.length <= 16) {
					cap = "0" + cap;
				}
				if (cap.charAt(cap.length - bittarget40) == "1") {
					Mhz = 2;
					Str = "*";
				}
				var sig = rssi;
				if (sig > maximum) { sig = maximum; } else if (sig < minimum) { sig = minimum; }

				var str40 = "";
				var str80 = "";
				if (cfg.is2G) {
					var xcoord2 = 80 + (channel * 40);
					ctx.beginPath();
					ctx.strokeStyle = color;
					ctx.moveTo(xcoord2 - (80 * Mhz), 350);
					ctx.quadraticCurveTo(xcoord2, get_curve_y_from_sig(maximum, minimum, range, sig), xcoord2 + (80 * Mhz), 350);
					ctx.stroke();
				} else {
					var chlist40 = [38, 46, 54, 62, 102, 110, 118, 126, 134, 142];
					var chlist80 = [42, 58, 106, 122, 138];
					var i;
					for (i = 0; i <= chlist40.length; i++) {
						if (chlist40[i] == channel) {
							str40 = "*";
							Mhz = 2;
						}
					}
					for (i = 0; i <= chlist80.length; i++) {
						if (chlist80[i] == channel) {
							str80 = "*";
							Mhz = 4;
						}
					}
					var xcoord5 = (channel <= 64) ? (60 + ((channel - 36) * 7.5)) : (360 + ((channel - 100) * 7.5));
					ctx.beginPath();
					ctx.strokeStyle = color;
					ctx.moveTo(xcoord5 - (15 * Mhz), 350);
					ctx.quadraticCurveTo(xcoord5, get_curve_y_from_sig(maximum, minimum, range, sig), xcoord5 + (15 * Mhz), 350);
					ctx.stroke();
				}

				var row = $("<div>").css("color", color);
				$("#key").append(row);
				var cols = [
					$("<div>").addClass("col_ssid").text(ssid),
					$("<div>").addClass("col_channel").text(channel)
				];
				if (cfg.is2G) {
					cols.push($("<div>").addClass("col_str").text(Str));
				} else {
					cols.push($("<div>").addClass("col_str").text(str40));
					cols.push($("<div>").addClass("col_str").text(str80));
				}
				cols.push($("<div>").addClass("col_rssi").text(rssi));
				cols.push($("<br/>"));
				$(row).append.apply($(row), cols);
			}

			function show_rescanconfirming(freq, show) {
				var msg_id = "confirming-msg_" + freq;
				var rescan_id = "rescan-changes_" + freq;
				if (show == 1) {
					$("div[id^= " + rescan_id + "]").show();
					$("div[id^= " + msg_id + "]").show();
				} else {
					$("div[id^= " + rescan_id + "]").hide();
					$("div[id^= " + msg_id + "]").hide();
				}
			}

			$("div[id^='ReScan_']").off("click" + NS).on("click" + NS, function () {
				var freq = (this.id).split("_")[1];
				show_rescanconfirming(freq, 1);
			});

			$("div[id^='rescan-cancel_']").off("click" + NS).on("click" + NS, function () {
				var freq = (this.id).split("_")[1];
				show_rescanconfirming(freq, 0);
			});

			$("div[id^='rescan-confirm_']").off("click" + NS).on("click" + NS, function () {
				var freq = (this.id).split("_")[1];
				show_rescanconfirming(freq, 0);

				var params = [];
				params.push({ name: "action", value: "rescan" });
				params.push({ name: "curradio", value: cfg.radio || "" });
				params.push(tch.elementCSRFtoken());
				tch.showProgress((cfg.tRescanning || "") + "...");
				$.post("/modals/wireless-modal.lp", params, function (acsData) {
					tch.removeProgress();
					initializeAnalyzer();
					if (acsData.length > 0) {
						$.each(acsData, function (i, data) {
							generateGraph(data.ssid, data.channel, data.rssi, data.cap);
						});
					}
				});
			});

			initializeAnalyzer();
			$.get("/modals/wireless-modal.lp?isWifiAnalyzer=" + encodeURIComponent(cfg.wifiAnalyzer || "") + "&getAcsData=true&radio=" + encodeURIComponent(cfg.radio || ""), function (acsData) {
				$("#analyzerloader").addClass("hide");
				$("#analyzerGraph").removeClass("hide");
				$("#analyzerloader1").addClass("hide");
				$.each(acsData, function (i, data) {
					generateGraph(data.ssid, data.channel, data.rssi, data.cap);
				});
			});
		}

		if (!cfg.isTableLoaded) {
			$.get(
				"/modals/wireless-modal.lp?radio=" + encodeURIComponent(cfg.curradio || "") +
				"&iface=" + encodeURIComponent(cfg.curiface || "") +
				"&action=GET_ACL_MAC_LIST&acl_mode=" + encodeURIComponent(cfg.aclMode || ""),
				function (data) {
					$("#acl_list_div").replaceWith(data);
				}
			);
		}

		function show_linkconfirming(freq, show) {
			var msg_id = "linkconfirming-msg_" + freq;
			var link_id = "linkrescan-changes_" + freq;

			if (show == 1) {
				$("div[id = " + link_id + "]").show();
				$("div[id = " + msg_id + "]").show();
			} else {
				$("div[id = " + link_id + "]").hide();
				$("div[id = " + msg_id + "]").hide();
			}
		}

		$("a[id^='wifianalyzer_']").off("click" + NS).on("click" + NS, function () {
			var iface = (this.id).split("_")[1];
			var freq = iface.split(".")[0];
			show_linkconfirming(freq, 1);
			return false;
		});

		$("div[id^='linkrescan-confirm_']").off("click" + NS).on("click" + NS, function () {
			var iface = (this.id).split("_")[1];
			var freq = iface.split(".")[0];
			show_linkconfirming(freq, 0);
		});

		$("div[id^='linkrescan-cancel_']").off("click" + NS).on("click" + NS, function () {
			var iface = (this.id).split("_")[1];
			var freq = iface.split(".")[0];
			show_linkconfirming(freq, 0);
		});

		$("#aclmode").off("change" + NS).on("change" + NS, function () {
			var aclmode = $(this).val();
			if (aclmode == "register") {
				$("#acl_whitelist").attr("id", "acl_register");
			} else {
				$("#acl_register").attr("id", "acl_whitelist");
			}
		});

		if (cfg.aclModeChanged) {
			$("#modal-no-change").hide();
			$("#modal-changes").show();
		}

		function get_status_acl() {
			$("#btn_acl").attr("disabled", true);
			clearAclTimer();
			aclStatusTimer = window.setTimeout(function () {
				$.get("/modals/wireless-modal.lp?action=get_reg_status&curap=" + encodeURIComponent(cfg.curap || ""), function (res) {
					if (res != "register") {
						get_status_acl();
					} else {
						$("#btn_acl").removeAttr("disabled", false);
					}
					$("#btn_acl").html(res);
				});
			}, 5000);
		}

		$("#btn_acl").off("click" + NS).on("click" + NS, function () {
			if ($("#btn_acl").attr("disabled") != undefined) return false;
			$.post(
				"/modals/wireless-modal.lp",
				{ action: "set_reg", curap: cfg.curap || "", CSRFtoken: $("meta[name=CSRFtoken]").attr("content") },
				get_status_acl
			);
		});

		var bschecked = $('input[id="band_steer_enabled"]').val();
		if ("1" == bschecked) {
			$('option[value="wep"]').hide();
			$('option[value="wpa-wpa2"]').hide();
			$('option[value="wpa2"]').hide();
			$('option[value="wpa"]').hide();

			$("#save-config").off("click" + BS_NS).on("click" + BS_NS, function () {
				var params = [
					{ name: "ssidName", value: $("#ssid").val() },
					{ name: "wpa_psk", value: $("#wpa_psk").val() },
					{ name: "security", value: $("#security").val() },
					{ name: "curradio", value: cfg.curradio || "" },
					{ name: "curiface", value: cfg.curiface || "" },
					{ name: "CSRFtoken", value: $("meta[name=CSRFtoken]").attr("content") },
					{ name: "action", value: "bs_check" }
				];
				$.post(
					"/modals/wireless-modal.lp?radio=" + encodeURIComponent(cfg.curradio || "") + "&iface=" + encodeURIComponent(cfg.curiface || ""),
					params
				);
			});
		}

		$('input[id="band_steer_enabled"]').off("click" + NS).on("click" + NS, function () {
			if ("1" == bschecked) {
				$('option[value="wep"]').hide();
				$('option[value="wpa-wpa2"]').hide();
				$('option[value="wpa2"]').hide();
				$('option[value="wpa"]').hide();
			}
		});

		$("#guest_network_switch").off("change" + NS).on("change" + NS, function () {
			var newState = $(this).val() === "1" ? "1" : "0";
			$.post("/modals/wireless-modal.lp", {
				action: "toggle_guest",
				guest_state: newState,
				CSRFtoken: $("meta[name=CSRFtoken]").attr("content")
			}, function (data) {
				if (data && data.success) {
					location.reload();
				}
			}, "json");
		});
	};
}());
