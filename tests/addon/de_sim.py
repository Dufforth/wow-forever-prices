"""Runs Disenchant.lua outside the game and checks its tables, prices and tooltip lines.

    python tests/addon/de_sim.py
"""
import os
import sys
import lupa.lua51 as L

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = open(os.path.join(ROOT, "addon", "DufforthTweaksHelper", "Disenchant.lua"), encoding="utf-8").read()

MOCK = r"""
NOW = 1000000
CHAT = {}
time = function() return NOW end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
ITEMS = {
  [1] = { "Green Helm", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_HEAD", nil, nil, 4 },
  [2] = { "Green Sword", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_WEAPON", nil, nil, 2 },
  [3] = { "Blue Ring", nil, 3, 28, nil, nil, nil, nil, "INVTYPE_FINGER", nil, nil, 4 },
  [4] = { "Purple Cloak", nil, 4, 60, nil, nil, nil, nil, "INVTYPE_CLOAK", nil, nil, 4 },
  [5] = { "Green Shirt", nil, 2, 30, nil, nil, nil, nil, "INVTYPE_BODY", nil, nil, 4 },
  [6] = { "Linen Cloth", nil, 1, 5, nil, nil, nil, nil, "", nil, nil, 7 },
}
GetItemInfo = function(id) local i = ITEMS[id]; if i then return unpack(i, 1, 12) end end
HOOKS = {}
local function tooltip(name)
  local t = { lines = {} }
  function t:HookScript(event, f) HOOKS[name .. ":" .. event] = f end
  function t:AddLine(text) self.lines[#self.lines+1] = text end
  function t:AddDoubleLine(l, r) self.lines[#self.lines+1] = l .. " || " .. r end
  function t:Show() end
  function t:GetItem() return "x", "|cff1eff00|Hitem:" .. self.id .. "::|h[x]|h|r" end
  return t
end
GameTooltip = tooltip("GameTooltip")
CreateFrame = function() local f = { events = {}, scripts = {} }; function f:RegisterEvent(e) self.events[e] = true end; function f:SetScript(k, v) self.scripts[k] = v end; MOD_FRAME = f; return f end
DufforthTweaksHelper = { MarketName = function() return "forever.normal.horde.us" end }
DufforthTweaksHelperPrices = { at = NOW - 3600, ["forever.normal.horde.us"] = { [11083] = 1000, [11082] = 4000, [11084] = 6000, [20725] = 90000 } }
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
for _loc in ("Locale.lua", "LocaleES.lua"): lua.execute((__import__("pathlib").Path(__file__).resolve().parents[2] / "addon" / "DufforthTweaksHelper" / _loc).read_text(encoding="utf-8"))
lua.execute(MOCK)
lua.execute(SRC)
g = lua.globals()
DE = g.DufforthTweaksHelperDE
fails = []


def check(name, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + name + ("" if ok or detail is None else f"   [{detail}]"))
    if not ok:
        fails.append(name)


def item(quality, level, class_id, slot="INVTYPE_HEAD"):
    return lua.table_from({"quality": quality, "level": level, "classID": class_id, "slot": slot})


armor = DE.Outcomes(item(2, 30, 4))
check("armor 30: 75% Soul Dust", armor[1].id == 11083 and abs(armor[1].chance - 0.75) < 1e-9)
weapon = DE.Outcomes(item(2, 30, 2))
check("weapons favor essence", abs(weapon[1].chance - 0.2) < 1e-9 and abs(weapon[2].chance - 0.75) < 1e-9)
check("rare 28: Large Glimmering Shard", DE.Outcomes(item(3, 28, 4))[1].id == 11084)
epic = DE.Outcomes(item(4, 60, 4))
check("epic 60: one Nexus Crystal", epic[1].id == 20725 and epic[1].min == 1 and epic[1].max == 1)
check("common items can't be disenchanted", DE.Outcomes(item(1, 30, 4)) is None)
check("shirts can't be disenchanted", DE.Outcomes(item(2, 30, 4, "INVTYPE_BODY")) is None)
check("trade goods can't be disenchanted", DE.Outcomes(item(2, 30, 7)) is None)
lua.execute("DufforthTweaksHelperNoDE = { [11287] = true }")
wand = item(2, 15, 2, "INVTYPE_RANGEDRIGHT"); wand.id = 11287
check("flagged items like Lesser Magic Wand can't be disenchanted", DE.Outcomes(wand) is None)
lua.execute("DufforthTweaksHelperNoDE = nil")
check("skill: level 15 needs 1", DE.SkillNeeded(item(2, 15, 4)) == 1)
check("skill: level 30 needs 50", DE.SkillNeeded(item(2, 30, 4)) == 50)
check("skill: rare level 20 needs 25", DE.SkillNeeded(item(3, 20, 2)) == 25)
check("skill: epic 60 needs 200", DE.SkillNeeded(item(4, 60, 4)) == 200)

market = "forever.normal.horde.us"
shipped = g.DufforthTweaksHelperPrices
check("bundled price for this market", DE.Price(11084, market, shipped) == 6000)
check("no price for an unlisted item", DE.Price(10940, market, shipped) is None)

# Average for the level-30 helm with download prices: 75% x1.5 x1000 + 20% x1.5 x4000 + 5% x1 x6000, after 5%.
expected = (0.75 * 1.5 * 1000 + 0.2 * 1.5 * 4000 + 0.05 * 6000) * 0.95
value = DE.ExpectedValue(armor, lua.eval("function(id) return DufforthTweaksHelperPrices['forever.normal.horde.us'][id] end"))
check("average value matches the page's formula", abs(value - expected) < 1e-6)

def tip(it, skill=300, **opts):
    o = lua.table_from(opts) if opts else None
    res = DE.TooltipLines(it, market, shipped, 1000000, skill, o)
    lines, advice = res if isinstance(res, tuple) else (res, None)
    if lines is None:
        return None, None, advice
    return [lines[i][1] for i in range(1, len(lines) + 1)], lines, advice


def right(lines, i):
    return str(lines[i][2])


helm = item(2, 30, 4)
texts, lines, advice = tip(helm)
check("verdict first: Best: Disenchant with ~value", texts[0] == "Best: Disenchant" and right(lines, 1).startswith("~") and advice.key == "de")
check("verdict green for disenchant", lines[1][3] < 0.5 and lines[1][4] == 1)
check("details: one disenchant line, no odds by default", texts[1:] == ["  Disenchant (average)"], texts)
check("disenchant detail shows the value", right(lines, 2).startswith("~"))
texts, lines, _ = tip(helm, odds=True)
check("odds on: one line per material", "75%  1-2x Soul Dust" in texts[2] and "5%  1x Large Glimmering Shard" in texts[4], texts)
texts, _, _ = tip(helm, details=False, odds=True)
check("verdict only: one line", texts == ["Best: Disenchant"], texts)
texts, _, _ = tip(helm, shift=True)
check("hold Shift: verdict and a hint", texts == ["Best: Disenchant", "  Hold Shift for details"], texts)
texts, _, _ = tip(helm, shift=True, shiftDown=True)
check("Shift held: details, no hint", texts == ["Best: Disenchant", "  Disenchant (average)"], texts)

# Without the skill: disenchanting isn't your option, but it's still worth knowing.
texts, lines, advice = tip(helm, skill=False)
check("no Enchanting, nothing else: verdict says the skill it needs", texts[0] == "Best: Disenchant (Enchanting 50)" and advice.key == "de", texts)
check("no Enchanting: detail line notes the skill", "  Disenchant (needs Enchanting 50)" in texts, texts)
low = item(2, 15, 4)
shipped[market][10940] = 100; shipped[market][10938] = 300
texts, _, _ = tip(low, skill=False)
check("no Enchanting at all, even for level 1 items", texts[0] == "Best: Disenchant (Enchanting 1)", texts)

rich = item(2, 30, 4); rich.id = 7; rich.sellPrice = 50
shipped[market][7] = 100000
texts, lines, advice = tip(rich)
check("sells for more on the AH: gold verdict with the price after the cut", advice.key == "ah" and texts[0] == "Best: Auction house"
      and "9g" in right(lines, 1) and "50s" in right(lines, 1) and lines[1][3] == 1 and lines[1][5] == 0, texts)
check("details: auction, vendor and disenchant, aligned prices", texts[1:] == ["  Auction house (after 5% cut)", "  Vendor", "  Disenchant (average)"], texts)
texts, _, _ = tip(rich, skill=10)
check("lacking the skill and disenchant isn't best: no disenchant line", "  Disenchant (average)" not in texts and not any("needs Enchanting" in t for t in texts), texts)
rich.sellPrice = 999999
texts, lines, advice = tip(rich)
check("a vendor pays most: gray verdict", advice.key == "vendor" and texts[0] == "Best: Vendor")
rich.sellPrice = 50; rich.bindType = 1
check("Bind on Pickup can't go to the AH", tip(rich)[2].key == "de")
check("advice ties go to the least work", DE.Advice(100, 100, 100).key == "vendor" and DE.Advice(None, None, None) is None)

# Anything with an auction price gets the advice, not only gear.
cloth = item(1, 5, 7, ""); cloth.id = 8; cloth.sellPrice = 13; cloth.stack = 20
shipped[market][8] = 200
texts, lines, advice = tip(cloth)
check("materials: auction house vs vendor for everyone", texts[0] == "Best: Auction house" and advice.key == "ah" and "each" in right(lines, 1), texts)
check("materials: no disenchant line", not any("Disenchant" in t for t in texts), texts)
cloth.id = 9
check("no auction price and can't be disenchanted: no lines", tip(cloth)[0] is None)
check("cloth without a price gets no lines", DE.TooltipLines(item(1, 5, 7), market, shipped, 1000000, None) is None)

shipped.at = 1000000 - 3 * 86400
texts, _, _ = tip(helm)
check("old prices say how old they are", texts[-1] == "  Prices are 3 days old", texts)
shipped.at = 1000000 - 3600

# Real tooltip hooks: the fallback path adds lines once per item.
GT = g.GameTooltip
GT.id = 1
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("tooltip gets the lines once", len(GT.lines) >= 1 and GT.lines[1].startswith("Best: "), list(GT.lines.values()))
n_once = len(GT.lines)
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table()
GT.id = 6
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("cloth without a price: tooltip untouched", len(GT.lines) == 0)

# Another PC: Forever has no global GetItemInfo (another addon, GearQuest Forever, adds it on the user's PC).
lua.execute("OLD_GII = GetItemInfo; GetItemInfo = nil; C_Item = { GetItemInfo = OLD_GII, RequestLoadItemDataByID = function(id) REQUESTED = id end }")
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table(); GT.id = 1
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("no global GetItemInfo: the advice still shows (C_Item.GetItemInfo)", len(GT.lines) == n_once, list(GT.lines.values()))
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table(); GT.id = 4242
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("item not cached yet: asks the game to load it", g.REQUESTED == 4242 and len(GT.lines) == 0)
lua.execute("GetItemInfo = nil; C_Item = nil")
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table(); GT.id = 1
ok = lua.eval("function(f, t) return (pcall(f, t)) end")(g.HOOKS["GameTooltip:OnTooltipSetItem"], GT)
check("no item API at all: no error, no lines", ok and len(GT.lines) == 0)
lua.execute("GetItemInfo = OLD_GII")

# Settings in DufforthTweaksHelperDB.deTooltip.
g.DufforthTweaksHelperDB = lua.table()
O = DE.TooltipOptions()
check("settings default: details on, odds off, Shift off", O.details is True and O.odds is False and O.shift is False)
O.details = False
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table(); GT.id = 1
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("verdict-only setting: one tooltip line", len(GT.lines) == 1, list(GT.lines.values()))
check("Shift changes refresh the tooltip", g.MOD_FRAME is not None and g.MOD_FRAME.events["MODIFIER_STATE_CHANGED"] is True)

# Prices for a market that isn't in the download: the same ruleset and faction in the US, then normal.
check("EU market falls back to the US prices", DE.Price(11084, "forever.normal.horde.eu", shipped) == 6000)
check("missing ruleset falls back to normal", DE.Price(11084, "forever.pvp.horde.us", shipped) == 6000)
check("no fallback across factions", DE.Price(11084, "forever.normal.alliance.us", shipped) is None)

DE.Toggle("off")
GT.id = 2
g.HOOKS["GameTooltip:OnTooltipCleared"](GT)
GT.lines = lua.table()
g.HOOKS["GameTooltip:OnTooltipSetItem"](GT)
check("off means no lines", len(GT.lines) == 0 and "OFF" in g.CHAT[1])

if fails:
    sys.exit(f"{len(fails)} failed")
print("all passed")
