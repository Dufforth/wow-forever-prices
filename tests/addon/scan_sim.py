import os, sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = open(os.path.join(ROOT, "addon", "DufforthAHScanner", "Scan.lua"), encoding="utf-8").read()

MOCK = r"""
NOW, UPTIME = 1000000, 500
CHAT, QUERIES, MORE, RELOADS = {}, {}, 0, 0
REALM, FACTION, READY, FULL = "CAMWOW US1 Realm 4 PvP", "Horde", true, true
RESULTS = {}
time = function() return NOW end
GetTime = function() return UPTIME end
GetRealmName = function() return REALM end
UnitFactionGroup = function() return FACTION end
GetCurrentRegion = function() return 1 end
ReloadUI = function() RELOADS = RELOADS + 1 end
UIParent = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
SlashCmdList = {}
TICKS, HOOKS = {}, {}
AFTERS = {}
C_Timer = { NewTicker = function(_, f) TICKS[#TICKS+1] = f end, After = function(_, f) AFTERS[#AFTERS+1] = f end }
hooksecurefunc = function(t, name, f) HOOKS[name] = f end
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return READY end,
  SendBrowseQuery = function(q) QUERIES[#QUERIES+1] = q.itemClassFilters[1].classID; if HOOKS.SendBrowseQuery then HOOKS.SendBrowseQuery() end end,
  RequestMoreBrowseResults = function() MORE = MORE + 1 end,
  HasFullBrowseResults = function() return FULL end,
  GetBrowseResults = function() return RESULTS end,
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key, sorts) SEARCHES[#SEARCHES+1] = key.itemID; SORT = sorts and sorts[1]; if HOOKS.SendSearchQuery then HOOKS.SendSearchQuery() end end,
  GetCommoditySearchResultInfo = function(id, i) local c = COMMODITY[id]; return c and { unitPrice = c[1] } or nil end,
  GetCommoditySearchResultsQuantity = function(id) local c = COMMODITY[id]; return c and c[2] or 0 end,
  GetNumItemSearchResults = function(key) return #(ITEMS[key.itemID] or {}) end,
  GetItemSearchResultInfo = function(key, i) return ITEMS[key.itemID][i] end,
}
SEARCHES, COMMODITY, ITEMS = {}, {}, {}
Enum = { AuctionHouseSortOrder = { Price = 0 } }
ChatFontNormal = {}
function CreateFrame(kind, name)
  local f = { scripts = {}, events = {} }
  function f:SetScript(k, v) self.scripts[k] = v end
  function f:SetText(t) self.text = t end
  function f:GetText() return self.text end
  function f:CreateFontString() return setmetatable({}, { __index = function() return function() end end }) end
  function f:SetShown(v) self.shown = v end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:RegisterEvent(e) self.events[e] = true end
  if name == "DufforthAHScannerScanFrame" then FRAME = f end
  if name == "DufforthAHScannerScanButton" then BUTTON = f end
  if name == "DufforthAHScannerScanListButton" then LISTBUTTON = f end
  if name == "DufforthAHScannerListFrame" then LISTFRAME = f end
  if name == "DufforthAHScannerListEdit" then LISTEDIT = f end
  if name == "DufforthAHScannerListSave" then LISTSAVE = f end
  return setmetatable(f, { __index = function() return function() end end })
end
function FIRE(e, a) FRAME.scripts.OnEvent(FRAME, e, a) end
function ANSWER(rows) RESULTS = rows; FIRE("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
function R(id, price, qty, suffix, pet) return { itemKey = { itemID = id, itemSuffix = suffix or 0, battlePetSpeciesID = pet or 0 }, minPrice = price, totalQuantity = qty } end
function SAVED(m) return DufforthAHScannerDB.scans and DufforthAHScannerDB.scans[m or "forever.pvp.horde.us"] end
function TICK(s) UPTIME = UPTIME + s; NOW = NOW + s; for _, f in ipairs(TICKS) do f() end end
"""

def fresh():
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute(SRC)
    # The automatic scan has its own tests below, so the others start with it off.
    lua.execute('DufforthAHScannerDB = { autoScan = false }; FIRE("ADDON_LOADED", "DufforthAHScanner")')
    return lua

failed = False
def check(label, cond, detail=""):
    global failed
    print(("PASS " if cond else "FAIL ") + label + (f"   [{detail}]" if detail != "" else ""))
    failed = failed or not cond

def queries(lua): return [lua.eval(f"QUERIES[{i}]") for i in range(1, lua.eval("#QUERIES") + 1)]

