#!/usr/bin/env python3
import subprocess
import json

test_script = """
package.path = "/www/lua/?.lua;/www/lua/?/init.lua;/usr/lib/lua/?.lua;/usr/lib/lua/?/init.lua;" .. package.path
local cards = require("cards")
local sm = require("web.sessionmgr")
local sessioncontrol = require("web.sessioncontrol")
local dm = require("datamodel")

cards.setpath("/www/cards/")

print("=== 1. TOTAL CARDS ON DISK (/www/cards/) ===")
local lfs = require("lfs")
local all_disk_cards = {}
for f in lfs.dir("/www/cards") do
    if f:match("%.lp$") then
        all_disk_cards[#all_disk_cards + 1] = f
    end
end
table.sort(all_disk_cards)
print("Total .lp files in /www/cards/: " .. #all_disk_cards)
for i, c in ipairs(all_disk_cards) do
    print(string.format("  [%02d] %s", i, c))
end

print("\\n=== 2. CARDS VISIBLE FOR ADMIN vs RESTRICTED ROLE ===")
local mgr = sessioncontrol.getmgr()

-- Admin session
local admin_sess = sm.new("admin")
admin_sess.user = { name = "admin", role = "admin" }
admin_sess.role = "admin"
ngx.ctx.session = admin_sess.proxy
local admin_cards = cards.cards()
print(string.format("Admin Visible Cards count: %d / %d", #admin_cards, #all_disk_cards))
for _, c in ipairs(admin_cards) do
    print("  + " .. c)
end

-- Guest / Restricted session
local guest_sess = sm.new("guest")
guest_sess.user = { name = "guest_user", role = "guest" }
guest_sess.role = "guest"
ngx.ctx.session = guest_sess.proxy
local guest_cards = cards.cards()
print(string.format("\\nGuest/Restricted Visible Cards count: %d / %d", #guest_cards, #all_disk_cards))
for _, c in ipairs(guest_cards) do
    print("  + " .. c)
end

-- Compare hidden cards for guest
local hidden_for_guest = {}
local guest_set = {}
for _, c in ipairs(guest_cards) do guest_set[c] = true end
for _, c in ipairs(admin_cards) do
    if not guest_set[c] then
        hidden_for_guest[#hidden_for_guest + 1] = c
    end
end
print(string.format("\\nCards hidden from Guest (%d):", #hidden_for_guest))
for _, c in ipairs(hidden_for_guest) do
    print("  - " .. c)
end

print("\\n=== 3. DATAUSAGE & EASYMESH ROLE BEHAVIOR (78fa2fc3, 456ef1b4) ===")
local post_helper = require("web.post_helper")
print("post_helper.isFeatureEnabled('noCardBackgroundIcons', 'admin'): " .. tostring(post_helper.isFeatureEnabled("noCardBackgroundIcons", "admin")))
print("post_helper.isFeatureEnabled('noCardBackgroundIcons', 'guest'): " .. tostring(post_helper.isFeatureEnabled("noCardBackgroundIcons", "guest")))
print("post_helper.isFeatureEnabled('noCardBackgroundIcons', nil):     " .. tostring(post_helper.isFeatureEnabled("noCardBackgroundIcons", nil)))
"""

routers = [
    ("DGA4331", "192.0.2.6"),
    ("DGA4132", "192.0.2.3"),
    ("TG789vac_v2", "192.0.2.7"),
]

for name, ip in routers:
    print(f"\n=======================================================")
    print(f"[*] Testing Role Visibility on {name} ({ip})")
    print(f"=======================================================")
    res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "lua"], input=test_script.encode('utf-8'), capture_output=True, text=True)
    print(res.stdout.strip())
    if res.stderr:
        print("ERR:", res.stderr.strip())

    # 4. Check /ajax/dashboard_sync.lua anonymous response payload
    print(f"\n--- Checking /ajax/dashboard_sync.lua Anonymous Payload on {name} ---")
    sync_res = subprocess.run(["ssh", "-o", "StrictHostKeyChecking=no", f"root@{ip}", "curl -k -s https://127.0.0.1/ajax/dashboard_sync.lua"], capture_output=True, text=True)
    print("Payload length:", len(sync_res.stdout), "bytes")
    print("Payload preview:", sync_res.stdout[:500])
