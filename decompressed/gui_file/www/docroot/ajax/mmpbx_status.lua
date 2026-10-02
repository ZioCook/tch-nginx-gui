-- Enable localization
gettext.textdomain('webui-core')

local json = require("dkjson")
local proxy = require("datamodel")
local ngx = ngx

local content_helper = require("web.content_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")
local untaint_mt = require("web.taint").untaint_mt

local mmpbx_state = "0"
local mmpbx_state_uci = proxy.get("uci.mmpbx.mmpbx.@global.enabled")
if not mmpbx_state_uci or not mmpbx_state_uci[1] or mmpbx_state_uci[1].value == "" then
    mmpbx_state_uci = proxy.get("uci.mmpbx.global.enabled")
end
if mmpbx_state_uci and mmpbx_state_uci[1] and mmpbx_state_uci[1].value == "1" then
    local rpc_state = proxy.get("rpc.mmpbx.state")
    if not rpc_state or not rpc_state[1] or rpc_state[1].value ~= "NA" then
        mmpbx_state = "1"
    end
end

local mmpbx_info = (mmpbx_state == "1") and T"Telephony enabled" or T"Telephony disabled"

local function flatten_html(tbl)
    local res = {}
    local function helper(t)
        if type(t) == "table" then
            for _, v in pairs(t) do
                helper(v)
            end
        elseif type(t) == "userdata" then
            res[#res + 1] = string.untaint(t)
        elseif t ~= nil then
            res[#res + 1] = tostring(t)
        end
    end
    helper(tbl)
    return table.concat(res)
end

local mmpbx_status_html = flatten_html(ui_helper.createSimpleLight(mmpbx_state, mmpbx_info, { light = { id = "Telephony_LEDStatus" }, span = { id = "Telephony_Status" } }, "fa-phone"))
local mmpbx_table_html = ""

if mmpbx_state == "1" then
    local mmpbxd_columns = {
        {
            header = T"Line Status",
            name = "sipRegisterState",
            param = "sipRegisterState",
            type = "text",
        },
        {
            header = T"Number",
            name = "uri",
            param = "uri",
            type = "text",
        },
        {
            header = T"Call State",
            name = "callState",
            param = "callState",
            type = "text",
        },
    }

    local callStateMap = {
        MMPBX_CALLSTATE_IDLE = T"Idle",
        MMPBX_CALLSTATE_DIALING = T"Dialing",
        MMPBX_CALLSTATE_CALL_DELIVERED = T"Delivered/In Progress",
        MMPBX_CALLSTATE_CONNECTED = T"In Progress/Connected",
        MMPBX_CALLSTATE_ALERTING = T"Ringing"
    }
    setmetatable(callStateMap, untaint_mt)

    local registrationStatusMap = {
        Registered = T"Registered",
        Registering = T"Registering"
    }
    setmetatable(registrationStatusMap, untaint_mt)

    local failReasonMap = {
        MMPBX_REG_CLIENT_REASON_RESPONSE_REQUEST_FAILURE_RECVD = T"Registration refused",
        MMPBX_REG_CLIENT_REASON_NETWORK_ERROR = T"Network error",
        MMPBX_REG_CLIENT_REASON_TRANSACTION_TIMEOUT = T"Registration Timeout"
    }
    setmetatable(failReasonMap, untaint_mt)

    local time_t = {}
    local function convert2Sec(value)
        value = string.untaint(value)
        time_t.year, time_t.month, time_t.day, time_t.hour, time_t.min, time_t.sec = value:match("(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):(%d+)")
        if time_t.year then
            return os.time(time_t)
        end
        return 0
    end

    local mmpbxd_filter = function(data)
        if ( data.enable == "false" ) or ( data.sipRegisterState == "" ) then
            return false
        end
        local originuri = data.uri
        if data.uri and data.uri:match("+") then
            data.uri = data.uri:sub(4)
        end

        local registerLight = "off"
        local registerState
        if data.sipRegisterState then
            registerState = registrationStatusMap[data.sipRegisterState] or data.sipRegisterState
            if data.sipRegisterState=="Registered" then
                registerLight="green"
            end
            if data.failReason ~= "" then
                registerLight="red"
                registerState = failReasonMap[data.failReason] or data.failReason
            end
            data.sipRegisterState = ui_helper.createSimpleLight(nil, registerState, { light = { class = registerLight } })
        end

        if data.callState then
            local statestr = callStateMap[data.callState] or data.callState
            if ( data.callState ~= "MMPBX_CALLSTATE_IDLE" ) then
                local pf_path = proxy.get("rpc.mmpbx.calllog.info.")
                local pf_data = content_helper.convertResultToObject("rpc.mmpbx.calllog.info.",pf_path)
                for i = #pf_data, 1, -1 do
                    local v = pf_data[i]
                    if v.Localparty  == originuri then
                        statestr = statestr .. "\n" .. v.Remoteparty
                        if ( data.callState == "MMPBX_CALLSTATE_CONNECTED" ) then
                            local Duration = ""
                            if v.connectedTime ~= "0" then
                                local connectedTime = convert2Sec(v.connectedTime)
                                if v.endTime ~= '0' then
                                    local endTime = convert2Sec(v.endTime)
                                    Duration = post_helper.secondsToTimeShort(endTime - connectedTime)
                                else
                                    Duration = post_helper.secondsToTimeShort(os.time() - connectedTime)
                                end
                            end
                            statestr =  statestr .. " " .. Duration
                        end
                        break
                    end
                end
            end
            data.callState = ui_helper.createSimpleLight(data.callState == "MMPBX_CALLSTATE_IDLE" and "0" or "1", statestr, nil, "fa fa-phone")
        end

        return true
    end

    local mmpbxd_options = {
        canEdit = false,
        canAdd = false,
        canDelete = false,
        tableid = "mmpbxd",
        basepath = "rpc.mmpbx.profile.",
    }

    local mmpbxd_data = content_helper.loadTableData(mmpbxd_options.basepath, mmpbxd_columns, mmpbxd_filter, nil)

    if #mmpbxd_data > 0 then
        local mmpbx_table = ui_helper.createTable(mmpbxd_columns, mmpbxd_data, mmpbxd_options, nil, nil)
        mmpbx_table_html = flatten_html(mmpbx_table)
    else
        mmpbx_table_html = '<p class="subinfos" style="margin-top:10px;"><br/>' .. T"No registered accounts" .. '</p>'
    end
end

local data = {
    mmpbx_status = mmpbx_status_html,
    mmpbx_table = mmpbx_table_html,
}

local buffer = {}
if json.encode(data, { indent = false, buffer = buffer }) then
    ngx.say(buffer)
else
    ngx.say("{}")
end
ngx.exit(ngx.HTTP_OK)