lua = fresh()
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
check("won't start with the auction house closed", lua.eval("#QUERIES") == 0 and "Open the auction house" in lua.eval("CHAT[#CHAT]"))
lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
check("does nothing until asked", lua.eval("#QUERIES") == 0)
check("button offers a scan", lua.eval("BUTTON.text") == "Scan prices")
lua.execute("BUTTON.scripts.OnClick()")
check("button starts with trade goods", queries(lua) == [7], queries(lua))
check("button shows progress", lua.eval("BUTTON.text") == "Stop scan (1/9)", lua.eval("BUTTON.text"))
lua.execute('ANSWER({ R(2447, 19, 100), R(2447, 25, 50), R(2770, 40, 5), R(2770, 0, 5), R(9000, 5, 1, 12), R(9001, 5, 1, 0, 7) })')
check("moves to the next category", queries(lua) == [7, 0], queries(lua))
for rows in ['{R(118, 5, 3)}', '{}', '{}', '{}', '{}', '{}', '{R(10042, 500, 1)}', '{R(12764, 900, 2)}']:
    lua.execute(f"ANSWER({rows})")
check("asks each category once, leaving out quest and misc", queries(lua) == [7, 0, 5, 6, 1, 11, 9, 4, 2], queries(lua))
d = lua.eval("SAVED().data")
check("saves lowest price and total quantity, plain items only", d == "10042:500:1;118:5:3;12764:900:2;2447:19:150;2770:40:5", d)
check("names the market like the page", lua.eval("SAVED() ~= nil") is True)
check("marked complete", lua.eval("SAVED().complete") is True and lua.eval("SAVED().mode") == "full")
check("button offers to save", lua.eval("BUTTON.text") == "Save scan (reload)", lua.eval("BUTTON.text"))
lua.execute("BUTTON.scripts.OnClick()")
check("button reloads", lua.eval("RELOADS") == 1)

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("quick")
lua.execute("ANSWER({R(1,1,1)}); ANSWER({}); ANSWER({}); ANSWER({})")
check("quick scan covers materials, consumables and ammo", queries(lua) == [7, 0, 5, 6], queries(lua))
check("quick scan is labeled", lua.eval("SAVED().mode") == "quick")

