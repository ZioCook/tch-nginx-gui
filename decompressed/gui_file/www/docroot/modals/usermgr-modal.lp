--pretranslated: do not change this file
 
-- Localization
gettext.textdomain('webui-core')

local proxy = require("datamodel")
local content_helper = require("web.content_helper")
local ui_helper = require("web.ui_helper")
local message_helper = require("web.uimessage_helper")
local post_helper = require("web.post_helper")
local string,ngx = string,ngx
local taint_mt = require("web.taint").taint_mt
local type, setmetatable, random = type, setmetatable, math.random
local table, ipairs, istainted, format = table, ipairs, string.istainted, string.format
local untaint = string.untaint
local srp = require("srp")
local json = require("dkjson")
local session = ngx.ctx.session
local printf = require("web.web").printf

local tech = false
if session:getrole() == "engineer" then
   tech = true
end

-- Shortcuts to validation helpers to make lines shorter
local gVIES = post_helper.getValidateInEnumSelect
local vNES = post_helper.validateNonEmptyString
local gVSLIR = post_helper.getValidateStringLengthInRange
local gAV = post_helper.getAndValidation

-- Start for legacy migration: GUI username/password [NG-48489]
local legacy_users = content_helper.getMatchedContent("uci.web.user.")
local userNames = ""
local legacySalts = ""

for _, user in ipairs(legacy_users) do
  if user.legacy_salt and user.legacy_salt ~= "" then
    userNames = userNames .. user.name ..","
    legacySalts = legacySalts .. user.legacy_salt .. ","
  end
end
-- End for legacy migration: GUI username/password [NG-48489]

local function gVEL(len)
    return function(value, object, key)
        if type(value) ~= "string" and not istainted(value) then
            return nil, "Received a non string value"
        end
        if #value ~= len then
            return nil, format("String must be exactly %d characters long", len)
        end
        return true
    end
end

if ngx.req.get_method() == "POST" then
    local post_args = ngx.req.get_post_args()
    local I, A, M = untaint(post_args.I), untaint(post_args.A), untaint(post_args.M)
    if I and A then
        session:store("editedUserName", I)
        local user = content_helper.getMatchedContent("uci.web.user.",{name=I})
        if user and #user > 0 then
            user = user[1]
        end
        local verifier, B = srp.Verifier(I, untaint(user.srp_salt), untaint(user.srp_verifier), A)
        session:store("verifier",verifier)
        session:store("edited_user", I)
        ngx.header.content_type = "application/json"
        printf('{ "s":"%s", "B":"%s" }', user.srp_salt, B)
        ngx.exit(ngx.HTTP_OK)
    end
    if M then
        local verifier =  session:retrieve("verifier")
        session:store("verifier",nil)
        ngx.header.content_type = "application/json"
        local M2, errmsg = verifier:verify(M)
        if M2 then
            local user = session:retrieve("edited_user")
            session:store("verified_user",user)
            printf('{ "M":"%s" }', M2)
        else
            printf('{ "error":"%s" }', errmsg or "failed")
        end
        ngx.exit(ngx.HTTP_OK)
    end
end

local roleslist = {
    { "guest", T"Guest"},
    { "admin", T"Admin"},
    { "engineer", T"Engineer"},
}

local password_warning = {
    alert = {
        class = "alert",
        style="margin-left:15px;display:inline;font-size:15px;",
    },
}
local warning = ui_helper.createAlertBlock(T"Provide a password to prevent unauthorized access to the gateway.", password_warning)

local umgr_columns = {
    {
        header = T"Name",
        name = "name",
        param = "name",
        type = "text",
        attr = { input = { class="span2" } },
    },
    {
        header = T"Role",
        name = "role",
        param = "role",
        default = "guest",
        type = "select",
        values = roleslist,
        attr = { select = { class="span2" } },
    },
    {
        header = "",
        legend = T"Change password" .. warning[1],
        name = "passwordmgt",
        param = "passwordmgt",
        type = "aggregate",
        synthesis = nil,
        subcolumns = {
            {
                header = T"Password",
                name = "password",
                param = "password",
                type = "password",
                attr = { input = { class="span2", onkeyup="passwordCheck(this.value)", id = "usrmodal_password" },},
            },
            {
                header = T"Repeat Password",
                name = "password2",
                param = "password2",
                type = "password",
                attr = { input = { class="span2", id = "repeat_pass" }},
            },
            {
                header = T"SRP salt",
                name = "srp_salt",
                param = "srp_salt",
                type = "hidden",
                attr = { },
            },
            {
                header = T"SRP verifier",
                name = "srp_verifier",
                param = "srp_verifier",
                type = "hidden",
                attr = { },
            },

        },
    }
}

local umgr_attributes = {
}

local wu = {}
local users
local currentuser = ngx.ctx.session:getusername()

