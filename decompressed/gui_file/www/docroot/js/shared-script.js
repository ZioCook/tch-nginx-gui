var KoRequest={};var connectionissue=0;
var _loadedScripts={};
function ensureScript(url,checkFn,cb){
    if(typeof checkFn==="function"&&checkFn()){if(typeof cb==="function")cb();return;}
    var entry=_loadedScripts[url];
    if(entry){
        if(entry.done){if(typeof cb==="function")cb();return;}
        if(typeof cb==="function")entry.cbs.push(cb);
        return;
    }
    entry={done:false,cbs:typeof cb==="function"?[cb]:[]};
    _loadedScripts[url]=entry;
    var srcUrl=url;
    if(srcUrl.indexOf("?")===-1&&typeof gui_var!=="undefined"&&gui_var.gui_version){
        srcUrl+="?version="+encodeURIComponent(gui_var.gui_version);
    }
    var s=document.createElement("script");
    s.src=srcUrl;
    s.async=true;
    s.onload=s.onreadystatechange=function(){
        if(s.readyState&&s.readyState!=="loaded"&&s.readyState!=="complete")return;
        s.onload=s.onreadystatechange=s.onerror=null;
        entry.done=true;
        var list=entry.cbs.splice(0,entry.cbs.length);
        for(var i=0;i<list.length;i++){list[i]();}
    };
    s.onerror=function(){
        s.onload=s.onreadystatechange=s.onerror=null;
        delete _loadedScripts[url];
        if(s.parentNode)s.parentNode.removeChild(s);
    };
    (document.head||document.documentElement).appendChild(s);
}
window.ensureScript=ensureScript;
function get_bitrate(b){b*=8;return 1E9<b?(b=(b/1E9).toFixed(1),b+" Gbit/s"):1E6<b?(b/=1E6,b=b.toFixed(1),b+" Mbit/s"):1E3<b?(b/=1E3,b=b.toFixed(1),b+" Kbit/s"):b+" bit/s"}
var modgui=modgui||{};!function(module){function standardCloseAction(){tch.showProgress(waitMsg);window.location.reload(true);}
function postAction(action,logModal,customCloseAction,customTarget){var onClose=(typeof customCloseAction==="function")&&customCloseAction||function(){tch.showProgress(waitMsg);window.location.reload(true);}
var target=customTarget?customTarget:$(".modal form").attr("action");$.post(target,{action:action,CSRFtoken:$("meta[name=CSRFtoken]").attr("content")},null,"json");if(logModal){clearKoInterval();$(window).on('shown.bs.modal',function(){$(".modal-backdrop").unbind();$("#close-config,.modal-action-close").unbind("click");$("#close-config,.modal-action-close").on("click",function(){onClose();});});tch.openModal("/modals/command-log-read-modal.lp?cmd_action="+encodeURIComponent(action||""));}
return false;}
var _syncCards={};var _syncTimer=null;var _syncInFlight=false;var _syncPaused=false;
function _stopSyncTimer(){if(_syncTimer){clearInterval(_syncTimer);_syncTimer=null;}}
function _startSyncTimer(){if(!_syncTimer&&!document.hidden&&!_syncPaused&&Object.keys(_syncCards).length>0){_syncTimer=setInterval(_masterSync,4000);}}
function _getSyncModule(link){
    if(!link)return null;
    if(link.indexOf("cpuload.lua")!==-1)return "gateway";
    if(link.indexOf("internet.lua")!==-1){
        if(link.indexOf("datatype=xdsl")!==-1)return "xdsl";
        return "wan";
    }
    if(link.indexOf("connected_device.lua")!==-1)return "devices";
    if(link.indexOf("mmpbx_status.lua")!==-1)return "mmpbx";
    if(link.indexOf("port_status.lua")!==-1)return "ports";
    if(link.indexOf("dashboard_sync.lua")!==-1)return "all";
    return null;
}
function _masterSync(){
    if(document.hidden){_stopSyncTimer();return;}
    if(_syncInFlight)return;
    var activeCards=[];var modulesSet={};
    for(var cardId in _syncCards){
        var card=_syncCards[cardId];
        var el=document.getElementById(card.id);
        if(!el){delete _syncCards[cardId];continue;}
        if(card.bindings&&card.bindings._isIntersecting===false){continue;}
        activeCards.push(card);
        if(card.module)modulesSet[card.module]=true;
    }
    if(activeCards.length===0)return;
    _syncInFlight=true;
    var modulesList=Object.keys(modulesSet).join(",");
    var postData=[tch.elementCSRFtoken()];
    postData.push({name:"modules",value:modulesList});
    $.ajax({
        url:"/ajax/dashboard_sync.lua?auto_update=true",
        type:"POST",
        dataType:"json",
        timeout:8000,
        data:postData,
        success:function(data){
            if(!data||typeof data!=="object")return;
            for(var c=0;c<activeCards.length;c++){
                var card=activeCards[c];
                var modData=data[card.module];
                if(!modData||typeof modData!=="object")continue;
                for(var i=0;i<card.list.length;i++){
                    var key=card.list[i];
                    var val=modData[key];
                    if(val!==undefined&&typeof card.bindings[key]==="function"){
                        card.bindings[key](val);
                    }
                }
            }
        }
    }).done(function(){
        if(connectionissue==1){
            if($("#popUp").is(":visible"))tch.removeProgress();
            connectionissue=0;
        }
    }).fail(function(data){
        if(data.status===503){
            if(window.isUpgrading){return;}
            if(!window._maintRedirect){window._maintRedirect=true;window.location.replace("/");}
            return;
        }
        connectionissue=1;
        switch(data.status){
            case 200:
                if(data.responseText&&data.responseText.indexOf("sign-me-in")!==-1){
                    if(!$("#popUp").is(":visible"))tch.showProgress(loginMsg);
                    window.location.href="/";
                }
                break;
            case 500:
                window.location.href="/error.lp?status="+data.status+"&err="+data.getResponseHeader("error-msg");
                break;
            default:
                if(!window.isUpgrading&&!$("#popUp").is(":visible"))tch.showProgress(connectionLost+" "+data.statusText);
        }
    }).always(function(){
        _syncInFlight=false;
    });
}
var _visCallbacks=(typeof WeakMap!=="undefined")?new WeakMap():null;
var _sharedObserver=(window.IntersectionObserver&&_visCallbacks)?new IntersectionObserver(function(entries){
    for(var i=0;i<entries.length;i++){
        var cb=_visCallbacks.get(entries[i].target);
        if(cb)cb(entries[i].isIntersecting);
    }
}):null;
function _initLogText(element){
    var scroller=element;
    if(window.getComputedStyle){
        var cs=window.getComputedStyle(element);
        if(cs.overflowY!=="auto"&&cs.overflowY!=="scroll"&&element.parentNode&&element.parentNode.parentNode&&element.parentNode.parentNode.parentNode){
            scroller=element.parentNode.parentNode.parentNode;
        }
    }
    var st={element:element,node:document.createTextNode(""),scroller:scroller,src:"",pending:"",stick:true,raf:0};
    element.classList.add("log-console");
    element.textContent="";
    element.appendChild(st.node);
    st.onScroll=function(){
        if(document.body&&!document.body.contains(st.element)){
            st.scroller.removeEventListener("scroll",st.onScroll);
            return;
        }
        st.stick=(st.scroller.scrollHeight-st.scroller.scrollTop-st.scroller.clientHeight<=32);
    };
    st.scroller.addEventListener("scroll",st.onScroll,{passive:true});
    return st;
}
function _updateLogText(st,v){
    st.pending=(v===null||v===undefined)?"":String(v);
    if(!st.raf){
        st.raf=requestAnimationFrame(function(){
            st.raf=0;
            if(document.body&&!document.body.contains(st.element)){
                st.scroller.removeEventListener("scroll",st.onScroll);
                return;
            }
            var value=st.pending;
            if(value===st.src)return;
            if(value.length>=st.src.length&&value.indexOf(st.src)===0){
                st.node.appendData(value.slice(st.src.length));
            }else{
                st.node.nodeValue=value;
            }
            st.src=value;
            if(st.stick&&st.node.length>200000){st.node.deleteData(0,st.node.length-150000);}
            if(st.stick){
                st.scroller.scrollTop=st.scroller.scrollHeight;
                if(st.scroller!==st.element){st.element.scrollTop=st.element.scrollHeight;}
            }
        });
    }
}
function _applyBindTarget(target,val){
    var el=target.el;
    var anim=(typeof gui_var!=="undefined"&&gui_var.gui_animation=="1");
    if(target.type==="text"){
        var tVal=(val===null||val===undefined)?"":String(val);
        if(tVal!==$(el).text()){
            if(!$(el).hasClass("hide")&&anim){$(el).fadeOut(function(){$(this).text(tVal).fadeIn();});}
            else{el.textContent=tVal;}
        }
    }else if(target.type==="html"){
        var hVal=(val===null||val===undefined)?"":String(val);
        if(hVal!=$(el).html()){
            if(!$(el).hasClass("hide")&&anim){$(el).fadeOut(function(){$(this).html(hVal).fadeIn();});}
            else{$(el).html(hVal);}
        }
    }else if(target.type==="visible"){
        el.style.display=val?"":"none";
    }else if(target.type==="log_text"){
        _updateLogText(target.state,val);
    }
}
function _createProp(){
    var curVal;
    var targets=[];
    var fn=function(val){
        if(arguments.length===0)return curVal;
        curVal=val;
        for(var i=0;i<targets.length;i++){_applyBindTarget(targets[i],val);}
    };
    fn._addTarget=function(type,el){
        var target={type:type,el:el};
        if(type==="log_text"){target.state=_initLogText(el);}
        targets.push(target);
    };
    return fn;
}
function createAjaxUpdateCard(CardIdRefresh,ajaxLink,IntervalVar,RefreshTime,CustomRefreshFunction){
    var element=document.getElementById(CardIdRefresh);
    if(!element)return;
    var ElementBinding=element._modguiBindings||{};
    var ElementBindingList=element._modguiBindingList||[];
    if(!element._modguiBound){
        element._modguiBound=true;
        element._modguiBindings=ElementBinding;
        element._modguiBindingList=ElementBindingList;
        var boundNodes=element.querySelectorAll("[data-bind]");
        for(var b=0;b<boundNodes.length;b++){
            var node=boundNodes[b];
            var bindVal=node.getAttribute("data-bind")||"";
            var pairs=bindVal.split(",");
            for(var p=0;p<pairs.length;p++){
                var colon=pairs[p].indexOf(":");
                if(colon!==-1){
                    var bType=pairs[p].slice(0,colon).trim();
                    var obs=pairs[p].slice(colon+1).trim();
                    if(obs){
                        if(!ElementBinding[obs]){
                            ElementBindingList.push(obs);
                            ElementBinding[obs]=_createProp();
                        }
                        ElementBinding[obs]._addTarget(bType,node);
                    }
                }
            }
        }
    }
    var arrayLength=ElementBindingList.length;
    var syncModule=!CustomRefreshFunction&&_getSyncModule(ajaxLink);
    if(syncModule){
        _syncCards[CardIdRefresh]={
            id:CardIdRefresh,
            module:syncModule,
            bindings:ElementBinding,
            list:ElementBindingList
        };
        if(_sharedObserver){
            ElementBinding._isIntersecting=true;
            _visCallbacks.set(element,function(vis){
                ElementBinding._isIntersecting=vis;
                if(vis){_masterSync();}
            });
            _sharedObserver.observe(element);
        }
        if(!window._syncVisBound){
            window._syncVisBound=true;
            document.addEventListener("visibilitychange",function(){
                if(document.hidden){
                    _stopSyncTimer();
                }else if(!_syncPaused&&Object.keys(_syncCards).length>0){
                    _startSyncTimer();
                    _masterSync();
                }
            });
        }
        if(!_syncTimer&&!_syncPaused&&!document.hidden){
            _startSyncTimer();
            setTimeout(_masterSync,100);
        }
        return;
    }
    var AjaxRefresh=(typeof CustomRefreshFunction==="function")&&CustomRefreshFunction||function(){
        if(document.hidden)return;
        if(ElementBinding._isIntersecting===false)return;
        var updateLink="auto_update=true";
        if(/[a-z]+=[a-z]+/.test(ajaxLink)){updateLink="&"+updateLink;}else{updateLink="?"+updateLink;};
        $.post(ajaxLink+updateLink,[tch.elementCSRFtoken()],function(data){
            for(var i=0;i<arrayLength;i++){
                if(data[ElementBindingList[i]]!=undefined){
                    ElementBinding[ElementBindingList[i]](data[ElementBindingList[i]]);
                }
            }
        },"json").done(function(data){
            if(connectionissue==1){
                if($("#popUp").is(":visible"))tch.removeProgress();
                connectionissue=0;
            }
        }).fail(function(data){
            if(data.status===503){
                if(window.isUpgrading){return;}
                if(!window._maintRedirect){window._maintRedirect=true;window.location.replace("/");}
                return;
            }
            connectionissue=1;
            switch(data.status){
                case 200:
                    if(data.responseText.indexOf("sign-me-in")!==-1){
                        if(!$("#popUp").is(":visible"))tch.showProgress(loginMsg);
                        window.location.href="/";
                    }
                    break;
                case 500:
                    window.location.href="/error.lp?status="+data.status+"&err="+data.getResponseHeader("error-msg");
                    break;
                default:
                    if(!window.isUpgrading&&!$("#popUp").is(":visible"))tch.showProgress(connectionLost+" "+data.statusText);
            }
        });
    };
    AjaxRefresh(ElementBinding);
    if(_sharedObserver){
        ElementBinding._isIntersecting=true;
        _visCallbacks.set(element,function(vis){
            ElementBinding._isIntersecting=vis;
            if(vis){AjaxRefresh(ElementBinding);}
        });
        _sharedObserver.observe(element);
    }
    KoRequest[IntervalVar]={interval:setInterval(AjaxRefresh,RefreshTime,ElementBinding),function:AjaxRefresh,binding:ElementBinding,refreshTime:RefreshTime,};
}
function linkCheckUpdate(){$(".check_update").on("click",function(e){e.stopPropagation();if(KoRequest.CheckVer)return;postAction("checkver",null,null,'/modals/modgui-modal.lp?auto_update=true');$(".check_update_spinner").addClass("fa-spin");KoRequest.CheckVer={interval:setInterval(function(){$.ajax({url:"/ajax/commandlogread.lua?auto_update=true",data:[tch.elementCSRFtoken()],type:"POST",dataType:"json",timeout:500,success:function(data){if(data.state=="Checking"){if(data.new_version_text){if(data.new_version_text=="Unknown"){$(".gui_version_status").removeClass("yellow").addClass("green");$(".gui_version_status_text").text(gui_var.gui_updated);$("#upgrade-alert").addClass("hide");$("#upgradebtn, .sub-upgrade").addClass("hide");}else{$(".gui_version_status").removeClass("green").addClass("yellow");$("#upgradebtn, .sub-upgrade").removeClass("hide");$(".gui_version_status_text").text(gui_var.gui_outdated);$("#upgrade-alert").removeClass("hide");var ver_tag=data.new_version_text.split(" ")[0];$("#new-version-text").html('<a target="_blank" href="https://github.com/ZioCook/tch-nginx-gui/releases/tag/'+ver_tag+'">'+data.new_version_text+'</a>');}}}else if(data.state=="Complete"){$(".gui_version_status_text").parent().fadeOut().fadeIn();$(".check_update_spinner").removeClass("fa-spin");clearInterval(KoRequest.CheckVer.interval);KoRequest.CheckVer=null;}}})},"500")}})};function freshStyle(stylesheet){$("#theme_skin").attr("href","/theme/"+stylesheet);}
function scrollFunction(){if(document.body.scrollTop>60||document.documentElement.scrollTop>60){$("#scroll-up").removeClass("hide");$("#scroll-down").addClass("hide");}else{$("#scroll-up").addClass("hide");$("#scroll-down").removeClass("hide");}}
function clearKoInterval(){
    _syncPaused=true;
    _stopSyncTimer();
    Object.keys(KoRequest).forEach(function(interval){if(KoRequest[interval]&&KoRequest[interval].interval)clearInterval(KoRequest[interval].interval);});
}
function restartKoInterval(){
    _syncPaused=false;
    if(!_syncTimer&&!document.hidden&&Object.keys(_syncCards).length>0){
        _startSyncTimer();
        _masterSync();
    }
    Object.keys(KoRequest).forEach(function(interval){if(KoRequest[interval]&&KoRequest[interval].function)KoRequest[interval].interval=setInterval(KoRequest[interval].function,KoRequest[interval].refreshTime,KoRequest[interval].binding);});
}
function getVendorFromMac(mac,div){div.addClass("fa fa-sync fa-spin");$.ajax({url:"/modals/modgui-modal.lp?auto_update=true",method:'POST',data:{action:'getVendor',mac:mac,CSRFtoken:$("meta[name=CSRFtoken]").attr("content")},error:function(){div.removeClass("fa fa-sync fa-spin");div.text('Error');},success:function(data){div.removeClass("fa fa-sync fa-spin");div.text(data||'Unknown');}});}
module.postAction=postAction,module.createAjaxUpdateCard=createAjaxUpdateCard,module.linkCheckUpdate=linkCheckUpdate,module.freshStyle=freshStyle,module.scrollFunction=scrollFunction,module.clearKoInterval=clearKoInterval,module.restartKoInterval=restartKoInterval,module.getVendorFromMac=getVendorFromMac,module.ensureScript=ensureScript}
(modgui);if(!window._scrollBound){window._scrollBound=true;window.addEventListener("scroll",function(){modgui.scrollFunction();},{passive:true});}$(function(){$("a[href*=\'#\']").on("click",function(e){e.preventDefault();$("html, body").animate({scrollTop:$($(this).attr("href")).offset().top},500,"linear");});$(document).on('mouseenter','td[data-toggle="tooltip_mac"]',function(){var elem=this;var mac=$(elem).children("#mac_data").text();$(elem).append('<div class="tooltip bottom fade in"><div class="tooltip-arrow"></div><div class="tooltip-inner">'+
mac+'</br>'+'<div data-type="vendor"></div>'
+'</div></div>');modgui.getVendorFromMac(mac,$(elem).children('.tooltip').children('.tooltip-inner').children('div[data-type="vendor"]'));}).on('mouseleave','td[data-toggle="tooltip_mac"]',function(){$('.tooltip').remove();});if(gui_var.randomcolor=="1"){setInterval(function(){var colorR=Math.floor((Math.random()*256));var colorG=Math.floor((Math.random()*256));var colorB=Math.floor((Math.random()*256));$(":root").get(0).style.setProperty("--first-color-accent","rgb("+colorR+","+colorG+","+colorB+")");$(":root").get(0).style.setProperty("--first-color-accent-50","rgba("+colorR+","+colorG+","+colorB+", 0.5)");$(":root").get(0).style.setProperty("--first-color-accent-80","rgba("+colorR+","+colorG+","+colorB+", 0.8)");},750);}
var currentPath = document.location.pathname;
var activeView = (currentPath == "/stats.lp" || (currentPath == "/" && gui_var.pageselector_othertext == gui_var.stats_text)) ? "stats" : "cards";

function updateSwitchButtonUI() {
    if (activeView == "stats") {
        $("#cards-text").text(gui_var.cards_text);
        document.title = "Gateway - " + gui_var.stats_text;
    } else {
        $("#cards-text").text(gui_var.stats_text);
        document.title = "Gateway - " + gui_var.cards_text;
    }
}
updateSwitchButtonUI();

$("#switchViewButton").on("click", function() {
    var targetPage = (activeView == "stats") ? "cards.lp" : "stats.lp";
    var nextView = (activeView == "stats") ? "cards" : "stats";
    var buttonNextText = (nextView == "stats") ? gui_var.cards_text : gui_var.stats_text;
    var pageTitle = "Gateway - " + ((nextView == "stats") ? gui_var.stats_text : gui_var.cards_text);

    $("#cards-text").text(openMsg);
    $("#refresh-cards").show();
    $("#refresh-cards").css("margin-right", "5px");
    $("#refresh-cards").addClass("fa fa-sync fa-spin");
    modgui.clearKoInterval();
    KoRequest = {};

    $.get(targetPage + "?contentonly=true").done(function(data) {
        $(".dynamic-content").replaceWith(data);
        activeView = nextView;
        $("#cards-text").text(buttonNextText);
        $("#refresh-cards").hide();
        window.history.pushState("gateway", pageTitle, targetPage);
        document.title = pageTitle;
        $("#switchViewButton").trigger("switchcard");
    }).fail(function() {
        $("#refresh-cards").hide();
        updateSwitchButtonUI();
    });
});
$("#upgradebtn").on("hover",function(){$("#upgradebtn").css("color","white");},function(){$("#upgradebtn").css("color","orangered");});if((gui_var.autoupgradeview!="")&&(gui_var.autoupgradeview!="none")){modgui.postAction("autoupgrade_view");};if(gui_var.gui_animation=="1"){AOS.init();};});