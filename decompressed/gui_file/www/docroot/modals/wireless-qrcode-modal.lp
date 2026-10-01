--pretranslated: do not change this file
 
-- Enable localization
gettext.textdomain('webui-core')

local ui_helper = require("web.ui_helper")
local content_helper = require("web.content_helper")
local untaint_mt = require("web.taint").untaint_mt

local getargs = ngx.req.get_uri_args()
local getiface = string.format("%s",getargs.iface or "")
local getap = string.format("%s",getargs.ap or "")
local ifacepath = "uci.wireless.wifi-iface.@"
local appath = "uci.wireless.wifi-ap.@"

local secmodes = setmetatable({
     ["none"] =  "nopass" ,
     ["wpa-psk"] = "WPA",
     ["wpa2-psk"] = "WPA",
     ["wpa-wpa2-psk"] = "WPA",
     ["wpa2"] = "WPA",
     ["wpa-wpa2"] =  "WPA",
     ["wpa3-psk"] = "WPA",
     ["wpa2-wpa3-psk"] = "WPA",
     ["owe"] = "nopass",
     ["wep"] =  "WEP",
}, untaint_mt )

local content = {
    ssid = ifacepath .. getiface .. ".ssid",
    secmode = appath .. getap .. ".security_mode",
    wepkey = appath .. getap .. ".wep_key",
    wpakey = appath .. getap .. ".wpa_psk_key",
    key = appath .. getap .. ".key",
    public = appath .. getap .. ".public",
    rpc_ssid = "rpc.wireless.ssid.@" .. getiface .. ".ssid",
    rpc_wpakey = "rpc.wireless.ap.@" .. getap .. ".security.wpa_psk_passphrase",
    rpc_secmode = "rpc.wireless.ap.@" .. getap .. ".security.mode",
    rpc_public = "rpc.wireless.ap.@" .. getap .. ".public",
}
content_helper.getExactContent(content)

if (not content.ssid or content.ssid == "") and content.rpc_ssid then
    content.ssid = content.rpc_ssid
end
if (not content.secmode or content.secmode == "") and content.rpc_secmode then
    content.secmode = content.rpc_secmode
end
if (not content.public or content.public == "") and content.rpc_public then
    content.public = content.rpc_public
end

local wpakey = (content.wpakey and content.wpakey ~= "") and content.wpakey
    or ((content.key and content.key ~= "") and content.key
    or (content.rpc_wpakey or ""))

local keypassphrases = setmetatable({
    ["none"] = "" ,
    ["owe"] = "" ,
    ["wpa-psk"] = wpakey,
    ["wpa2-psk"] = wpakey,
    ["wpa-wpa2-psk"] = wpakey,
    ["wpa3-psk"] = wpakey,
    ["wpa2-wpa3-psk"] = wpakey,
    ["wep"] = content.wepkey or "",
}, untaint_mt )

-- QR-Code escape function for SSID and PSK strings
-- the following characters needs to be escaped with a backslash (\): backslash (\), single-quote ('), double-quote ("),
-- dot (.), colon (:), comma (,), and semicolon (;)
-- we have the lua and the JavaScript escaping to pass as well, that's way you see so many backslashes
local qrcode_escape_entities = {  ["\\"] = "\\\\", ["\'"] = "\\'", ['"'] = '\\"',
                    ["."] = "\\.", [":"] = "\\:", [","] = "\\,", [";"] = "\\;" }
local javascript_escape_entities = {  ["\\"] = "\\\\", ["\'"] = "\\'", ['"'] = '\\"'}

--Use WLAN configuratin to compose a string: "WIFI:T:WEP;S:mynetwork;P:mypassword;;"
--These parameters are needed: SSID, Security Mode and password
local wlanconfstr = ""
if content.ssid and content.ssid ~= "" then
    local mode = secmodes[content.secmode] or "WPA"
    local password = keypassphrases[content.secmode] or wpakey or ""
    local ssid = tostring(content.ssid)
    local public = content.public
    --qr code escaping of dynamic data
    ssid = ssid:gsub('[\\\'".:,;]', qrcode_escape_entities)
    password = tostring(password):gsub('[\\\'".:,;]', qrcode_escape_entities)

    local hidden = ";H:false;;"
    if public == "0" then
        hidden = ";H:true;;"
    end

    if mode == "nopass" then
        wlanconfstr  = "WIFI:T:" .. mode .. ";S:" .. ssid .. hidden
    else
        wlanconfstr  = "WIFI:T:" .. mode .. ";S:" .. ssid .. ";P:" .. password .. hidden
    end

    --javascript escaping of special characters
    wlanconfstr = string.untaint(wlanconfstr:gsub('[\\\'"]', javascript_escape_entities))
end
  ngx.print('\
\
');  ngx.print( ui_helper.createHeader(T"WiFi QR Code", false, false) ); ngx.print('\
\
<div class="modal-body update">\
  <form class="form-horizontal" method="post" action="modals/wireless-qrcode-modal.lp">\
   <fieldset>\
        <center>\
            <div id="qrcode"></div>\
        <center>\
    </fieldset>\
    </form>\
</div>\
\
');  ngx.print( ui_helper.createFooter() ); ngx.print('\
\
<script>\
$(function(){\
    var wlanconfstr = "');  ngx.print(wlanconfstr); ngx.print('";\
    var typeNumber = 8;\
    var errorCorrectLevel = \'M\';\
    var qr = qrcode(typeNumber, errorCorrectLevel);\
    qr.addData(wlanconfstr);\
\
    qr.make();\
    qr.createImgTag(typeNumber);\
    var html = qr.createTableTag(typeNumber);\
    $("#qrcode").html(html)\
  });\
</script>\
'); 