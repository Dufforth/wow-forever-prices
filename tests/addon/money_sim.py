"""Runs the Money tab outside the game with the real MoneyData.lua: your market's ideas, the four views, row texts,
Search only at the auction house, and a market with no data.

    python tests/addon/money_sim.py
"""
import os
import sys

import lupa.lua51 as L

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "warrior_sim.py"), encoding="utf-8").read().split("lua = L.LuaRuntime")[0]
_env = {"__file__": os.path.join(HERE, "warrior_sim.py")}
exec(_src, _env)
MOCK, source = _env["MOCK"], _env["source"]

lua = L.LuaRuntime(unpack_returned_tuples=True)
for name in ("Locale.lua", "LocaleES.lua"):
    lua.execute(source(name))
lua.execute(MOCK)
lua.execute("""
local realCreate = CreateFrame
CreateFrame = function(...)
  local f = realCreate(...)
  f.CreateFontString = function() local t = realCreate("FontString"); t.SetText = function(self, v) self.text = v end; return t end
  f.SetText = function(self, v) self.text = v end
  f.SetShown = function(self, v) self.shown = v end
  return f
end
MARKET = "forever.pvp.horde.us"
DufforthTweaksHelper = { MarketName = function() return MARKET end }
time = function() return DufforthTweaksHelperMoneyData and DufforthTweaksHelperMoneyData.at + 3 * 3600 or 0 end
SEARCHED = nil
TIP = {}
GameTooltip = { SetOwner = function() TIP = {} end, SetText = function(_, t) TIP[#TIP+1] = t end,
  AddLine = function(_, t) TIP[#TIP+1] = t end, SetHyperlink = function(_, l) TIP[#TIP+1] = l end,
  Show = function() end, Hide = function() end }
DufforthTweaksHelperLeveling = { where = { auction = false }, SearchAuctionHouse = function(id) SEARCHED = id; return true end }
""")
lua.execute(source("MoneyData.lua"))
lua.execute(source("Money.lua"))
g = lua.globals()
M = g.DufforthTweaksHelperMoney
fails = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + (("  [" + str(detail) + "]") if detail and not ok else ""))
    if not ok:
        fails.append(name)


name, market = M.Market()
check("your market has ideas", market is not None and name == "forever.pvp.horde.us")
check("money text", M.Gold(1234567) == "123.5g" and M.Gold(250) == "2s" and M.Gold(40) == "40c")
check("prices' age", M.Age(1000, 1000 + 3 * 3600) == "3 hours ago" and M.Age(1000, 1000 + 50 * 3600) == "2 days ago")
for view in ("cheap", "crafts", "flips", "farm"):
    rows = list(M.Rows(view, market).values())
    check(f"{view}: rows with name, detail and value", all(r.name and r.sub and r.value for r in rows), view)
cheap = list(M.Rows("cheap", market).values())
check("underpriced rows: something to buy, with profit", len(cheap) > 0 and cheap[0].id and cheap[0].value.startswith("+"))
farm = list(M.Rows("farm", market).values())
check("farming rows: per hour, nothing to search", len(farm) > 0 and farm[0].value.endswith("/h") and farm[0].id is None)

parent = lua.eval("CreateFrame('Frame')")
M.BuildPanel(parent, 420)
texts = [f.text for f in g.FRAMES.values() if isinstance(getattr(f, "text", None), str)]
check("the tab shows its title and your market with the prices' age", "Money ideas" in texts
      and any("forever.pvp.horde.us" in t and "3 hours ago" in t for t in texts), texts[:4])
rawget = lua.eval("rawget")
LINES = list(parent.lines.values())
shown = [f for f in LINES if rawget(f, "row") is not None and rawget(f, "shown")]
check("rows are filled", len(shown) > 0)
check("away from the AH: no Search buttons", not any(rawget(f.search, "shown") for f in shown))
lua.execute("DufforthTweaksHelperLeveling.where.auction = true")
M.ShowView("crafts")
shown = [f for f in LINES if rawget(f, "row") is not None and rawget(f, "shown")]
check("at the AH: Search on item rows", any(rawget(f.search, "shown") for f in shown))
check("the view is remembered", g.DufforthTweaksHelperDB.money.view == "crafts")
first = shown[0]
first.search.scripts["OnClick"]()
check("Search opens the item at the AH", g.SEARCHED == first.row.id, (g.SEARCHED, first.row.id))
lua.execute('MARKET = "forever.nowhere.horde.us"')
M.Refresh()
texts = [f.text for f in g.FRAMES.values() if isinstance(getattr(f, "text", None), str)]
check("a market with no data says so", any("No money ideas" in t for t in texts))

# ---- Vendor flips explain themselves (user, 2026-11-27: "i dont understand this") ----
check("exact coins when silver hides the margin", M.Coins(483) == "4s 83c" and M.Coins(500) == "5s"
      and M.Coins(12345) == "1g 23s 45c" and M.Coins(40) == "40c" and M.Coins(20000) == "2g", (M.Coins(483), M.Coins(12345)))
fake = lua.eval('{ flips = { { 7, "Rough Bronze Leggings", 483, 590, 500 } } }')
flip = list(M.Rows("flips", fake).values())[0]
check("flip row: buy and vendor price with copper", "4s 83c" in flip.sub and "5s 90c" in flip.sub and "500" in flip.sub, flip.sub)
check("flip row: green value is the profit PER ITEM", flip.value == "+1s 7c each", flip.value)
tip = " ".join(list(flip.tip.values()))
check("flip hover: total if you buy all, and what to do", "5g 35s" in tip and "500" in tip
      and "sell them to any vendor" in tip, tip)
real = list(M.Rows("flips", market).values())
check("real flips: every one makes at least 1s per item", all(r.each >= 100 for r in real), [(r.name, r.each) for r in real][:3])
for key in ("cheap", "crafts", "flips", "farm"):
    M.ShowView(key)
    legend = panel_legend = rawget(parent.legend, "text") or ""
    check(f"{key}: a one-line legend says what the list and the green number mean", len(legend) > 20 and "green" in legend.lower(), legend)
    on = [b.key for b in parent.views.values() if rawget(b, "on")]
    check(f"{key}: only the selected view button is marked", on == [key] and all(
        bool(rawget(b.mark, "shown")) == (b.key == key) for b in parent.views.values()), on)
M.ShowView("flips")
lua.execute('MARKET = "forever.pvp.horde.us"'); M.Refresh()
row = [f for f in LINES if rawget(f, "row") is not None and rawget(f, "shown")]
if row:
    row[0].scripts["OnEnter"](row[0])
    hover = " ".join(str(t) for t in g.TIP.values())
    check("row hover explains it with an action", "vendor" in hover and "Buy" in hover, hover)
M.ShowView("farm")
row = [f for f in LINES if rawget(f, "row") is not None and rawget(f, "shown")]
row[0].scripts["OnEnter"](row[0])
hover = " ".join(str(t) for t in g.TIP.values())
check("farm hover explains it with an action", "Kill" in hover, hover)

print(f"{len(fails)} failed" if fails else "all passed")
sys.exit(1 if fails else 0)
