local ngx = ngx
local find, require = string.find, require
local sort = table.sort
local lfs = require("lfs")
local uci = require("uci")
local untaint = string.untaint or function(s) return tostring(s) end

local includepath

local M = {}

local rules = {}
local config = {}
local card_to_modal = {}
local modal_to_card = {}

local function reload_config()
  rules = {}
  config = {}
  card_to_modal = {}
  modal_to_card = {}

  local cursor = uci.cursor()
  cursor:foreach('web', 'rule', function(s)
    rules[s['.name']] = s
  end)

  cursor:foreach('web', 'card', function(card)
    local rule = rules[card.modal]
    if rule and not card['.anonymous'] then
      local target = untaint(rule.target)
      local orig_card = untaint(card.card)
      local clean_card = orig_card:gsub("^%d+_", "")

      card.modal = target
      card.hide = (card.hide ~= '0')
      card.card = clean_card

      config[clean_card] = card
      card_to_modal[orig_card] = target
      card_to_modal[clean_card] = target
      modal_to_card[target] = orig_card
    end
  end)
  cursor:unload('web')
end

reload_config()

local function card_visible(session, conf, cardname)
  local card = conf[cardname]
  if card then
    if card.hide then
      return false
    end
    if card.modal and not session:hasAccess(card.modal) then
      return false
    end
  end
  return true
end

local cards_limiter
do
  local found
  found, cards_limiter = pcall(require, "cards_limiter")
  if not found then
    cards_limiter = nil
  end
end

local function get_limit_info()
  local fn = cards_limiter and cards_limiter.get_limit_info
  if fn then
    return fn()
  end
end

local function card_limited(info, cardname, incpath)
  local fn = cards_limiter and cards_limiter.card_limited
  if fn then
    return fn(info, cardname, incpath)
  end
  return false
end

function M.setpath(path)
  includepath = untaint(path)
end

function M.reload_config()
  reload_config()
end

-- Returns card filename from modal path provided or nil
function M.get_card_from_modal(ModalSearch)
  if not ModalSearch then return nil end
  ModalSearch = untaint(ModalSearch)
  local session = ngx.ctx.session
  local orig_card = modal_to_card[ModalSearch]
  if orig_card then
    local clean_card = untaint(orig_card):gsub("^%d+_", "")
    if card_visible(session, config, clean_card) then
      return orig_card
    end
  end
  return nil
end

-- Returns modal path from card filename provided or nil
function M.get_modal_from_card(CardSearch)
  if not CardSearch then return nil end
  CardSearch = untaint(CardSearch)
  local clean = CardSearch:gsub("^%d+_", "")
  return card_to_modal[CardSearch] or card_to_modal[clean]
end

function M.cards()
  local session = ngx.ctx.session
  local limit_info = get_limit_info()
  local result = {}
  if includepath and lfs.attributes(includepath, 'mode') == 'directory' then
    for file in lfs.dir(includepath) do
      if find(file, "%.lp$") then
        local cardname = file:gsub("^%d+_", "")
        if card_visible(session, config, cardname) and not card_limited(limit_info, cardname, includepath) then
          result[#result+1] = file
        end
      end
    end
  end
  sort(result)
  return result
end

return M
