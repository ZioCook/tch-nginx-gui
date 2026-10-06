--pretranslated: do not change this file

local lp = require("web.lp")
local cards = require("cards")
local proxy = require("datamodel")

local rightcard = {}
local leftcard = {}
local active_cards = {}

lp.setpath("/www/info-cards/")
cards.setpath("/www/info-cards/")

-- Check whether the traffic monitor graph card is active
local wan_ifname = proxy.get("rpc.network.interface.@wan.ifname")
local wan_up = proxy.get("rpc.network.interface.@wan.up")
local is_wan_up = wan_ifname and wan_ifname[1] and wan_ifname[1].value ~= ""
                  and wan_up and wan_up[1] and wan_up[1].value == "1"

for _, card in ipairs(cards.cards()) do
	local include_card = true
	if card == "004_graph.lp" and not is_wan_up then
		include_card = false
	end
	if include_card then
		table.insert(active_cards, card)
	end
end

for n, card in ipairs(active_cards) do
	if n % 2 == 1 then
		table.insert(leftcard, card)
	else
		table.insert(rightcard, card)
	end
end

ngx.print('\
<div class="dynamic-content row" id="infocardrow" >\
')

ngx.print( '<div id="leftinfocard">' )
for _,card in ipairs(leftcard) do
	lp.include(card)
end
ngx.print( '</div>' )
ngx.print( '<div id="rightinfocard">' )
for _,card in ipairs(rightcard) do
	lp.include(card)
end
ngx.print( '</div>' )

ngx.print('\
</div>\
')
