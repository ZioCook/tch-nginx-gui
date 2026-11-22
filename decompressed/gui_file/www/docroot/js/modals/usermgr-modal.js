(function () {
	"use strict";

	var NS = ".usermgrModal";

	function getCfg() {
		var $els = $(".modal #usermgr-modal-cfg");
		var el = $els.length ? $els.last()[0] : document.getElementById("usermgr-modal-cfg");
		if (!el) return {};
		try {
			return JSON.parse(el.textContent || "{}") || {};
		} catch (e) {
			return {};
		}
	}

	function passwordCheck(password) {
		var level = 0;

		if (password.length >= 6) level++;
		if ((password.match(/[a-z]/)) && (password.match(/[A-Z]/))) level++;
		if (password.match(/\d+/)) level++;
		if (password.match(/[!,@,#,$,%,^,&,*,?,_,~,-,(,)]/)) level++;
		if (password.length >= 8) level++;

		$("#Strength").removeClass().addClass("strength" + level);
		return level;
	}

	// Required by inline onkeyup="passwordCheck(this.value)" in usermgr-modal.lp
	window.passwordCheck = passwordCheck;

	window.initUsermgrModal = function () {
		var cfg = getCfg();
		window.ensureScript("/js/srp-min.js", function () { return typeof SRP === "function"; });

		var oldusername = $('input[name="name"]').val();
		if (cfg.editedUserName) {
			oldusername = cfg.editedUserName;
		}

		function clear_error_password() {
			var upass = $('.modal input[name="password"],.modal input[name="password2"],.modal input[name="oldpassword"]');
			upass.removeClass("tooltip-on error");
			upass.closest(".control-group").removeClass("error");
			upass.next().remove();
		}

		function display_error_password(msg) {
			var upass = $('.modal input[name="password"],.modal input[name="password2"]');
			upass.addClass("error");
			upass.closest(".control-group").addClass("error");
			upass.first().after('<span class="help-inline">' + msg + '</span>');
		}

		function display_error_message(msg) {
			var upass = $('.modal input[name="password"]');
			upass.addClass("error");
			upass.closest(".control-group").addClass("error");
			upass.first().after('<span class="help-inline">' + msg + '</span>');
		}

		function display_info_message(msg) {
			var upass = $('.modal input[name="password"]');
			upass.addClass("info");
			upass.closest(".control-group").addClass("info");
			upass.first().after('<span class="help-inline">' + msg + '</span>');
		}

		function clear_error_user() {
			var uinput = $('.modal input[name="name"]');
			uinput.removeClass("tooltip-on").removeClass("error");
			uinput.closest(".control-group").removeClass("error");
		}

		function display_error_user() {
			var uinput = $('.modal input[name="name"]');
			uinput.addClass("tooltip-on error");
			uinput.attr("placement", "top");
			uinput.attr("data-original-title", cfg.emptyUser || "");
			uinput.closest(".control-group").addClass("error");
			$(".tooltip-on").tooltip();
		}

		$(".modal .btn-table-modify").removeClass("btn-table-modify").addClass("btn-table-modify-custom");
		$(".modal .btn-table-add").removeClass("btn-table-add").addClass("btn-table-add-custom");
		$(".modal .btn-table-modify-custom,.modal .btn-table-add-custom")
			.off("click" + NS)
			.on("click" + NS, function () {
				clear_error_user();
				clear_error_password();

				var self = this;
				var user = $('input[name="name"]').val();
				var password = $('input[name="password"]').val();
				var password2 = $('input[name="password2"]').val();
				if (user == "") {
					display_error_user();
					return;
				}

				if ((password.length < 12) || (passwordCheck(password)) < 5) {
					if (password.length == 0) {
						display_error_message(cfg.providePassword || "");
						return;
					} else {
						display_error_message(cfg.weakPassword || "");
						display_info_message(cfg.securityRiskWarning || "");
					}
				}

				if (password !== password2) {
					display_error_password(cfg.passwordsMismatch || "");
					return;
				}

				function sendData(cryptpw) {
					var target = $(".modal form").attr("action");
					var table = $(self).closest("table");
					var id = table.attr("id");
					var line = $(self).closest("tr");
					var index = line.index();
					var action;
					var params = table.find(".line-edit :input").serializeArray();

					if ($(self).hasClass("btn-table-add-custom")) {
						action = "TABLE-ADD";
					} else {
						action = "TABLE-MODIFY";
						index = index - 2;
					}
					var add_params = table.find(".additional-edit :input").serializeArray();
					params = params.concat(add_params);
					params.push({ name: "tableid", value: id });
					params.push({ name: "stateid", value: table.attr("data-stateid") });
					params.push({ name: "action", value: action });
					params.push({ name: "cryptpw", value: cryptpw });
					params.push({ name: "index", value: index + 1 });
					params.push(tch.elementCSRFtoken());
					tch.loadModal(target, params, function () {
						tch.scrollRowIntoView(id, index);
					});
				}

				window.ensureScript("/js/srp-min.js", function () { return typeof SRP === "function"; }, function () {
					var srp = new SRP();
					function generateSaltAndVerifier() {
						srp.generateSaltAndVerifierTheCallback(user, password, function (salt, verifier, cryptpw) {
							$('input[name="srp_salt"]').val(salt);
							$('input[name="srp_verifier"]').val(verifier);
							$('input[name="password"]').val("");
							$('input[name="password2"]').val("");
							$('input[name="oldpassword"]').val("");
							sendData(cryptpw);
						});
					}

					if ((password.length < 12) || (passwordCheck(password)) < 5) {
						setTimeout(srp.success = generateSaltAndVerifier, 2000);
					} else {
						srp.success = generateSaltAndVerifier;
					}

					srp.error_message = function () {
						var upass = $('.modal input[name="oldpassword"]');
						upass.addClass("error");
						upass.closest(".control-group").addClass("error");
						upass.first().after('<span class="help-inline">' + (cfg.oldPasswordIncorrect || "") + '</span>');
					};
					var oldpassword = $('input[name="oldpassword"]').val();
					if (oldpassword != undefined) {
						var legacySalts = cfg.legacySalts || "";
						var userNames = cfg.userNames || "";
						var index = -1;
						var userNameArray = userNames.split(",");
						var legacySaltArray = legacySalts.split(",");

						for (var i = 0; i < userNameArray.length - 1; i++) {
							if (oldusername == userNameArray[i]) {
								index = i;
							}
						}

						if (index >= 0) {
							var hashObj = new jsSHA((legacySaltArray[index] + tch.stringToHex(oldpassword)), "HEX");
							oldpassword = hashObj.getHash("SHA-1", "HEX");
						}

						srp.identify("/modals/usermgr-modal.lp", oldusername, oldpassword);
					} else {
						generateSaltAndVerifier();
					}
				});
			});

		if ($("#Strength").length === 0) {
			$("#usrmodal_password").parent().after('<div class = "controls"><div id="Strength"></div></div>');
			$("#repeat_pass").parent().css("padding-top", "5px");
		}
	};
}());