local umgr_filter = function(data)
    if not users then -- we need to initialize it after the current table operation happened so do this on the first run of umgr_filter
        -- this is because filter is called in loadTableData which happens after committing the current operation
        users = setmetatable({}, taint_mt)
        content_helper.addListContent(wu, { users = "uci.web.sessionmgr.@default.users." })
        for _,v in ipairs(wu.users) do
            users[v] = true
        end
    end
    local name = data.paramindex -- name of the entry
    local username = data.name

    -- check either it's an already existing entry
    if name and users[name] then
        if name == "usr_guest" then
            return nil
        elseif name == "usr_admin" or currentuser == username then
            return {
                canEdit = true,
                canDelete = false
            }
        else
            return true
        end
    elseif ngx.req.get_method() == "POST" and ngx.req.get_post_args().action == "TABLE-ADD" and ngx.req.get_post_args().name == username then
        return true
    else
        return nil
    end
end

local umgr_defaultObject = nil

-- when creating a new user, name the entry with a random name otherwise won't be able to retrieve the name of the entry
-- after calling proxy.add
local function generateNewObjectname()
    return "usr_default_" .. tostring(random()):sub(3)
end

local function setCryptedPassword()
    local post_args = ngx.req.get_post_args()
    if (post_args.action == "TABLE-MODIFY") then
        local username = untaint(post_args.name)
        local cryptpw  = post_args.cryptpw
        local r, err = proxy.set("rpc.user.@" .. username .. ".pwcrypt", cryptpw)
        if not r then
          -- error 9005 is returned if rpc not installed, or user `username` is not a CLI user;
          -- this is not considered an error at this point, so don't report.
            if err[1].errcode ~= 9005 then
                return nil, err[1].errmsg
            end
        else
            proxy.apply()
        end
    end
    return true
end

local umgr_options = {
    tableid = "usermgr",
    basepath = "uci.web.user.@.",
    createMsg = T"Add new user",
    addNamedObject = true,
    sorted = "name",
    objectName = generateNewObjectname(),
    valid = setCryptedPassword
}

if not tech then
	umgr_options.canAdd = false
end

local function userStateModified(object)
    local post_args = ngx.req.get_post_args()
    if (post_args.action == "TABLE-MODIFY") then
        local basepath = "uci.web.user.@" .. umgr_options.changesessionindex .. "."
        local userData = {
            name = basepath .. "name",
            srp_salt = basepath .. "srp_salt",
        }
        content_helper.getExactContent(userData)
        return true, userData.name ~= object.name, userData.srp_salt ~= object.srp_salt
    end
    return false
end

local function clearPassword(value, object, key)
    local state, bname, bsalt = userStateModified(object)
    if state and bname then
        if not bsalt then
            return nil, T"Please set the new password for new user."
        end
    end

    object[key] = nil
    return true
end

local function rvalidation(rl)
    if ngx.var.request_method == "POST" then
        local post_args = ngx.req.get_post_args()
        if post_args.action == "TABLE-MODIFY" and post_args.name == currentuser and post_args.role ~= nil then
             return nil, T"Current user can not edit their role"
        end
    end
    return gVIES(rl)
end

local function checkDuplicatedUser(value)
    local defaultusers = {}
    content_helper.addListContent(defaultusers, { users = "uci.web.sessionmgr.@default.users." })
    for _,usrrolename in ipairs(defaultusers.users) do
        local path = format("uci.web.user.@%s.name", usrrolename)
        local usrname = proxy.get(path)
        if usrname ~= nil then
            if value == usrname[1].value and (umgr_options.changesessionindex == nil or usrrolename ~= umgr_options.changesessionindex) then
                return true
            end
        end
    end
    return false
end

local function validateName(value, object, key)
    local state, msg = vNES(value)
    if not state then
        return nil, msg
    end
    if ngx.req.get_post_args().action == "TABLE-MODIFY" then
        local user = session:retrieve("verified_user")
        session:store("verified_user",nil)
        local usrname_fromuci = proxy.get("uci.web.user.@" .. umgr_options.changesessionindex .. ".name")
        if usrname_fromuci then
            if user ~= usrname_fromuci[1].value then
                return nil, T"Old password must be validated"
            end
        end
        if checkDuplicatedUser(value) then
            return nil, T"A user with this username already exists"
        end
        return true
    end
    if ngx.req.get_post_args().action == "TABLE-ADD" then
        if checkDuplicatedUser(value) then
            return nil, T"A user with this username already exists"
        end
        return true
    end
    return state, msg
end

local umgr_valid = {
    name = gAV(validateName,gVSLIR(1,63)),
    role = rvalidation(roleslist),
    srp_salt = gVEL(8),
    srp_verifier = gVEL(512),
    password = clearPassword,
    password2 = clearPassword,
}

local function onAdd(index, content)
    local _, msg = ngx.ctx.session:addUserToManager(index)
    umgr_options.errmsg = msg
