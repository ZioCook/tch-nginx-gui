--pretranslated: do not change this file

-- Localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")

local header = '<span id="header_title">'..T"Executing"..'</span><span id="show_progress"></span>'

ngx.print(ui_helper.createHeader(header, false, false))

local html = {}

html[#html + 1] = [[
<div class="modal-body update fake_console">
  <form class="form-horizontal" id="commandlogmodal" method="post" action="/modals/command-log-read-modal.lp">
<style>
  #modal-container .modal-action-close,
  #modal-container .modal-footer,
  .modal-action-close,
  .modal-footer {
    display: none !important;
  }
  .upgrade-finished .modal-action-close,
  .upgrade-finished.modal .modal-action-close,
  #modal-container.upgrade-finished .modal-action-close {
    display: block !important;
  }
  .upgrade-finished .modal-footer,
  .upgrade-finished.modal .modal-footer,
  #modal-container.upgrade-finished .modal-footer {
    display: block !important;
  }
  .upgrade-finished #close-config,
  .upgrade-finished #modal-no-change {
    display: inline-block !important;
  }
</style>
]]

html[#html + 1] = '<fieldset class="modal-body" id="upgrade-gui-bar" style="min-height: unset; margin-bottom: 15px;">'
html[#html + 1] = '<div class="alert alert-info" style="margin-bottom: 0;">'
html[#html + 1] = '<div style="display: flex; justify-content: space-between; font-weight: bold; margin-bottom: 6px;"><span id="update-text">'..T"Operation in progress... Please wait."..'</span><span id="progress-percent">0%</span></div>'
html[#html + 1] = '  <div class="progress progress-striped active" style="margin-bottom: 0;">'
html[#html + 1] = '     <div id="upgrade-progress-bar-fill" class="bar bar-warning" role="progressbar" style="width: 5%;" aria-valuenow="5" aria-valuemin="0" aria-valuemax="100"></div>'
html[#html + 1] = '</div></div>'
html[#html + 1] = '</fieldset>'
html[#html + 1] = '<fieldset>'
html[#html + 1] = '<div id="command-log-text-container" style="white-space: pre-wrap; font-family: monospace; font-size: 12px; max-height: min(280px, 35vh); overflow-y: auto; scroll-behavior: smooth; background: rgba(0,0,0,0.05); padding: 8px; border-radius: 4px;" data-bind="log_text: log">'
html[#html + 1] = '[Inizializzazione] Avvio operazione in corso...'
html[#html + 1] = '</div>'
html[#html + 1] = '</fieldset>'

html[#html + 1] = [[
  </form>
</div>
<script>
	var requestInProgress = false;
	var isUpgradeComplete = false;
	var hasStartedExecution = false;
	var pollCount = 0;
	var consecutiveFailures = 0;

	var lastProgress = 5;
	var targetVer = "";
	var cmdAction = "<%= ngx.req.get_uri_args().cmd_action or '' %>";
	var isGuiUpgrade = (cmdAction === "system_upgrade_gui") || (cmdAction === "upgradeguifile") || (cmdAction === "autoupgrade_view");
	window.isUpgrading = isGuiUpgrade;

	var $activeModal = $("#modal-container, .modal");
	$activeModal.data("backdrop", "static");
	$activeModal.data("keyboard", false);
	$(".modal-backdrop").off("click").css("cursor", "default");
	$(document).off("keydown.bs.modal");
	$(".modal-footer, .modal-action-close, #close-config").hide();

	var CommandLogReadRefresh = function CommandLogReadRefresh(ElementBinding) {
		if (!isUpgradeComplete) {
			$(".modal-footer, .modal-action-close, #close-config").hide();
		}
		if (!requestInProgress && !isUpgradeComplete) {
			requestInProgress = true;
			$.ajax({
				url: "/ajax/commandlogread.lua?auto_update=true",
				type: "POST",
				data: {
					CSRFtoken: $("meta[name=CSRFtoken]").attr("content")
				},
				complete: function(data) { requestInProgress = false; },
				dataType: "json"
			})
			.done(function(data) {
				pollCount++;
				consecutiveFailures = 0;
				var clean_log = (data.log || "")
					.replace(/\x1b\x5b[0-9;]*[a-zA-Z]/g, "")
					.replace(/^[-#=O\s]*\d+\.?\d*%\s*$/gm, "")
					.replace(/^[-#=O\s]+$/gm, "")
					.replace(/\n\s*\n/g, "\n");
				if (!clean_log) {
					if (data.state == "Extracting") {
						clean_log = "[1/3] Download pacchetto completato (100%).\n[2/3] Estrazione e installazione file GUI in corso...";
					} else if (data.state == "In Progress") {
						clean_log = "[1/3] Download pacchetto completato.\n[2/3] Estrazione file completata.\n[3/3] Configurazione e migrazione overlay in corso...";
					} else if (data.state == "Downloading") {
						clean_log = "[1/3] Download pacchetto in corso" + (data.progress ? " (" + Math.round(data.progress) + "%)" : "") + "...";
					} else {
						clean_log = "[Inizializzazione] Avvio procedura di aggiornamento in corso...";
					}
				}
				if (ElementBinding && typeof ElementBinding.log === "function") {
					try { ElementBinding.log(clean_log); } catch(e) {}
				}
				$("#command-log-text-container").text(clean_log);
				var $logElem = $("#command-log-text-container, [data-bind*='log_text']");
				if ($logElem.length && $logElem[0]) {
					$logElem.scrollTop($logElem[0].scrollHeight);
				}

				var header_text = $("#header_title").text();
				if (data.state && header_text != data.state) $("#header_title").text(data.state);

				var targetProgress = 5;
				var stageText = "Avvio procedura di aggiornamento...";

				if (data.state == "Downloading" || (data.progress !== undefined && data.progress > 0)) {
					hasStartedExecution = true;
					var dlPct = (data.progress !== undefined) ? Math.round(data.progress) : 0;
					targetProgress = Math.min(50, Math.max(5, Math.round(dlPct * 0.50)));
					stageText = "Download pacchetto GUI (" + dlPct + "%)... Non spegnere il modem";
				} else if (data.state == "Clearing" || (clean_log && clean_log.indexOf("Cleaning www") !== -1)) {
					hasStartedExecution = true;
					targetProgress = 58;
					stageText = "Download completato (100%). Preparazione file di sistema...";
				} else if (data.state == "Extracting" || (clean_log && clean_log.indexOf("Extracting GUI") !== -1)) {
					hasStartedExecution = true;
					targetProgress = 75;
					stageText = "Estrazione e decompressione componenti GUI (75%)...";
				} else if (data.state == "In Progress" || (clean_log && clean_log.indexOf("Root Script") !== -1)) {
					hasStartedExecution = true;
					if (clean_log.indexOf("transformer") !== -1 || clean_log.indexOf("restarting services") !== -1) {
						targetProgress = 96;
						stageText = "Riavvio servizi di rete e finalizzazione (96%)...";
					} else if (clean_log.indexOf("05_app") !== -1 || clean_log.indexOf("Adblock") !== -1 || clean_log.indexOf("Trafficmon") !== -1) {
						targetProgress = 90;
						stageText = "Configurazione estensioni e overlay (90%)...";
					} else {
						targetProgress = 83;
						stageText = "Applicazione script di root e permessi (83%)...";
					}
				} else if (clean_log && clean_log.indexOf("Upgrade Script") !== -1) {
					hasStartedExecution = true;
					targetProgress = 15;
					stageText = "Inizializzazione procedura di aggiornamento...";
				}

				if (targetProgress > lastProgress) {
					lastProgress = targetProgress;
				}

				if (hasStartedExecution) {
					$("#upgrade-gui-bar").removeClass("hide");
					$("#upgrade-progress-bar-fill").css("width", lastProgress + "%").attr("aria-valuenow", lastProgress);
					if (lastProgress >= 50 && lastProgress < 100) {
						$("#upgrade-progress-bar-fill").removeClass("bar-warning").addClass("bar-info");
					}
					$("#progress-percent").text(lastProgress + "%");
					$("#update-text").text(stageText);
				}

				$("#show_progress").text($("#show_progress").text().replace(/\.{10}/g, ""));
				$("#show_progress").append(".");
				if (!isGuiUpgrade) {
					isGuiUpgrade = !!targetVer || (clean_log && (
						clean_log.indexOf("Upgrade Script") !== -1 ||
						clean_log.indexOf("Downloading GUI") !== -1 ||
						clean_log.indexOf("Cleaning www") !== -1 ||
						clean_log.indexOf("Extracting GUI") !== -1 ||
						clean_log.indexOf("Root Script") !== -1 ||
						clean_log.indexOf("version_gui=") !== -1
					));
				}

				var hasFatalError = clean_log && /(?:Upgrade Script ERROR:|Root Script ERROR:|File corrupted|not enough space)/i.test(clean_log);
				var isFailed = (data.state == "Failed" || data.state == "Error") || hasFatalError;

				var isUpgradeDoneInLog = clean_log && (
					clean_log.indexOf("Upgrade Done") !== -1 ||
					clean_log.indexOf("Process complete, restarting services") !== -1
				);

				var isSuccess = false;
				if (isGuiUpgrade) {
					// GUI upgrade is only completed when state is explicitly Complete or log says Upgrade Done
					isSuccess = !isFailed && ((data.state == "Complete") || isUpgradeDoneInLog);
				} else {
					// For non-upgrade utilities (app install/remove, etc.)
					isSuccess = !isFailed && ((data.state == "Complete") || (data.state == "Idle" && hasStartedExecution && pollCount >= 6));
				}

				if (!isUpgradeComplete && (isSuccess || isFailed)) {
					isUpgradeComplete = true;
					if (KoRequest.CommandLogReadInterval) {
						KoRequest.CommandLogReadInterval.active = false;
						if (KoRequest.CommandLogReadInterval.timer) clearTimeout(KoRequest.CommandLogReadInterval.timer);
						if (KoRequest.CommandLogReadInterval.interval) clearInterval(KoRequest.CommandLogReadInterval.interval);
					}
					$("#upgrade-gui-bar").removeClass("hide");
					$("#show_progress").text("");
					if (data.new_version_text && data.new_version_text !== "Unknown") {
						targetVer = data.new_version_text;
					} else if (!targetVer) {
						var matchVer = clean_log.match(/version_gui=([0-9]+\.[0-9]+\.[0-9]+)/i) || clean_log.match(/Online version:\s*([0-9]+\.[0-9]+\.[0-9]+)/i);
						if (matchVer && matchVer[1]) targetVer = matchVer[1];
					}

					if (isSuccess) {
						$("#upgrade-progress-bar-fill").css("width", "100%").removeClass("bar-warning bar-info bar-danger").addClass("bar-success");
						$("#progress-percent").text("100%");
						if (isGuiUpgrade) {
							var successMsg = "Aggiornamento completato con successo" + (targetVer ? " alla versione v" + targetVer : "") + "!";
							try { sessionStorage.setItem("gui_upgrade_success", successMsg); } catch(e) {}
							$("#header_title").text("Aggiornamento Completato");
							var countdown = 3;
							$("#update-text").html("Aggiornamento completato con successo!<br><span style='font-size: 13px; font-weight: normal; opacity: 0.9;'>Reindirizzamento automatico al login in <strong id='redirect-countdown'>" + countdown + "</strong>s...</span>");
							var redirectTimer = setInterval(function() {
								countdown--;
								if ($("#redirect-countdown").length) $("#redirect-countdown").text(countdown);
								if (countdown <= 0) {
									clearInterval(redirectTimer);
									window.location.href = "/login.lp" + (targetVer ? "?upgraded_version=" + encodeURIComponent(targetVer) : "");
								}
							}, 1000);
						} else {
							$("#header_title").text("Operazione Completata");
							$("#update-text").text("Operazione completata con successo!");
							var redirectTimer = setTimeout(function() {
								window.location.reload(true);
							}, 1800);
						}
					} else {
						$("#upgrade-progress-bar-fill").css("width", "100%").removeClass("bar-warning bar-info").addClass("bar-danger");
						$("#update-text").text(isGuiUpgrade ? "Aggiornamento non riuscito." : "Operazione non riuscita o terminata con errore.");
						$("#header_title").text("Errore");
					}
					$("body, .modal, #modal-container").addClass("upgrade-finished");
					$(".modal-footer").show().css("display", "block");
					$("#modal-no-change").show().css("display", "block");
					$("#close-config").show().css("display", "inline-block");
					$(".modal-action-close").show().css("display", "block");
					$("#close-config, .modal-action-close, .btn-close").off("click").on("click", function(e) {
						e.preventDefault();
						if (typeof redirectTimer !== "undefined") {
							clearInterval(redirectTimer);
							clearTimeout(redirectTimer);
						}
						if (isGuiUpgrade && isSuccess) {
							window.location.href = "/login.lp" + (targetVer ? "?upgraded_version=" + encodeURIComponent(targetVer) : "");
						} else {
							window.location.reload(true);
						}
					});
				}
			})
			.fail(function(data) {
				consecutiveFailures++;
				var isAuthRedirect = (data.status == 200 && data.responseText && data.responseText.indexOf("sign-me-in") !== -1);
				
				// Se Nginx ha riavviato i servizi, ha azzerato le sessioni in memoria. Se l'aggiornamento era già in fase avanzata (>= 75% o almeno 12 fallimenti di transizione), l'update è completato!
				if (isAuthRedirect && (lastProgress >= 75 || consecutiveFailures >= 12)) {
					if (!isUpgradeComplete) {
						isUpgradeComplete = true;
						window.isUpgrading = false;
						if (KoRequest.CommandLogReadInterval) {
							KoRequest.CommandLogReadInterval.active = false;
							if (KoRequest.CommandLogReadInterval.timer) clearTimeout(KoRequest.CommandLogReadInterval.timer);
							if (KoRequest.CommandLogReadInterval.interval) clearInterval(KoRequest.CommandLogReadInterval.interval);
						}
						$("#upgrade-gui-bar").removeClass("hide");
						$("#upgrade-progress-bar-fill").css("width", "100%").removeClass("bar-warning bar-info bar-danger").addClass("bar-success");
						$("#progress-percent").text("100%");
						$("#header_title").text("Aggiornamento Completato");
						
						var successMsg = "Aggiornamento completato con successo" + (targetVer ? " alla versione v" + targetVer : "") + "!";
						try { sessionStorage.setItem("gui_upgrade_success", successMsg); } catch(e) {}
						
						var countdown = 4;
						$("#update-text").html("Aggiornamento completato con successo!<br><span style='font-size: 13px; font-weight: normal; opacity: 0.9;'>Reindirizzamento automatico alla pagina di accesso in <strong id='redirect-countdown'>" + countdown + "</strong>s...</span>");
						var redirectTimer = setInterval(function() {
							countdown--;
							if ($("#redirect-countdown").length) $("#redirect-countdown").text(countdown);
							if (countdown <= 0) {
								clearInterval(redirectTimer);
								window.location.href = "/login.lp" + (targetVer ? "?upgraded_version=" + encodeURIComponent(targetVer) : "");
							}
						}, 1000);
						$("body, .modal, #modal-container").addClass("upgrade-finished");
						$(".modal-footer, #close-config, .modal-action-close").show().css("display", "block");
						return;
					}
				}

				if (hasStartedExecution) {
					// Durante l'estrazione e il riavvio dei servizi il webserver è temporaneamente non raggiungibile.
					// Facciamo avanzare la barra con gradualità e non usciamo prematuramente prima che l'estrazione sia reale!
					if (lastProgress < 75) {
						lastProgress = 75;
					} else if (lastProgress < 95 && consecutiveFailures >= 6) {
						lastProgress = 95;
					}
					$("#upgrade-gui-bar").removeClass("hide");
					$("#upgrade-progress-bar-fill").css("width", lastProgress + "%").removeClass("bar-warning bar-danger").addClass("bar-info");
					$("#progress-percent").text(lastProgress + "%");
					$("#update-text").html("Estrazione e riavvio servizi in corso (" + lastProgress + "%)...<br><span style='font-size: 13px; font-weight: normal; opacity: 0.9;'>In attesa che il router torni online, non spegnere il modem...</span>");

					// Solo dopo che sono trascorsi almeno 15-20 secondi di estrazione verifichiamo la risposta effettiva di /login.lp
					if (consecutiveFailures >= 15) {
						$.ajax({
							url: "/login.lp",
							type: "GET",
							cache: false,
							timeout: 3000,
							success: function(resp) {
								if (resp && (resp.indexOf("login") !== -1 || resp.indexOf("CSRFtoken") !== -1 || resp.indexOf("Gateway") !== -1)) {
									if (!isUpgradeComplete) {
										isUpgradeComplete = true;
										window.isUpgrading = false;
										$("#upgrade-progress-bar-fill").css("width", "100%").removeClass("bar-warning bar-info bar-danger").addClass("bar-success");
										$("#progress-percent").text("100%");
										$("#header_title").text("Aggiornamento Completato");
										var successMsg = "Aggiornamento completato con successo" + (targetVer ? " alla versione v" + targetVer : "") + "!";
										try { sessionStorage.setItem("gui_upgrade_success", successMsg); } catch(e) {}
										
										var countdown = 4;
										$("#update-text").html("Aggiornamento completato con successo!<br><span style='font-size: 13px; font-weight: normal; opacity: 0.9;'>Reindirizzamento alla schermata di accesso in <strong id='redirect-countdown'>" + countdown + "</strong>s...</span>");
										var redirectTimer = setInterval(function() {
											countdown--;
											if ($("#redirect-countdown").length) $("#redirect-countdown").text(countdown);
											if (countdown <= 0) {
												clearInterval(redirectTimer);
												window.location.href = "/login.lp" + (targetVer ? "?upgraded_version=" + encodeURIComponent(targetVer) : "");
											}
										}, 1000);
										$("body, .modal, #modal-container").addClass("upgrade-finished");
										$(".modal-footer, #close-config, .modal-action-close").show().css("display", "block");
									}
								}
							}
						});
					}
				}
				$("#show_progress").text($("#show_progress").text().replace(/\.{10}/g, ""));
				$("#show_progress").append('<span style="color: red;">.</span>');
			});

		}
	};

	modgui.createAjaxUpdateCard("commandlogmodal", null, "CommandLogReadInterval", 1000, CommandLogReadRefresh);
	setTimeout(function() {
		CommandLogReadRefresh();
	}, 100);

	$(window).on("focus", function() {
		if (!isUpgradeComplete) {
			CommandLogReadRefresh();
		}
	});
</script>
]]

ngx.print(html)
ngx.print(ui_helper.createFooter())
