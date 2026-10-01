var labelHide = $("[id='controllermac'], [id='agentmac']");
var stateBlock = $("[id='state@cred0'], [id='state@cred1'],[id='state@cred2']");
var fronthaulBlock = $("[id='fronthaul@cred0'], [id='fronthaul@cred1'],[id='fronthaul@cred2']");
var backhaulBlock = $("[id='backhaul@cred0'], [id='backhaul@cred1'],[id='backhaul@cred2']");

$(document).on("click", "#ok, #cancel", function() {
  tch.removeProgress();
});

if (typeof multiapAgent !== "undefined" && typeof multiapContr !== "undefined" && multiapAgent == "1" && multiapContr == "1") {
  stateBlock.closest(".control-group .controls").css({"pointer-events":"none","opacity":"0.5"});
  fronthaulBlock.closest(".control-group .controls").css({"pointer-events":"none","opacity":"0.5"});
  backhaulBlock.closest(".control-group .controls").css({"pointer-events":"none","opacity":"0.5"});
}

function updateTabsVisibility(enabled) {
  var $tabs = $(".nav-tabs li a").filter(function() {
    var txt = $.trim($(this).text());
    var id = $(this).attr("id");
    return (typeof extenderInfo !== "undefined" && extenderInfo && (txt === extenderInfo || id === extenderInfo)) ||
           (typeof agentList !== "undefined" && agentList && (txt === agentList || id === agentList)) ||
           (typeof devicesList !== "undefined" && devicesList && (txt === devicesList || id === devicesList));
  }).closest("li");
  if (enabled) {
    $tabs.show();
  } else {
    $tabs.hide();
  }
}

function easyMeshEnable() {
  $("#agentEnable").val("1");
  $("#controllerEnable").val("1");
  $("#wificonductorEnable").val("1");
  $("#wifibandsteerEnable").val("0");
  if (typeof isGuest !== "undefined" && isGuest) {
    $("#wifiGuestbandsteerEnable").val("0");
  }
  labelHide.closest(".control-group").show();
  $("#fronthaul-config-wrap").css({"opacity": "1", "pointer-events": "auto", "transition": "opacity 0.25s"});
  updateTabsVisibility(true);
}

function easyMeshDisable() {
  $("#agentEnable").val("0");
  $("#controllerEnable").val("0");
  $("#wificonductorEnable").val("0");
  if (typeof bandsteerDisabled !== "undefined" && bandsteerDisabled) {
    if (typeof ap0_state !== "undefined" && ap0_state == "1" && typeof ap1_state !== "undefined" && ap1_state == "1") {
      $("#wifibandsteerEnable").val("1");
    }
    var count = 0;
    if (typeof guestAP !== "undefined" && typeof content !== "undefined") {
      for (var ap in guestAP) {
        var apVal = guestAP[ap];
        if (content[apVal] == "1") {
          count = count + 1;
        }
      }
      if (count == guestAP.length && typeof isGuest !== "undefined" && isGuest && count > 1) {
        $("#wifiGuestbandsteerEnable").val("1");
      }
    }
  }
  labelHide.closest(".control-group").hide();
  $("#fronthaul-config-wrap").css({"opacity": "0.45", "pointer-events": "none", "transition": "opacity 0.25s"});
  updateTabsVisibility(false);
}

if ($("#easyMeshEnable").val() == "1") {
  easyMeshEnable();
} else {
  easyMeshDisable();
}

$("#easyMeshEnable").closest(".switch").on("click", function() {
  setTimeout(function() {
    var val = $("#easyMeshEnable").val();
    if (val == "1") {
      easyMeshEnable();
    } else {
      easyMeshDisable();
    }
  }, 60);
});
