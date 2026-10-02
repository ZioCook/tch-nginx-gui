-- Enable localization
gettext.textdomain('webui-core')

local json = require("dkjson")
local proxy = require("datamodel")
local ngx = ngx

local content_helper = require("web.content_helper")
local post_helper = require("web.post_helper")
local ui_helper = require("web.ui_helper")
local untaint_mt = require("web.taint").untaint_mt

local mmpbxd_columns = {
    {--[2]
        header = T"Line Status",
        name = "sipRegisterState",
        param = "sipRegisterState",
        type = "text",
    },
    {--[3]
        header = T"Number",
        name = "uri",
        param = "uri",
        type = "text",
    },
    {--[4]
        header = T"Call State",
        name = "callState",
        param = "callState",
        type = "text",
    },
}

local content = {
    status = "rpc.mmpbx.state",
    emission = "rpc.mmpbx.dectemission.state",
}

content_helper.getExactContent(content)

local status_map = {
	STARTING = T"Starting",
	RUNNING = T"Running",
	STOPPING = T"Stopping",
	NA = T"Not Available",
}
setmetatable(status_map, untaint_mt)

local mmpbx_light = (content.status == "NA" or content.status == "" or not content.status) and "0" or "1"
local mmpbx_status = status_map[content.status] or content.status
if not mmpbx_status or mmpbx_status == "" then
    mmpbx_status = T"Not Available"
end

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
                v = pf_data[i]
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

local basic = {
    span = {
        class = "span3",
    },
}

local function flatten_html(tbl)
    local res = {}
    local function helper(t)
        for _, v in pairs(t) do
            if type(v) == "table" then
                helper(v)
            elseif type(v) == "userdata" then
                res[#res + 1] = string.untaint(v)
            elseif v ~= nil then
                res[#res + 1] = tostring(v)
            end
        end
    end
    helper(tbl)
    return table.concat(res)
end

local  mmpbxd_options = {
    canEdit = false,
    canAdd = false,
    canDelete = false,
    tableid = "mmpbxd",
    basepath = "rpc.mmpbx.profile.",
}

local  mmpbxd_data = content_helper.loadTableData(mmpbxd_options.basepath, mmpbxd_columns ,  mmpbxd_filter , nil)

local mmpbx_table_html = ""
if #mmpbxd_data > 0 then
    local mmpbx_table = ui_helper.createTable(mmpbxd_columns, mmpbxd_data, mmpbxd_options, nil, nil)
    mmpbx_table_html = flatten_html(mmpbx_table)
else
    local no_lines_text = (content.status == "NA" or content.status == "") and T"Not Available" or T"No lines configured"
    mmpbx_table_html = flatten_html(ui_helper.createLabel(T"Line Status", no_lines_text, basic))
end

local data = {
    mmpbx_status = flatten_html(ui_helper.createLabel(T"Service", ui_helper.createSimpleLight(mmpbx_light, mmpbx_status), basic)),
    mmpbx_table = mmpbx_table_html,
}

local buffer = {}
if json.encode (data, { indent = false, buffer = buffer }) then
    ngx.say(buffer)
else
    ngx.say("{}")
end
ngx.exit(ngx.HTTP_OK)