lua = fresh(); lua.execute('FULL = false; FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
lua.execute("ANSWER({R(1,10,1)})")
check("asks for more when results are split", lua.eval("MORE") == 1 and queries(lua) == [7])
lua.execute("READY = false; ANSWER({R(1,10,1), R(2,20,1)})")
check("waits for the throttle before asking for more", lua.eval("MORE") == 1)
lua.execute('READY = true; FIRE("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")')
check("asks when the throttle clears", lua.eval("MORE") == 2)
lua.execute("FULL = true; ANSWER({R(1,10,1), R(2,20,1), R(3,30,1)})")
check("reads each result once at the end", queries(lua) == [7, 0])
lua.execute("ANSWER({}) ANSWER({})")
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("stop")
check("stop keeps what was read, as partial", lua.eval("SAVED().data") == "1:10:1;2:20:1;3:30:1" and lua.eval("SAVED().complete") is False, lua.eval("SAVED().data"))

lua = fresh(); lua.execute('READY = false; FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
check("waits for the throttle before the first query", lua.eval("#QUERIES") == 0)
lua.execute('READY = true; FIRE("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")')
check("sends when ready", queries(lua) == [7])
lua.execute('FIRE("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")')
check("doesn't send twice", queries(lua) == [7])

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
lua.execute("ANSWER({R(1,10,1)})")
lua.execute('FIRE("AUCTION_HOUSE_CLOSED")')
check("closing saves a partial scan", lua.eval("SAVED().complete") is False)
n = lua.eval("#QUERIES")
lua.execute("TICK(100)"); check("no queries after closing", lua.eval("#QUERIES") == n)

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
lua.execute("TICK(21)"); lua.execute("TICK(21)")
check("retries a silent category", queries(lua) == [7, 7, 7], queries(lua))
lua.execute("TICK(21)")
check("then skips it", queries(lua) == [7, 7, 7, 0], queries(lua))

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("")
lua.execute("C_AuctionHouse.SendBrowseQuery({ itemClassFilters = {{ classID = 99 }} })")
lua.execute("ANSWER({R(77, 1, 1)})")
check("ignores another addon's results", lua.eval("#AFTERS") == 1 and queries(lua) == [7, 99], queries(lua))
lua.execute("AFTERS[1]()")
check("asks again after another addon's search", queries(lua) == [7, 99, 7], queries(lua))

for realm, faction, want in [("CAMWOW US1 Realm 4 PvP", "Alliance", "forever.pvp.alliance.us"), ("Some Normal Realm", "Horde", "forever.normal.horde.us"), ("Something RP Realm", "Horde", "forever.rp.horde.us")]:
    lua = fresh(); lua.execute(f'REALM, FACTION = "{realm}", "{faction}"; FIRE("AUCTION_HOUSE_SHOW")')
    lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN("quick")
    lua.execute("ANSWER({R(1,1,1)}); ANSWER({}); ANSWER({}); ANSWER({})")
    check(f"market name {want}", lua.eval(f'SAVED("{want}") ~= nil') is True)

# Your own scan list
def slash(lua, text): lua.globals().SlashCmdList.DUFFORTHAHSCANNERSCAN(text)
def searches(lua): return [lua.eval(f"SEARCHES[{i}]") for i in range(1, lua.eval("#SEARCHES") + 1)]
def paste(lua, text):
    slash(lua, "list")
    lua.globals().LISTEDIT.text = text
    lua.execute("LISTSAVE.scripts.OnClick()")

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
slash(lua, "mine")
check("an empty list explains what to do", "scan list is empty" in lua.eval("CHAT[#CHAT]") and lua.eval("#SEARCHES") == 0)
check("no list button until there is a list", lua.eval("LISTBUTTON.shown") in (False, None))
paste(lua, "  GT1:2447,2770, 2447,abc,0,99999999999,118\n")
ids = [lua.eval(f"DufforthAHScannerDB.scanList[{i}]") for i in range(1, lua.eval("#DufforthAHScannerDB.scanList") + 1)]
check("pasted list is read, without repeats or bad IDs", ids == [2447, 2770, 118], ids)
check("the window closes and confirms", lua.eval("LISTFRAME.shown") is False and "3 items" in lua.eval("CHAT[#CHAT]"))
check("list button appears with the count", lua.eval("LISTBUTTON.shown") is True and lua.eval("LISTBUTTON.text") == "Scan my list (3)", lua.eval("LISTBUTTON.text"))
slash(lua, "list")
check("the window shows the current list", lua.eval("LISTEDIT.text") == "GT1:2447,2770,118", lua.eval("LISTEDIT.text"))
lua.execute("LISTSAVE.scripts.OnClick()")

lua.execute("LISTBUTTON.scripts.OnClick()")
check("list scan skips the categories", lua.eval("#QUERIES") == 0 and searches(lua) == [2447], searches(lua))
check("asks cheapest first", lua.eval("SORT.reverseSort") is False)
lua.execute('COMMODITY[2447] = {19, 3351}; FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2770)')
check("ignores answers for other items", searches(lua) == [2447])
lua.execute('FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 2447)')
check("moves on after a commodity answer", searches(lua) == [2447, 2770])
lua.execute('ITEMS[2770] = {{buyoutAmount=500, quantity=5}, {buyoutAmount=90, quantity=1}, {quantity=2}}; FIRE("ITEM_SEARCH_RESULTS_UPDATED", {itemID=2770})')
lua.execute('FIRE("ITEM_SEARCH_RESULTS_UPDATED", {itemID=118})')
d = lua.eval("SAVED().data")
check("per unit price, total quantity, and 0 when none for sale", d == "118:0:0;2447:19:3351;2770:90:8", d)
check("labeled as a list scan", lua.eval("SAVED().mode") == "list" and lua.eval("SAVED().complete") is True)

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW"); DufforthAHScannerDB.scanList = {2447, 777}')
slash(lua, "quick")
lua.execute("ANSWER({R(2447, 10, 2)}); ANSWER({}); ANSWER({}); ANSWER({})")
check("after categories, asks only for list items they missed", searches(lua) == [777], searches(lua))
check("progress counts the extra items", lua.eval("BUTTON.text") == "Stop scan (5/5)", lua.eval("BUTTON.text"))
lua.execute("TICK(9)")
check("an item that never answers is skipped, not marked as none", "777:" not in lua.eval("SAVED().data") and "didn't answer" in " ".join(lua.eval("CHAT")[i] for i in range(1, lua.eval("#CHAT")+1)), lua.eval("SAVED().data"))

lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW"); DufforthAHScannerDB.scanList = {1}')
lua.execute('DufforthAHScannerDB.scans = { ["forever.pvp.horde.us"] = { at = NOW - 3600, data = "1:50:5;2:60:6" } }')
slash(lua, "mine")
lua.execute('COMMODITY[1] = {70, 7}; FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 1)')
check("a list scan keeps recent results for other items", lua.eval("SAVED().data") == "1:70:7;2:60:6", lua.eval("SAVED().data"))
lua = fresh(); lua.execute('FIRE("AUCTION_HOUSE_SHOW"); DufforthAHScannerDB.scanList = {1}')
lua.execute('DufforthAHScannerDB.scans = { ["forever.pvp.horde.us"] = { at = NOW - 90000, data = "2:60:6" } }')
slash(lua, "mine")
lua.execute('COMMODITY[1] = {70, 7}; FIRE("COMMODITY_SEARCH_RESULTS_UPDATED", 1)')
check("results older than a day are dropped", lua.eval("SAVED().data") == "1:70:7", lua.eval("SAVED().data"))

# Automatic scan
def auto_lua(saved="nil"):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute(SRC)
    lua.execute(f'DufforthAHScannerDB = {saved}; FIRE("ADDON_LOADED", "DufforthAHScanner")')
    return lua
def run_afters(lua): lua.execute("local a = AFTERS; AFTERS = {}; for _, f in ipairs(a) do f() end")
def other_search(lua): lua.execute("C_AuctionHouse.SendBrowseQuery({ itemClassFilters = {{ classID = 99 }} })")

lua = auto_lua()
lua.execute('FIRE("AUCTION_HOUSE_SHOW")')
check("waits a moment after the window opens", lua.eval("#QUERIES") == 0)
run_afters(lua)
check("scans automatically by default", queries(lua) == [7], queries(lua))
check("says how to turn it off", "/ahscan auto off" in lua.eval("CHAT[1]"), lua.eval("CHAT[1]"))
for rows in ['{R(1, 5, 2)}', '{}', '{}', '{}', '{}', '{}', '{}', '{}', '{}']:
    lua.execute(f"ANSWER({rows})")
check("finishes a full scan and saves it", lua.eval("SAVED().mode") == "full" and lua.eval("SAVED().complete") is True)
check("chat stays quiet: start and finish only", lua.eval("#CHAT") == 2, lua.eval("#CHAT"))
lua.execute('FIRE("AUCTION_HOUSE_CLOSED"); NOW = NOW + 30; FIRE("AUCTION_HOUSE_SHOW")')
n = lua.eval("#QUERIES"); run_afters(lua)
check("reopening within a minute doesn't scan again", lua.eval("#QUERIES") == n)
lua.execute('FIRE("AUCTION_HOUSE_CLOSED"); NOW = NOW + 61; FIRE("AUCTION_HOUSE_SHOW")')
run_afters(lua)
check("reopening later scans again", lua.eval("#QUERIES") == n + 1, lua.eval("#QUERIES"))

lua = auto_lua('{ autoScan = false }')
lua.execute('FIRE("AUCTION_HOUSE_SHOW")'); run_afters(lua)
check("the setting turns it off", lua.eval("#QUERIES") == 0)
slash(lua, "auto on"); check("/ahscan auto on", lua.eval("DufforthAHScannerDB.autoScan") is True)
slash(lua, "auto off"); check("/ahscan auto off", lua.eval("DufforthAHScannerDB.autoScan") is False)
slash(lua, "auto"); check("/ahscan auto toggles", lua.eval("DufforthAHScannerDB.autoScan") is True)

lua = auto_lua()
lua.execute('FIRE("AUCTION_HOUSE_SHOW"); FIRE("AUCTION_HOUSE_CLOSED")'); run_afters(lua)
check("no scan if the window closed during the wait", lua.eval("#QUERIES") == 0)

lua = auto_lua()
lua.execute('FIRE("AUCTION_HOUSE_SHOW")'); run_afters(lua)
lua.execute("ANSWER({R(1, 5, 2)})")
other_search(lua)
check("another search pauses the automatic scan", lua.eval("#AFTERS") == 1 and queries(lua) == [7, 0, 99], queries(lua))
run_afters(lua)
check("then it tries once more", queries(lua) == [7, 0, 99, 0], queries(lua))
other_search(lua)
check("a second search stops it and keeps the partial scan", lua.eval("SAVED().complete") is False and lua.eval("SAVED().data") == "1:5:2", lua.eval("SAVED().data"))
n = lua.eval("#QUERIES"); run_afters(lua); lua.execute("TICK(100)")
check("it stays stopped", lua.eval("#QUERIES") == n)

lua = auto_lua('{ scanList = {777} }')
lua.execute('FIRE("AUCTION_HOUSE_SHOW")'); run_afters(lua)
for _ in range(9): lua.execute("ANSWER({})")
check("the automatic scan includes your list", searches(lua) == [777], searches(lua))
lua.execute("C_AuctionHouse.SendSearchQuery({ itemID = 5 })")
check("a search also counts as another search", lua.eval("#AFTERS") == 1)

sys.exit(1 if failed else 0)