end

local function onDelete(index)
    local _, msg = ngx.ctx.session:delUserFromManager(index)
    umgr_options.errmsg = msg
end

local function onModify(index, content)
    local _, msg = ngx.ctx.session:reloadAllUsers()
    umgr_options.errmsg = msg
end

umgr_options.onAdd = onAdd
umgr_options.onModify = onModify
umgr_options.onDelete = onDelete

-- Start for legacy migration: GUI username/password [NG-48489]
if ngx.req.get_method() == "POST" then
    --If modified the password, and set the user's option legacy_salt to empty.
    local post_args = ngx.req.get_post_args()
    if (post_args.action == "TABLE-MODIFY") then
        local username = untaint(post_args.name)
        local user = content_helper.getMatchedContent("uci.web.user.", {name = username})
        local proxyapply = false
        if user and #user > 0 then
          user = user[1]
          if (user.legacy_salt and user.legacy_salt ~= "") then
              proxy.set(user.path .. "legacy_salt", "")
              proxyapply = true
          end
          if proxy.set(user.path .. "password_reminder", "0") then
            proxyapply = true
          end
          if proxyapply then
              proxy.apply()
          end
        end
    end
end
-- End for legacy migration: GUI username/password [NG-48489]

local umgr_helpmsg
local post_args = ngx.req.get_method() == "POST" and ngx.req.get_post_args() or {}
if post_args.action == "TABLE-EDIT" or post_args.action == "TABLE-MODIFY" then
    local oldpassword = {
        header = T"Old Password",
        name = "oldpassword",
        type = "password",
        attr = { input = { class="span2"}}
    }
    table.insert(umgr_columns[3].subcolumns,1,oldpassword)
else
  session:store("editedUserName", nil)
end

local umgr_data
umgr_data, umgr_helpmsg = post_helper.handleTableQuery(umgr_columns, umgr_options, umgr_filter, umgr_defaultObject, umgr_valid)

if ngx.req.get_method() == "POST" and ngx.req.get_post_args().action == "TABLE-MODIFY" and ngx.req.get_post_args().name == session:getusername() and not (umgr_helpmsg and next(umgr_helpmsg)) then
    -- When password changed successfully for the current user with no error message
    -- then logout the user and redirect to login screen
  ngx.print('\
    <script type="text/javascript">\
        window.location="login.lp";\
    </script>\
');  
    session:logout()
    ngx.exit(ngx.HTTP_OK)
end
  ngx.print('\
\
');  ngx.print(ui_helper.createHeader(T"Management", false, false))   ngx.print('\
\
<div class="modal-body update">\
');  
    local lp = require("web.lp")
    lp.setpath("/www/snippets/")
    lp.include("tabs-management.lp")
  ngx.print('\
\
<form class="form-horizontal" method="post" action="modals/usermgr-modal.lp">\
');  
    ngx.print(ui_helper.createMessages(message_helper.popMessages()))
  ngx.print('\
\
<fieldset>\
<legend>');  ngx.print( T"Users list" ); ngx.print('</legend>\
');  
    if post_args.action == "TABLE-EDIT" then
        local index = post_args.index
        if index and umgr_data[tonumber(index)] and umgr_data[tonumber(index)][1] == currentuser then
            umgr_columns[2].readonly = true
        end
    end
    ngx.print(ui_helper.createTable(umgr_columns, umgr_data, umgr_options, umgr_attributes, umgr_helpmsg))
  ngx.print('\
</fieldset>\
</form>\
</div>\
\
');  ngx.print( ui_helper.createFooter() );
local edited_user = session:retrieve("editedUserName")
local cfg_json = json.encode({
    editedUserName = edited_user and untaint(tostring(edited_user)) or "",
    legacySalts = untaint(tostring(legacySalts or "")),
    userNames = untaint(tostring(userNames or "")),
    emptyUser = untaint(tostring(T"User name cannot be empty")),
    providePassword = untaint(tostring(T"Provide a password to prevent unauthorized access to the gateway")),
    weakPassword = untaint(tostring(T"Password should contain at least 12 alphanumeric characters including both upper and lower case letters," .. "<br/>" .. T"at least one number and at least one special character")),
    securityRiskWarning = untaint(tostring(T"This could cause security risk, take care of this." .. "<b>" .. T"Applying anyway...")),
    passwordsMismatch = untaint(tostring(T"Passwords do not match")),
    oldPasswordIncorrect = untaint(tostring(T"Old password is incorrect")),
}):gsub("</", "<\\/")
ngx.print('\
<script type="application/json" id="usermgr-modal-cfg">'); ngx.print(cfg_json); ngx.print('</script>\
<script>window.ensureScript("/js/modals/usermgr-modal.js",function(){return typeof window.initUsermgrModal==="function";},function(){window.initUsermgrModal();});</script>\
'); 
